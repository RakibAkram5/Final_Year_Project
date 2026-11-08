# Migration Execution Plan

Status: Phase 1 complete; Phase 2 schema staging complete on local test databases; Phase 3 tooling implemented, real export pending  
Repository: `H:\Final Version`  
Baseline commit: `9d42d9ff01d1a9abde914f8e61858aae2f2bd5a8`  
Date: 2026-11-07

This plan migrates TaleemPlus from Firestore to the existing Express/Prisma/PostgreSQL API without destroying uncommitted work, data, or rollback options. It is ordered by dependency and uses staged, verifiable gates.

## 1. Scope and Non-Negotiable Constraints

### In scope

- REST backend parity for every currently used Firestore collection.
- Additive or staged PostgreSQL schema changes.
- Identity and tenant-key migration from Firebase UIDs to PostgreSQL UUIDs.
- Firestore data export/import, reconciliation, cutover, and cleanup.
- Flutter model, service, repository, provider, and configuration changes.
- Security fixes discovered during parity work.
- Tests, staging validation, deployment, and rollback procedures.

### Out of scope unless separately approved

- Rewriting the application UI.
- Replacing the Express/Prisma stack.
- Building a general file-storage service.
- Designing a new real-time push system.
- Changing authentication away from JWT.
- Integrating the unconfigured external ML service.

### Non-negotiable constraints

1. Preserve the verified backup at `C:\Users\Mraki\AppData\Local\Temp\opencode\taleemplus_phase0_backup_20261105_102932`.
2. Do not reset Git, overwrite uncommitted work, or force-push.
3. Do not remove Firebase packages until REST parity, data migration, and the observation window are complete.
4. Do not run destructive database commands against a shared database.
5. Do not insert placeholder passwords.
6. Do not expose or commit secrets, service-account files, exports containing PII, or `.env` values.
7. Do not assume `Firebase UID == academy UUID`. Every legacy reference must resolve through an explicit mapping.
8. Do not claim migration success from empty tables or empty exports.
9. Real-time behavior must be explicitly replaced by refresh-on-mutation or another approved mechanism.
10. The old Firebase-backed app must not keep writing after cutover; otherwise data diverges.

## 2. Target Architecture

```
Flutter app
  -> ApiClient (JWT, canonical JSON/date parsing, typed errors)
  -> REST /api/v2
  -> Express controllers + validation + tenant scoping
  -> Prisma
  -> PostgreSQL
```

Target rules:

- PostgreSQL owns all application data.
- The JWT determines `userId`, `academyId`, and `role`.
- Client-supplied `academyId` is never trusted.
- All related IDs are validated inside the caller’s academy.
- Responses use one casing and one date format.
- Firebase exists only as a read-only archive during the rollback/observation window.

## 3. Decisions Required Before Implementation

These decisions gate the affected phases. Recommended defaults are included.

| Decision | Recommended default | Gate |
|---|---|---|
| Real-time replacement | One-shot reads plus explicit refresh after mutation; add polling only for notification badges if required | Client phase |
| Canonical section model | Add `ClassSection` + `ClassSectionEnrollment`; keep `Class` as subject offering linked to a section | Schema phase |
| Roll-number ownership | Store on section/subject enrollment, not `User` | Schema phase |
| Previous Firebase data | Use real export and identity mapping; no import without reconciliation | Data phase |
| Firebase Storage files | Preserve external URLs initially; migrate files only if private/expiring URLs are found | Data phase |
| Password credentials | Verify hash format before import; otherwise implement legacy verification/rehash or force secure reset. Never use a fixed placeholder | Identity phase |
| Password recovery | Implement real reset or remove the fake UI; do not ship fake success | Auth slice |
| Academy-code mutation | Add validated backend update or remove reconnect/regeneration UI | Auth slice |
| Old app shutdown | Force minimum version or disable old builds after cutover | Cutover phase |
| Firebase project deletion | Archive read-only; delete only after retention/legal approval | Cleanup phase |

If any recommended default is rejected, update the inventory and gap analysis before starting that phase.

## 4. Phase Overview

| Phase | Name | Primary outcome | Gate |
|---|---|---|---|
| 0 | Baseline and documentation | Inventory, gap analysis, plan, backup | This document set verified |
| 1 | Contract and safety foundation | Stable DTO/date/error contract, routing and tenant helpers, test harness | Contract tests pass |
| 2 | Schema staging | Additive schema and indexes ready for parity work | Migrations pass on staging and local copy |
| 3 | Identity and tenant mapping | User/academy legacy IDs resolved; no `uid`-as-academy keys | Mapping report has zero unexplained references |
| 4 | Backend parity slices | Every collection has secure REST behavior | Per-slice acceptance criteria pass |
| 5 | Client parity slices | Flutter uses REST for all migrated modules | No Firestore imports remain in active code |
| 6 | Data dry run and reconciliation | Real export imports idempotently to staging | Counts/references/samples reconciled |
| 7 | Production cutover | REST-only release with frozen Firebase writes | Smoke tests and monitoring pass |
| 8 | Observation and Firebase removal | Firebase archived and code/config removed | Retention window passes; build/tests pass |

Phases 4 and 5 can overlap after each API contract is frozen. Data work in Phase 6 can start once identity and schema are stable.

## 5. Phase 0: Baseline and Documentation

Completed artifacts:

- `TALEEMPLUS_PROJECT_AUDIT.md`
- `FIREBASE_MIGRATION_INVENTORY.md`
- `REST_API_GAP_ANALYSIS.md`
- `MIGRATION_EXECUTION_PLAN.md`

Required final checks:

- Confirm backup manifest and hashes still match.
- Confirm baseline `flutter analyze`, `flutter test` (12/12), `npm test` (17), web release, debug APK, and `/health`.
- Confirm no source files were changed by Phase 0 except the documentation files.
- Record exact commit and environment in the migration runbook.

Exit: documentation reviewed; open decisions accepted or revised.

## 6. Phase 1: Contract and Safety Foundation

Do this before module rewrites so later work does not repeat contract bugs.

### 6.1 Backend

1. Add a canonical response layer:
   - one casing convention for collection DTOs;
   - ISO-8601 dates;
   - lowercase enum values;
   - consistent `{ success, data, message }` envelope;
   - stable error codes/statuses.
2. Add shared validators for IDs, dates, enums, and pagination. Use the installed validation library consistently.
3. Add tenant helpers:
   - `requireAcademy(req)`;
   - `assertEntityInAcademy(model, id, academyId)`;
   - `assertRole(req, roles)`.
4. Fix resource router mounting so the canonical paths are `/api/v2/resources` and `/api/v2/queries`.
5. Add backend contract tests using at least:
   - two academies;
   - admin, teacher, student, parent;
   - same-tenant and cross-tenant access attempts.
6. Add seed/fixture utilities for tests and staging. `prisma/seed.js` is referenced but missing.
7. Add rate limiting for login and sensitive auth actions.
8. Document v1 as deprecated. Do not add new v1 routes.

### 6.2 Flutter

1. Add centralized parsing in `ApiClient`:
   - ISO date parser;
   - nullable/missing-field handling;
   - typed API exception.
2. Stop converting API failures to empty lists in repositories.
3. Add a shared test fixture strategy for API payloads.
4. Document the refresh semantics that replace Firestore streams.

### 6.3 Gate

- Two-academy contract tests pass.
- Resource/query canonical paths are reachable exactly once.
- A deliberately invalid date, enum, tenant ID, and role returns a defined non-2xx response.
- Flutter parses a shared fixture suite without exceptions.
- No schema or Firebase removal yet.

### 6.4 Implementation status (2026-11-05)

Completed:

- Canonical response/error helpers: `src/utils/response.js`, `src/utils/apiError.js`.
- Tenant guards: `src/utils/tenant.js` (`requireAcademy`, `assertRole`, `assertEntityInAcademy`, class/student/enrollment assertions).
- Shared Zod validators and middleware: `src/utils/validation.js`.
- DTO date/enum helpers: `src/utils/dto.js`.
- Rate limiting for login, registration, and refresh: `src/middleware/rateLimit.js`.
- Canonical resource/query mounting at `/api/v2/resources` and `/api/v2/queries`; v1 marked deprecated with headers.
- Attendance and resource/query controllers now validate tenant, role, ID, date, and enum input, return canonical DTOs, and reject cross-tenant access.
- Idempotent demo/staging seed: `prisma/seed.js` (refuses production unless `ALLOW_SEED=true`).
- Backend contract tests: `tests/contract.test.js`, `tests/helpers/contractFixtures.js`, plus limiter/date unit tests.
- Flutter central date/enum parsing and typed `ApiException`: `ApiClient.parseDate`, `parseRequiredDate`, `dateOnly`, `normalizeEnum`; attendance save now sends `YYYY-MM-DD`.
- Flutter fixture test: `test/api_parsing_test.dart`.

Verification run:

```powershell
# Disposable local test database on port 5433
$env:TEST_DATABASE_URL='postgresql://postgres:postgres@localhost:5433/taleemplus_test?schema=public'
$env:DATABASE_URL=$env:TEST_DATABASE_URL
npm test          # 9 suites, 31 tests passed in taleemplus_backend
flutter test      # 20 tests passed
flutter analyze   # no issues
```

Contract tests run only when `TEST_DATABASE_URL` is set, so a developer machine that
points `DATABASE_URL` at a shared database cannot accidentally run them. CI sets
`TEST_DATABASE_URL` to its disposable PostgreSQL service.

Deferred to the client parity phase: removing all repository error-to-empty-list
fallbacks. The API client now preserves status/code, but screens must gain error
states before those fallbacks are removed safely.

## 7. Phase 2: Schema Staging

Use Prisma migrations. Do not use `db push` for shared environments. Create a database snapshot before applying to any non-disposable database.

### 7.1 Migration sequence

**M1 — Identity and academy structure**

- Add optional `User.legacyFirebaseUid` (`@unique`).
- Add optional `Academy.legacyFirebaseUid` (`@unique`).
- Add optional profile fields needed by current UI: `subject`, `extraInfo`, `joiningDate`.
- Add `Academy.academicStructure Json?`.
- Add a migration-only `LegacyIdMap` table keyed by `(collection, legacyId)` with target table/ID and status.
- Add supporting indexes.

**M2 — Sections and rosters**

- Add `ClassSection` (`academyId`, `className`, `program`, `section`, timestamps, unique key).
- Add `ClassSectionEnrollment` (`sectionId`, `studentId`, `rollNumber`, timestamps, unique keys).
- Add optional `Class.program` and `Class.classSectionId`.
- Validate `rollNumber` format and uniqueness per section.
- Do not remove the existing per-class enrollment table.

**M3 — Reports and attendance indexes**

- Add `ClassReport` with academy, section label, generated time, counts, and fee/attendance summary fields.
- Add attendance indexes for `(academyId, logDate)` and reporting.

**M4 — Timetable alignment**

- Add target typed columns for integer day, start/end minutes, room, semester, break flag, effective dates, and optional teacher.
- Keep old columns temporarily if the table may contain remote data.
- Backfill from old strings only after validating formats.
- Do not drop old columns until the client no longer uses them and data reconciliation is complete.

**M5 — Fee, resource, OCR, notification fields**

- Add/validate `FeeChallan.billingPeriod`; backfill from due dates where possible, then make required only after duplicate/missing review.
- Add `SharedResource.contentText`; make `fileUrl` nullable.
- Add `OcrDocument.academyId`, `createdByName`, `updatedAt`.
- Add notification/announcement/query indexes.
- Add any required updated-at fields used by delta exports.

**M6 — Indexes and constraints**

- Add indexes listed in the gap analysis.
- Add foreign keys carefully; quarantine or clean orphans before constraint tightening.
- Add uniqueness constraints last, after duplicate resolution.

### 7.2 Migration safety rules

- Every migration is additive first, backfill second, constraint third, cleanup last.
- Record before/after row counts and constraint validation.
- Test each migration against:
  - a fresh empty database;
  - a copy of the current local database;
  - staging data resembling production.
- Keep rollback SQL or a verified snapshot for each production migration.
- Never rewrite or delete rows without a dry-run report.

### 7.3 Gate

- `prisma migrate` succeeds from baseline and from empty.
- Backfills are idempotent.
- Constraint validation has zero unexplained failures.
- Seeded local/staging data supports all backend slices.

### 7.4 Implementation status (2026-11-05)

Migration `20261105190000_phase2_schema_staging` adds the additive Phase 2 schema:

- Identity: `User.legacyFirebaseUid`, `User.subject`, `User.extraInfo`, `User.joiningDate`; `Academy.legacyFirebaseUid`, `Academy.academicStructure` JSON.
- Section rosters: `ClassSection`, `ClassSectionEnrollment`, `Class.program`, `Class.classSectionId`.
- Reports: `ClassReport` snapshot fields for students, attendance, and fee totals.
- Timetable: typed `dayOfWeekInt`, `startMinutes`, `endMinutes`, `room`, `semester`, `isBreak`, effective dates; legacy string columns retained; `teacherId` nullable for break slots.
- Content: `SharedResource.contentText`, `fileName`, `mimeType`, nullable `fileUrl`, `updatedAt`; `OcrDocument.academyId`, `createdByName`, `updatedAt`.
- Mapping and indexes: `LegacyIdMap` plus the indexes listed in the gap analysis.

Deliberately deferred until after data review: backfilling legacy IDs, making `OcrDocument.academyId` required, tightening timetable constraints, dropping legacy timetable columns, and making `FeeChallan.billingPeriod` required.

Verification run:

- `prisma migrate deploy` succeeded on the local `taleemplus_test` database from the baseline history.
- `prisma migrate deploy` succeeded on a fresh empty database, which was then dropped.
- The expanded `prisma/seed.js` ran twice with identical row counts (idempotent) and seeded a section, roster, attendance, challan, quiz, mark, resource, query, notification, announcement, timetable slot, report, and OCR document.
- Backend tests still pass: 9 suites, 31 tests.
- No shared or production database was touched.

## 8. Phase 3: Identity and Tenant Mapping

This is the highest-risk phase. It must complete before data import or client identity cutover.

### 8.1 Source-of-truth mapping

1. Export Firestore `users` and any academy/settings documents with a real Admin SDK export.
2. Classify legacy documents:
   - admin user;
   - teacher;
   - student;
   - parent;
   - academy/settings document;
   - unknown.
3. Create or match a PostgreSQL `Academy` for each real academy.
4. Create/match PostgreSQL users by normalized email.
5. Generate PostgreSQL UUIDs and record `(collection, legacyId) -> (table, targetId)` in `LegacyIdMap`.
6. Set `User.legacyFirebaseUid` and `Academy.legacyFirebaseUid` where applicable.
7. Map every legacy `academy_id`, `created_by`, `teacher_id`, `student_id`, `parent_id`, `uploaded_by`, `recipient_id`, and equivalent field through the ledger.
8. Quarantine unresolved references. Do not guess a tenant.

### 8.2 Credential policy

- Inspect the actual exported hash format before importing users.
- If the hash is bcrypt-compatible, import it and verify one test account.
- If hashes come from Firebase Auth’s incompatible format, choose one:
  - implement a legacy verification path and rehash to bcrypt on successful login;
  - force a secure password reset through an email/provider;
  - have an admin issue one-time reset credentials.
- Never import the fixed placeholder used by `scripts/migrate_firebase_to_postgres.js`.
- If no Firebase Auth data exists, create a controlled initial admin and document it.

### 8.3 Required identity rules

- Login is by normalized email, globally unique as defined by the schema.
- Parent links reference PostgreSQL user UUIDs.
- `linkedChildren` is returned by login or hydrated through `/auth/me` before parent features load.
- Roll numbers are enrollment data, not identity.
- Academy codes remain unique per academy.

### 8.4 Gate

- Mapping report covers 100% of imported users and academy references.
- No imported record contains a legacy UID in a UUID field.
- No tenant reference is unresolved or guessed.
- Admin UID → academy UUID mapping is reproducible.
- Test users can authenticate with the approved credential path.
- Cross-tenant probing returns not-found/forbidden, not data.

### 8.5 Implementation status (2026-11-07)

Tooling is implemented; the phase gate remains open until a real Firestore export is processed.

Completed:

- Real Admin SDK export tool: `taleemplus_backend/scripts/migration/exportFirestore.js`
  (`npm run migrate:export`). Writes JSONL per collection plus `manifest.json` with
  per-collection counts, byte sizes, and SHA-256 checksums, converts Firestore
  timestamps/geo points/references, and refuses to run without a service account.
- Dry-run-first identity planner: `taleemplus_backend/scripts/migration/lib/identity.js`.
  Pure functions normalize emails, roles, statuses, dates, and bcrypt hashes; classify
  academy/user records; create or match academies by `LegacyIdMap`, `legacyFirebaseUid`,
  PostgreSQL ID, or academy code; match users by normalized email; and quarantine
  invalid emails, invalid roles, duplicate emails, unresolved academies, academy/role
  conflicts, legacy-UID conflicts, and non-importable password hashes.
- Identity importer: `taleemplus_backend/scripts/migration/runIdentityImport.js`
  (`npm run migrate:identity`). Reads `users` and `academy_settings` JSONL/JSON,
  builds the plan, writes a PII-masked report, and only writes to PostgreSQL when
  `--apply` is passed. Applies inside one transaction, records `LegacyIdMap` rows for
  every mapped and quarantined identity, sets `User/Academy.legacyFirebaseUid`, and is
  idempotent across reruns. Missing/incompatible password hashes are quarantined by
  default; `--on-missing-password reset` creates the account as `PENDING` with a random
  unknown hash and a `PASSWORD_RESET_REQUIRED` note. No fixed placeholder is ever used.
  `--apply` refuses to write while the gate still has unresolved identities unless
  `--allow-incomplete` is passed, which applies the mappable records and leaves the
  rest quarantined.
- Mapping gate verifier: `taleemplus_backend/scripts/migration/verifyIdentity.js`
  (`npm run migrate:verify`). Checks export checksums, empty exports, unmapped users
  and academy references, non-UUID targets, missing target rows, and missing/mismatched
  `legacyFirebaseUid` values. Fails the gate on any unresolved identity.
- Root placeholder scripts now delegate to the safe tooling instead of inserting
  placeholder users or printing misleading counts.
- `.gitignore` excludes `migration_exports/` and `*.jsonl`; reports mask email addresses.
- Unit tests: `taleemplus_backend/tests/migrationIdentity.test.js` (15 tests).
- End-to-end verification on a disposable local PostgreSQL cluster: dry run, apply,
  idempotent rerun, quarantine gate (`verify` exits 1), and `--allow-incomplete` all
  behaved as designed. The throwaway cluster and fixtures were removed afterward.

Not yet done (requires the real project):

- Run the export against the live Firebase project.
- Resolve every quarantine and academy-reference review item in the real report.
- Verify one imported account per role against the approved credential path.
- Backfill remaining legacy reference fields (`created_by`, `teacher_id`, `student_id`,
  `parent_id`, `recipient_id`) when the other collections are exported in Phase 6.

Commands:

```powershell
cd taleemplus_backend
npm install --no-save firebase-admin
$env:FIREBASE_SERVICE_ACCOUNT='C:\secure\service-account.json'
npm run migrate:export -- --out ..\migration_exports\2026-11-07
npm run migrate:identity -- --export-dir ..\migration_exports\2026-11-07
npm run migrate:verify -- --export-dir ..\migration_exports\2026-11-07
# Only after reviewing the dry-run report and taking a verified database backup:
npm run migrate:identity -- --export-dir ..\migration_exports\2026-11-07 --apply
```

## 9. Phase 4: Backend Parity Slices

Implement backend slices in dependency order. Each slice includes route, controller, validation, DTO, tests, and documentation.

### Slice B1 — Auth, users, profiles, parents

Deliverables:

- Profile fields in login/me/user DTOs.
- Add linked children to login or enforce `/me` hydration.
- `PATCH /users/me` or equivalent profile update.
- Parent directory/search endpoint scoped to academy and STUDENT role.
- Remove-child endpoint.
- Roll-number capture and response path.
- Real account recovery or removal of fake recovery UI.
- Restrict `GET /users/by-role`; return role-appropriate fields.
- Parent self-link enforcement for PARENT callers.
- Academy-code persistence if the feature remains.
- Approval/rejection behavior: backend notification, no duplicate Firestore dependency, no false failure after success.

Acceptance:

- Parent can find and link/unlink an eligible student.
- Member edit persists and is visible after refresh.
- Any authenticated non-admin cannot enumerate all users.
- Parent cannot link another parent ID.
- Roll-number uniqueness is enforced where the product requires it.

### Slice B2 — Academic structure, sections, classes, enrollment

Deliverables:

- Academic structure GET/PUT with defaults.
- Section CRUD and roster management.
- Class CRUD including update.
- Enroll/unenroll with academy, role, and section validation.
- Class create-with-roster or transactional client orchestration.
- Canonical section label and roster DTOs.

Acceptance:

- Academy A cannot read or mutate Academy B’s structure/classes/sections.
- Class update persists.
- Unenroll removes the roster row.
- Selected students are enrolled on create.
- Roll numbers round-trip.
- No screen passes an admin UID where an academy UUID is required.

### Slice B3 — Attendance

Deliverables:

- Class attendance response DTO with `student_name`, lowercase status, snake_case fields.
- Accept `logDate` as date-only.
- Academy-wide/date-range query.
- Roster/role validation on mark.
- Preserve last-editor metadata or add audit.

Acceptance:

- Save/encode works with `YYYY-MM-DD`.
- Class reload renders names and statuses.
- Academy stats show real rows.
- Cross-class/student mismatch is rejected.
- Duplicate marks update rather than duplicate.

### Slice B4 — Fees

Deliverables:

- Consistent ISO date DTOs.
- Section/roster-based bulk generation.
- Atomicity and duplicate protection.
- `billingPeriod` rules.
- Overdue derivation.
- Safe challan correction/void if required.

Acceptance:

- Bulk run either creates all eligible challans or rolls back.
- Re-running does not create duplicates.
- Dates display correctly in list/detail/analytics.
- Student and parent fee views work.
- Cross-tenant challan access is denied.

### Slice B5 — Quizzes and marks

Deliverables:

- Robust quiz date parsing contract.
- Student-safe quiz DTO without `correct_index`.
- Role/class scoping.
- Update/delete quiz.
- Question replacement/update.
- Marks by quiz/class and admin views.
- Delete mark.
- Enrollment validation.
- Submission decision: implement or remove.

Acceptance:

- Quiz list renders with ISO dates.
- Student cannot retrieve answer keys or unrelated class quizzes.
- Teacher can see results only for authorized classes.
- Update/delete and mark deletion persist.
- PDF test paper obtains academy/profile data from REST.

### Slice B6 — Timetable

Deliverables:

- Final timetable contract approved with Flutter.
- Update and bulk operations.
- Break-slot representation without a required teacher.
- Range/class/room collision validation.
- Effective-date/semester filters.
- Class-delete cleanup/cascade.

Acceptance:

- Create/update/delete round-trip matches the Flutter model.
- Break slots save.
- Overlapping ranges are rejected.
- Cross-tenant access is denied.
- Class deletion leaves no orphan slots.

### Slice B7 — Resources and student queries

Deliverables:

- Correct router mount and canonical URLs.
- Resource create/read/delete, text-only content, optional attachment URL.
- Query create/list/answer with role and enrollment scoping.
- Teacher query filter.
- Tenant/class validation for related IDs.
- Parent/student visibility policy.

Acceptance:

- OCR can publish a text-only resource.
- Teacher sees only assigned queries.
- A student cannot answer or read another student’s private query.
- Cross-tenant class/resource/query IDs are rejected.
- Resource/query deletes are safe and authorized.

### Slice B8 — Announcements and notifications

Deliverables:

- Announcement CRUD.
- Server-side target-role filtering.
- Notification fan-out or an explicitly documented alternative.
- Mark-one/mark-all-read.
- Pagination/cap.
- Optional system/admin notification creation.
- Rejection notification if required.

Acceptance:

- A student does not receive teacher-only announcements.
- Announcement create/update/delete works.
- Notification badge count updates after read-all.
- Approval/rejection produces exactly one correct notification.
- Cross-tenant recipient injection is rejected.

### Slice B9 — OCR and PDF

Deliverables:

- OCR CRUD with owner/admin scope.
- Academy audit fields.
- Text-only resource publishing.
- PDF academy profile from REST.
- Attachment decision implemented or documented.

Acceptance:

- OCR history survives app restart.
- Delete removes the correct owner record.
- Publish creates a resource visible in the target class.
- Test-paper PDF works without Firestore.

### Slice B10 — Hardening and operational readiness

Deliverables:

- Full role/tenant test matrix.
- Pagination and limits where required.
- Error codes documented.
- Seed data for demo/staging.
- Rate limit and auth audit.
- Logging without secrets/PII.
- OpenAPI or equivalent endpoint reference.

Exit gate for Phase 4:

- All P0 gaps in the gap analysis are closed or explicitly removed.
- Two-academy tests prove isolation.
- No production client code is changed yet except test scaffolding; backend remains backward compatible during build-out.

## 10. Phase 5: Client Parity Slices

Migrate one slice at a time. Keep Firebase code until the slice passes, then remove that slice’s Firestore path. Do not leave two writable backends.

### 10.1 Model and infrastructure work

1. Replace Firestore `Timestamp`/`FieldValue` parsing with plain JSON date/string parsing in all 15 affected models.
2. Add explicit `fromJson`/`toJson` mapping tests using backend DTO fixtures.
3. Add typed errors and user-visible failure states.
4. Implement refresh-after-mutation in screens that previously relied on streams.
5. Keep parent/member SQLite only if separately approved; otherwise remove it as a source of truth after REST parity.

### 10.2 Client slices

| Slice | Replace | Verification |
|---|---|---|
| C1 | Auth/profile/parent/member services and providers | Login, profile edit, child link/unlink, roll number, role lists |
| C2 | Academic structure, sections, class management | Structure save/reload, section CRUD, roster, create/edit/delete class |
| C3 | Attendance repository and screens | Save, class reload, student history, academy stats |
| C4 | Fee repositories/screens | Student list, bulk generation, pay, proofs, ledger, parent view |
| C5 | Quiz service, marks, PDF | List/create/edit/delete, marks, results, PDF |
| C6 | Timetable service/provider | CRUD, breaks, collisions, filters |
| C7 | Classroom resource/query service/screens | Publish text resource, query, teacher queue, answer |
| C8 | Announcements/notifications and badges | CRUD, filtering, read-all, badge refresh |
| C9 | OCR history/publish and admin reports | History, delete, publish, report generate/list |
| C10 | App bootstrap/config | No Firebase initialization; production API URL; manifest networking |

### 10.3 Client rules

- Never pass `user.uid` as `academyId`.
- Use the JWT-derived tenant; remove academy arguments that exist only to work around identity confusion.
- Do not silently convert network/auth errors to empty data.
- Do not use Firestore timestamps in REST code.
- Do not keep a Firestore write path “just in case.”
- Every migrated module needs at least one contract/fixture test and one widget or provider test for its main workflow.

### 10.4 Firebase removal inside the client

Remove only after every slice passes:

1. Remove `cloud_firestore` usages and types.
2. Remove `firebase_auth` if still unused.
3. Remove `Firebase.initializeApp` and `firebase_options.dart`.
4. Remove Firebase dependencies from `pubspec.yaml` and regenerate lockfiles.
5. Remove Google Services references, rules/indexes, and Firebase scripts/config after the archive step.
6. Add Android `INTERNET` permission and production HTTPS network configuration.
7. Re-run `flutter analyze`, `flutter test`, web release, and Android release/debug builds.
8. Search with PowerShell `Select-String`/`Get-ChildItem` for `firebase`, `Firestore`, `Timestamp`, and `FieldValue`; zero active references required.

Exit gate:

- The application is fully REST-backed.
- No active Firebase import or initialization remains.
- All migrated workflows pass in staging.
- Baseline tests plus new contract/workflow tests pass.

## 11. Phase 6: Data Export, Import, and Reconciliation

This phase may be marked “no remote data” only if a real export proves the collections are empty. Do not infer emptiness from placeholder local export files.

### 11.1 Export

1. Create a read-only Firebase Admin service account outside the repository.
2. Export each live collection to JSONL with document IDs, timestamps, and counts:
   - `academy_settings`, `users`, `announcements`, `class_reports`, `class_sections`, `classes`, `learning_resources`, `notifications`, `student_queries`, `timetables`, `ocr_documents`.
3. Export Firebase Auth metadata only if credentials are in scope and allowed.
4. Export Storage object inventory/URLs if attachments are present.
5. Record per-collection counts, checksums, export time, and schema samples.
6. Encrypt or restrict access; delete working copies after the retention period.

### 11.2 Import tool

Replace the placeholder scripts. The importer must:

- connect to Firestore/export files and PostgreSQL;
- validate collection/document schemas;
- use `LegacyIdMap` for idempotency;
- run dry-run by default;
- show planned creates/updates/quarantines;
- remap all identity/tenant references;
- import in dependency order;
- use transactions/chunks with progress and retry;
- produce a machine-readable reconciliation report;
- never print secrets or full PII rows;
- abort on unresolved tenant references unless explicitly quarantining.

### 11.3 Import order

1. Academies and settings → academic structure.
2. Users and credentials → identity map.
3. Parent-child links.
4. Class sections and rosters.
5. Classes and enrollments.
6. Attendance.
7. Fees/challans/payments.
8. Quizzes/questions/marks/submissions.
9. Timetable.
10. Resources/attachments metadata.
11. Student queries.
12. Announcements and notifications.
13. OCR documents.
14. Class reports.

### 11.4 Reconciliation

Required checks:

- document count vs imported/quarantined count per collection;
- unique email/academy-code conflicts;
- unresolved legacy tenant IDs = 0;
- orphan foreign keys = 0 or quarantined;
- duplicate challenging/challan/roll/quiz records resolved;
- sums for fee amounts, attendance counts, and marks match source;
- random sample of at least 20 records per non-empty collection verified field by field;
- login test for each role;
- cross-tenant probe test;
- rerun import produces no duplicates.

Exit gate: dry-run and staging import reconcile with zero unexplained discrepancies.

## 12. Phase 7: Production Cutover

### 12.1 Preflight

- Confirm backup and restore rehearsal succeeded.
- Confirm no untracked critical files are missing; rerun preservation manifest.
- Apply production migrations during a controlled window.
- Verify `/health`, DB connectivity, migrations, seed/initial admin, and monitoring.
- Deploy the REST backend before the client release.
- Confirm production API URL and HTTPS.
- Confirm old-app shutdown enforcement.

### 12.2 Freeze and final delta

1. Announce a write freeze.
2. Stop accepting writes from old Firebase-backed clients.
3. Perform the final export/delta import and reconciliation.
4. Re-run smoke tests with staging-equivalent accounts.
5. Release the REST-only client.
6. Monitor login, class, attendance, fees, quizzes, notifications, and error rates.

### 12.3 Rollback policy

- **Before the new client accepts writes:** restore the previous client and backend; Firestore is unchanged.
- **After real writes begin:** there is no automatic reverse sync to Firestore. Prefer forward fixes.
- If a full rollback is unavoidable, restore the verified PostgreSQL snapshot and accept loss of writes after that snapshot; communicate explicitly.
- Do not claim dual-write or lossless rollback unless dual-write was actually implemented and tested. It is not part of this plan.
- Keep Firebase data read-only and the previous build available for the agreed observation period.

Exit gate: REST-only release stable for the observation window; no critical data discrepancy.

## 13. Phase 8: Observation and Firebase Removal

### 13.1 Observation

- Keep Firebase project and export read-only.
- Monitor backend errors, auth failures, tenant violations, and data correction requests.
- Compare daily counts and key financial/attendance totals.
- Fix defects through normal releases; do not re-enable Firestore writes.

### 13.2 Removal checklist

Only after the retention window and formal sign-off:

1. Remove Firebase packages, initialization, options, and all active code references.
2. Remove `firebase.json`, `.firebaserc`, Firestore rules/indexes, and obsolete migration placeholders after archiving them outside the repo.
3. Remove Google Services references and any service-account artifacts from the workspace.
4. Rotate any credentials exposed during setup.
5. Archive the approved export and reconciliation report according to the data-retention policy.
6. Delete or restrict the Firebase project only with owner approval.
7. Re-run all tests and release builds.
8. Update README/deployment docs with PostgreSQL-only operation.

Exit gate: zero active Firebase references, passing builds/tests, documented archive location, and signed cleanup approval.

## 14. Test Strategy

### Backend

- Unit: validators, tenant helpers, date/enum formatters.
- Integration: Supertest against a disposable PostgreSQL database.
- Matrix: two academies × admin/teacher/student/parent × allowed/denied.
- Contract: every DTO used by Flutter has a fixture.
- Migration: dry-run, idempotent rerun, orphan/quarantine report.
- Regression: login/refresh, approve/reject, class roster, attendance, fee pay, quiz marks, notification read.

### Flutter

- Model parsing with ISO dates, missing optional fields, nulls, uppercase enums.
- Service/repository tests with mocked HTTP.
- Provider/widget tests for the main workflow per slice.
- Offline/error/retry states, not just success.
- Full analyze/test/build gate.

### Data

- Count reconciliation per collection.
- Referential integrity and tenant isolation assertions.
- Financial/attendance/marks totals.
- Sample field-level comparison.
- Rerun idempotency.

### Manual staging smoke

1. Admin login, profile, structure, sections.
2. Create/edit/delete class; enroll/unenroll; roll number.
3. Teacher attendance save/reload/stats.
4. Fee generate/pay/proof/ledger.
5. Quiz create/edit/delete/marks/results/PDF.
6. Timetable with break and collision rejection.
7. OCR publish text resource; student query/teacher answer.
8. Announcement target filtering/notification read-all.
9. Parent child link, attendance, fees, quiz marks.
10. Cross-tenant URL/ID probes.

## 15. Deployment and Environment Plan

- Separate local, staging, and production databases.
- Use environment variables for `DATABASE_URL`, `JWT_SECRET`, `JWT_REFRESH_SECRET`, API base URL, and optional ML settings. Never commit them.
- Keep production HTTPS; remove HTTP dev defaults from release builds.
- Add `INTERNET` to the main Android manifest and verify release networking.
- Back up before migrations; verify restore before cutover.
- Run migrations as a controlled deploy step, not at app startup.
- Add monitoring/alerts for 5xx rate, login failures, migration/import failures, and DB connectivity.
- Document on-call rollback steps and the Firebase archive owner.

## 16. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Remote data shapes differ from assumptions | High | High | Export first; schema validation; quarantine unknown records. |
| Legacy password hashes incompatible | Medium | High | Verify format; legacy verify/rehash or forced reset; never placeholder. |
| Admin UID used as academy ID | High | High | Explicit mapping ledger; zero unresolved references gate. |
| Tenant leak through ID-only updates | High | Critical | Tenant-scoped helpers and two-academy tests. |
| Client still writes to Firestore after cutover | Medium | High | Force old-app shutdown; remove Firebase code; monitor. |
| Real-time UI silently stops updating | High | Medium | Implement refresh-after-mutation and test each screen. |
| Empty tables hide missing parity | High | High | Fixture/staging data required; empty-data rule. |
| Schema migration lock/rewrite | Medium | High | Additive columns, staged backfill, maintenance window. |
| Attachment URLs expire | Medium | Medium | Inventory Storage; copy or preserve URLs deliberately. |
| Rollback after write loss | Medium | High | Short controlled cutover, backups, forward-fix culture, explicit policy. |
| Unrelated uncommitted work lost | Medium | High | Verified backup, preservation manifest, no resets. |

## 17. Definition of Done

Migration is complete only when all are true:

- Every used Firestore collection is represented in PostgreSQL through REST or formally removed.
- No active Flutter code imports Firebase, Firestore, or Firestore types.
- No Firebase initialization or placeholder options run at startup.
- Every identity and tenant reference uses PostgreSQL UUIDs with valid foreign keys.
- All role/tenant isolation tests pass, including cross-tenant probes.
- Data reconciliation shows zero unexplained discrepancies.
- All P0 and P1 security findings are fixed or explicitly accepted.
- Parent linking, class/section rosters, attendance, fees, quizzes, timetable, resources/queries, notifications, OCR, reports, and PDF work through REST.
- Release web/APK builds pass with production networking.
- The migration runbook, archive location, rollback policy, and ownership are documented.
- The observation window is complete and Firebase removal is approved.
