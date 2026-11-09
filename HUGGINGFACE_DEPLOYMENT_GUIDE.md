# Deploying the ML service to Hugging Face Spaces

Status: **prepared, not deployed** (you chose "prepare only"). The files were
assembled and the service was run locally with the Space's start command; the
container image itself was not built here (no Docker on this machine).

## Free tier facts that shape the design

| Constraint (CPU basic, free) | Consequence |
|---|---|
| 2 vCPU, 16 GB RAM | scikit-learn on academy-sized data fits comfortably |
| Sleeps after ~48 h without traffic; first request wakes it (tens of seconds) | backend timeout is 25 s; the admin screen may need one retry after a long idle period |
| Disk is **ephemeral** | trained artifacts are mirrored to a private HF model repo (`HF_ARTIFACT_REPO`) and restored at start-up |
| Public URL | every endpoint except `/health` requires `ML_INTERNAL_TOKEN`; only the backend has it |

Check current limits at https://huggingface.co/docs/hub/spaces-overview before
deploying; they can change.

## One-time setup

1. Create a write token: https://huggingface.co/settings/tokens
2. Create a **private model repo** for artifacts, e.g. `<you>/taleemplus-ml-artifacts`.
3. Create a Space: SDK **Docker**, hardware **CPU basic (free)**, e.g. `<you>/taleemplus-ml`.
4. Space → Settings → *Variables and secrets* → add **secrets**:
   `ML_INTERNAL_TOKEN`, `DATABASE_URL` (read-only role, see `ML_TRAINING_GUIDE.md` §5),
   `HF_TOKEN`, `HF_ARTIFACT_REPO`.

## Deploy

```powershell
pip install -U "huggingface_hub[cli]"
hf auth login                                   # paste the write token locally; never commit it
py ml_service/hf_space/prepare_space.py         # writes ml_service/hf_space/build (13 files)
hf upload <you>/taleemplus-ml ml_service/hf_space/build . --repo-type space
```

The build contains only `Dockerfile`, `README.md` (Space metadata, port 7860),
`requirements.txt` and `app/` — no tests, caches, artifacts or `.env` files.

## Verify (required before claiming it is deployed)

```powershell
curl https://<you>-taleemplus-ml.hf.space/health
# {"status":"ok","database":"connected"}
curl -H "Authorization: Bearer <ML_INTERNAL_TOKEN>" "https://<you>-taleemplus-ml.hf.space/models/status?academy_id=<an academy id>"
```

## Connect the backend (Vercel)

```powershell
vercel env add ML_SERVICE_URL production     # https://<you>-taleemplus-ml.hf.space
vercel env add ML_INTERNAL_TOKEN production  # same value as the Space secret
```

Redeploy the backend, then Admin → AI Insights should show a model status
instead of "ML service not available".
