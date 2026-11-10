"""Vercel Python serverless entrypoint for the TaleemPlus ML service.

Vercel's Python runtime serves the module-level ``app`` (an ASGI application);
``../vercel.json`` rewrites every path to this function. Vercel does not reliably
emit ASGI lifespan events, so trained models are restored from the Hugging Face
Hub at cold start here instead of relying solely on FastAPI's lifespan.
"""
import os
import sys

# This file lives in ml_service/api/; add ml_service/ to the path so the sibling
# ``app`` package (ml_service/app) is importable.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import artifact_store, config  # noqa: E402
from app.main import app  # noqa: E402  — exposed to Vercel as the ASGI handler

# Cold-start restore into the writable /tmp artifact dir (ML_ARTIFACT_DIR). A
# restore hiccup must never prevent the service from serving /health or status.
try:
    artifact_store.pull(config.ARTIFACT_DIR)
except Exception:
    pass
