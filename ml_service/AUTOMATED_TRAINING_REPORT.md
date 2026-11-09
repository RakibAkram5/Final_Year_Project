# TaleemPlus ML — Automated Training Lifecycle Report

_Independently verified against the real repository, with all tests executed.
No training results, metrics, or data were fabricated; no privileged DB operation
was run; the read-only ML account was never granted write access._

Legend: **PASS** (implemented + tested) · **CODE-ONLY** (implemented, not live-tested)
· **BLOCKED-HOST** (limited by free hosting) · **INSUFFICIENT DATA** · **MANUAL** (needs your config).

---

## Outcome in one line
You enter data into TaleemPlus normally; the ML service now **monitors eligibility,
trains when enough real data exists, evaluates, and promotes only validated models —
automatically**, with no manual commands. Until real data accumulates it correctly
stays `INSUFFICIENT_DATA` and trains nothing.

---

## What was added / changed (existing working code preserved)

| File | Type | Purpose |
|---|---|---|
| `app/state.py` | **new** | One shared lock + in-progress set for API **and** scheduler → no duplicate/concurrent training. |
| `app/monitoring.py` | **new** | Pure functions: eligibility decision, class-balance, feature distribution, drift detection. |
| `app/training/scheduler.py` | **rewritten** | 6h eligibility check + daily sweep, startup catch-up, retry/backoff, per-attempt history, drift alerts. Backward-compatible `retrain_all()` kept. |
| `app/training/pipeline.py` | **additive** | Stores `feature_stats` in model metadata (drift baseline). Training logic unchanged. |
| `app/main.py` | **additive** | Uses shared state; new `GET /models/dashboard`; lifecycle labels. All old endpoints/behaviour unchanged. |
| `app/config.py` | **additive** | New env-configurable thresholds (all have safe defaults). |
| `tests/test_monitoring.py`, `tests/test_scheduler.py` | **new** | 16 new tests. |
| `taleemplus_backend/src/{routes,controllers}` | **additive** | `GET /api/v2/admin/ml/dashboard` passthrough (admin-only). |

No endpoints renamed, no models/artifacts deleted, Flutter contract unchanged.

---

## 1. Automatic data monitoring — **PASS**
- `monitoring.evaluate_eligibility()` counts usable records, tracks **new records since the active model** (`eligible − active_model.records`), and returns a data-state.
- Re-processing avoidance: the pipeline's existing `data_fingerprint` skips identical-data retrains; the scheduler additionally gates on the new-records threshold. Verified by `test_no_retrain_without_enough_new_data`.
- Academy isolation: every query is `academyId`-scoped; artifacts keyed by SHA-256(academy_id). Verified by `test_academy_isolation_only_touches_its_own_folder`.
- Invalid/unlabeled rows excluded from class counts (`test_class_balance_ignores_unlabeled_rows`); leakage prevention lives in the extractor SQL (unchanged, already time-bounded).

## 2. Automatic training scheduler — **PASS (logic) / BLOCKED-HOST (24×7 execution)**
- Two APScheduler jobs: `eligibility_check` every `ML_CHECK_INTERVAL_HOURS` (6) and `full_sweep` every `ML_FULL_CHECK_INTERVAL_HOURS` (24). `max_instances=1`, `coalesce=True`.
- Duplicate prevention: shared `state` lock (`test_duplicate_training_is_prevented`).
- Job status + history persisted to the **artifact store** (`history.jsonl` + HF Hub), **not Postgres** — see §7 for why. Statuses recorded: TRAINING, INSUFFICIENT_DATA, NOT_READY, TRAINING_FAILED, DRIFT_ALERT.
- **Host limitation:** on free hosting the service **sleeps**, so timers don't fire while asleep. Mitigation implemented: **startup catch-up** job + `coalesce` + generous `misfire_grace_time`, so it re-evaluates immediately on wake. This is honest — it is *not* guaranteed continuous background execution.

## 3. Data thresholds & readiness — **PASS**
- Separate env thresholds per model (`ML_MIN_FEE_SAMPLES`, `ML_MIN_PERFORMANCE_SAMPLES`, both 100).
- Fee-risk: requires **both** classes and a minimum minority share (`ML_MIN_MINORITY_CLASS_FRACTION`, 0.1). Verified (`test_single_class…`, `test_severe_class_imbalance…`).
- Performance: time-based validation (unchanged pipeline), leakage-safe extractor.
- Insufficient data → `INSUFFICIENT_DATA` with an explicit shortfall message; keeps monitoring. Never trains a meaningless model.

## 4. Automatic training — **PASS**
- Reuses the existing multi-algorithm pipeline (LogReg/RF/GB for fee; Linear/RF/GB for performance), preprocessing, imputation, validation.
- Records algorithm, version, dataset fingerprint, `records`, metrics, and now `feature_stats`. Active model never overwritten (new versioned dir; pointer moves only on promotion). Verified `test_process_model_trains_and_promotes_first_model`.

## 5. Evaluation & automatic deployment — **PASS**
- Existing promotion gate retained: fee-risk promotes only if ROC-AUC ≥ 0.60 **and** ≥ incumbent; performance promotes only if RMSE < baseline **and** ≤ incumbent. Worse models are rejected; previous model stays active and is rollback-able. (Covered by existing `test_failed_candidate_does_not_move_production_pointer` + training tests.)
- No unvalidated model is ever activated (status gated `VALIDATED`→`PRODUCTION`).

## 6. Scheduling reliability — **PASS (code) / BLOCKED-HOST (while asleep)**
- Starts with the service (lifespan) — **verified live** (`running: true`, next check scheduled).
- Restart recovery + graceful shutdown verified (`test_scheduler_starts_and_shuts_down_cleanly`).
- Transient DB failures retry with exponential backoff (`ML_SCHEDULER_MAX_RETRIES`, `…_BACKOFF_SECONDS`); failure recorded as NOT_READY, never silently “successful” (`test_data_source_failure_records_not_ready`).
- Does not block FastAPI requests (training runs off the request path).

## 7. Academy isolation & security — **PASS (design) / MANUAL (role) / documented risk**
- Reads only via the dedicated read-only account (`taleemplus_ml_reader`); scheduler writes **nothing** to Postgres.
- **Why job metadata is NOT in Postgres:** the ML account is intentionally read-only, and granting it write access would violate the security model. Job status/history therefore persists to the artifact store (HF Hub). If you later want it in Postgres, do it through the **backend's** authorized write API or a *separate* narrowly-privileged role — never by widening `taleemplus_ml_reader`.
- **Documented risk (no RLS):** the DB does not enforce row-level academy isolation. Isolation relies on every query filtering `academyId` — which is true in all verified extractor/scheduler/Node paths — but a future query that forgets the filter would not be stopped by the DB. RLS is optional future hardening.
- Secrets stay server-side; Flutter never receives DB creds or `ML_INTERNAL_TOKEN`.
- **`taleemplus_ml_reader` write-denial: NOT TESTED** — the role is not created yet (awaiting your approval + owner password; see `POSTGRESQL_SETUP_REPORT.md`). The SQL grants SELECT-only by construction.

## 8. Training dashboard & API — **PASS (API) / MANUAL (Flutter UI)**
- New `GET /models/dashboard` (admin-only, token-protected) — **verified live** — returns per-model: status, lifecycle (ACTIVE/EVALUATING/READY_TO_TRAIN/TRAINING/WAITING_FOR_DATA/INSUFFICIENT_DATA/FAILED), version, metrics, eligible vs required counts, new-records-since-training, class balance, feature distribution; plus scheduler `last_check`/`next_check`/interval/threshold.
- Backend passthrough added at `/api/v2/admin/ml/dashboard`.
- Existing `/models/status`, `/models/history`, `/models/metrics` unchanged (history page already available). **Flutter UI widgets for the new fields are not built** — the data is available to the existing provider; rendering it is a manual front-end step.

## 9. Monitoring & drift — **PASS (basic)**
- Feature-distribution baseline saved at training; `detect_drift()` flags features whose mean shifts beyond `ML_DRIFT_MEAN_THRESHOLD` (0.5). Drift raises a `DRIFT_ALERT` history event and prompts an eligibility check; it never auto-activates a model. Verified `test_drift_detection`.
- Prediction-distribution / realized-outcome drift is **basic** (mean-shift on inputs); richer population-stability/label-feedback monitoring is future work.

## 10. Free-deployment compatibility — **PASS / BLOCKED-HOST (documented)**
- CPU-only, no GPU, no Docker required locally, no paid service. Compatible with the existing FastAPI + Hugging Face Space (free) target.
- Artifacts persist via HF Hub (ephemeral Space disk is restored on boot).
- **Limitation (stated honestly):** free hosts sleep → no guaranteed continuous timers. Catch-up-on-wake is implemented; true 24×7 cadence would need an external free pinger/cron (e.g., a scheduled GitHub Action hitting `/models/retrain`) — optional, not added, no paid dependency introduced.

## 11. Testing — **PASS**
```
Python: 34 passed   (18 pre-existing + 9 monitoring + 7 scheduler)
Node:    2 passed   (ML client)
```
Covered: insufficient data, threshold reached, new records detected, duplicate-data ignored, invalid labels excluded, academy isolation, scheduler start/restart/shutdown, duplicate-training prevention, training success, training failure/DB disconnection, evaluation/promotion, drift. Mocked data only — never used for production training.

## 12. Final verification
- Existing APIs & Flutter contract intact (additive changes only). ✔
- Python 34/34, Node 2/2. ✔
- Live boot: scheduler starts in lifespan, dashboard works, auth enforced, no-DB handled. ✔
- No secrets tracked by Git (`git ls-files` → no `.env`). ✔
- Read-only role write-denial: **NOT TESTED** (role not yet created). ✔ documented.

---

## Status summary

| Capability | Status |
|---|---|
| Data monitoring & new-record tracking | **PASS** |
| Scheduler (6h/24h, catch-up, backoff, locks) | **PASS (logic)** / sleep-limited on free host |
| Thresholds, class balance, leakage-safe validation | **PASS** |
| Automatic training (real data) | **PASS (mechanism)** / **INSUFFICIENT DATA** (DB nearly empty) |
| Evaluate + promote-better-only + rollback | **PASS** |
| Reliability (restart/shutdown/retry) | **PASS** |
| Security / academy isolation / read-only reader | **PASS (design)**; role creation **MANUAL**; no-RLS risk **documented** |
| Dashboard API | **PASS**; Flutter UI **MANUAL** |
| Drift monitoring | **PASS (basic)** |
| Free deployment | **PASS**; continuous execution **BLOCKED-HOST (documented)** |
| Automated tests | **PASS (34 + 2)** |

## Manual steps to go fully live
1. Create `taleemplus_ml_reader` (see `POSTGRESQL_SETUP_REPORT.md`) and put its URL in `ml_service/.env`.
2. Deploy the FastAPI service to a free HF Space; set `ML_SERVICE_URL` + `ML_INTERNAL_TOKEN` + `DATABASE_URL` (reader) + `HF_TOKEN`/`HF_ARTIFACT_REPO`.
3. (Optional) Add a free external pinger/GitHub Action to call `/models/retrain` on a cadence so checks still run while the Space would otherwise sleep.
4. Enter real academy data. Training auto-starts once eligibility thresholds are met; until then both models remain `INSUFFICIENT_DATA` by design.
5. (Optional) Build Flutter dashboard widgets for the new `/admin/ml/dashboard` fields.
```
Tune via env (optional): ML_CHECK_INTERVAL_HOURS, ML_FULL_CHECK_INTERVAL_HOURS,
ML_RETRAIN_NEW_RECORDS, ML_MIN_MINORITY_CLASS_FRACTION, ML_DRIFT_MEAN_THRESHOLD,
ML_SCHEDULER_MAX_RETRIES, ML_SCHEDULER_BACKOFF_SECONDS.
```
