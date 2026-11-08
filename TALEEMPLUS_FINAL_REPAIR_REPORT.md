# TaleemPlus — Final Repair Report

Date: 2026-11-08 · Branch `fix/ci-pipeline` · Base commit `9d42d9f` · All changes are **uncommitted** for your review.
Companion documents: `TALEEMPLUS_TEST_RESULTS.md` (evidence) and `TALEEMPLUS_REMAINING_ISSUES.md` (open items).

> This file replaces an earlier `TALEEMPLUS_FINAL_REPAIR_REPORT.md` that claimed "A — Fully Ready". When this session started, that claim was false: 9 DB tests were skipped (not passed), 20 client API calls hit non-existent routes, and 5 modules still used Firestore.

## Overall verdict: **C — Partially Ready** (code-complete and API-verified; device/UI runtime unverified)

Why not B: the acceptance criteria require Android runtime smoke tests and a working UI walkthrough. Neither could be performed (no device attached, no browser session). Backend, database, API contract, and all four roles are verified end to end over HTTP against the real database, and both release builds succeed. Once A1/A2 in the remaining-issues file pass on a device, this is a defensible **B — Ready with Minor Issues**.

| Acceptance criterion | Status |
|---|---|
| Database migrations synchronized | **PASS** — 9/9 applied; `migrate diff` vs live DB: no difference |
| Login works with real DB records | **PASS** — contract tests + live smoke |
| All four roles log in and reach their data | **PASS (API)** / **UNVERIFIED (UI)** |
| Core features work end to end | **PASS (API)** / **UNVERIFIED (UI)** |
| No active core module depends on placeholder Firebase | **PASS** — Firebase SDK removed; 0 Firebase references in `lib/` |
| Quiz and fee date handling correct | **PASS** — unit + contract tests |
| User management correct | **PASS** |
| Attendance and fee analytics show correct data | **PASS (API)** |
| Parent–child relationships work | **PASS** |
| Class enrollment secure | **PASS** — cross-tenant attempts tested (403/404) |
| APIs enforce permissions | **PASS** — role + tenant tests on every module |
| Automated tests pass | **PASS** — backend 81/81, Flutter 31/31, ML 13/13 |
| Flutter analysis clean | **PASS** |
| Web and Android release builds succeed | **PASS** — both built on the final code |
| Android runtime smoke tests | **UNVERIFIED** |
| No critical/high security defects remain | **PASS** (to the extent tested; see remaining issues §B) |
| No unresolved critical crashes | **PASS (tests)** / **UNVERIFIED (device)** |

---

## 1. Phase 1 — Inspection and backup

- Found substantial uncommitted work from a previous session; built on it, did not discard anything.
- Configured DB is **Neon (cloud)**, not the local `.pgdata` cluster. Owner confirmed it is a development database.
- Backup: new `taleemplus_backend/scripts/backup-db.js` (`npm run db:backup`) wrote a JSON snapshot of all 23 tables to `taleemplus_backend/backups/` (gitignored) before any schema change.
- `.pgdata` (1,367 tracked files) untracked with `git rm --cached` — local files kept; `.gitignore` now covers `.pgdata/`, `backups/`, `android/.kotlin/`.
- An attempted Prisma *shadow-database* diff against Neon was blocked by the safety layer (it would have reset the DB). It was not retried; a read-only `migrate diff --from-url` was used instead.

## 2. Audit checklist — status per item

Legend: Original = status in the official audit; Final = status after this session.

### A. Database and authentication

| Item | Original | Final | Root cause → change | Key files |
|---|---|---|---|---|
| Pending migration `20261105190000_phase2_schema_staging` | Pending | **Fixed** | Already applied to Neon before this session; verified. New additive migration `20261108150000_account_lifecycle_lockout` (INACTIVE status, lockout + deactivation columns) applied after backup. | `prisma/migrations/*`, `schema.prisma` |
| Login HTTP 500 / P2022 `legacyFirebaseUid` | Broken | **Fixed** | Schema/DB drift; resolved by migrations. Login verified with real rows. | — |
| Register, refresh, logout, session restore, `/auth/me` | Partial | **Fixed** | Refresh tokens lacked a unique `jti` (same-second tokens identical → rotation no-op, 500 on collision). Refresh now re-reads role/academy from DB. | `authController.js` |
| Invalid credentials / inactive accounts | Partial | **Fixed** | Status-specific 403 codes (`ACCOUNT_PENDING/REJECTED/INACTIVE`); generic 401 for bad credentials. | `authController.js` |
| Case-sensitive email matching | (new) | **Fixed** | Case-insensitive lookup; new accounts stored lower-case. | `authController.js`, `userController.js` |
| Password recovery stubs (`getSecurityQuestion` null, `verifySecurityAnswer` always true, `sendPasswordReset` no-op) | Stub | **Fixed** | Client wired to existing backend reset; new `PUT /auth/security-question`; new admin reset `PUT /users/:id/password`; email reset honestly reported as unavailable. | `auth_service.dart`, `login_screen.dart`, `user_management_screen.dart` |
| `findAcademyByCode` fabricated academy | Stub | **Fixed** | New public, rate-limited `GET /auth/academy-lookup`. | `authController.js`, `signup_screen.dart` |
| `relinkAcademy` local-only | Stub | **Fixed (by design)** | Verifies code against server; refuses self-move across tenants (bypassed approval). | `auth_service.dart` |

### B. User management

| Item | Original | Final | Change |
|---|---|---|---|
| `updateUserProfile()` no-op | Broken | **Fixed** | Calls `PUT /users/:id` or `/users/me`; throws when no target. |
| Roll number not persisted | Broken | **Fixed** | Persisted on create/update; uniqueness (409) case-insensitive per academy. |
| `isRollNumberTaken()` always false | Broken | **Fixed** | New `GET /users/roll-number-available` (old search ignored queries < 2 chars). |
| Add-member false failure | Broken | **Fixed** | Account creation separated from follow-ups; partial failures reported as "created, but …"; single-student section enroll instead of roster rewrite. |
| Approval/rejection false failure (Firestore) | Broken | **Fixed** | Removed client Firestore/duplicate notification calls; server creates approval notification. |
| Delete/deactivate not implemented | Missing | **Fixed** | `PUT /users/:id/deactivate|reactivate`; history kept, sessions revoked; UI dialog text says exactly that. |
| `getProfilesByIds()` returns empty | Broken | **Fixed** | Client called `/users/profiles-by-ids`; backend is `/users/profiles`. |
| Parent–child link/unlink stubs | Broken | **Fixed** | Unlink called non-existent `/users/linked-children/:id`; now `/users/link-child/:id[?parentId]`. |
| `findStudentByEmail()` null / wrong child | Broken | **Fixed** | Exact email match only (old code fell back to the *first* search result → could link the wrong child). |

### C. Classes and enrollment

| Item | Original | Final | Change |
|---|---|---|---|
| `updateClassDetails()` no-op | Broken | **Fixed** | Client → `PUT /classes/:id` (backend existed). |
| Create ignores selected students | Broken | **Fixed** | `studentIds` sent and validated. |
| No unenrollment | Missing | **Fixed** | `DELETE /classes/:id/enroll/:studentId` used by enrollment sync. |
| Cross-academy student enrollment | Vulnerable | **Fixed + tested** | Tenant checks on classes and **sections** (section roster previously dropped foreign IDs silently; now 403). |
| Cross-academy teacher assignment | Vulnerable | **Fixed + tested** | `validateTeacher` checks academy. |
| Academy-ID inconsistencies | Inconsistent | **Fixed (server-side)** | All endpoints derive academy from the token; client-supplied academy IDs are ignored. Several screens still pass `uid` as a no-op argument (harmless). |

### D. Attendance

| Item | Original | Final | Change |
|---|---|---|---|
| `getAllForAcademy()` empty | Broken | **Fixed** | Wrong path (`/attendance/academy` → `/attendance`), errors no longer swallowed, optional date range. |
| Analytics show zero | Broken | **Fixed** | Follows from above; teacher "marked today" also read classes before they loaded → always 0; now server-scoped. |
| Firestore timestamp logic in REST models | Broken | **Fixed** | `log_date` parsed as local calendar day; missing date rejected instead of "today". |
| Teacher could mark/read any class | (new) | **Fixed + tested** | Teachers restricted to their own classes. |
| Duplicate prevention | OK | **Verified** | Upsert on class+student+day; test asserts exactly one row. |

### E. Fees and payments

| Item | Original | Final | Change |
|---|---|---|---|
| `fromMap()` ISO dates / `DateTime.now()` fallback | Broken | **Fixed** | Local-time ISO parsing; missing due date throws; Decimal strings parsed. |
| Overdue status incorrect | Broken | **Fixed** | Overdue once the due *day* has passed (client) / start of UTC day (server); ledger counts overdue. |
| Monthly ledger grouping | Broken | **Fixed** | Groups by billing period, sorted chronologically (was issue date, alphabetical). Server ledger adds monthly breakdown. |
| Printed challan dates | Broken | **Fixed** | Follows from correct parsing. |
| Bulk generation depends on Firestore sections | Broken | **Fixed** | `ClassSectionRepository` migrated to REST. |
| Errors swallowed to empty lists | Broken | **Fixed** | Repository rethrows; screens already had error states. |
| Parent dashboard fee total | (new) | **Fixed** | Called admin-only `/fees/challans` (403); now per-child endpoint. |
| Single response format | (new) | **Fixed** | One `formatChallan` (ISO dates, `paid_at`, `updated_at`) for all endpoints. |

### F. Quizzes, marks, AI

| Item | Original | Final | Change |
|---|---|---|---|
| ISO → Timestamp cast / listing empty | Broken | **Fixed** | Model parses ISO; Firestore types removed. |
| `updateQuestions` / `deleteQuiz` / `deleteMark` no-ops | Broken | **Fixed** | Wired; `deleteMark` was passing the **quiz id** as mark id → always 404. |
| Marks by quiz/class, academy marks empty | Broken | **Fixed** | Academy marks path was `/quizzes/marks` (matched `/:id`). |
| Missing quiz metadata | Broken | **Fixed** | Month/session/chapter/difficulty/test date sent. Fractional question marks rounded (Int column). |
| Teacher could edit/mark/delete others' quizzes; read any answer key | (new) | **Fixed + tested** | `assertCanManageQuiz` / `assertCanReadQuiz`. |
| AI features | Unverified | **Verified locally, honestly scoped** | TF-IDF grading, TextRank summary, fee-risk model: Dart unit tests pass. Python ML service: 13 tests pass. Live ML proxy UNVERIFIED (no `ML_SERVICE_URL`). No external generative AI exists. |

### G–I. Timetable, notifications/announcements, classroom

| Item | Original | Final | Change |
|---|---|---|---|
| Timetable on Firestore | Broken | **Fixed** | REST + `liveQuery` refresh after create/update/delete; errors surfaced. |
| Notifications/announcements on Firestore | Broken | **Fixed** | REST; refresh on change + 1–2 min polling; mark-read refreshes counters. |
| Classroom resources/queries on Firestore | Broken | **Fixed** | REST. Resource upload sent snake_case keys the validator rejected (every upload 400) — now camelCase with `contentText`. |

### J. Academic structure, sections, reports

| Item | Original | Final | Change |
|---|---|---|---|
| Academic structure | Firestore | **Fixed** | `GET/PUT /academic-structure`. |
| Class sections / section enrollment | Firestore | **Fixed** | Full REST repository; cascades to subject classes server-side. Section delete keeps classes and history (dialog text updated to say so). |
| Class reports | Firestore | **Fixed** | Generated **server-side** from stored attendance/fees with the client's local date (client can no longer persist invented figures). |

### K. OCR and PDF

| Item | Original | Final | Change |
|---|---|---|---|
| OCR persistence/history/view/delete | Broken | **Fixed** | Wrong paths (`/ocr/documents` → `/ocr`); private per author. ML Kit extraction untouched. |
| Publish OCR to classroom | Broken | **Fixed** | See resource payload fix; full text in `contentText` (50k limit). |
| Test-paper PDF Firestore academy lookup | Broken | **Fixed** | Academy header from `/auth/me`; fails loudly instead of printing without header. Printing/sharing on device UNVERIFIED. |

### L. Firebase cleanup

- Removed `firebase_core`, `firebase_auth`, `cloud_firestore`; deleted `lib/firebase_options.dart` and `lib/core/firebase_bootstrap.dart`; removed init from `main.dart` and splash; removed Google Services Gradle plugin declaration.
- Converted 11 models from `Timestamp/FieldValue` to ISO-8601.
- Admin dashboard "legacy migration" (wrote placeholder "N/A" addresses + Firestore doc) replaced with a profile refresh.
- Result: **0** Firebase references in `lib/`; `flutter analyze` clean. Offline SQLite member cache unaffected.

### M. Security

| Item | Final |
|---|---|
| `/users/by-role` role authorization | **Fixed** — ADMIN/TEACHER/PARENT only; parents see staff + own children; non-admins get reduced fields. |
| Cross-tenant enrollment / teacher assignment / all related entities | **Fixed + tested** across classes, sections, attendance, fees, quizzes, timetable, approvals. |
| Parent–child data access | **Tested** — attendance, fees, marks, profiles limited to linked children. |
| Financial data | **Tested** — challan list admin-only; per-student access checked. |
| JWT / refresh tokens | **Fixed** — unique `jti`, rotation, revocation on logout/deactivate/reset; configured expiries honoured. |
| Login rate limiting + account lockout | **Fixed** — per-IP limiter (existing) + per-account lockout (5 tries / 15 min, DB-backed). |
| Secrets/PII in logs | **Fixed** — error handler logs a sanitized summary instead of raw Prisma errors (which embed query args). |
| Runtime config validation | **Fixed** — new `src/config/env.js`; production refuses weak/example/identical secrets. `.env.example` no longer contains realistic secrets. |
| Committed DB files | **Fixed** — `.pgdata` untracked. |
| Firebase placeholder credentials | **Removed from tree**; key remains in git history (see remaining issues B2). |
| Automated authorization/tenant tests | **Added** — `repair.contract.test.js` (30 tests). |

### N. CI/CD

| Item | Final |
|---|---|
| Firebase empty-secret injection (`main.yml`) | **Fixed** — no Firebase injection anywhere. |
| Vercel output inconsistency | **Fixed** — `vercel.yml` stages `vercel_web/` then `vercel build` + `deploy --prebuilt`, so web **and** API functions deploy (old prebuilt output was static-only and dropped the API). |
| ML container build | **Fixed** — `container.yml` pointed at the deleted root `Dockerfile`; now `ml_service/Dockerfile` (+ HEALTHCHECK). |
| Python ML tests in CI | **Added** — `ml-service-test` job. |
| Backend CI | Node 22, schema validate, migration-drift check, route-contract check, DB contract tests on a disposable Postgres. |
| API URL validation | Release builds require an HTTPS `…/api/v2` URL in CI. Android allows cleartext **only** when the build's own `API_BASE_URL` is `http://` (LAN testing). |
| Runs on GitHub | **UNVERIFIED** (not pushed). |

## 3. Cross-cutting improvement

`lib/data/remote/live_query.dart`: REST "streams" previously fetched once and turned every error into an empty list, so screens never refreshed after edits and outages looked like "no data". The shared `liveQuery` refetches after local mutations (and optionally polls) and delivers errors as errors. Applied to classes, sections, reports, structure, timetable, announcements, notifications, resources/queries, quizzes/marks, OCR, and profile watching.

## 4. Database migration status

```
9 migrations found in prisma/migrations
Database schema is up to date!
prisma migrate diff --from-url <Neon dev> --to-schema-datamodel schema.prisma --exit-code
No difference detected.
```
New migration: `20261108150000_account_lifecycle_lockout` — `ALTER TYPE "AccountStatus" ADD VALUE 'INACTIVE'`; `users.failedLoginAttempts`, `lockedUntil`, `deactivatedAt`. Purely additive.

Test data created in the dev DB: 29 academies / 171 users, all `Contract …` / `Smoke Test Academy …`, `@test.taleemplus`. Non-test data (2 academies, 2 users) was not modified. Cleanup: `scripts/cleanup-test-data.js` (dry run by default).

## 5. New/changed files (main)

Backend: `src/controllers/{auth,user,attendance,fee,quiz,classSection,classReport}Controller.js`, `src/routes/{auth,user}Routes.js`, `src/app.js`, `src/config/env.js` (new), `src/middleware/errorMiddleware.js`, `prisma/schema.prisma`, `prisma/migrations/20261108150000_account_lifecycle_lockout/`, `package.json` (Jest setup, scripts), `scripts/{backup-db,check-client-routes,smoke-e2e,cleanup-test-data}.js` (new), `tests/{repair.contract,env}.test.js` (new), `tests/contract.test.js`, `tests/helpers/contractFixtures.js`, `.env.example`.

Flutter: `lib/data/remote/{live_query (new), auth_service, quiz_service, timetable_service, announcement_service, notification_service, classroom_service, academic_structure_service, pdf_generator_service}.dart`; `lib/data/repositories/{class, class_section, class_report, attendance, fee_challan}_repository.dart`; 14 model files; `lib/logic/{class_section_provider, member_provider, quiz_provider}.dart`; screens: login, signup, user management, approvals, class sections, class reports, fee ledger, admin dashboard, quiz results, splash, OCR service/publish; widgets: parent/teacher/admin stats rows; `lib/main.dart`; `pubspec.yaml`; `test/rest_models_test.dart` (new).

Build/CI: `.github/workflows/{main,flutter-ci,backend-ci,vercel,container}.yml`, `android/app/build.gradle.kts`, `android/settings.gradle.kts`, `AndroidManifest.xml`, `ml_service/Dockerfile`, `.gitignore`, `API_V2.md`.

UI design, colours, layouts and navigation were not changed. The only visible UI changes: a "Reset password" text button in the member edit sheet, the security-answer dialog now asks for the new password, deactivate/section-delete dialogs state accurate consequences, and error states replace silent empty lists.
