"""Versioned training with minimum-sample and temporal validation safeguards."""
from datetime import datetime, timezone
import json
import hashlib
import os
from pathlib import Path
import tempfile
import uuid

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import (GradientBoostingClassifier, GradientBoostingRegressor,
                              RandomForestClassifier, RandomForestRegressor)
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression, LinearRegression
from sklearn.metrics import (accuracy_score, confusion_matrix, f1_score,
                             mean_absolute_error, mean_squared_error,
                             precision_score, r2_score, recall_score,
                             roc_auc_score, average_precision_score)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

FEE_FEATURES = ["attendance_pct", "late_count", "delay_avg", "consistency", "outstanding"]
PERFORMANCE_FEATURES = ["prior_avg", "prior_count", "attendance_pct"]


class InsufficientData(ValueError):
    pass


def _time_split(frame: pd.DataFrame, date_column: str):
    dates = sorted(frame[date_column].dropna().unique())
    if len(dates) < 2:
        raise InsufficientData("Chronological validation requires at least two distinct dates")
    # Choose the date boundary whose training share is closest to 80% of ROWS
    # (not 80% of distinct dates): with few dates, a date-count quantile can
    # leave only the single latest day in the holdout. Still strictly
    # chronological: every training row precedes every validation row.
    counts = frame[date_column].value_counts()
    total = float(counts.sum())
    before, best, best_gap = 0.0, 1, None
    for index in range(1, len(dates)):
        before += counts[dates[index - 1]]
        gap = abs(before / total - .8)
        if best_gap is None or gap <= best_gap:
            best, best_gap = index, gap
    cutoff = dates[best]
    return frame[frame[date_column] < cutoff], frame[frame[date_column] >= cutoff]


def _feature_stats(frame: pd.DataFrame, features: list[str]) -> dict:
    """mean/std/missing per feature, stored in metadata for drift comparison."""
    stats = {}
    total = len(frame)
    for name in features:
        column = pd.to_numeric(frame[name], errors="coerce") if name in frame else pd.Series(dtype=float)
        present = column.dropna()
        stats[name] = {
            "mean": float(present.mean()) if not present.empty else None,
            "std": float(present.std(ddof=0)) if len(present) > 1 else 0.0,
            "missing_fraction": round((total - len(present)) / total, 4) if total else 0.0,
            "count": int(len(present)),
        }
    return stats


def _atomic_json(path: Path, data: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(data, stream, indent=2, default=str)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def train(model_name: str, rows: list[dict], artifact_root: Path, academy_key: str,
          minimum: int = 100, history_file: Path | None = None):
    if len(rows) < minimum:
        raise InsufficientData(f"Need at least {minimum} usable labeled records; found {len(rows)}")
    df = pd.DataFrame(rows)
    fingerprint = hashlib.sha256(
        df.sort_index(axis=1).to_json(orient="records", date_format="iso").encode("utf-8")
    ).hexdigest()
    production_dir = artifact_root / academy_key / model_name
    pointer = production_dir / "production.json"
    if pointer.exists():
        production = json.loads(pointer.read_text(encoding="utf-8"))["version"]
        production_meta_path = production_dir / production / "metadata.json"
        if production_meta_path.exists():
            production_meta = json.loads(production_meta_path.read_text(encoding="utf-8"))
            if production_meta.get("data_fingerprint") == fingerprint:
                return {**production_meta, "retrained": False}
    if model_name == "fee-risk":
        features, target = FEE_FEATURES, "label"
        if target not in df or df[target].nunique() < 2:
            raise InsufficientData("Fee labels must contain both on-time and late classes")
        train_df, valid_df = _time_split(df, "issue_date")
        if valid_df.empty or valid_df[target].nunique() < 2:
            raise InsufficientData("Temporal validation requires both classes in holdout")
        prep = ColumnTransformer([("numeric", Pipeline([("impute", SimpleImputer(strategy="median")), ("scale", StandardScaler())]), features)])
        candidates = [("logistic-regression", LogisticRegression(class_weight="balanced", max_iter=2000)),
                      ("random-forest", RandomForestClassifier(n_estimators=300, class_weight="balanced", random_state=41)),
                      ("gradient-boosting", GradientBoostingClassifier(random_state=41))]
        Xtr, ytr = train_df[features], train_df[target].astype(int)
        Xv, yv = valid_df[features], valid_df[target].astype(int)
        results = []
        for name, estimator in candidates:
            model = Pipeline([("preprocess", prep), ("model", estimator)])
            model.fit(Xtr, ytr)
            prob = model.predict_proba(Xv)[:, 1]
            pred = (prob >= .5).astype(int)
            metrics = {"roc_auc": float(roc_auc_score(yv, prob)), "pr_auc": float(average_precision_score(yv, prob)),
                       "precision": float(precision_score(yv, pred, zero_division=0)),
                       "recall": float(recall_score(yv, pred, zero_division=0)), "f1": float(f1_score(yv, pred, zero_division=0)),
                       "accuracy": float(accuracy_score(yv, pred)), "confusion_matrix": confusion_matrix(yv, pred).tolist()}
            results.append((metrics["roc_auc"], name, estimator, metrics))
        _, selected, estimator, metrics = max(results, key=lambda item: item[0])
        final = Pipeline([("preprocess", prep), ("model", estimator)]).fit(df[features], df[target].astype(int))
        metric_payload = {"selected": selected, "metrics": metrics, "candidates": [{"name": n, "metrics": m} for _, n, _, m in results]}
    elif model_name == "performance":
        features, target = PERFORMANCE_FEATURES, "target"
        train_df, valid_df = _time_split(df, "target_date")
        if len(train_df) < 2 or len(valid_df) < 2:
            raise InsufficientData("Chronological validation needs at least 10 usable target rows")
        prep = ColumnTransformer([("numeric", Pipeline([("impute", SimpleImputer(strategy="median")), ("scale", StandardScaler())]), features)])
        candidates = [("linear-regression", LinearRegression()), ("random-forest", RandomForestRegressor(n_estimators=300, random_state=41)),
                      ("gradient-boosting", GradientBoostingRegressor(random_state=41))]
        results = []
        for name, estimator in candidates:
            model = Pipeline([("preprocess", prep), ("model", estimator)])
            model.fit(train_df[features], train_df[target])
            pred = model.predict(valid_df[features])
            rmse = float(np.sqrt(mean_squared_error(valid_df[target], pred)))
            results.append((rmse, name, estimator, {"mae": float(mean_absolute_error(valid_df[target], pred)), "rmse": rmse, "r2": float(r2_score(valid_df[target], pred))}))
        _, selected, estimator, metrics = min(results, key=lambda item: item[0])
        final = Pipeline([("preprocess", prep), ("model", estimator)]).fit(df[features], df[target])
        metric_payload = {"selected": selected, "metrics": metrics, "candidates": [{"name": n, "metrics": m} for _, n, _, m in results]}
    else:
        raise ValueError("Unknown model name")

    version = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    directory = artifact_root / academy_key / model_name / version
    directory.mkdir(parents=True, exist_ok=False)
    joblib.dump(final, directory / "pipeline.joblib")
    meta = {"version": version, "model": model_name, "algorithm": selected, "status": "VALIDATED",
            "trained_at": datetime.now(timezone.utc).isoformat(), "records": len(df), "features": features,
            "metrics": metric_payload, "schema_version": 1, "data_fingerprint": fingerprint,
            "feature_stats": _feature_stats(df, features), "retrained": True}
    _atomic_json(directory / "metadata.json", meta)
    # Conservative production gate: require useful validation over a constant baseline.
    if model_name == "fee-risk":
        promote = metrics["roc_auc"] >= .60 and metrics["f1"] > 0
        incumbent = _incumbent(artifact_root, academy_key, model_name)
        if incumbent:
            old_prob = incumbent.predict_proba(Xv)[:, 1]
            promote = promote and metrics["roc_auc"] >= roc_auc_score(yv, old_prob)
    else:
        baseline = float(np.sqrt(mean_squared_error(valid_df[target], np.repeat(train_df[target].mean(), len(valid_df)))))
        promote = metrics["rmse"] < baseline
        incumbent = _incumbent(artifact_root, academy_key, model_name)
        if incumbent:
            old_pred = incumbent.predict(valid_df[features])
            old_rmse = float(np.sqrt(mean_squared_error(valid_df[target], old_pred)))
            promote = promote and metrics["rmse"] <= old_rmse
            meta_baseline = {"production_rmse": old_rmse}
        else:
            meta_baseline = {}
        meta["metrics"]["baseline_rmse"] = baseline
        meta["metrics"].update(meta_baseline)
        _atomic_json(directory / "metadata.json", meta)
    if promote:
        _atomic_json(artifact_root / academy_key / model_name / "production.json", {"version": version})
        meta["status"] = "PRODUCTION"
        _atomic_json(directory / "metadata.json", meta)
    if history_file:
        history_file.parent.mkdir(parents=True, exist_ok=True)
        with history_file.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(meta) + "\n")
    return meta


def _incumbent(artifact_root: Path, academy_key: str, model_name: str):
    pointer = artifact_root / academy_key / model_name / "production.json"
    if not pointer.exists():
        return None
    version = json.loads(pointer.read_text(encoding="utf-8"))["version"]
    artifact = artifact_root / academy_key / model_name / version / "pipeline.joblib"
    return joblib.load(artifact) if artifact.exists() else None
