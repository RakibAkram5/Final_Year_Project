# TaleemPlus — Remaining Issues, Limitations and Next Steps

Date: 2026-11-08 · Branch: `fix/ci-pipeline` (all work is **uncommitted** in the working tree)

Nothing below is a known crash or a known data-loss bug. Items are ordered by how much they affect an evaluation or a production launch.

## A. Not verified (environment limitations)

| # | Item | Status | What is needed |
|---|---|---|---|
| A1 | Android runtime on a real device or emulator (login, navigation, camera OCR, PDF share) | **UNVERIFIED** | `adb devices` listed no device. Connect a phone on the same Wi-Fi, install `build/app/outputs/flutter-apk/app-release.apk` (built against `http://192.168.1.12:5055/api/v2`), start the backend with `PORT=5055 npm start` and walk through the four role logins. |
| A2 | Flutter web app clicked through in a browser | **UNVERIFIED** | The release web build succeeds and every API it calls was exercised over HTTP, but no browser session was driven. Serve `build/web` (or `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5055/api/v2`) and smoke-test the UI. |
| A3 | GitHub Actions workflows | **UNVERIFIED** | Workflows were rewritten and YAML-linted locally, but have not run on GitHub. Push the branch and check `Backend CI`, `Flutter CI`, `TaleemPlus CI/CD`, `ML service container`. |
| A4 | Vercel deployment | **UNVERIFIED** | `vercel.yml` now builds web + API functions together. Needs `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` secrets and `DATABASE_URL`, `JWT_SECRET`, `REFRESH_TOKEN_SECRET` in the Vercel project. |
| A5 | Live ML predictions through `/api/v2/admin/ml/*` | **UNVERIFIED** | The Python service's 13 tests pass locally, but `ML_SERVICE_URL` is not set in `taleemplus_backend/.env`, so the proxy endpoints were not exercised end to end. Run `ml_service` (Docker or `uvicorn app.main:app --port 8100`) and set `ML_SERVICE_URL`. |
| A6 | Printing/sharing generated PDFs on a device | **UNVERIFIED** | Challan and test-paper PDF code no longer depends on Firestore (academy header now comes from `/auth/me`), but `Printing.sharePdf` needs a device/browser. |

## B. Security follow-ups (no critical/high open item in code)

| # | Item | Severity | Recommendation |
|---|---|---|---|
| B1 | `JWT_SECRET` / `REFRESH_TOKEN_SECRET` in the local `taleemplus_backend/.env` are short. The server now warns at startup and **refuses to start in production** with weak secrets. | Medium (config) | Generate new 64-hex-char secrets for every deployed environment. |
| B2 | A Firebase web API key (`AIza…`) remains in **git history** (`lib/firebase_options.dart`, now deleted). | Low–Medium | If that Firebase project is still live, restrict or rotate the key in Google Cloud Console. |
| B3 | Neon credentials live in the local `.env` (correctly gitignored, never committed). | Info | Rotate the Neon password if the file was ever shared. |
| B4 | Refresh tokens are stored as plain JWT strings (unique, rotated, revocable). | Low | Store a SHA-256 hash instead of the raw token. |
| B5 | IP rate limiting is in-memory (per instance on serverless). | Low | Per-account DB lockout (added) covers brute force; add Redis/Upstash if needed. |

## C. Functional gaps (features that do not exist rather than broken ones)

| # | Item | Notes |
|---|---|---|
| C1 | No file upload/storage for classroom resources | Resources are text or links (`contentText` / `fileUrl`). Publishing OCR scans to a class works; uploading a PDF/image file needs object storage (S3/R2/Vercel Blob). |
| C2 | No push notifications | In-app notifications poll every minute; FCM was never wired to the REST backend. |
| C3 | No email-based password reset | Recovery is security question (self-service) or admin reset (new). No email transport is configured. |
| C4 | AI features are on-device and rule/statistics based | TF-IDF answer grading, TextRank summaries, rule-based question extraction from OCR text, and the logistic-regression fee-risk model all run locally in Dart. No external LLM API is integrated, so nothing should be described as "generative AI". |
| C5 | Switching a user to a different academy | `relinkAcademy` now verifies the code and explains that the target academy's admin must add the user. Self-moving between tenants was removed on purpose (it bypassed approval). |
| C6 | Offline mode | Offline SQLite member cache still exists for mobile; all other modules require the API. |

## D. Housekeeping

| # | Item | Action |
|---|---|---|
| D1 | Test data in the Neon **dev** database: 29 academies / 171 users named `Contract …` / `Smoke Test Academy …` with `@test.taleemplus` emails | `node taleemplus_backend/scripts/cleanup-test-data.js` (dry run) then `--confirm`. Take `npm run db:backup` first. |
| D2 | The server already running on port 5000 (started before this session) is running **old code** | Restart it (`npm start` in `taleemplus_backend`) so it serves the repaired API and new schema. Not stopped automatically. |
| D3 | Legacy Firebase files `firebase.json`, `firestore.rules`, `firestore.indexes.json`, `.firebaserc` | No longer used by the app; kept for reference. Delete when the Firebase project is decommissioned. |
| D4 | Older audit/report markdown files in the repo root contradict each other (a previous `TALEEMPLUS_FINAL_REPAIR_REPORT.md` claimed "A — Fully Ready" without evidence) | Superseded by the three `TALEEMPLUS_*` reports from this session. |
| D5 | Commit | Review `git diff` and commit on `fix/ci-pipeline`. `.pgdata` has been untracked with `git rm --cached` (local files kept). |

## E. Exact next steps

1. Restart the port-5000 backend (D2) or keep using `PORT=5055`.
2. Install the APK on a phone on the same network and run the four-role walkthrough (A1).
3. `git add -A && git commit` on `fix/ci-pipeline`, push, and confirm CI is green (A3).
4. Configure Vercel env and secrets, then deploy (A4) and run `node taleemplus_backend/scripts/smoke-e2e.js https://<your-domain>/api/v2`.
5. Rotate secrets (B1, B2) before any public deployment.
