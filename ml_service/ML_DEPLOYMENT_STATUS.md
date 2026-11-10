# TaleemPlus ML — Deployment Status (Render + GitHub Actions + HF Hub)

_Implemented against the real repo; every test below was actually executed. No
deploy was performed, nothing was pushed to GitHub, no synthetic production data,
no hardcoded secrets. Budget respected: **PKR 0** (Render free + GitHub Actions free
+ HF Hub free storage + Neon free)._

Statuses: **PASS · FAIL · BLOCKED · NOT TESTED**

---

## 1. Files created
| File | Purpose |
|---|---|
| `render.yaml` (repo root) | Render Blueprint: Free web service, native Python 3.13, build/start, health check, env vars (secrets `sync:false`). |
| `.github/workflows/ml-monitor.yml` | Scheduled + manual health check and authorized eligibility-gated sweep; concurrency, timeouts, failure reporting, no secret leakage. |
| `ml_service/RENDER_DEPLOYMENT_GUIDE.md` | Exact Render steps, env vars, verification, troubleshooting, limits. |
| `ml_service/GITHUB_ACTIONS_SETUP.md` | Secrets, schedule, guarantees, security notes. |
| `ml_service/ML_DEPLOYMENT_STATUS.md` | This report. |

## 2. Files modified
| File | Change |
|---|---|
| `ml_service/app/main.py` | Added protected `POST /models/monitor` (eligibility-gated sweep for the cron); imported `run_eligibility_check`. No existing endpoint changed. |
| `taleemplus_backend/src/services/mlServiceClient.js` | Cold-start-aware timeout (default 60 s) + retry on 502/503/504/timeout + clean error mapping (no stack traces). |
| `ml_service/HF_PERSISTENCE_REPORT.md` | Hosting note: compute → Render, HF Hub stays the artifact store. |
| `ml_service/tests/test_api.py` | +2 tests for `/models/monitor` auth. |

> Preserved: `app.main:app` entry point, all prediction/training/status/rollback endpoints,
> `artifact_store.py`, the scheduler, the pipeline, and the Flutter/Node contract.

## 3. Architecture
```
Flutter (Android/Web)
  → Vercel (Node/Express backend, admin-auth, holds ML_INTERNAL_TOKEN)
    → Render Free Web Service (FastAPI ML, native Python 3.13, no Docker)
      → Neon PostgreSQL (READ-ONLY role taleemplus_ml_reader)
      → Hugging Face Hub model repo (durable artifacts; Render disk is ephemeral)
GitHub Actions (free cron, ~6h) → wakes Render + POST /models/monitor (eligibility-gated)
```

## 4. Render deployment (summary — full steps in RENDER_DEPLOYMENT_GUIDE.md)
- New → Blueprint (uses `render.yaml`) **or** New → Web Service, root `ml_service`, Free plan.
- Build `pip install -r requirements.txt`; Start `uvicorn app.main:app --host 0.0.0.0 --port $PORT`; Health `/health`.
- Set secrets in the dashboard; set Vercel `ML_SERVICE_URL` to the Render URL.

## 5. GitHub Actions setup (summary — full steps in GITHUB_ACTIONS_SETUP.md)
- Repo secrets: `ML_SERVICE_URL`, `ML_INTERNAL_TOKEN`.
- Runs every ~6 h + manual dispatch; health-check with cold-start retry → `POST /models/monitor`.

## 6. Environment variables & where to set them
| Variable | Render | Vercel backend | GitHub secret |
|---|:--:|:--:|:--:|
| `ML_INTERNAL_TOKEN` | ✅ (secret) | ✅ | ✅ |
| `ML_SERVICE_URL` | — | ✅ (Render URL) | ✅ |
| `DATABASE_URL` (ml_reader) | ✅ (secret) | — | — |
| `HF_TOKEN` / `HF_REPO_ID` | ✅ (secret) | — | — |
| `HF_REPO_TYPE=model`, `HF_MAX_RETRIES=3`, `HF_BACKOFF_SECONDS=2` | ✅ | — | — |
| `ML_TIMEOUT_MS` (≤ Vercel maxDuration), `ML_MAX_RETRIES` | — | optional | — |

## 7. Test results (actual outputs)
```
# Python
python -m compileall app scripts tests   -> compile OK
python -m pytest -q                       -> 53 passed
    18 original + 9 monitoring + 9 scheduler + 15 artifact_store + 2 api(monitor)

# Node
node --check src/services/mlServiceClient.js   -> OK
npx jest tests/mlServiceClient.test.js         -> 2 passed

# Live smoke (uvicorn app.main:app --host 0.0.0.0 --port … , Render start cmd)
GET  /health                              -> 200 {"status":"degraded","database":"unavailable"}
POST /models/monitor (no token)           -> 401
POST /models/monitor (valid token)        -> 202 {"status":"MONITORING", ...}
```

### Test classification
| Type | Items | Status |
|---|---|---|
| Unit | monitoring, pipeline, scheduler decisions, pointer/atomic writes | **PASS** |
| Mocked integration | HF push/pull/retry/integrity/persist-revert (fake hub) | **PASS (mocked)** |
| Live local | uvicorn boot, `/health`, `/models/monitor` auth, scheduler start/shutdown | **PASS** |
| Real integration — HF Hub round-trip | real upload/download on Render | **BLOCKED** (needs real creds + deploy) |
| Real integration — read-only DB perms | `taleemplus_ml_reader` write-denial | **BLOCKED** (role not created yet) |
| Deployment — Render live | build/boot on Render | **NOT TESTED** (deploy requires your approval) |
| Deployment — GitHub Actions live | scheduled run hitting Render | **NOT TESTED** (needs repo secrets + deploy) |

## 8. Component status
| Component | Status | Note |
|---|---|---|
| Render config (`render.yaml`, native Python, no Docker) | **PASS (config)** / deploy **NOT TESTED** | start cmd boots locally; Render run pending approval |
| FastAPI startup + `/health` bind `0.0.0.0:$PORT` | **PASS** | verified locally |
| Artifact restore + integrity on startup | **PASS (logic)** / real restore **BLOCKED** | lifespan pull→verify→scheduler verified; real Hub pending |
| `/models/monitor` protected endpoint | **PASS** | 401 without / 202 with token (unit + live) |
| Duplicate/concurrent training prevention | **PASS** | sweep lock + per-job lock (tested) |
| Eligibility gating (no forced training) | **PASS** | monitor runs `run_eligibility_check` |
| Academy isolation | **PASS (query layer)** | every query `academyId`-scoped; **no DB RLS** (documented) |
| HF persistence (upload/restore/retry/revert) | **PASS (mocked)** / real **BLOCKED** | see `HF_PERSISTENCE_REPORT.md` |
| Read-only DB role | **BLOCKED** | `taleemplus_ml_reader` not yet created (see `POSTGRESQL_SETUP_REPORT.md`) |
| Node timeout/retry for cold starts | **PASS** | default 60 s + retry; tests green |
| GitHub Actions workflow | **PASS (config)** / live **NOT TESTED** | YAML lint clean (no tabs); run pending secrets+deploy |
| Real training data | **BLOCKED (INSUFFICIENT DATA)** | DB near-empty; models correctly stay `INSUFFICIENT_DATA` |

## 9. Remaining manual steps
1. Create `taleemplus_ml_reader` (read-only) on Neon — `scripts/create_ml_readonly_user.sql`.
2. Create a **private** HF model repo + write token.
3. Deploy to Render (Blueprint or Web Service), set the secrets.
4. Set Vercel `ML_SERVICE_URL` to the Render URL (and optionally `ML_TIMEOUT_MS`).
5. Add GitHub secrets `ML_SERVICE_URL`, `ML_INTERNAL_TOKEN`; the workflow then runs.
6. Verify the **real** HF round-trip (train → files appear in repo → restart Render → model restored).
7. Enter real academy data until eligibility thresholds are met.
8. (Approval needed) push these files to GitHub.

## 10. Known limitations (honest)
- **Not 24/7**: Render free sleeps after 15 min; cold start 30–60 s. Cron + client retries mitigate, don't eliminate. GitHub cron timing is best-effort.
- **512 MB RAM**: large training jobs can OOM on free hardware.
- **Ephemeral disk**: durability depends entirely on HF Hub being configured.
- **No DB-level RLS**: tenant isolation is enforced in query code, not the database.
- **Vercel ↔ Render timeout**: `ML_TIMEOUT_MS` must stay within the Vercel function `maxDuration`.

## 11. Production readiness assessment
**NOT production-ready yet — code-complete and tested, deployment-blocked.**
Per the rule "do not mark production-ready if real HF persistence, read-only DB access,
authentication, or deployment verification remains incomplete": authentication is **PASS**, but
**real HF persistence (BLOCKED)**, **read-only DB role (BLOCKED)**, and **live Render/Actions
deployment (NOT TESTED)** are outstanding. The config and code are complete, 53+2 tests pass, and
the service boots and authenticates locally — it becomes production-ready once steps 1–7 above are
done and verified.
