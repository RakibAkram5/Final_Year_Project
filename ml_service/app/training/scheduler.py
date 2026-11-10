"""Automated training lifecycle scheduler.

Design goals (see AUTOMATED_TRAINING_REPORT.md):
  * Two cadences: a frequent eligibility check (default 6h) that trains when
    ready, and a daily full sweep.
  * Catch-up on restart: a check runs shortly after startup, and missed runs
    coalesce into one (``coalesce=True`` + generous ``misfire_grace_time``), so
    a service that was asleep re-evaluates as soon as it wakes.
  * No duplicate / concurrent training: ``max_instances=1`` on each job plus the
    shared ``app.state`` lock (also held by the HTTP API).
  * Transient DB failures retry with exponential backoff; every attempt is
    logged to the artifact store (never silently marked successful).
  * Reads data through the read-only ML account only; writes nothing to Postgres.
  * Production pointers move only through the pipeline's validation gate.
"""
from __future__ import annotations

import hashlib
import json
import logging
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

from apscheduler.schedulers.background import BackgroundScheduler

from app import artifact_store, config, monitoring, state
from app.data.extractor import (extract_fee_rows, extract_performance_rows,
                                list_academy_ids)
from app.models import load_production, read_pointer
from app.training.pipeline import InsufficientData, train

log = logging.getLogger("taleemplus.ml.scheduler")
scheduler = BackgroundScheduler(daemon=True)
# Guarantees only ONE full sweep runs at a time, no matter which trigger fired
# it (the 6h check, the daily sweep, or the startup catch-up). This removes the
# race where two concurrent sweeps would double the read-only DB load and
# interleave history writes. Per-job training is additionally guarded by the
# shared app.state lock, so a manual /models/retrain is also safe alongside it.
_sweep_lock = threading.Lock()

MODELS = (
    ("fee-risk", extract_fee_rows, "MIN_FEE_SAMPLES"),
    ("performance", extract_performance_rows, "MIN_PERFORMANCE_SAMPLES"),
)


def _academy_key(academy_id: str) -> str:
    return hashlib.sha256(academy_id.encode()).hexdigest()


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _append_event(academy_key: str, event: dict) -> None:
    path = config.ARTIFACT_DIR / academy_key / "history.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps({**event, "at": _now()}) + "\n")


def _with_retry(fn, *args):
    """Call ``fn`` retrying transient failures with exponential backoff."""
    delay = config.SCHEDULER_BACKOFF_SECONDS
    last = None
    for attempt in range(1, config.SCHEDULER_MAX_RETRIES + 1):
        try:
            return fn(*args)
        except Exception as exc:  # pragma: no cover - timing dependent
            last = exc
            if attempt >= config.SCHEDULER_MAX_RETRIES:
                break
            time.sleep(delay)
            delay *= 2
    raise last


def _active_snapshot(key: str, model_name: str):
    """Records count + feature stats of the currently active model, if any."""
    loaded = load_production(config.ARTIFACT_DIR, key, model_name)
    if not loaded:
        return None, None
    _, meta = loaded
    return meta.get("records"), meta.get("feature_stats")


def process_model(academy_id: str, model_name: str, extractor, minimum: int,
                  train_if_ready: bool = True) -> dict:
    """Monitor one academy+model and train if eligible. Returns a summary."""
    key = _academy_key(academy_id)
    job_key = f"{key}:{model_name}"
    last_records, baseline_stats = _active_snapshot(key, model_name)
    previous_version = read_pointer(config.ARTIFACT_DIR, key, model_name)

    try:
        rows = _with_retry(extractor, config.DATABASE_URL, academy_id)
    except Exception:
        state.TRAINING_ERRORS[job_key] = "The academy data source is unavailable."
        _append_event(key, {"model": model_name, "status": "NOT_READY",
                            "reason": "data source unavailable"})
        return {"model": model_name, "data_state": "NOT_READY"}

    decision = monitoring.evaluate_eligibility(
        model_name, rows, minimum, last_records,
        config.RETRAIN_NEW_RECORDS, config.MIN_MINORITY_CLASS_FRACTION)

    # Drift signal (does not itself activate any model).
    current_stats = monitoring.feature_distribution(
        rows, monitoring._features_for(model_name))
    drift = monitoring.detect_drift(baseline_stats, current_stats,
                                    config.DRIFT_MEAN_THRESHOLD)
    if drift["drifted"]:
        _append_event(key, {"model": model_name, "status": "DRIFT_ALERT",
                            "features": drift["features"]})
    decision["drift"] = drift

    if not (train_if_ready and decision["should_train"]):
        return decision

    if not state.try_acquire(job_key):
        decision["data_state"] = "TRAINING"      # already in progress elsewhere
        return decision
    try:
        _append_event(key, {"model": model_name, "status": "TRAINING",
                            "records": decision["eligible_records"]})
        state.TRAINING_ERRORS.pop(job_key, None)
        try:
            meta = train(model_name, rows, config.ARTIFACT_DIR, key, minimum,
                         config.ARTIFACT_DIR / key / "history.jsonl")
            promoted = meta.get("status") == "PRODUCTION" and meta.get("retrained")
            outcome = artifact_store.persist_training(
                config.ARTIFACT_DIR, key, model_name, promoted,
                previous_version, f"auto-train {model_name}")
            decision["trained"] = True
            decision["persisted"] = outcome["persisted"]
            decision["version"] = meta.get("version")
            if promoted and outcome["enabled"] and not outcome["persisted"]:
                # Upload failed -> promotion reverted, previous model kept active.
                decision["result_status"] = "PERSIST_FAILED"
                _append_event(key, {"model": model_name, "status": "PERSIST_FAILED"})
            else:
                decision["result_status"] = meta.get("status")
        except InsufficientData:
            _append_event(key, {"model": model_name, "status": "INSUFFICIENT_DATA",
                                "records": len(rows)})
            decision["trained"] = False
    except Exception:
        state.TRAINING_ERRORS[job_key] = "Training failed; check service diagnostics."
        _append_event(key, {"model": model_name, "status": "TRAINING_FAILED"})
        decision["trained"] = False
        decision["result_status"] = "FAILED"
    finally:
        state.release(job_key)
    return decision


def run_eligibility_check(train_if_ready: bool = True) -> dict:
    """Sweep every academy + model once. Safe to call on any cadence."""
    summary = {"checked": 0, "trained": 0, "academies": 0, "at": _now()}
    if not config.DATABASE_URL:
        state.SCHEDULER["last_check"] = _now()
        state.SCHEDULER["last_check_result"] = "SKIPPED: DATABASE_URL not configured"
        return {**summary, "skipped": "no database"}

    # Only one sweep at a time (6h check vs daily sweep vs startup catch-up).
    if not _sweep_lock.acquire(blocking=False):
        return {**summary, "skipped": "sweep already running"}
    try:
        try:
            academy_ids = _with_retry(list_academy_ids, config.DATABASE_URL)
        except Exception:
            log.error("Scheduled academy discovery failed")
            state.SCHEDULER["last_check"] = _now()
            state.SCHEDULER["last_check_result"] = "FAILED: academy discovery"
            return {**summary, "error": "academy discovery failed"}

        summary["academies"] = len(academy_ids)
        for academy_id in academy_ids:
            for model_name, extractor, min_attr in MODELS:
                minimum = getattr(config, min_attr)
                try:
                    decision = process_model(academy_id, model_name, extractor,
                                             minimum, train_if_ready)
                    summary["checked"] += 1
                    if decision.get("trained"):
                        summary["trained"] += 1
                except Exception:
                    # Tenant identifiers and payloads are deliberately kept out of logs.
                    log.error("Scheduled processing failed for model %s", model_name)
        artifact_store.push(config.ARTIFACT_DIR, "scheduled eligibility sweep")
        state.SCHEDULER["last_check"] = _now()
        state.SCHEDULER["last_check_result"] = summary
        _refresh_next_check()
        return summary
    finally:
        _sweep_lock.release()


# Backward-compatible name used by earlier versions / external callers.
def retrain_all() -> dict:
    return run_eligibility_check(train_if_ready=True)


def _refresh_next_check() -> None:
    job = scheduler.get_job("eligibility_check")
    if job and job.next_run_time:
        state.SCHEDULER["next_check"] = job.next_run_time.isoformat()


def start_scheduler() -> None:
    if scheduler.running:
        return
    grace = max(3600, config.CHECK_INTERVAL_HOURS * 3600)
    scheduler.add_job(run_eligibility_check, "interval",
                      hours=config.CHECK_INTERVAL_HOURS, id="eligibility_check",
                      replace_existing=True, max_instances=1, coalesce=True,
                      misfire_grace_time=grace)
    scheduler.add_job(lambda: run_eligibility_check(True), "interval",
                      hours=config.FULL_CHECK_INTERVAL_HOURS, id="full_sweep",
                      replace_existing=True, max_instances=1, coalesce=True,
                      misfire_grace_time=grace)
    scheduler.start()
    state.SCHEDULER["running"] = True
    # Catch-up: evaluate shortly after startup (covers a just-woken service).
    try:
        scheduler.add_job(run_eligibility_check, "date", id="startup_catchup",
                          replace_existing=True, misfire_grace_time=grace)
    except Exception:  # pragma: no cover
        pass
    _refresh_next_check()


def stop_scheduler() -> None:
    if scheduler.running:
        scheduler.shutdown(wait=False)
    state.SCHEDULER["running"] = False
