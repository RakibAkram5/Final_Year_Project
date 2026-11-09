"""Durable persistence of trained model artifacts on the Hugging Face Hub.

Hugging Face Spaces have an ephemeral disk: everything written at runtime is lost
when the Space restarts or sleeps. When a repo id and token are configured, the
whole artifact directory (model pipelines, metadata, ``production.json`` pointers,
per-academy ``history.jsonl``) is mirrored to a *private* Hub repository:

- ``pull`` at start-up restores the latest promoted models;
- ``push`` after every training run / rollback uploads a new commit;
- ``persist_training`` enforces "activate only after a successful upload": if a
  run promoted a new model but the upload fails, the production pointer is
  reverted so an un-persisted model is never left active.

Configuration (env):
  HF_TOKEN       - write token (never logged, never returned in any API).
  HF_REPO_ID     - e.g. "your-name/taleemplus-ml-artifacts"
                   (legacy ``HF_ARTIFACT_REPO`` is still accepted).
  HF_REPO_TYPE   - "model" (default), "dataset", or "space".
  HF_MAX_RETRIES / HF_BACKOFF_SECONDS - transient-failure retry budget.

Artifacts contain only model pipelines and aggregate metrics, keyed by a SHA-256
of the academy id; no student identifiers or raw rows. Without configuration
every function is a safe no-op, so local runs and tests are unaffected.
"""
from __future__ import annotations

import json
import logging
import os
import threading
import time
from pathlib import Path

log = logging.getLogger("taleemplus.ml.artifacts")
_lock = threading.Lock()


def _settings() -> tuple[str, str, str] | None:
    repo = (os.getenv("HF_REPO_ID") or os.getenv("HF_ARTIFACT_REPO") or "").strip()
    token = os.getenv("HF_TOKEN", "").strip()
    repo_type = (os.getenv("HF_REPO_TYPE", "model") or "model").strip()
    return (repo, token, repo_type) if repo and token else None


def _retry_cfg() -> tuple[int, float]:
    return max(1, int(os.getenv("HF_MAX_RETRIES", "3"))), float(os.getenv("HF_BACKOFF_SECONDS", "2"))


def enabled() -> bool:
    return _settings() is not None


def pull(artifact_dir: Path) -> bool:
    settings = _settings()
    if not settings:
        return False
    repo, token, repo_type = settings
    retries, backoff = _retry_cfg()
    artifact_dir.mkdir(parents=True, exist_ok=True)
    delay = backoff
    for attempt in range(1, retries + 1):
        try:
            from huggingface_hub import snapshot_download

            snapshot_download(repo_id=repo, repo_type=repo_type, token=token,
                              local_dir=str(artifact_dir))
            log.info("Restored model artifacts from the Hub")
            return True
        except Exception as exc:  # repo may be empty on first deploy
            log.warning("Hub restore attempt %d failed: %s", attempt, type(exc).__name__)
            if attempt >= retries:
                return False
            time.sleep(delay)
            delay *= 2
    return False


def push(artifact_dir: Path, message: str) -> bool:
    settings = _settings()
    if not settings or not artifact_dir.exists():
        return False
    repo, token, repo_type = settings
    retries, backoff = _retry_cfg()
    with _lock:   # serialize uploads so concurrent jobs cannot corrupt a commit
        delay = backoff
        for attempt in range(1, retries + 1):
            try:
                from huggingface_hub import HfApi

                api = HfApi(token=token)
                api.create_repo(repo_id=repo, repo_type=repo_type, private=True, exist_ok=True)
                api.upload_folder(folder_path=str(artifact_dir), repo_id=repo,
                                  repo_type=repo_type, commit_message=message[:200])
                return True
            except Exception as exc:
                log.error("Hub upload attempt %d failed: %s", attempt, type(exc).__name__)
                if attempt >= retries:
                    return False
                time.sleep(delay)
                delay *= 2
    return False


def verify_integrity(artifact_dir: Path) -> list[str]:
    """Return a list of problems: production pointers whose referenced version is
    missing its pipeline or metadata. Empty list == all active models are intact.
    """
    problems: list[str] = []
    if not artifact_dir.exists():
        return problems
    for pointer in artifact_dir.glob("*/*/production.json"):
        label = f"{pointer.parent.parent.name[:8]}…/{pointer.parent.name}"
        try:
            version = json.loads(pointer.read_text(encoding="utf-8"))["version"]
        except Exception:
            problems.append(f"unreadable production pointer: {label}")
            continue
        vdir = pointer.parent / version
        if not (vdir / "pipeline.joblib").is_file() or not (vdir / "metadata.json").is_file():
            problems.append(f"missing artifact files for {label}@{version}")
    return problems


def persist_training(artifact_dir: Path, academy_key: str, model_name: str,
                     promoted: bool, previous_version: str | None,
                     message: str) -> dict:
    """Durably persist after a training run.

    When the Hub is configured and the run promoted a NEW model, the upload must
    succeed before that model stays active: on upload failure the production
    pointer is reverted to ``previous_version`` (or cleared when there was none),
    keeping the previous validated model active. Returns an outcome dict.

    When the Hub is not configured this is a no-op that leaves the local promotion
    in place (single-node / development behaviour), preserving backward
    compatibility.
    """
    if not enabled():
        return {"enabled": False, "persisted": False, "reverted": False}
    if push(artifact_dir, message):
        return {"enabled": True, "persisted": True, "reverted": False}
    reverted = False
    if promoted:
        from app import models
        models.restore_pointer(artifact_dir, academy_key, model_name, previous_version)
        log.error("Upload failed after promotion; reverted %s to previous model", model_name)
        reverted = True
    return {"enabled": True, "persisted": False, "reverted": reverted}
