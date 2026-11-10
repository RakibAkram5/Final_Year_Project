import hashlib
import sys
import types
from datetime import date, timedelta
from unittest.mock import MagicMock

from app import config, state
from app.models import load_production
from app.training import scheduler


def _fee_rows(n=80):
    origin = date(2024, 1, 1)
    return [{"issue_date": origin + timedelta(days=d), "attendance_pct": 90 - (d % 2) * 70,
             "late_count": (d % 2) * 3, "delay_avg": (d % 2) * 10, "consistency": 1 - (d % 2),
             "outstanding": 1000.0, "label": d % 2} for d in range(n)]


def _key(academy_id):
    return hashlib.sha256(academy_id.encode()).hexdigest()


def test_eligibility_check_skips_without_database(monkeypatch, tmp_path):
    monkeypatch.setattr(config, "DATABASE_URL", "")
    monkeypatch.setattr(config, "ARTIFACT_DIR", tmp_path)
    out = scheduler.run_eligibility_check()
    assert out.get("skipped") == "no database"
    assert state.SCHEDULER["last_check_result"].startswith("SKIPPED")


def test_process_model_trains_and_promotes_first_model(monkeypatch, tmp_path):
    monkeypatch.setattr(config, "DATABASE_URL", "postgresql://unused")
    monkeypatch.setattr(config, "ARTIFACT_DIR", tmp_path)
    rows = _fee_rows()
    decision = scheduler.process_model("academy-A", "fee-risk",
                                       lambda *_: rows, minimum=40)
    assert decision["should_train"] is True
    assert decision.get("trained") is True
    loaded = load_production(tmp_path, _key("academy-A"), "fee-risk")
    assert loaded is not None
    # Feature statistics are recorded for later drift comparison.
    assert "feature_stats" in loaded[1] and loaded[1]["feature_stats"]["attendance_pct"]["count"] > 0


def test_duplicate_training_is_prevented(monkeypatch, tmp_path):
    monkeypatch.setattr(config, "DATABASE_URL", "postgresql://unused")
    monkeypatch.setattr(config, "ARTIFACT_DIR", tmp_path)
    job_key = f"{_key('academy-busy')}:fee-risk"
    assert state.try_acquire(job_key) is True       # simulate a train already running
    try:
        decision = scheduler.process_model("academy-busy", "fee-risk",
                                           lambda *_: _fee_rows(), minimum=40)
        assert decision["should_train"] is True
        assert decision["data_state"] == "TRAINING"   # not started again
        assert "trained" not in decision
    finally:
        state.release(job_key)


def test_data_source_failure_records_not_ready(monkeypatch, tmp_path):
    monkeypatch.setattr(config, "DATABASE_URL", "postgresql://unused")
    monkeypatch.setattr(config, "ARTIFACT_DIR", tmp_path)
    monkeypatch.setattr(config, "SCHEDULER_MAX_RETRIES", 1)
    monkeypatch.setattr(config, "SCHEDULER_BACKOFF_SECONDS", 0)

    def boom(*_):
        raise ConnectionError("db down")
    decision = scheduler.process_model("academy-down", "fee-risk", boom, minimum=40)
    assert decision["data_state"] == "NOT_READY"
    history = (tmp_path / _key("academy-down") / "history.jsonl").read_text(encoding="utf-8")
    assert "NOT_READY" in history


def test_no_retrain_without_enough_new_data(monkeypatch, tmp_path):
    monkeypatch.setattr(config, "DATABASE_URL", "postgresql://unused")
    monkeypatch.setattr(config, "ARTIFACT_DIR", tmp_path)
    monkeypatch.setattr(config, "RETRAIN_NEW_RECORDS", 50)
    rows = _fee_rows()
    first = scheduler.process_model("academy-W", "fee-risk", lambda *_: rows, minimum=40)
    assert first.get("trained") is True
    # Same data, no new records -> should wait, not retrain.
    second = scheduler.process_model("academy-W", "fee-risk", lambda *_: rows, minimum=40)
    assert second["should_train"] is False
    assert second["data_state"] == "WAITING_FOR_DATA"


def test_academy_isolation_only_touches_its_own_folder(monkeypatch, tmp_path):
    monkeypatch.setattr(config, "DATABASE_URL", "postgresql://unused")
    monkeypatch.setattr(config, "ARTIFACT_DIR", tmp_path)
    scheduler.process_model("academy-ONE", "fee-risk", lambda *_: _fee_rows(), minimum=40)
    assert (tmp_path / _key("academy-ONE")).exists()
    assert not (tmp_path / _key("academy-TWO")).exists()


def test_process_model_does_not_activate_when_upload_fails(monkeypatch, tmp_path):
    # End-to-end: scheduler trains a model, the Hub upload fails, and the model
    # is NOT left active (previous state preserved — here, no active model).
    monkeypatch.setattr(config, "DATABASE_URL", "postgresql://unused")
    monkeypatch.setattr(config, "ARTIFACT_DIR", tmp_path)
    monkeypatch.setenv("HF_REPO_ID", "acme/taleemplus-ml")
    monkeypatch.setenv("HF_TOKEN", "hf_dummy")
    monkeypatch.setenv("HF_MAX_RETRIES", "1")
    monkeypatch.setenv("HF_BACKOFF_SECONDS", "0")
    api = MagicMock()
    api.upload_folder.side_effect = RuntimeError("upload interrupted")
    fake = types.ModuleType("huggingface_hub")
    fake.HfApi = MagicMock(return_value=api)
    fake.snapshot_download = MagicMock()
    monkeypatch.setitem(sys.modules, "huggingface_hub", fake)

    decision = scheduler.process_model("academy-hf", "fee-risk",
                                       lambda *_: _fee_rows(), minimum=40)
    assert decision["trained"] is True
    assert decision["result_status"] == "PERSIST_FAILED"
    assert decision["persisted"] is False
    # The un-persisted model must not be active.
    assert load_production(tmp_path, _key("academy-hf"), "fee-risk") is None


def test_concurrent_sweep_is_skipped_not_duplicated(monkeypatch, tmp_path):
    # Regression for the 6h-check vs daily-sweep race: while one sweep holds the
    # lock, a second trigger must no-op instead of running a parallel sweep.
    monkeypatch.setattr(config, "DATABASE_URL", "postgresql://unused")
    monkeypatch.setattr(config, "ARTIFACT_DIR", tmp_path)
    assert scheduler._sweep_lock.acquire(blocking=False) is True
    try:
        out = scheduler.run_eligibility_check()
        assert out.get("skipped") == "sweep already running"
    finally:
        scheduler._sweep_lock.release()


def test_scheduler_starts_and_shuts_down_cleanly(monkeypatch, tmp_path):
    monkeypatch.setattr(config, "DATABASE_URL", "")   # keep startup catch-up a no-op
    monkeypatch.setattr(config, "ARTIFACT_DIR", tmp_path)
    try:
        scheduler.start_scheduler()
        assert scheduler.scheduler.running is True
        assert state.SCHEDULER["running"] is True
        assert scheduler.scheduler.get_job("eligibility_check") is not None
        assert scheduler.scheduler.get_job("full_sweep") is not None
    finally:
        scheduler.stop_scheduler()
    assert state.SCHEDULER["running"] is False
