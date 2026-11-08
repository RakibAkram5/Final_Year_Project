# Changelog — TaleemPlus

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
