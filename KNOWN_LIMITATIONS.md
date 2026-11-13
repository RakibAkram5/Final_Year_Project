# Known limitations (v1.2.0, 2026-11-13)

What TaleemPlus does **not** do, so the documentation never over-claims. Each
item says why and what would be needed to lift it.

## Offline

| Limitation | Detail |
|---|---|
| Read cache only | Authenticated **GET** responses are cached on the device (`lib/data/local/offline_cache.dart`, scoped to the signed-in user, ≤ 150 entries / 256 KB each, wiped on sign-out). When the server is unreachable the app shows the last saved copy and an orange banner "showing the last saved data". |
| No offline writes / sync queue | Attendance, marks, uploads, quiz answers, payments and every other write fail immediately with a clear error while offline and must be retried online. Replaying writes later without the server's conflict checks (one attendance record per student per day, one challan per billing month, one quiz submission) could corrupt records, so queuing was deliberately not implemented. |
| Files are not pre-downloaded | Course materials and documents stream from the API; only a file the user has already opened may still be in the browser/OS cache. |
| Web OCR needs the network | Tesseract.js and its language data load from a CDN at first use. Android OCR (ML Kit) works offline. |

## Notifications
In-app only (bell icon + announcements). No push (FCM) or e-mail delivery.

## Online tests
* Multiple-choice questions are graded automatically; short/long answers are graded by the teacher in **Submissions & grading**. A result (TestMark) is published only when every question has a score.
* One attempt per student per test. There is no proctoring, no question shuffling and no per-question time limit (the whole attempt has an optional time limit and deadline).
* A test is PAPER or ONLINE at creation; existing printed tests are unaffected.

## Pagination
List endpoints return a fixed window (200–500 newest rows). Cursor pagination is not implemented; academies above ~500 students per list would need it.

## Permissions model
Roles are fixed in code (ADMIN / TEACHER / STUDENT / PARENT). Admins cannot define custom permission sets.

## AI / ML
* Fee-risk and performance models train **per academy** on that academy's real records and are promoted only after passing the hold-out evaluation; with fewer than the minimum labelled records the UI says *Not enough data yet*. No metrics or predictions are fabricated.
* The revenue "forecast" on the AI screen is a labelled fixed-assumption heuristic, not ML. The notes summariser (TextRank) and answer grader (TF-IDF) are deterministic algorithms.
* Production ML wiring (`ML_SERVICE_URL`, `ML_INTERNAL_TOKEN` on the backend; GitHub secrets for the monitor cron) must be set by the project owner; until then admin AI screens show "ML service not available".

## Maps
OpenStreetMap tiles + Nominatim geocoding (not Google Maps). Subject to the OSM tile usage policy; a commercial deployment should use its own tile provider.

## Security
* Rate limiting is per serverless instance (in memory) with `trust proxy` for the real client IP; a shared store (Upstash/Postgres) would make limits global. Brute-force protection relies primarily on the database-backed account lockout.
* Row-level security is enforced in application code (every query filtered by the caller's academy) and guarded by contract tests, not by PostgreSQL policies.
* Secrets found in old git history (a Firebase web key, a dev `.env`, a local `.pgdata` directory) still need the rotation / history rewrite described in `SECURITY_ROTATION_PLAN.md` — both require the owner's approval.

## Release engineering
* Android release signing uses a keystore kept **outside** the repository; CI signs only when the `KEYSTORE_*` secrets exist, otherwise it debug-signs and says so in the log.
* Backend and web deploys are triggered by the owner (Vercel / Netlify CLI or the `VERCEL_TOKEN` secret); database migrations are applied with `prisma migrate deploy` **before** the backend that needs them.
