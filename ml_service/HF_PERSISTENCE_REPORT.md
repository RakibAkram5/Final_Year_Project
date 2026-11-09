# TaleemPlus ML — Hugging Face Persistence Report

_Independently implemented and tested. Persistence logic is covered by hermetic
tests against a **mocked** Hugging Face Hub; a **real** Hub upload/download
round-trip was NOT performed (no `huggingface_hub` installed here, no `HF_TOKEN`,
and no deployment), so anything requiring the real Hub is marked **BLOCKED**, not
PASS. No secrets exposed, nothing deployed, no fabricated training data._

Labels: **PASS** (implemented + tested here) · **CODE ONLY** (implemented, not
live-tested) · **BLOCKED** (needs real Hub creds / network / deploy).

> **Hosting update (deployment task):** Hugging Face now requires a **paid plan to create a
> compute-backed Space** (Gradio/Docker); only Static Spaces are free and can't run Python. So
> the ML **compute** now targets **Render Free Web Service** (see `RENDER_DEPLOYMENT_GUIDE.md`),
> while the **Hugging Face model repository stays as the free, durable artifact store** used by
> `artifact_store.py`. Nothing in the persistence code changed for this; the real-Hub round-trip
> is simply verified on Render instead of on a Space — still **BLOCKED** until run with real creds.

---

## What changed (backward compatible)

| File | Change |
|---|---|
| `app/artifact_store.py` | New env `HF_REPO_ID` + `HF_REPO_TYPE` (legacy `HF_ARTIFACT_REPO` still works); retries w/ backoff on push & pull; `verify_integrity()`; `persist_training()` enforcing "activate only after successful upload". |
| `app/models.py` | Atomic production-pointer helpers: `read_pointer`, `write_pointer`, `restore_pointer` (used to undo an activation whose upload failed). |
| `app/main.py` | `_run_training` persists via `persist_training` (reverts on failure); lifespan now does **pull → verify_integrity → start scheduler**. |
| `app/training/scheduler.py` | `process_model` persists via `persist_training`; records `PERSIST_FAILED` when an upload fails after promotion. |
| `app/.env.example` | Documents `HF_TOKEN`, `HF_REPO_ID`, `HF_REPO_TYPE`, retry knobs. |

`train()`, all HTTP endpoints, the Node/Flutter contract, and prior behaviour are unchanged. Existing tests still pass.

---

## Requirement-by-requirement

### 1. Inspect existing store & structure — **PASS**
Layout confirmed: `ARTIFACT_DIR/<sha256(academy_id)>/<model>/<version>/{pipeline.joblib,metadata.json}` + `<model>/production.json` pointer + `<academy>/history.jsonl`. Keyed by academy hash; no identifiers/raw rows.

### 2. Use HF Hub for all artifact types — **PASS (logic) / BLOCKED (real Hub)**
`push` uploads the whole `ARTIFACT_DIR` (models, metadata, `production.json` pointers, version history, `history.jsonl`) in **one atomic Hub commit**; `pull` restores it. Covers rollback artifacts too (old versions are never deleted). Verified with a mocked Hub; real upload is BLOCKED.

### 3. Env vars `HF_TOKEN` / `HF_REPO_ID` / `HF_REPO_TYPE` — **PASS**
Resolved in `_settings()`; `HF_REPO_ID` preferred, `HF_ARTIFACT_REPO` accepted for back-compat, `HF_REPO_TYPE` defaults to `model`. Tested: `test_legacy_repo_env_still_accepted`, `test_repo_type_is_honoured`.

### 4. Never expose `HF_TOKEN` — **PASS**
Token is read from env, passed only to the Hub client, and **never** logged, returned by any API, or written to disk. Logs record only `type(exc).__name__`. `.env` is git-ignored (verified earlier). No token in any response (dashboard/status payloads contain no secrets).

### 5. On startup: restore + verify + load + handle missing Hub — **PASS (local) / BLOCKED (real restore)**
Lifespan runs `pull()` → `verify_integrity()` → `start_scheduler()`. `load_production()` loads the active model on demand. Missing Hub = safe no-op (service boots `degraded` but functional — **verified live** just now). Real restore from a real repo is BLOCKED.

### 6. After training: upload, then activate only on success — **PASS**
`persist_training(promoted, previous_version, …)`:
- Hub disabled → no-op, local promotion kept (dev/single-node). `test_persist_training_local_mode_keeps_promotion`.
- Hub enabled + upload **ok** → model stays active. `test_persist_training_keeps_pointer_on_successful_upload`.
- Hub enabled + upload **fails** → production pointer **reverted** to the previous version (or cleared if none); status recorded `PERSIST_FAILED`. Unit: `test_persist_training_reverts_activation_on_upload_failure`, `…_clears_pointer_when_no_previous_model`. End-to-end through the scheduler: `test_process_model_does_not_activate_when_upload_fails`.

### 7. Rollback using persisted versions — **PASS (logic) / CODE ONLY (happy-path restore)**
Old versions are retained on disk and in the Hub commit, so `/models/rollback` can repoint `production.json` to any previously-promoted version. Rejection of invalid/unpromoted versions is tested; the successful-restore API path is code-verified (not unit-exercised — needs two independently-promoted real versions).

### 8. Network failures / retries / interrupted uploads / missing creds — **PASS**
`push`/`pull` retry `HF_MAX_RETRIES` times with exponential backoff; upload is a single atomic commit (an interrupted upload leaves no half-state on the Hub). Missing creds → no-op. Tests: `test_push_failure_returns_false_and_does_not_raise`, `test_push_retries_then_succeeds`, `test_pull_handles_empty_or_missing_repo`, `test_push_and_pull_are_noops_without_credentials`.

### 9. Concurrent jobs cannot corrupt artifacts — **PASS**
Three layers: (a) each train writes a **unique versioned dir**; (b) the shared `state` lock prevents two trainings of the same `academy:model`; (c) `push` holds a module `_lock` so uploads serialize into distinct commits. Pointer writes are atomic (`os.replace`). Duplicate-prevention tested (`test_duplicate_training_is_prevented`).

### 10–11. Mocked-Hub tests for every scenario — **PASS** (real Hub **BLOCKED**)
| Scenario | Test | Result |
|---|---|---|
| Upload success | `test_push_uploads_to_a_private_repo` | PASS (mock) |
| Upload failure | `test_push_failure_returns_false_and_does_not_raise` | PASS (mock) |
| Download after restart | `test_pull_restores_from_hub` + live lifespan boot | PASS (mock) |
| Missing HF token | `test_push_and_pull_are_noops_without_credentials` | PASS |
| Missing repository | `test_pull_handles_empty_or_missing_repo` | PASS (mock) |
| Corrupted artifact | `test_verify_integrity_detects_missing_artifact` | PASS |
| Rollback after failed promotion | `test_persist_training_reverts_activation_on_upload_failure` | PASS (mock) |
| Previous active model remains available | same test asserts pointer == previous `v1` | PASS (mock) |
| **Real Hub round-trip** | — | **BLOCKED** |

### 12–15. No fake data / no deploy / no secrets / no false claims — **PASS**
No production training data fabricated; nothing deployed; no credentials exposed; and real-Hub persistence is explicitly **not** claimed as verified.

---

## Tests executed
```
python -m compileall app           -> exit 0
python -m pytest -q                 -> 51 passed
    18 original + 9 monitoring + 9 scheduler + 15 artifact_store
live boot: lifespan pull->verify->scheduler OK; /models/status 200 (back-compat)
```

## Still BLOCKED (requires you)
1. **Real Hub round-trip** — install `huggingface_hub` on the host (it's in `requirements.txt`), set `HF_TOKEN` + `HF_REPO_ID` (private repo), then run one train and confirm files appear in the repo and are restored after a restart. Until then persistence is **mock-verified only**.
2. Without `HF_TOKEN`/`HF_REPO_ID` the service keeps artifacts on **ephemeral disk** → lost on a Space restart. HF config is required for durability on free hosting.

## Final answer
The persistence **logic is complete, backward-compatible, and fully unit/integration-tested against a mocked Hub**, including the critical guarantee that a model is **never activated unless its upload succeeded**. Real Hugging Face durability is **BLOCKED** pending `huggingface_hub` + real credentials + a one-time live round-trip — which I have not performed and do not claim.
