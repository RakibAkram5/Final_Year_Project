"""Internal TaleemPlus ML API. Never returns raw training rows or identifiers."""
from contextlib import asynccontextmanager
import hashlib
import hmac
import math
import re
import threading
import json
from pathlib import Path
from datetime import datetime, timezone
from typing import Literal

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from app import config
from app.data.extractor import database_is_healthy, extract_fee_rows, extract_performance_rows
from app.models import load_production
from app.training.pipeline import InsufficientData, _atomic_json, train
from app.training.scheduler import start_scheduler, stop_scheduler
from app import artifact_store

@asynccontextmanager
async def lifespan(_app: FastAPI):
    # Restore trained models persisted on the Hugging Face Hub (no-op when
    # HF_ARTIFACT_REPO is not configured, e.g. locally).
    artifact_store.pull(config.ARTIFACT_DIR)
    start_scheduler()
    try:
        yield
    finally:
        stop_scheduler()


app = FastAPI(title="TaleemPlus ML Service", version="1.0.0", lifespan=lifespan)
_training: set[str] = set()
_training_errors: dict[str, str] = {}
_training_lock = threading.Lock()


class PredictRequest(BaseModel):
    academy_id: str = Field(min_length=1, max_length=128)
    features: dict[str, float | None]


class TrainRequest(BaseModel):
    academy_id: str = Field(min_length=1, max_length=128)


class RollbackRequest(BaseModel):
    academy_id: str = Field(min_length=1, max_length=128)
    model: Literal["fee-risk", "performance"]
    version: str = Field(min_length=1, max_length=64)


def _academy_key(academy_id: str) -> str:
    return hashlib.sha256(academy_id.encode()).hexdigest()


def internal_auth(authorization: str | None = Header(default=None)):
    if len(config.INTERNAL_TOKEN) < 32 or not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Internal service authentication required")
    if not hmac.compare_digest(authorization[7:], config.INTERNAL_TOKEN):
        raise HTTPException(status_code=401, detail="Invalid internal service credential")


def _status(model_name: str, academy_id: str):
    key = _academy_key(academy_id)
    state_key = f"{key}:{model_name}"
    if state_key in _training:
        return {"status": "TRAINING", "version": None}
    loaded = load_production(config.ARTIFACT_DIR, key, model_name)
    history_path = config.ARTIFACT_DIR / key / "history.jsonl"
    history = [json.loads(line) for line in history_path.read_text(encoding="utf-8").splitlines() if line] if history_path.exists() else []
    last_event = next((event for event in reversed(history) if event.get("model") == model_name), None)
    if loaded:
        result = {"status": "PRODUCTION", "version": loaded[1]["version"], "metadata": loaded[1]}
        if state_key in _training_errors or (last_event and last_event.get("status") == "TRAINING_FAILED"):
            result["last_training_error"] = _training_errors.get(state_key, "Training failed; check service diagnostics.")
        return result
    if last_event and last_event.get("status") == "TRAINING_FAILED":
        return {"status": "TRAINING_FAILED", "reason": "Training failed; check service diagnostics.", "version": None}
    versions = config.ARTIFACT_DIR / key / model_name
    if versions.exists():
        metadata_files = list(versions.glob("*/metadata.json"))
        if metadata_files:
            latest = max(metadata_files, key=lambda path: path.stat().st_mtime)
            metadata = json.loads(latest.read_text(encoding="utf-8"))
            return {"status": "VALIDATED", "version": metadata["version"], "metadata": metadata}
    if state_key in _training_errors:
        return {"status": "TRAINING_FAILED", "reason": _training_errors[state_key], "version": None}
    if not config.DATABASE_URL:
        return {"status": "NOT_READY", "reason": "DATABASE_URL is not configured", "version": None}
    try:
        rows = extract_fee_rows(config.DATABASE_URL, academy_id) if model_name == "fee-risk" else extract_performance_rows(config.DATABASE_URL, academy_id)
    except Exception:
        return {"status": "NOT_READY", "reason": "The academy data source is unavailable", "version": None}
    minimum = config.MIN_FEE_SAMPLES if model_name == "fee-risk" else config.MIN_PERFORMANCE_SAMPLES
    # Enough rows but nothing trained yet is not "insufficient data".
    state = "READY_TO_TRAIN" if len(rows) >= minimum else "INSUFFICIENT_DATA"
    return {"status": state, "usable_records": len(rows), "minimum_records": minimum, "version": None}


@app.get("/health")
def health():
    healthy = bool(config.DATABASE_URL) and database_is_healthy(config.DATABASE_URL)
    return {"status": "ok" if healthy else "degraded", "database": "connected" if healthy else "unavailable"}


@app.get("/models/status", dependencies=[Depends(internal_auth)])
def models_status(academy_id: str):
    return {"fee_risk": _status("fee-risk", academy_id), "performance": _status("performance", academy_id)}


@app.get("/models/metrics", dependencies=[Depends(internal_auth)])
def models_metrics(academy_id: str):
    return models_status(academy_id)


@app.get("/models/history", dependencies=[Depends(internal_auth)])
def models_history(academy_id: str):
    path = config.ARTIFACT_DIR / _academy_key(academy_id) / "history.jsonl"
    if not path.exists():
        return {"history": []}
    return {"history": [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]}


def _run_training(model_name: str, academy_id: str, state_key: str):
    """Runs extraction + training. Called in a worker thread, never inside an
    HTTP request: training time grows with data and must not hit the API's
    request timeout (Vercel functions are capped at 30 s)."""
    academy_key = _academy_key(academy_id)
    try:
        try:
            rows = extract_fee_rows(config.DATABASE_URL, academy_id) if model_name == "fee-risk" else extract_performance_rows(config.DATABASE_URL, academy_id)
        except Exception:
            _training_errors[state_key] = "The academy data source is unavailable."
            _append_training_event(academy_key, model_name, "NOT_READY", None)
            return
        minimum = config.MIN_FEE_SAMPLES if model_name == "fee-risk" else config.MIN_PERFORMANCE_SAMPLES
        try:
            train(model_name, rows, config.ARTIFACT_DIR, academy_key, minimum,
                  config.ARTIFACT_DIR / academy_key / "history.jsonl")
            artifact_store.push(config.ARTIFACT_DIR, f"trained {model_name}")
        except InsufficientData:
            _append_training_event(academy_key, model_name, "INSUFFICIENT_DATA", len(rows))
    except Exception:
        _training_errors[state_key] = "Training failed; check service diagnostics."
        _append_training_event(academy_key, model_name, "TRAINING_FAILED", None)
    finally:
        with _training_lock:
            _training.discard(state_key)


def _start_training(model_name: str, request: TrainRequest, background: bool = True):
    if not config.DATABASE_URL:
        raise HTTPException(503, {"status": "NOT_READY", "message": "ML database is not configured"})
    state_key = f"{_academy_key(request.academy_id)}:{model_name}"
    with _training_lock:
        if state_key in _training:
            raise HTTPException(409, {"status": "TRAINING", "message": "Training is already in progress"})
        _training.add(state_key)
    _training_errors.pop(state_key, None)
    if background:
        threading.Thread(target=_run_training, args=(model_name, request.academy_id, state_key),
                         name=f"train-{model_name}", daemon=True).start()
    else:
        _run_training(model_name, request.academy_id, state_key)
    return {"status": "TRAINING", "model": model_name,
            "message": "Training started. Poll /models/status for the result."}


def _append_training_event(academy_key: str, model_name: str, status: str, record_count: int | None):
    path = config.ARTIFACT_DIR / academy_key / "history.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    event = {"model": model_name, "status": status, "records": record_count,
             "at": datetime.now(timezone.utc).isoformat()}
    with path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(event) + "\n")


@app.post("/models/train/fee-risk", status_code=202, dependencies=[Depends(internal_auth)])
def train_fee(request: TrainRequest):
    return _start_training("fee-risk", request)


@app.post("/models/train/performance", status_code=202, dependencies=[Depends(internal_auth)])
def train_performance(request: TrainRequest):
    return _start_training("performance", request)


@app.post("/models/retrain", status_code=202, dependencies=[Depends(internal_auth)])
def retrain(request: TrainRequest):
    outcomes = {}
    for name, model_name in (("fee_risk", "fee-risk"), ("performance", "performance")):
        try:
            outcomes[name] = _start_training(model_name, request)
        except HTTPException as exc:
            detail = exc.detail if isinstance(exc.detail, dict) else {"message": str(exc.detail)}
            outcomes[name] = {"status": detail.get("status", "NOT_READY"), "message": detail.get("message")}
    return outcomes


@app.post("/models/rollback", dependencies=[Depends(internal_auth)])
def rollback(request: RollbackRequest):
    if not re.fullmatch(r"[A-Za-z0-9T-]+", request.version):
        raise HTTPException(422, "Invalid model version")
    key = _academy_key(request.academy_id)
    folder = config.ARTIFACT_DIR / key / request.model
    metadata_path = folder / request.version / "metadata.json"
    artifact_path = folder / request.version / "pipeline.joblib"
    if not metadata_path.is_file() or not artifact_path.is_file():
        raise HTTPException(404, "Model version was not found")
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if metadata.get("status") != "PRODUCTION" or metadata.get("model") != request.model:
        raise HTTPException(409, "Only a previously promoted model version can be restored")
    _atomic_json(folder / "production.json", {"version": request.version})
    artifact_store.push(config.ARTIFACT_DIR, f"rollback {request.model} to {request.version}")
    return {"status": "PRODUCTION", "version": request.version, "model": request.model}


def _predict(model_name: str, request: PredictRequest):
    loaded = load_production(config.ARTIFACT_DIR, _academy_key(request.academy_id), model_name)
    if not loaded:
        raise HTTPException(409, {"status": "NOT_READY", "message": "No validated production model is available"})
    model, metadata = loaded
    expected = metadata["features"]
    missing = [name for name in expected if name not in request.features]
    if missing:
        raise HTTPException(422, {"message": "Missing model features", "fields": missing})
    unknown = [name for name in request.features if name not in expected]
    if unknown:
        raise HTTPException(422, {"message": "Unknown model features", "fields": unknown})
    limits = {"attendance_pct": (0, 100), "late_count": (0, None),
              "delay_avg": (0, None), "consistency": (0, 1),
              "outstanding": (0, None), "prior_avg": (0, 100), "prior_count": (0, None)}
    for name, value in request.features.items():
        low, high = limits[name]
        if value is not None and (not math.isfinite(value) or value < low or (high is not None and value > high)):
            raise HTTPException(422, {"message": "Feature value is outside its valid range", "field": name})
    import pandas as pd
    row = {name: request.features[name] for name in expected}
    output = model.predict(pd.DataFrame([row]))[0]
    if model_name == "fee-risk":
        probability = float(model.predict_proba(pd.DataFrame([row]))[0, 1])
        category = "High Risk" if probability >= .7 else "Medium Risk" if probability >= .4 else "Low Risk"
        return {"version": metadata["version"], "probability": probability, "risk_category": category}
    return {"version": metadata["version"], "predicted_marks": float(max(0, min(100, output))), "uncertainty": None}


@app.post("/predict/fee-risk", dependencies=[Depends(internal_auth)])
def predict_fee(request: PredictRequest):
    return _predict("fee-risk", request)


@app.post("/predict/performance", dependencies=[Depends(internal_auth)])
def predict_performance(request: PredictRequest):
    return _predict("performance", request)
