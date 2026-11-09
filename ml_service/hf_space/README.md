---
title: TaleemPlus ML
emoji: 🎓
colorFrom: green
colorTo: blue
sdk: docker
app_port: 7860
pinned: false
license: mit
short_description: Fee-risk and performance models for TaleemPlus academies
---

# TaleemPlus ML service

Private prediction/training API used by the TaleemPlus backend. Every
endpoint except `GET /health` requires the `ML_INTERNAL_TOKEN` bearer token,
which only the TaleemPlus backend holds.

Configure these **Space secrets** (Settings → Variables and secrets):

| Secret | Purpose |
|---|---|
| `ML_INTERNAL_TOKEN` | ≥ 32 random characters; the same value as the backend's `ML_INTERNAL_TOKEN` |
| `DATABASE_URL` | **read-only** PostgreSQL connection string (Neon role with SELECT only) |
| `HF_TOKEN` | Hugging Face write token used to persist trained models |
| `HF_ARTIFACT_REPO` | private model repo for artifacts, e.g. `your-name/taleemplus-ml-artifacts` |

See `HUGGINGFACE_DEPLOYMENT_GUIDE.md` in the TaleemPlus repository.
