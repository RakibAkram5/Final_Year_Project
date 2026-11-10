"""Hugging Face persistence tests with a MOCKED hub module (no network, and no
dependency on huggingface_hub being installed locally).

artifact_store imports ``from huggingface_hub import HfApi`` / ``snapshot_download``
lazily inside its functions, so we inject a fake ``huggingface_hub`` module into
``sys.modules`` and assert the persistence contract.
"""
import sys
import types
from unittest.mock import MagicMock

from app import artifact_store, models


def _install_fake_hub(monkeypatch, *, hf_api=None, snapshot=None):
    module = types.ModuleType("huggingface_hub")
    module.HfApi = hf_api if hf_api is not None else MagicMock()
    module.snapshot_download = snapshot if snapshot is not None else MagicMock()
    monkeypatch.setitem(sys.modules, "huggingface_hub", module)
    return module


def _fast_retries(monkeypatch):
    monkeypatch.setenv("HF_MAX_RETRIES", "1")
    monkeypatch.setenv("HF_BACKOFF_SECONDS", "0")


def _enable(monkeypatch, repo_env="HF_REPO_ID"):
    monkeypatch.delenv("HF_REPO_ID", raising=False)
    monkeypatch.delenv("HF_ARTIFACT_REPO", raising=False)
    monkeypatch.setenv(repo_env, "acme/taleemplus-ml")
    monkeypatch.setenv("HF_TOKEN", "hf_dummy")


# --- configuration / credentials -------------------------------------------

def test_push_and_pull_are_noops_without_credentials(monkeypatch, tmp_path):
    for var in ("HF_REPO_ID", "HF_ARTIFACT_REPO", "HF_TOKEN"):
        monkeypatch.delenv(var, raising=False)
    assert artifact_store.enabled() is False
    assert artifact_store.pull(tmp_path) is False
    assert artifact_store.push(tmp_path, "msg") is False


def test_legacy_repo_env_still_accepted(monkeypatch):
    _enable(monkeypatch, repo_env="HF_ARTIFACT_REPO")
    assert artifact_store.enabled() is True


def test_repo_type_is_honoured(monkeypatch, tmp_path):
    _enable(monkeypatch)
    _fast_retries(monkeypatch)
    monkeypatch.setenv("HF_REPO_TYPE", "dataset")
    snap = MagicMock(return_value=str(tmp_path))
    _install_fake_hub(monkeypatch, snapshot=snap)
    assert artifact_store.pull(tmp_path) is True
    assert snap.call_args.kwargs["repo_type"] == "dataset"


# --- upload / download ------------------------------------------------------

def test_push_uploads_to_a_private_repo(monkeypatch, tmp_path):
    _enable(monkeypatch)
    _fast_retries(monkeypatch)
    (tmp_path / "model.bin").write_text("x", encoding="utf-8")
    api = MagicMock()
    HfApi = MagicMock(return_value=api)
    _install_fake_hub(monkeypatch, hf_api=HfApi)

    assert artifact_store.push(tmp_path, "trained fee-risk") is True
    HfApi.assert_called_once_with(token="hf_dummy")
    assert api.create_repo.call_args.kwargs.get("private") is True
    assert api.upload_folder.call_args.kwargs["repo_id"] == "acme/taleemplus-ml"


def test_push_missing_directory_does_not_upload(monkeypatch, tmp_path):
    _enable(monkeypatch)
    HfApi = MagicMock()
    _install_fake_hub(monkeypatch, hf_api=HfApi)
    assert artifact_store.push(tmp_path / "nope", "msg") is False
    HfApi.assert_not_called()


def test_push_failure_returns_false_and_does_not_raise(monkeypatch, tmp_path):
    _enable(monkeypatch)
    _fast_retries(monkeypatch)
    (tmp_path / "m.bin").write_text("x", encoding="utf-8")
    api = MagicMock()
    api.upload_folder.side_effect = RuntimeError("network down")
    _install_fake_hub(monkeypatch, hf_api=MagicMock(return_value=api))
    assert artifact_store.push(tmp_path, "msg") is False


def test_push_retries_then_succeeds(monkeypatch, tmp_path):
    _enable(monkeypatch)
    monkeypatch.setenv("HF_MAX_RETRIES", "3")
    monkeypatch.setenv("HF_BACKOFF_SECONDS", "0")
    (tmp_path / "m.bin").write_text("x", encoding="utf-8")
    api = MagicMock()
    api.upload_folder.side_effect = [RuntimeError("blip"), None]  # fail once, then ok
    _install_fake_hub(monkeypatch, hf_api=MagicMock(return_value=api))
    assert artifact_store.push(tmp_path, "msg") is True
    assert api.upload_folder.call_count == 2


def test_pull_restores_from_hub(monkeypatch, tmp_path):
    _enable(monkeypatch)
    _fast_retries(monkeypatch)
    snap = MagicMock(return_value=str(tmp_path))
    _install_fake_hub(monkeypatch, snapshot=snap)
    assert artifact_store.pull(tmp_path) is True
    assert snap.call_args.kwargs["repo_id"] == "acme/taleemplus-ml"
    assert snap.call_args.kwargs["token"] == "hf_dummy"


def test_pull_handles_empty_or_missing_repo(monkeypatch, tmp_path):
    _enable(monkeypatch)
    _fast_retries(monkeypatch)
    snap = MagicMock(side_effect=RuntimeError("404"))
    _install_fake_hub(monkeypatch, snapshot=snap)
    assert artifact_store.pull(tmp_path) is False


# --- integrity verification -------------------------------------------------

def _make_version(root, key, model, version, *, with_files=True):
    vdir = root / key / model / version
    vdir.mkdir(parents=True, exist_ok=True)
    if with_files:
        (vdir / "pipeline.joblib").write_text("p", encoding="utf-8")
        (vdir / "metadata.json").write_text("{}", encoding="utf-8")
    models.write_pointer(root, key, model, version)
    return vdir


def test_verify_integrity_passes_for_intact_model(tmp_path):
    _make_version(tmp_path, "acad", "fee-risk", "v1")
    assert artifact_store.verify_integrity(tmp_path) == []


def test_verify_integrity_detects_missing_artifact(tmp_path):
    _make_version(tmp_path, "acad", "fee-risk", "v1", with_files=False)
    problems = artifact_store.verify_integrity(tmp_path)
    assert len(problems) == 1 and "missing artifact" in problems[0]


# --- persist_training: activate only after successful upload ----------------

def test_persist_training_local_mode_keeps_promotion(monkeypatch, tmp_path):
    for var in ("HF_REPO_ID", "HF_ARTIFACT_REPO", "HF_TOKEN"):
        monkeypatch.delenv(var, raising=False)
    _make_version(tmp_path, "acad", "fee-risk", "v2")   # already promoted locally
    out = artifact_store.persist_training(tmp_path, "acad", "fee-risk",
                                          promoted=True, previous_version="v1",
                                          message="m")
    assert out == {"enabled": False, "persisted": False, "reverted": False}
    assert models.read_pointer(tmp_path, "acad", "fee-risk") == "v2"  # unchanged


def test_persist_training_keeps_pointer_on_successful_upload(monkeypatch, tmp_path):
    _enable(monkeypatch)
    _fast_retries(monkeypatch)
    _make_version(tmp_path, "acad", "fee-risk", "v2")
    _install_fake_hub(monkeypatch, hf_api=MagicMock())   # upload succeeds
    out = artifact_store.persist_training(tmp_path, "acad", "fee-risk",
                                          promoted=True, previous_version="v1", message="m")
    assert out["persisted"] is True and out["reverted"] is False
    assert models.read_pointer(tmp_path, "acad", "fee-risk") == "v2"


def test_persist_training_reverts_activation_on_upload_failure(monkeypatch, tmp_path):
    _enable(monkeypatch)
    _fast_retries(monkeypatch)
    # Previous active model v1 exists and stays available; new v2 was just promoted.
    _make_version(tmp_path, "acad", "fee-risk", "v1")
    _make_version(tmp_path, "acad", "fee-risk", "v2")
    api = MagicMock()
    api.upload_folder.side_effect = RuntimeError("upload interrupted")
    _install_fake_hub(monkeypatch, hf_api=MagicMock(return_value=api))

    out = artifact_store.persist_training(tmp_path, "acad", "fee-risk",
                                          promoted=True, previous_version="v1", message="m")
    assert out["persisted"] is False and out["reverted"] is True
    # The un-persisted model is NOT left active; the previous model remains.
    assert models.read_pointer(tmp_path, "acad", "fee-risk") == "v1"


def test_persist_training_clears_pointer_when_no_previous_model(monkeypatch, tmp_path):
    _enable(monkeypatch)
    _fast_retries(monkeypatch)
    _make_version(tmp_path, "acad", "fee-risk", "v1")   # first-ever model, just promoted
    api = MagicMock()
    api.upload_folder.side_effect = RuntimeError("fail")
    _install_fake_hub(monkeypatch, hf_api=MagicMock(return_value=api))
    out = artifact_store.persist_training(tmp_path, "acad", "fee-risk",
                                          promoted=True, previous_version=None, message="m")
    assert out["reverted"] is True
    assert models.read_pointer(tmp_path, "acad", "fee-risk") is None  # nothing active
