# Render Deployment Guide — TaleemPlus ML Service (Free, No Docker)

Deploys the existing FastAPI ML service to a **Render Free Web Service** using
Render's **native Python runtime** (no Docker). Budget: **PKR 0**.

```
Flutter → Vercel (Node) → Render Free Web Service (FastAPI) → Neon (read-only)
                                   └── artifacts → Hugging Face Hub (free storage)
GitHub Actions (free cron) → wakes Render + triggers an eligibility-gated sweep
```

## Why Render (and not HF Spaces)
Hugging Face now requires a **paid plan to create a compute-backed Space** (Gradio/Docker);
only **Static** Spaces are free, and those cannot run Python. So **compute** moves to
Render's free tier, while the **Hugging Face model repo stays as the (free) artifact store**.

## Render free-tier facts (verify on render.com/docs before relying on them)
- **No credit card** required to start a Free Web Service.
- **512 MB RAM**, fractional CPU, **no persistent disk** → artifacts MUST live on HF Hub (they do).
- **Sleeps after ~15 min** of no inbound traffic; **cold start ~30–60 s**.
- **750 instance-hours/month** shared per workspace.
- Native Python runtime supports **Python 3.13** (pinned in `render.yaml`).
> 512 MB is tight. Training tiny datasets (our 100–500 row thresholds) should fit, but large
> academies could OOM. If training is killed, upgrade that one service to a paid instance later —
> not required to start.

## Files (already in the repo)
- `render.yaml` (repo root) — Blueprint: web service, Python 3.13, build/start, health check, env vars.
- Entry point: **existing** `app.main:app` (unchanged).

## One-time prerequisites
1. **Read-only DB role** `taleemplus_ml_reader` created on Neon (see `POSTGRESQL_SETUP_REPORT.md`). Its connection string = `DATABASE_URL`.
2. **Private HF model repo** + a **write token** (see `HF_PERSISTENCE_REPORT.md`).
3. The shared **`ML_INTERNAL_TOKEN`** (same value already in the Vercel backend `.env`).

## Deploy (choose one)
### A) Blueprint (uses `render.yaml`)
1. Push this repo to GitHub (your call — not done automatically).
2. Render dashboard → **New → Blueprint** → select the repo. Render reads `render.yaml`.
3. When prompted, fill the `sync: false` secrets (below). Create resources.

### B) Manual Web Service (no Blueprint)
1. Render → **New → Web Service** → connect repo.
2. **Root Directory**: `ml_service` · **Runtime**: Python 3 · **Plan**: Free.
3. **Build**: `pip install -r requirements.txt`
4. **Start**: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`
5. **Health Check Path**: `/health`
6. Add the env vars below.

## Environment variables (set in Render dashboard — never in git)
| Key | Value | Notes |
|---|---|---|
| `PYTHON_VERSION` | `3.13.4` | pinned (in `render.yaml`) |
| `ML_INTERNAL_TOKEN` | *(secret)* | same value as the Vercel backend |
| `DATABASE_URL` | *(secret)* | `taleemplus_ml_reader` **read-only** Neon URL (direct host, `sslmode=require`) |
| `HF_TOKEN` | *(secret)* | Hugging Face **write** token |
| `HF_REPO_ID` | *(secret)* | e.g. `your-name/taleemplus-ml-artifacts` (**private**) |
| `HF_REPO_TYPE` | `model` | in `render.yaml` |
| `HF_MAX_RETRIES` / `HF_BACKOFF_SECONDS` | `3` / `2` | in `render.yaml` |
| `ML_ARTIFACT_DIR` | `/tmp/ml_artifacts` | ephemeral; HF Hub is the durable store |

## Verify after deploy
1. **Health**: `curl https://<svc>.onrender.com/health` → `{"status":"ok"|"degraded",...}` (200).
2. **Auth**: `curl https://<svc>.onrender.com/models/status?academy_id=x` → **401** (no token).
   With `-H "Authorization: Bearer <ML_INTERNAL_TOKEN>"` → **200**.
3. **Artifacts restore**: check logs on boot — `pull` runs, then integrity check; no integrity warnings.
4. **Point the backend at it**: set Vercel env `ML_SERVICE_URL=https://<svc>.onrender.com`.

## Cold starts & the Vercel timeout
Render may cold-start (~30–60 s). The Node client (`mlServiceClient.js`) now defaults
`ML_TIMEOUT_MS=60000` and retries transient 502/503/504/timeout once. **Important:** keep
`ML_TIMEOUT_MS` within the Vercel function's `maxDuration`, or Vercel cancels the request first.
The GitHub Actions cron also wakes the service periodically.

## Troubleshooting
| Symptom | Cause / fix |
|---|---|
| Build fails on a dependency | Confirm `PYTHON_VERSION=3.13.4`; 3.15 lacks some wheels. |
| `/health` 200 but `database: unavailable` | `DATABASE_URL` missing/invalid, or role lacks `CONNECT`. |
| `503 No validated production model` on predict | Expected until a model is trained (data is currently insufficient). |
| First request after idle times out | Cold start; retry (client auto-retries once). Keep-warm via the cron. |
| Training killed mid-run | 512 MB OOM or 15-min sleep during a long train — only a risk with large data. |
| `401` on every call | `ML_INTERNAL_TOKEN` not set on Render, or differs from the backend's. |

## Free-tier limitations (honest)
- **Not 24/7**: sleeps when idle; cold starts happen. The cron + client retries mitigate, they don't eliminate.
- **512 MB RAM** can OOM on large training jobs.
- **Ephemeral disk**: durability depends entirely on HF Hub persistence being configured.
