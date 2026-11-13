# Changelog — TaleemPlus

## [1.2.0] — 2026-11-13

### Added
* **Online quiz attempts**: `Quiz.attemptMode/availableFrom/availableUntil/durationMinutes`, tables `quiz_submissions` and `quiz_answers` (migration `20261113120000_quiz_online_attempts`), controller `quizAttemptController.js` (start/resume, autosave, idempotent submit with server-side MCQ grading, teacher grading that publishes a `TestMark`, parent read through the linked child). Flutter: `TakeQuizScreen` (real attempt UI replacing the placeholder), `OnlineTestsScreen`, `SubmissionReviewScreen`, `QuizSubmissionsScreen`, online settings in the create-test form, navigation entries for all roles.
* **Bulk challans by section**: `POST /fees/challans/generate` accepts `sectionId`; transactional and duplicate-safe; the admin screen makes one call instead of one per student.
* **Offline read cache** (`OfflineCache`), `ConnectionStatus` + global `ConnectionBanner`.
* **Academy branding** and **ML analytics dashboard** (backend, migration, screens, tests) committed.
* Content-Security-Policy + `_headers`/`_redirects` shipped from `web/`.
* Release keystore workflow (`android/key.properties`, outside-repo keystore, `TaleemPlus` archive name).
* Tests: `securityRegressions.contract`, `quizAttempt.contract`, `feeBulkGenerate.contract`, `offline_cache_test.dart`; smoke E2E extended to 41 journeys; responsive matrix +5 screens.
* Docs: `KNOWN_LIMITATIONS.md`, `SECURITY_ROTATION_PLAN.md`; API, schema, user guides, CI and deployment docs updated.

### Fixed
* B1 compile error (`contentAsBase64`), B3 401/refresh contract (+ resume refresh), B4 parent directory leak, B5 formatting + AllChallans overflow, B7 route-checker false positive, B8 analytics date validation, B9 `trust proxy`/prod logging, B10 announcement & query ownership, B11 prediction limiter, B12 `/version` metadata, B13 duplicated HF Space copy.

### Changed
* Backend version 1.2.0 (`releaseDate` in `package.json`); app 1.2.0+7. The "offline-first" wording was replaced by the accurate "offline read cache".

## [1.1.0] — 2026-11-09

> Production release. Android (APK/AAB) and Web are built from this same source
> by the tag-driven CI pipeline (`.github/workflows/main.yml`). Package ID
> `com.taleemplus.app`; production API `https://taleemplus.vercel.app/api/v2`.

### Added
* **Professional exam-paper generator (AI Test Generator)**: produces genuine
  Pakistani-academy examination papers — full header (academy, subject, class, exam
  type, student/roll/section lines, time allowed, chapters, total marks, date,
  signature), a **Section A MCQ table** (`No. | Question | A | B | C | D`),
  roman-numbered short-question groups with "attempt any N (m×N=T)" rules, and a
  **Part II** of long questions, rendered to A4 with page numbers, running headers and
  a "Generated with TaleemPlus" footer. Generates a **separate teacher answer key**
  (MCQ answers + short/long model answers / marking guidelines) that the student paper
  never exposes. Dynamic configuration (exam type, time, chapters, counts, marks,
  attempt-any, difficulty, language) with **live marks validation** that always prints
  the computed total (fixes the reference paper's 20-vs-42 class of error). Hybrid
  engine: offline curriculum bank (Computer Science / Mathematics / English) + scanned
  or pasted source material, with an **optional** server LLM path that degrades
  gracefully to offline when no key is configured. Preview, print, download paper,
  download answer key, and save to examination history. Shared Flutter code serves both
  the web and Android apps. New: `lib/logic/exam_paper_generator.dart`,
  `lib/data/exam/curriculum_bank.dart`,
  `lib/features/quiz/screens/exam_paper_generator_screen.dart`; bundled Noto Sans font
  for full-Unicode PDFs; new `Quiz.paperMeta` JSON column (+ migration) persisting the
  paper layout and answer key; optional `POST /quizzes/ai-generate` endpoint
  (`AI_API_KEY`).
* **Automated ML training lifecycle**: eligibility monitoring, configurable thresholds
  (min samples, new-record retrain, class-imbalance guard), a 6h/daily scheduler with
  startup catch-up, a shared lock preventing duplicate/concurrent training, and basic
  feature-drift detection. New protected `POST /models/monitor` endpoint and
  `GET /models/dashboard`.
* **Hugging Face persistence hardening**: `HF_REPO_ID`/`HF_REPO_TYPE` env support,
  upload/download retries with backoff, startup artifact **integrity verification**, and
  "activate-only-after-successful-upload" (promotion reverts if the upload fails).
* **Free deployment for the ML service**: Render Blueprint (`render.yaml`, native Python,
  no Docker) + `.github/workflows/ml-monitor.yml` (eligibility-gated cron) + guides.
  (HF Spaces compute became paid; HF Hub remains the free artifact store.)
* **Node ML client**: cold-start-aware timeout (default 60s) + retry on 502/503/504/timeout.
* **Demo academy seeder** (`prisma/seed-demo-academy.js` + cleanup): one isolated
  "Bright Future Science Academy" with 100 students, 12 teachers, parents, classes,
  timetable, fees, attendance and quizzes/marks — to exercise both ML models.
* **Proprietary licensing docs**: `LICENSE`, `COPYRIGHT.md`, `OWNERSHIP.md`, `CONTRIBUTING.md`.

### Security
* **Discovered:** `taleemplus_backend/.env` (real DB URL + JWT/refresh secrets) was
  committed in earlier history reachable from pushed branches. Rotation + optional history
  purge required — see FINAL_SUBMISSION_REPORT.md. (No history was rewritten automatically.)

### Tests
* ML service: 53 passing (monitoring, scheduler, HF persistence with mocked hub, API).

## [1.0.1] — 2026-11-09

### Added
* **Private file storage** (Vercel Blob in production, local folder in development) with content-type detection, 4 MB limit and per-role access rules; PDF/image viewer with zoom, download/share.
* **Course materials with files**, **student/teacher documents**, **exam documents**.
* **Assignments**: create with instruction files and deadlines, student submissions (replace before the deadline when allowed), teacher grading.
* **Excel exports** (attendance, results, fee records) and **class PDF reports**.
* **Academy location** on OpenStreetMap: address search, tap-to-pin, device GPS, directions for every role.
* **Bank details** for fee payment with IBAN checksum validation.
* ML service: background training jobs, `READY_TO_TRAIN` status, model persistence to a private Hugging Face Hub repo, Hugging Face Space package.
* Responsive layout test suite (60 screens × 12 viewport/theme configurations) and contract tests for parents, files, reports and academy settings.
* Documentation set: API, schema, migrations, ML, deployment guides, user guides, audit/security/test reports.

### Fixed
* Class Management card squeezed the class name into a 10 px column on small phones; similar layout issues on ~15 screens; truncated dashboard titles.
* Parent portal: refresh did not re-fetch linked children; load errors looked like "no children"; Academy Support always showed "profile unavailable".
* **Security:** parents could link themselves to any student; class lists exposed classmates; teachers could change other classes' materials; students could read other classes' materials.
* Light theme: white-on-white text and dark cards; theme preference race.
* Attendance accepted future dates; malformed/oversized request bodies returned 500.
* Training no longer runs inside the HTTP request (timeouts).

### Removed
* Unused on-device "ML" classes whose weights came from synthetic data.

### Requires before deploying
* Apply migration `20261109090000_files_assignments_location_bank` and connect a private Vercel Blob store (see `VERCEL_DEPLOYMENT_GUIDE.md`).

## [1.0.0] — 2026-11-08

### Added
* **Netlify hosting for the Flutter web app** (`netlify.toml`, `tool/netlify_build_web.sh`):
  SPA fallback, security headers, static-asset caching, and a same-origin
  proxy of `/api/*` and `/health` to the Express API on Vercel.
* Release pipeline: one GitHub Release per `v*` tag with universal and
  per-ABI APKs built against the production API; optional release signing.
* Vercel CD applies pending Prisma migrations before deploying and checks
  production health afterwards (runs when the `VERCEL_TOKEN` secret is set).

### Fixed
* Nested API routes (e.g. `/api/v2/auth/login`) returned 404 on Vercel.
* API functions crashed with `Cannot find module 'zod'` on Vercel.
* Production database was missing three migrations, so every login failed.
* Android lint error for the camera permission (camera is now optional).
* Browser tab and PWA icons showed the Flutter logo instead of TaleemPlus.


## [0.6.0] — 2026-10-30

### Added
* **Node.js + Express + PostgreSQL Backend (`taleemplus_backend/`)**:
  * Complete REST API implementation mirroring all core academy workflows.
  * Prisma ORM schema covering 18 relational models with multi-tenant `academyId` scoping.
  * JWT access token & refresh token rotation with bcrypt password security.
  * Role-based authorization middleware (`ADMIN`, `TEACHER`, `STUDENT`, `PARENT`).
  * Automated Jest API integration tests.
  * Versioned API endpoints under `/api/v2`, including `GET /api/v2/version` and health checks.
* **Flutter REST API Client (`lib/data/remote/api_client.dart`)**:
  * Centralized HTTP client managing Bearer tokens and API base URLs.
  * Full reconciliation of `AuthService` and `QuizService` methods.
* **CI/CD & Automation (`.github/workflows/`)**:
  * Automated backend CI workflow with PostgreSQL service container.
  * Flutter formatting, analysis, and unit test workflows.
  * Android Release APK build workflow.
* **Documentation Artifacts**:
  * `API_V2.md`, `CI_CD_SETUP.md`, `DEPLOYMENT.md`, `BUG_FIX_REPORT.md`, `docs/PROJECT_AUDIT.md`, `docs/DATABASE_DESIGN.md`, `docs/API_DESIGN.md`, `docs/SECURITY_AUDIT.md`.

### Fixed
* Resolved all 75 Dart analyzer errors across the project (`flutter analyze` reports 0 issues).
* Resolved Gradle JDK 17+ native-platform loading warnings by configuring `--enable-native-access=ALL-UNNAMED` in `android/gradle.properties`.
