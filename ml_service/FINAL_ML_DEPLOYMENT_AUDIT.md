# TaleemPlus ML — Final Deployment Audit

_Strict independent audit performed by reading the files on disk, compiling the
whole service, running every test, and fixing bugs found. Nothing below is
claimed PASS without an actual run. No fabricated data, no privileged SQL, no
deployment, no secrets exposed._

Labels: **PASS** (implemented + tested) · **CODE ONLY** (implemented, not live-tested)
· **BLOCKED** (needs creds/DB/host) · **FAILED** (broken) · **INSUFFICIENT DATA**.

---

## Bugs found and fixed during this audit

1. **Scheduler race (FIXED).** `eligibility_check` (6h) and `full_sweep` (24h) are
   separate APScheduler jobs; `max_instances=1` only guards each job individually,
   so the two could run a full sweep **concurrently**. Training itself was already
   safe (shared `state` per-job lock), but concurrent sweeps doubled the read-only
   DB load (risking the `ml_reader` 5-connection limit) and interleaved
   `history.jsonl` writes. **Fix:** added a non-reentrant `_sweep_lock`; a second
   trigger now no-ops with `"skipped": "sweep already running"`. Regression test:
   `test_concurrent_sweep_is_skipped_not_duplicated`.
2. **`huggingface_hub` not installed locally (FINDING, handled).** It is in
   `requirements.txt` but absent from this machine. The code imports it *lazily*
   inside `push`/`pull`, so the service runs correctly without it when HF is not
   configured. Persistence tests were rewritten to inject a mock `huggingface_hub`
   module, so they are hermetic and do not require the package. Implication: HF
   persistence is **mock-tested, not live-tested** here (see §5).

No other defects (no malformed dicts, duplicate defs, dead code, early returns,
bad indentation, missing/duplicate imports, circular imports, undefined names, or
wrong arguments) were found.

---

## 1. Syntax & code integrity — **PASS**
- `python -m compileall app scripts tests` → exit 0.
- Import smoke of all modules → OK (no circular imports; `main`→`scheduler`/`state`/`monitoring`, `monitoring`→`pipeline`, `scheduler`→`state`/`monitoring`; no cycle).
- `node --check` on `mlController.js`, `mlRoutes.js`, `mlServiceClient.js` → OK.
- Old scheduler fully replaced; `retrain_all()` kept only as a thin backward-compatible alias (not dead code).

## 2. Scheduler correctness — **PASS (logic) / BLOCKED (24×7 on free host)**
- Starts exactly once via FastAPI lifespan (`if scheduler.running: return`) — verified live (`running: true`).
- Startup catch-up (`date` job) runs immediately on boot — verified live (a `last_check` timestamp appears right after start).
- 6h `eligibility_check` + daily `full_sweep` registered — asserted in `test_scheduler_starts_and_shuts_down_cleanly`.
- **Race fixed** (see above); both jobs now mutually exclusive via `_sweep_lock`.
- Duplicate training prevented by shared lock across manual + scheduled (`test_duplicate_training_is_prevented`).
- Transient DB failure retried with exponential backoff; failure recorded, never silently “successful” (`test_data_source_failure_records_not_ready`).
- Restart recovery + graceful shutdown tested.
- **Host limit:** while a free Space sleeps, timers do not fire; catch-up-on-wake mitigates but does not guarantee cadence.

## 3. Training & promotion — **PASS (mechanism) / INSUFFICIENT DATA (real run)**
- Fee labels (late vs on-time, window-elapsed) and performance labels (next-exam %) computed in leakage-safe, time-bounded SQL (verified in `test_extractor.py`).
- Time-based split; class imbalance guarded (`ML_MIN_MINORITY_CLASS_FRACTION`).
- **Validation/metric compatibility verified:** the incumbent is scored on the *new* model's holdout (`Xv/yv` for fee, `valid_df` for performance), so ROC-AUC / RMSE comparisons are apples-to-apples. Promotion requires new ≥ incumbent AND over baseline; inferior models are rejected and the active model is retained (`test_failed_candidate_does_not_move_production_pointer`).
- No model is activated before `VALIDATED`→`PRODUCTION` gating.
- Has **not** trained on real data: the DB is near-empty (see §ReadinessData).

## 4. Data & academy isolation — **PASS (query layer) / documented risk (no RLS)**
- Every extraction query filters `academyId = $1`; artifacts keyed by SHA-256(academy_id); `test_academy_isolation_only_touches_its_own_folder` confirms one academy's run never writes another's folder.
- Invalid/unlabeled rows excluded from class counts; incomplete fee rows dropped in the extractor.
- The ML reader performs **reads only**; the scheduler writes nothing to Postgres.
- **Documented risk:** PostgreSQL **RLS is not enabled**. Academy isolation is enforced by application/extractor query code, not by the database. A future query that forgets the `academyId` filter would not be stopped by the DB. RLS is optional future hardening.

## 5. Hugging Face persistence — **CODE ONLY (mock-tested) / BLOCKED (live)**
- `push` uploads to a **private** repo (`create_repo(private=True)` + `upload_folder`) — `test_push_uploads_to_a_private_repo`.
- `pull` restores on startup (wired in lifespan) — `test_pull_restores_from_hub`.
- Missing dir → no upload; upload failure → returns False without raising; missing/empty repo on first deploy → pull returns False; missing HF creds → both no-op. All tested with a mocked hub.
- **Pointer safety:** `train()` writes the versioned artifact and moves `production.json` **locally and atomically** before `push`. A failed push leaves local state consistent (pointer → existing local artifact) and simply means the new version is not yet durable remotely; it never creates a dangling pointer. On restart, `pull` restores the last successfully pushed state.
- **BLOCKED (live):** real HF round-trip not tested (package not installed locally; needs `HF_TOKEN`/`HF_ARTIFACT_REPO` and a deploy). **Without HF configured, artifacts live only on the Space's ephemeral disk and are lost on restart.**

## 6. API & Flutter compatibility — **PASS (API) / CODE ONLY (Flutter UI)**
- Node `/api/v2/admin/ml/dashboard` → ML `/models/dashboard` (verified live; returns scheduler + per-model lifecycle).
- **Authentication + admin authorization both enforced at the backend:** `router.use(authenticateToken, authorizeRoles('ADMIN'))` — the internal ML token is *not* the only gate.
- **Academy cannot be spoofed:** the controller uses `req.academyId`, set from the authenticated user's DB record (`authMiddleware` → `req.academyId = user.academyId`), never from client input.
- Existing predict/status/history endpoints unchanged; additive changes only. Flutter provider still consumes `/admin/ml/*` and stores full status maps; new dashboard fields flow through but **UI widgets for them are not built** (manual front-end step).

## 7. Tests executed (this audit)
```
python -m compileall app scripts tests      -> exit 0
python -m pytest -q                          -> 41 passed
    (18 pre-existing + 9 monitoring + 8 scheduler + 6 artifact_store)
npx jest tests/mlServiceClient.test.js       -> 2 passed
node --check (controller/routes/client)      -> OK
live boot: scheduler starts, /models/dashboard works, 401 without token
```
New regression tests added this audit: sweep-race skip; full HF push/pull/failure/no-creds suite.

### Readiness of real data — **INSUFFICIENT DATA**
Measured earlier via read-only diagnostic (Neon, 38 academies): fee usable labeled rows **0**, performance usable **2** (0 with prior history); raw volumes 20 challans / 3 marks / 17 attendance. Not enough to train either model honestly.

### Items still BLOCKED / manual
- `taleemplus_ml_reader` role not created yet → **read-only write-denial NOT TESTED**, and the ML service has no DB until you set its `.env` `DATABASE_URL`.
- HF persistence not configured → live restart-survival **BLOCKED**.
- Free-host sleep → reliable cadence needs an external free pinger (e.g., GitHub Action hitting `/models/retrain`).
- Flutter dashboard UI widgets → manual.
- Rollback: rejection path tested; **successful-restore path is CODE ONLY** (logic verified, not unit-exercised because crafting two independently-promoted versions needs distinct real datasets).

---

## Straight answers

1. **Is automatic training actually working?**
   The mechanism is implemented and **tested** (scheduler detects eligibility, respects thresholds/locks, trains, evaluates, promotes). It has **not** run on real data because the database is near-empty. So: *working and tested, but never yet exercised on production data.*

2. **Will real data trigger training automatically?**
   **Yes — once** (a) the `ml_reader` `DATABASE_URL` is set, (b) the service is running/awake, and (c) thresholds are met (≥100 eligible, both classes for fee, or ≥50 new records to retrain). Currently BLOCKED by the un-created role and insufficient data.

3. **Will a better model automatically become active?**
   **Yes.** The promotion gate (tested) activates a new model only if it beats the incumbent and a baseline on the same validation set; inferior models are rejected and the previous model stays active.

4. **Will the model survive a Hugging Face Space restart?**
   **Only if HF persistence is configured** (`HF_TOKEN` + `HF_ARTIFACT_REPO`). The pull-on-startup / push-on-train logic is wired and mock-tested, but the real round-trip is BLOCKED (not live-tested; package not installed here). **Without HF configured, artifacts are on ephemeral disk and will be lost on restart.**

5. **Does the scheduler work when the Space sleeps?**
   **No — not while asleep.** Timers don't fire on a sleeping free host. Catch-up-on-wake is implemented, but guaranteed cadence needs an external free pinger. This is a hosting limitation, not a code bug.

6. **Is the system safe for multiple academies?**
   **At the query/application layer, yes** (every query academy-scoped, artifacts per-academy, tested; academy id derived from the authenticated user, not client input). **Caveat:** there is **no database RLS**, so isolation depends on query code, and the read-only role's write-denial is not yet verified (role not created). Safe by design and tests; not DB-enforced.

7. **Is the project ready for deployment?**
   **Not production-ready yet.** The code is complete, compiles, and passes 41 Python + 2 Node tests, and the race condition is fixed. But deployment is **BLOCKED** on manual steps that are not yet done or verified: create the read-only role, configure + live-test HF persistence, add a wake pinger for the free host, and — most fundamentally — accumulate enough **real** data (currently INSUFFICIENT). Until those are done, mark it **CODE-COMPLETE & TESTED, deployment-BLOCKED**, not production-ready.
