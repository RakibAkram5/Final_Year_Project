# TaleemPlus — Test Results

Date: 2026-11-08 · Machine: Windows 10, Flutter 3.47.9, Node 26.13, Python 3.15
Database: Neon PostgreSQL **development** database (approved by the owner for migrations and test inserts), 9/9 migrations applied.

Every result below was produced in this session by actually running the command. Nothing is copied from earlier reports.

## 1. Summary

| Area | Command | Result |
|---|---|---|
| Backend unit + DB contract tests | `TEST_DATABASE_URL=<dev db> npm test` | **81 passed / 81** (12 suites, 0 skipped) |
| Live HTTP smoke test, all 4 roles | `node scripts/smoke-e2e.js http://localhost:5055/api/v2` | **29 / 29 checks passed** |
| Client ↔ backend route contract | `npm run check:routes` | **91 client calls, 0 without a backend route** (was 20 broken) |
| Prisma schema vs database | `prisma migrate status` / `migrate diff --from-url … --exit-code` | **Up to date, "No difference detected"** |
| Flutter static analysis | `flutter analyze` | **No issues found** |
| Flutter formatting | `dart format` | applied; CI check uses `--set-exit-if-changed` |
| Flutter unit tests | `flutter test` | **31 passed / 31** (20 existing + 11 new) |
| Python ML service | `py -3 -m pytest -q` (ml_service) | **13 passed** |
| Web release build | `flutter build web --release` | **Succeeded** |
| Android release build | `flutter build apk --release --dart-define=API_BASE_URL=http://192.168.1.12:5055/api/v2` | **Succeeded** (93.8 MB) |
| Android device runtime | — | **UNVERIFIED** (no device attached; `adb devices` empty) |
| Browser UI walkthrough | — | **UNVERIFIED** |
| GitHub Actions / Vercel | — | **UNVERIFIED** (not pushed/deployed) |

## 2. Baseline at the start of this session

| Check | Baseline |
|---|---|
| Backend tests | 37 passed, **9 skipped** (the DB contract suite never ran: `TEST_DATABASE_URL` unset, and `tests/setupEnv.js` was never loaded by Jest) |
| Route contract | **20** Flutter calls hit paths the backend does not serve (attendance analytics, OCR, parent unlink, profiles, etc.) |
| Firestore usage | 5 active `FirebaseFirestore.instance` call sites + Firebase SDK init |
| Previous report claim | "A — Fully Ready" — not supported by the code or tests |

## 3. Backend test detail (final run, 280 s)

```
PASS tests/repair.contract.test.js   (30 tests, new, DB-backed)
PASS tests/contract.test.js          (9 tests, DB-backed — previously always skipped)
PASS tests/auth.test.js
PASS tests/env.test.js               (5 tests, new)
PASS tests/migrationIdentity.test.js
PASS tests/mlServiceClient.test.js
PASS tests/validation.test.js
PASS tests/roleMiddleware.test.js
PASS tests/mlFeatureService.test.js
PASS tests/rateLimit.test.js
PASS tests/studentAccess.test.js
PASS tests/passwordPolicy.test.js
Test Suites: 12 passed, 12 total
Tests:       81 passed, 81 total
```

`repair.contract.test.js` covers, with success **and** failure cases:

- **Auth:** real DB login (case-insensitive email), `/auth/me`, invalid credentials (401, no hash leak), refresh rotation (old token rejected), logout revocation, unique tokens for simultaneous logins, lockout after 5 failures (423 `ACCOUNT_LOCKED`, correct password also blocked), academy-code lookup (valid/unknown), security-question reset (wrong answer 403, sessions revoked), admin password reset (cross-academy 404, teacher 403, weak 400), refusal of ADMIN self-registration into an existing academy, pending account login (403 `ACCOUNT_PENDING`).
- **Users:** roll number persisted, case-insensitive uniqueness per academy (409), single-character roll numbers, other academy unaffected; profile update + cross-academy edit (404); deactivate/reactivate (self 400, cross-academy 404, teacher 403, inactive login 403, existing access token rejected, row preserved); parent link/unlink, cross-academy link rejected, `/users/profiles` returns only linked children, parents cannot enumerate unlinked students, students forbidden from `by-role`.
- **Classes/sections:** create with students, cross-academy student/teacher/enrollment rejected (403), class edit, unenroll, section create/roster cascade to subject classes, cross-academy roster rejected, server-side class report with local `logDate`, invalid date 400, report isolation, academic structure per academy + role + validation.
- **Attendance:** absent→present re-save produces exactly **one** DB row, academy-wide analytics endpoint returns it, parent sees only linked child, cross-academy student read blocked, teacher of another class blocked (403).
- **Fees:** ISO due date preserved, overdue status derived, duplicate period 409, cross-academy student 404, ledger `overdue_count` / `total_overdue` / monthly grouping, parent/admin data protection, cross-academy pay 404, mark paid with `paid_at`, bulk generation creates then skips existing period.
- **Quizzes/marks:** metadata (month, session, chapter, difficulty, test date) persisted, fractional question marks rounded, ISO `created_at`, students never receive answer keys, other teacher cannot read/edit/mark/delete (403), other academy 404, update questions, marks out of range 400, grade calculation, marks by quiz/class/academy/student, delete mark (row gone), delete quiz.
- **Other modules:** timetable role scoping and admin-only writes, announcements role targeting + update/delete + isolation, approval notification created and marked read, OCR documents private to author with update/delete.

## 4. Live end-to-end smoke test (running server, real HTTP, real DB)

```
Backend http://localhost:5055/api/v2 — health: ok, database: connected
PASS  [admin] register academy + admin — code TP-…
PASS  [admin] login (real DB record)
PASS  [admin] invalid password rejected
PASS  [admin] create teacher / student / parent account
PASS  [admin] roll number persisted and uniqueness enforced
PASS  [admin] link parent to child
PASS  [admin] create section + class with teacher and student
PASS  [admin] edit class details
PASS  [admin] timetable slot (today)
PASS  [admin] announcement to students and parents
PASS  [admin] fee challan (overdue) + ledger stats — billed 3000, overdue 3000
PASS  [teacher] login + /auth/me
PASS  [teacher] sees own class and timetable — 1 slot(s)
PASS  [teacher] mark attendance, re-save (no duplicate), reload
PASS  [teacher] create quiz with metadata, enter marks — grade A
PASS  [teacher] share resource and save OCR scan
PASS  [teacher] cannot reach admin-only endpoints
PASS  [student] login + dashboard data — 1 class, 1 attendance, 1 mark, 1 challan, 1 notice
PASS  [student] quiz list hides the answer key
PASS  [student] ask a question, see resources — 1 resource(s)
PASS  [teacher] answer the student question
PASS  [student] cannot read another student or admin data
PASS  [parent] login sees linked child
PASS  [parent] child's attendance, marks, fees, timetable — 1 attendance, 1 challan (overdue), 1 slot
PASS  [parent] cannot list other students
PASS  [admin] mark challan paid, deactivate + reactivate parent
PASS  [admin] session refresh + logout
29/29 checks passed.
```

This exercises the same endpoints and payloads the Flutter screens use. It is **not** a substitute for clicking through the UI (see UNVERIFIED items).

## 5. Builds

| Build | Result |
|---|---|
| `flutter build web --release` | **Succeeded** on the final code — `√ Built build/web` (compile 222.7 s). Uses same-origin `/api/v2` in production. |
| `flutter build apk --release --dart-define=API_BASE_URL=http://192.168.1.12:5055/api/v2` | **Succeeded** on the final code — `√ Built build/app/outputs/flutter-apk/app-release.apk (93.8MB)` (Gradle 710 s). Merged release manifest has `usesCleartextTraffic="true"` only because this build targets `http://`; HTTPS builds keep it `false`. A first attempt failed (Kotlin `java.util.Base64` resolved to Gradle's `java` extension) and was fixed with an import. |

## 6. Flutter tests (31)

`test/rest_models_test.dart` (new, 11 tests): fee ISO dates kept (no `DateTime.now()` fallback), Decimal-as-string amounts, overdue only after the due day, paid never overdue, billing-month grouping, missing due date rejected; attendance `log_date` parsed as a local day, `leave` status, missing date rejected; quiz ISO dates + metadata (no `Timestamp` cast); class section roll numbers; class report numeric strings; `liveQuery` refetch on topic and error-as-error recovery.
Existing `api_parsing_test.dart` and `core_logic_test.dart` (TF-IDF grader, TextRank summarizer, fee-risk model) still pass.

## 7. Bugs found *by the tests* during this session

1. Same-second JWTs were byte-identical → refresh rotation could re-issue the old token, and simultaneous logins could hit the unique constraint (500). Fixed with a random `jti`.
2. `GET /quizzes/marks` was routed to `GET /quizzes/:id` (`id="marks"`) → academy-wide marks always "not found". Fixed client path; route checker now flags literal-into-param matches.
3. Academy codes with lowercase characters were not found after normalisation. Lookup is now case-insensitive.
4. `tests/setupEnv.js` was never loaded, so `TEST_DATABASE_URL` did not actually redirect test writes. Fixed via `jest.setupFiles`.
