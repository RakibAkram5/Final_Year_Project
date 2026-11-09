import os
from pathlib import Path


DATABASE_URL = os.getenv("DATABASE_URL", "")
INTERNAL_TOKEN = os.getenv("ML_INTERNAL_TOKEN", "")
ARTIFACT_DIR = Path(os.getenv("ML_ARTIFACT_DIR", "./artifacts"))
MIN_FEE_SAMPLES = int(os.getenv("ML_MIN_FEE_SAMPLES", "100"))
MIN_PERFORMANCE_SAMPLES = int(os.getenv("ML_MIN_PERFORMANCE_SAMPLES", "100"))
RETRAIN_INTERVAL_HOURS = int(os.getenv("ML_RETRAIN_INTERVAL_HOURS", "24"))

# --- Automated training lifecycle (all configurable via env) ----------------
# How often the scheduler checks for newly eligible data and trains if ready.
CHECK_INTERVAL_HOURS = int(os.getenv("ML_CHECK_INTERVAL_HOURS", "6"))
# How often a full eligibility sweep runs (also the retrain cadence fallback).
FULL_CHECK_INTERVAL_HOURS = int(os.getenv("ML_FULL_CHECK_INTERVAL_HOURS",
                                          str(RETRAIN_INTERVAL_HOURS)))
# Retrain once this many NEW eligible labeled records have accumulated since the
# currently active model was trained (even if the periodic cadence has not hit).
RETRAIN_NEW_RECORDS = int(os.getenv("ML_RETRAIN_NEW_RECORDS", "50"))
# Minimum share the minority class must reach for fee-risk to be trainable
# (guards against a degenerate all-one-class classifier). 0 disables the guard.
MIN_MINORITY_CLASS_FRACTION = float(os.getenv("ML_MIN_MINORITY_CLASS_FRACTION", "0.1"))
# Relative change in a feature's mean that counts as drift (0.5 = 50%).
DRIFT_MEAN_THRESHOLD = float(os.getenv("ML_DRIFT_MEAN_THRESHOLD", "0.5"))
# Transient-failure retry budget for the scheduler (exponential backoff).
SCHEDULER_MAX_RETRIES = int(os.getenv("ML_SCHEDULER_MAX_RETRIES", "3"))
SCHEDULER_BACKOFF_SECONDS = float(os.getenv("ML_SCHEDULER_BACKOFF_SECONDS", "2"))
