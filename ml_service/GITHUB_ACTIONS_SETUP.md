# GitHub Actions Setup — ML Monitor & Retrain

Workflow: `.github/workflows/ml-monitor.yml`. It wakes the (free, sleeping) Render
ML service and triggers an **eligibility-gated** monitoring sweep that trains only
models meeting their thresholds — it never blindly forces or duplicates training.

## What it does
1. **Health check** — `GET /health`, retrying up to 6×20 s to tolerate Render cold start.
2. **Authorized sweep** — `POST /models/monitor` with the internal bearer token. That
   endpoint runs the same eligibility logic as the in-process scheduler (min-sample +
   new-record thresholds, class balance, per-academy isolation, promotion gate) in the
   background and returns `202`.

## Schedule & guarantees
- Runs `cron: "0 */6 * * *"` (~every 6 h) **plus** manual `workflow_dispatch`.
- **GitHub cron is best-effort** — runs can be delayed or skipped under load. This does
  **not** guarantee 24/7 uptime or exact timing, and it is not a keep-warm for every minute.
- `concurrency.group: ml-monitor` + `cancel-in-progress: false` prevents overlapping runs.
- `timeout-minutes: 10` caps each run.

## Required GitHub repository secrets
Settings → Secrets and variables → Actions → **New repository secret**:

| Secret | Value |
|---|---|
| `ML_SERVICE_URL` | Your Render URL, e.g. `https://taleemplus-ml.onrender.com` |
| `ML_INTERNAL_TOKEN` | The **same** internal token configured on Render and the Vercel backend |

> Secrets are injected as env vars and **auto-masked** in logs. The workflow sends the token
> only as an `Authorization` header and never echoes it. No secret is committed.

## Run it
- **Manual**: Actions tab → *ML Monitor & Retrain* → **Run workflow** (toggle `run_monitor`).
- **Scheduled**: automatic every ~6 h once the file is on the default branch.

## Tuning
- More frequent checks: change the cron (e.g. `"0 */3 * * *"`). Mind GitHub Actions minutes
  on **private** repos (2000 min/month free); public repos are unlimited.
- The service-side cadence is independent and also configurable (`ML_CHECK_INTERVAL_HOURS`).

## Failure reporting
- Any non-2xx health or trigger response emits `::error::` and **fails the job** (visible in the
  Actions tab / email). It never marks a failed trigger as success.

## Security notes
- The workflow calls the Render service **directly** with the internal token (service-to-service),
  not through the public backend. The token authorizes only internal ML endpoints.
- `permissions: contents: read` — the workflow needs no write scope.
