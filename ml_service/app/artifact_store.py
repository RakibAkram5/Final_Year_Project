"""Persists trained model artifacts outside the container.

Hugging Face Spaces have an ephemeral disk: everything written at runtime is
lost when the Space restarts or goes to sleep. When ``HF_ARTIFACT_REPO`` and
``HF_TOKEN`` are set, the artifact directory is mirrored to a *private*
Hugging Face Hub repository:

- ``pull`` at start-up restores the latest promoted models;
- ``push`` after every training run / rollback uploads new versions.

Artifacts contain only model pipelines and aggregate metrics, keyed by a
SHA-256 of the academy id; no student identifiers or raw rows (see README).
Without configuration both functions do nothing, so local runs and tests
are unaffected.
"""
from __future__ import annotations

import logging
import os
import threading
from pathlib import Path

log = logging.getLogger("taleemplus.ml.artifacts")
_lock = threading.Lock()


def _settings() -> tuple[str, str] | None:
    repo = os.getenv("HF_ARTIFACT_REPO", "").strip()
    token = os.getenv("HF_TOKEN", "").strip()
    return (repo, token) if repo and token else None


def enabled() -> bool:
    return _settings() is not None


def pull(artifact_dir: Path) -> bool:
    settings = _settings()
    if not settings:
        return False
    repo, token = settings
    try:
        from huggingface_hub import snapshot_download

        artifact_dir.mkdir(parents=True, exist_ok=True)
        snapshot_download(repo_id=repo, repo_type="model", token=token,
                          local_dir=str(artifact_dir))
        log.info("Restored model artifacts from the Hub")
        return True
    except Exception as exc:  # repo may be empty on first deploy
        log.warning("Could not restore artifacts from the Hub: %s", type(exc).__name__)
        return False


def push(artifact_dir: Path, message: str) -> bool:
    settings = _settings()
    if not settings or not artifact_dir.exists():
        return False
    repo, token = settings
    with _lock:
        try:
            from huggingface_hub import HfApi

            api = HfApi(token=token)
            api.create_repo(repo_id=repo, repo_type="model", private=True, exist_ok=True)
            api.upload_folder(folder_path=str(artifact_dir), repo_id=repo,
                              repo_type="model", commit_message=message[:200])
            return True
        except Exception as exc:
            log.error("Could not upload artifacts to the Hub: %s", type(exc).__name__)
            return False
