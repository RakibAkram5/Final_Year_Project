"""Scheduled retraining; production pointers change only after validation gates."""
import logging

from apscheduler.schedulers.background import BackgroundScheduler

from app import config
from app.data.extractor import (extract_fee_rows, extract_performance_rows,
                                list_academy_ids)
from app.training.pipeline import InsufficientData, train
from app import artifact_store

log = logging.getLogger("taleemplus.ml.scheduler")
scheduler = BackgroundScheduler(daemon=True)


def retrain_all():
    if not config.DATABASE_URL:
        return
    try:
        academy_ids = list_academy_ids(config.DATABASE_URL)
        for academy_id in academy_ids:
            import hashlib
            key = hashlib.sha256(academy_id.encode()).hexdigest()
            for name, extractor, minimum in (
                ("fee-risk", extract_fee_rows, config.MIN_FEE_SAMPLES),
                ("performance", extract_performance_rows, config.MIN_PERFORMANCE_SAMPLES),
            ):
                try:
                    rows = extractor(config.DATABASE_URL, academy_id)
                    train(name, rows, config.ARTIFACT_DIR, key, minimum,
                          config.ARTIFACT_DIR / key / "history.jsonl")
                except InsufficientData:
                    continue
                except Exception:
                    # Database and tenant identifiers and exception payloads are
                    # deliberately omitted from scheduler logs.
                    log.error("Scheduled model training failed for model %s", name)
        artifact_store.push(config.ARTIFACT_DIR, "scheduled retraining")
    except Exception:
        log.error("Scheduled model discovery failed")


def start_scheduler():
    if not scheduler.running:
        scheduler.add_job(retrain_all, "interval", hours=config.RETRAIN_INTERVAL_HOURS,
                          id="academy_model_retraining", replace_existing=True)
        scheduler.start()


def stop_scheduler():
    if scheduler.running:
        scheduler.shutdown(wait=False)
