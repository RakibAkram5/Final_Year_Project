"""Process-wide training state, shared by the HTTP API and the scheduler.

Keeping this in its own module (imported by both ``app.main`` and
``app.training.scheduler``) gives a single lock and a single in-progress set, so
a manually triggered train and a scheduled train can never run the same
``academy:model`` job at the same time, and neither launches a duplicate.

All state here is in-memory. Durable job history is appended to the artifact
store (``history.jsonl`` + Hugging Face Hub), NOT to PostgreSQL, because the ML
database account (``taleemplus_ml_reader``) is intentionally read-only.
"""
from __future__ import annotations

import threading

# Set of "<academy_key>:<model_name>" currently training.
TRAINING_JOBS: set[str] = set()
# Last error message per job key (operator-facing, never includes identifiers).
TRAINING_ERRORS: dict[str, str] = {}
# One lock guarding both structures above.
TRAINING_LOCK = threading.Lock()
# Scheduler bookkeeping surfaced in the dashboard API.
SCHEDULER: dict[str, object] = {
    "running": False,
    "last_check": None,       # ISO timestamp of the last eligibility check
    "next_check": None,       # ISO timestamp of the next scheduled check
    "last_check_result": None,
}


def try_acquire(job_key: str) -> bool:
    """Atomically claim a job. Returns False if it is already running."""
    with TRAINING_LOCK:
        if job_key in TRAINING_JOBS:
            return False
        TRAINING_JOBS.add(job_key)
        return True


def release(job_key: str) -> None:
    with TRAINING_LOCK:
        TRAINING_JOBS.discard(job_key)


def is_running(job_key: str) -> bool:
    return job_key in TRAINING_JOBS
