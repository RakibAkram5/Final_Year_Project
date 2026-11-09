import asyncio

import httpx

from app import config
from app.main import app


def _request(method, path, **kwargs):
    async def send():
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            return await client.request(method, path, **kwargs)
    return asyncio.run(send())


def test_internal_api_requires_bearer_token(monkeypatch):
    monkeypatch.setattr(config, "INTERNAL_TOKEN", "internal-test-token-1234567890123456")
    response = _request("GET", "/models/status", params={"academy_id": "academy-test"})
    assert response.status_code == 401


def test_status_does_not_claim_training_when_database_is_unconfigured(monkeypatch, tmp_path):
    monkeypatch.setattr(config, "INTERNAL_TOKEN", "internal-test-token-1234567890123456")
    monkeypatch.setattr(config, "DATABASE_URL", "")
    monkeypatch.setattr(config, "ARTIFACT_DIR", tmp_path)
    response = _request("GET", "/models/status", params={"academy_id": "academy-test"},
                        headers={"Authorization": "Bearer internal-test-token-1234567890123456"})
    assert response.status_code == 200
    assert response.json()["fee_risk"]["status"] == "NOT_READY"
    assert response.json()["performance"]["status"] == "NOT_READY"


def test_prediction_refuses_unavailable_model(monkeypatch, tmp_path):
    monkeypatch.setattr(config, "INTERNAL_TOKEN", "internal-test-token-1234567890123456")
    monkeypatch.setattr(config, "ARTIFACT_DIR", tmp_path)
    response = _request("POST", "/predict/fee-risk", headers={"Authorization": "Bearer internal-test-token-1234567890123456"},
                        json={"academy_id": "academy-test", "features": {}})
    assert response.status_code == 409
    assert response.json()["detail"]["status"] == "NOT_READY"


def test_rollback_rejects_unavailable_version(monkeypatch, tmp_path):
    monkeypatch.setattr(config, "INTERNAL_TOKEN", "internal-test-token-1234567890123456")
    monkeypatch.setattr(config, "ARTIFACT_DIR", tmp_path)
    response = _request("POST", "/models/rollback", headers={"Authorization": "Bearer internal-test-token-1234567890123456"},
                        json={"academy_id": "academy-test", "model": "fee-risk", "version": "unknown"})
    assert response.status_code == 404


TOKEN = "internal-test-token-1234567890123456"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


def _fee_rows():
    from datetime import date, timedelta
    origin = date(2024, 1, 1)
    return [{"issue_date": origin + timedelta(days=d), "attendance_pct": 90 - (d % 2) * 70,
             "late_count": (d % 2) * 3, "delay_avg": (d % 2) * 10,
             "consistency": 1 - (d % 2), "outstanding": 1000, "label": d % 2}
            for d in range(80)]


def _wait_until_idle(timeout=30):
    import time
    from app import main
    deadline = time.time() + timeout
    while main._training and time.time() < deadline:
        time.sleep(0.05)


def test_training_runs_in_background_and_status_reports_result(monkeypatch, tmp_path):
    import time
    from app import main
    monkeypatch.setattr(config, "INTERNAL_TOKEN", TOKEN)
    monkeypatch.setattr(config, "DATABASE_URL", "postgresql://unused")
    monkeypatch.setattr(config, "ARTIFACT_DIR", tmp_path)
    monkeypatch.setattr(config, "MIN_FEE_SAMPLES", 40)

    def slow_rows(_url, _academy):
        time.sleep(0.5)  # simulate a slow extraction
        return _fee_rows()
    monkeypatch.setattr(main, "extract_fee_rows", slow_rows)

    started = _request("POST", "/models/train/fee-risk", headers=AUTH, json={"academy_id": "academy-bg"})
    assert started.status_code == 202
    assert started.json()["status"] == "TRAINING"
    # A second request while the first is running is rejected, not queued.
    again = _request("POST", "/models/train/fee-risk", headers=AUTH, json={"academy_id": "academy-bg"})
    assert again.status_code == 409
    status = _request("GET", "/models/status", headers=AUTH, params={"academy_id": "academy-bg"})
    assert status.json()["fee_risk"]["status"] == "TRAINING"

    _wait_until_idle()
    status = _request("GET", "/models/status", headers=AUTH, params={"academy_id": "academy-bg"})
    assert status.json()["fee_risk"]["status"] == "PRODUCTION"
    assert "roc_auc" in status.json()["fee_risk"]["metadata"]["metrics"]["metrics"]


def test_background_training_with_too_little_data_reports_insufficient(monkeypatch, tmp_path):
    from app import main
    monkeypatch.setattr(config, "INTERNAL_TOKEN", TOKEN)
    monkeypatch.setattr(config, "DATABASE_URL", "postgresql://unused")
    monkeypatch.setattr(config, "ARTIFACT_DIR", tmp_path)
    monkeypatch.setattr(main, "extract_fee_rows", lambda *_: _fee_rows()[:10])
    assert _request("POST", "/models/train/fee-risk", headers=AUTH,
                    json={"academy_id": "academy-small"}).status_code == 202
    _wait_until_idle()
    status = _request("GET", "/models/status", headers=AUTH, params={"academy_id": "academy-small"})
    assert status.json()["fee_risk"]["status"] == "INSUFFICIENT_DATA"
    assert status.json()["fee_risk"]["usable_records"] == 10


def test_training_without_database_is_refused(monkeypatch, tmp_path):
    monkeypatch.setattr(config, "INTERNAL_TOKEN", TOKEN)
    monkeypatch.setattr(config, "DATABASE_URL", "")
    monkeypatch.setattr(config, "ARTIFACT_DIR", tmp_path)
    r = _request("POST", "/models/retrain", headers=AUTH, json={"academy_id": "x"})
    assert r.status_code == 202
    assert r.json()["fee_risk"]["status"] == "NOT_READY"


def test_artifact_store_is_a_no_op_without_configuration(monkeypatch, tmp_path):
    from app import artifact_store
    monkeypatch.delenv("HF_ARTIFACT_REPO", raising=False)
    monkeypatch.delenv("HF_TOKEN", raising=False)
    assert artifact_store.pull(tmp_path) is False
    assert artifact_store.push(tmp_path, "x") is False


def test_status_distinguishes_ready_to_train_from_insufficient(monkeypatch, tmp_path):
    from app import main
    monkeypatch.setattr(config, "INTERNAL_TOKEN", TOKEN)
    monkeypatch.setattr(config, "DATABASE_URL", "postgresql://unused")
    monkeypatch.setattr(config, "ARTIFACT_DIR", tmp_path)
    monkeypatch.setattr(config, "MIN_FEE_SAMPLES", 40)
    monkeypatch.setattr(main, "extract_fee_rows", lambda *_: _fee_rows())
    monkeypatch.setattr(main, "extract_performance_rows", lambda *_: [])
    body = _request("GET", "/models/status", headers=AUTH, params={"academy_id": "a"}).json()
    assert body["fee_risk"]["status"] == "READY_TO_TRAIN"
    assert body["performance"]["status"] == "INSUFFICIENT_DATA"
