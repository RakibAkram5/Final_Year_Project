"""Data-availability monitoring, training-readiness decisions, and basic drift.

Pure functions (no I/O) so they are cheap to unit-test. The scheduler and the
dashboard API call these to decide *whether* to train and to surface honest
counts. Nothing here fabricates data or metrics.
"""
from __future__ import annotations

from statistics import fmean, pstdev

from app.training.pipeline import FEE_FEATURES, PERFORMANCE_FEATURES

# Lifecycle data-states (distinct from the model's deployment status).
INSUFFICIENT_DATA = "INSUFFICIENT_DATA"
READY_TO_TRAIN = "READY_TO_TRAIN"
WAITING_FOR_DATA = "WAITING_FOR_DATA"


def _features_for(model_name: str) -> list[str]:
    return FEE_FEATURES if model_name == "fee-risk" else PERFORMANCE_FEATURES


def class_balance(rows: list[dict]) -> dict:
    """Late/on-time counts and minority-class share for the fee-risk label."""
    late = sum(1 for r in rows if r.get("label") == 1)
    ontime = sum(1 for r in rows if r.get("label") == 0)
    total = late + ontime
    minority = min(late, ontime) / total if total else 0.0
    return {"late": late, "ontime": ontime, "minority_fraction": round(minority, 4),
            "both_classes_present": late > 0 and ontime > 0}


def feature_distribution(rows: list[dict], features: list[str]) -> dict:
    """mean / std / missing-share per feature over the usable rows."""
    stats: dict = {}
    n = len(rows)
    for name in features:
        values = [r[name] for r in rows if r.get(name) is not None]
        missing = (n - len(values)) / n if n else 0.0
        stats[name] = {
            "mean": round(fmean(values), 6) if values else None,
            "std": round(pstdev(values), 6) if len(values) > 1 else 0.0,
            "missing_fraction": round(missing, 4),
            "count": len(values),
        }
    return stats


def detect_drift(previous: dict | None, current: dict, threshold: float) -> dict:
    """Flag features whose mean shifted by more than ``threshold`` (relative)."""
    if not previous:
        return {"drifted": False, "reason": "no_baseline", "features": []}
    drifted = []
    details = {}
    for name, cur in current.items():
        prev = previous.get(name) or {}
        pm, cm = prev.get("mean"), cur.get("mean")
        if pm is None or cm is None:
            continue
        rel = abs(cm - pm) / max(abs(pm), 1e-9)
        details[name] = round(rel, 4)
        if rel > threshold:
            drifted.append(name)
    return {"drifted": bool(drifted), "features": drifted, "relative_shift": details}


def evaluate_eligibility(model_name: str, rows: list[dict], minimum: int,
                         last_trained_records: int | None,
                         new_record_threshold: int,
                         min_minority_fraction: float = 0.0) -> dict:
    """Decide the data-state and whether a (re)train should start now.

    ``last_trained_records`` is the record count of the currently ACTIVE model
    (None when none is deployed yet).
    """
    usable = len(rows)
    result: dict = {
        "model": model_name,
        "eligible_records": usable,
        "required_records": minimum,
        "new_records_since_training": (None if last_trained_records is None
                                       else max(0, usable - last_trained_records)),
        "should_train": False,
        "data_state": INSUFFICIENT_DATA,
        "reason": "",
    }

    if usable < minimum:
        result["reason"] = f"{usable}/{minimum} eligible records; need {minimum - usable} more."
        return result

    if model_name == "fee-risk":
        balance = class_balance(rows)
        result["class_balance"] = balance
        if not balance["both_classes_present"]:
            result["reason"] = "Only one payment class present; need both late and on-time."
            return result
        if min_minority_fraction and balance["minority_fraction"] < min_minority_fraction:
            result["reason"] = (f"Class imbalance too severe "
                                f"(minority {balance['minority_fraction']:.2f} "
                                f"< {min_minority_fraction:.2f}).")
            return result

    # Enough valid data + acceptable balance. Decide train-now vs wait.
    if last_trained_records is None:
        result.update(should_train=True, data_state=READY_TO_TRAIN,
                      reason="No active model yet; eligible to train the first one.")
        return result

    delta = usable - last_trained_records
    if delta >= new_record_threshold:
        result.update(should_train=True, data_state=READY_TO_TRAIN,
                      reason=f"{delta} new eligible records since last training "
                             f"(>= {new_record_threshold}); retraining.")
    else:
        need = new_record_threshold - max(0, delta)
        result.update(should_train=False, data_state=WAITING_FOR_DATA,
                      reason=f"Active model present; {max(0, delta)} new records, "
                             f"{need} more needed to retrain.")
    return result


def summarize(model_name: str, rows: list[dict], minimum: int,
              last_trained_records: int | None, new_record_threshold: int,
              min_minority_fraction: float = 0.0) -> dict:
    """Eligibility + current feature distribution in one payload (for dashboard)."""
    elig = evaluate_eligibility(model_name, rows, minimum, last_trained_records,
                                new_record_threshold, min_minority_fraction)
    elig["feature_distribution"] = feature_distribution(rows, _features_for(model_name))
    return elig
