# Changelog — TaleemPlus

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
