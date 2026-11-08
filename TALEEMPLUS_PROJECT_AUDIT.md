# TaleemPlus Project Audit

Audit date: 2026-11-05  
Repository: `H:\Final Version`  
Branch: `fix/ci-pipeline` at `9d42d9f`  
Workspace state: dirty before this audit (modified `api_client.dart`, backend `app.js`/`db.js`/`schema.prisma`, `vercel.json`, `.gitignore`, `container.yml`; deleted `Dockerfile`/`.dockerignore`/local pgdata files; untracked `api/`, root `package.json`/`package-lock.json`, `.vercelignore`). Those pre-existing changes were inspected only; nothing was modified by this audit.

**Status legend**

| Status | Meaning |
|---|---|
| Working | Exercised or verified against its real dependency; no blocking defect found. |
| Partial | Some flows work, but an important sub-flow is stubbed, mismatched or silently failing. |
| Broken | Cannot work at runtime because of a stub, Firestore dependency, contract mismatch or platform configuration. |
| UI-only | Screen exists, but data/actions are not backed by a real implementation. |
| Unverified | Could not be exercised in this environment (credentials, device, external service). |

---

## 1. Executive Summary

TaleemPlus is a substantial, well-structured Flutter application with a real Express/Prisma/PostgreSQL backend. Static quality is good: `flutter analyze` is clean, 12 Flutter tests and 17 backend tests pass, the web release build succeeds, and a debug APK builds. Authentication, tenant scoping, and several REST CRUD paths are genuinely implemented.

However, the project is **mid-migration from Firebase/Firestore to the REST backend**, and that migration is incomplete. Many user-facing modules still talk directly to Firestore, while `lib/firebase_options.dart` contains placeholder credentials and no `google-services.json`/`GoogleService-Info.plist` exists. Those modules fail at runtime. In addition, several REST adapters contain contract mismatches or silent no-op stubs, so even some “migrated” features do not function:

- Attendance saving cannot encode its request body, and attendance reload parses the wrong response shape.
- Quizzes cannot be listed because the model casts a backend ISO date string to a Firestore `Timestamp`.
- Fee dates are discarded, breaking overdue status, month filters and ledger analytics.
- Quiz deletion/updating and marks-by-quiz/class are stubs that report success or return empty lists.
- Member editing reports “Profile updated successfully!” but persists nothing.
- Parent child-linking is unreachable because the required auth methods are stubs.
- The release Android manifest omits `INTERNET`, so a release build cannot call the API.

**Verdict:** the architecture and backend foundation are credible, but the product is not currently demo-ready or FYP-defensible as a fully functional academy system. It can be presented honestly as a partially migrated system with a working backend core and a significant set of known integration defects.

---

## 2. Scope, Method and Evidence Limits

Read-only audit covering:

- Flutter client (`lib/`, `test/`, `integration_test/`, platform configs).
- Node/Express backend (`taleemplus_backend/src`, `prisma`, tests).
- Python ML service (`ml_service`, not started).
- Build, analyzer, unit tests, backend health, negative HTTP probes, and static contract comparison.

Evidence used in this report:

- Source inspection with file/line references.
- `flutter pub get`, `flutter analyze`, `flutter test`.
- `npm test` in `taleemplus_backend`.
- Backend launched temporarily by PID for `/health` and negative auth/CORS probes, then stopped.
- `flutter build web --release` and `flutter build apk --debug`.
- Read-only database counts via Prisma/Neon.
- A one-off Dart snippet (outside the repo) confirming `jsonEncode` rejects `DateTime`.

Limits:

- No credentials were available for domain users; only one ADMIN user and zero domain rows exist in the database. Authenticated role flows and CRUD could not be exercised end to end.
- No Android device/emulator was attached. Device-to-backend networking was not tested.
- Firebase is unconfigured by design (placeholders), so Firestore-backed features cannot be exercised or repaired from here.
- The ML service was not started; `ML_SERVICE_URL` and `ML_INTERNAL_TOKEN` are unset.
- No accounts, records or schema changes were created by this audit. No secrets are reproduced here.

---

## 3. Verified Toolchain, Test and Build Status

| Command | Result | Notes |
|---|---|---|
| `flutter pub get` | Passed | Dependencies resolve. |
| `flutter analyze` | Passed | `No issues found! (ran in 7.3s)`. |
| `flutter test` | Passed | 12/12 tests. |
| `flutter build web --release` | Passed | Built `build/web` in ~128 s. |
| `flutter build apk --debug` | Passed | Built `build/app/outputs/flutter-apk/app-debug.apk` in ~319 s. |
| `npm test` (backend) | Passed | 6 suites / 17 tests in ~5.3 s. |
| `GET /health` | Passed | HTTP 200, `database: connected`. |
| `POST /api/v2/auth/login` invalid | Passed (expected reject) | HTTP 401, `Invalid credentials...`. |
| `GET /api/v2/auth/me` without token | Passed (expected reject) | HTTP 401, `Access token required.`. |
| `GET /api/v2/quizzes` without token | Passed (expected reject) | HTTP 401. |
| `GET /api/v2/fees/challans` without token | Passed (expected reject) | HTTP 401. |
| `OPTIONS /api/v2/auth/login` (CORS) | Passed | HTTP 204. |
| `flutter build apk --release` | Not run | Release-specific risks noted in section 15. |
| `flutter test integration_test/...` | Not run | Requires a device and working Firebase configuration. |

Backend database snapshot (read-only):

- Academies: 1.
- Users: 1 (ADMIN, ACTIVE).
- Classes, enrollments, attendance, challans, quizzes, marks, resources, queries, notifications, announcements, timetable slots, OCR records: 0.
- Refresh tokens: 2.

Because domain tables are empty, runtime success for most features cannot be demonstrated without creating data, which this audit was instructed not to do.

---

## 4. Architecture and Data Flow

The client is a hybrid of three data paths:

1. **REST via `ApiClient`** for auth, users, classes, attendance, fees/payments, quizzes, timetable, resources, announcements and notifications on the backend.
2. **Direct Firestore** in older services for notifications, announcements, academic structure, class sections, class reports, timetable, classroom resources/queries, OCR persistence and test-paper PDFs.
3. **Local-only helpers** (SQLite, SharedPreferences) for legacy member data, session/token storage and preferences.

`ApiClient` is a singleton with platform-aware base URLs, bearer-token injection, 20 s timeout, automatic refresh on 401, and envelope unwrapping (`{success, data}` → data). See `lib/data/remote/api_client.dart:14-228`.

State management is Provider/`ChangeNotifier` throughout (`lib/main.dart:38-62`); there is no Bloc implementation.

Firebase is initialized unconditionally at startup from placeholder options (`lib/main.dart:34-36`, `lib/firebase_options.dart:41-82`). This makes every Firestore call reachable but unauthenticated, which is the source of the largest class of runtime failures.

---

## 5. Backend API and Database

Implemented v1/v2 API surface (`taleemplus_backend/src/app.js:73-94`):

- Auth: register admin/user, login, refresh, logout, `/me`, verify/change password, academy profile.
- Users: pending list, approve/reject, by-role, link child, admin create.
- Classes: list/create/delete/enroll.
- Attendance: mark, student history, class-by-date.
- Fees: payment settings, challan generate/create/list/student list/pay, ledger stats, proofs submit/review.
- Quizzes: list/create, marks upsert, student marks.
- Resources/queries: list/create/answer.
- Notifications/announcements: list, mark read, create announcement.
- Timetable: list/create/delete.
- Admin ML: status/metrics/history/predict/train/retrain/rollback.

Strengths:

- Tenant scoping is consistently applied with `req.academyId`.
- Role guards are applied to privileged routes via `authorizeRoles` (`src/middleware/roleMiddleware.js`).
- Passwords use bcrypt; access tokens are 15 minutes and refresh tokens 7 days (`src/controllers/authController.js:71-80`).
- Startup fails if JWT secrets are missing (`authController.js:74-76`).
- Helmet, explicit CORS allowlisting and JSON body limits are configured (`src/app.js:22-54`).
- Prisma migrations exist (`prisma/migrations/`, six migrations). The `prisma:seed` script references a missing `prisma/seed.js`; `data_export/*.json` is empty.

Defects and gaps:

- No rate limiting on login/register/password endpoints. Only ML training has an in-memory limiter (`src/routes/mlRoutes.js:8-18`).
- Resource routes are mounted at `/api/v2/resources` and then declare `/resources` and `/queries`, producing doubled paths such as `/api/v2/resources/resources` and `/api/v2/resources/queries` (`src/app.js:80`, `src/routes/resourceRoutes.js:9-12`). The frontend avoids this by using Firestore, so the backend resource API is effectively dead.
- There is no user-update or user-delete endpoint, and no marks-by-quiz/class or quiz/mark deletion endpoint. The frontend stubs mirror those absences.
- No rate limit or lockout on repeated failed logins is a security weakness for an academy system.

---

## 6. Authentication and Account Lifecycle

Working:

- Admin registration creates an academy with a generated code; user signup validates the academy code server-side and creates a `PENDING` user (`authController.js:99`, `159-204`).
- Login rejects non-`ACTIVE` accounts (`authController.js:241-245`).
- `/me`, refresh, logout, verify-password and change-password are implemented and protected.
- `ApiClient` stores tokens, refreshes on 401 and retries (`api_client.dart:133-203`).
- Signup UI correctly shows a pending-approval dialog and does not auto-enter a dashboard.

Broken or risky client behavior:

- `AuthService.findAcademyByCode` returns a fabricated success for any code (`lib/data/remote/auth_service.dart:295-297`). Signup verification is therefore cosmetic; the backend is the only real check.
- `getSecurityQuestion` returns `null`, `sendPasswordReset` is a no-op, and `verifySecurityAnswer` always returns `true` (`auth_service.dart:285-293`).
- `isRollNumberTaken` always returns `false` (`auth_service.dart:243-246`).
- `relinkAcademy` and `watchProfile` are local-only approximations; `watchProfile` yields the cached user once (`auth_service.dart:299-319`).
- `_verifyLegacyAdminData` in the dashboard writes directly to Firestore if academy metadata is missing (`lib/features/admin/admin_dashboard.dart:69-95`). With the current API `/me` returning `academyCode`, the condition is normally false, but on legacy data this path would fail against placeholder Firebase.

---

## 7. User and Role Management

Backend is functional:

- Admin create user, approve, reject, list by role, and link child are implemented (`src/controllers/userController.js:31-183`).
- `/users/by-role` returns only `ACTIVE` users and omits password hashes (`userController.js:85-117`).

Client problems:

- **Edit member is silent data loss.** `_EditMemberSheet` calls `auth.updateUserProfile`, which is an empty method (`user_management_screen.dart:801`, `auth_service.dart:248-258`), then shows “Profile updated successfully!” (`user_management_screen.dart:837`). Nothing is persisted.
- **Roll numbers are never stored.** The admin-create UI passes roll number, but `AuthService.adminCreateUser` does not send it (`auth_service.dart:260-283`) and the backend create endpoint ignores it (`userController.js:146-179`).
- **Add member can report failure after creating the account.** `adminCreateUser` succeeds, then section enrollment through Firestore `ClassSectionProvider` runs inside the same `try` (`user_management_screen.dart:1090-1140`). With placeholder Firebase it throws, so the UI shows “Failed to add user” even though the account exists.
- **Approval can report failure after approving.** `approveUser` succeeds on the backend, then `NotificationService().send` writes to Firestore inside the same `try` (`approval_requests_screen.dart:70-110`). The screen reports “Failed to approve” and skips reload/mirroring.
- **Delete is actually reject.** There is no delete endpoint; the UI can only set `REJECTED` (`userController.js:63-79`).
- Section assignment in member flows depends on Firestore class sections, which are broken (section 8).

---

## 8. Classes, Sections and Enrollment

Working:

- Class list is loaded from `GET /classes`; the backend returns `student_ids` and `student_names`, which `ClassEntity.fromMap` consumes (`src/controllers/classController.js:20-34`, `lib/data/models/class_entity.dart:61-80`).
- Class creation and deletion hit real endpoints (`lib/data/repositories/class_repository.dart:65-84`).

Broken or partial:

- `ClassRepository.watchAll`/`watchForTeacher`/`watchForStudent` swallow all errors and yield an empty list (`class_repository.dart:10-50`). A 401, network failure or parse error is indistinguishable from “no classes”.
- **Editing a class is a no-op.** `updateClassDetails` is empty (`class_repository.dart:96-104`), yet the edit sheet shows “Class details updated!” (`class_management_screen.dart:440-448`). Subject/teacher changes are silently lost.
- `createClassWithStudents` ignores the selected students; the repository creates only the class (`class_repository.dart:65-80`, `lib/logic/class_provider.dart:61-77`).
- Enrollment is add-only; there is no unenroll endpoint or client call (`class_repository.dart:86-94`).
- **Class sections, academic structure and class reports are Firestore-only** and have no backend fallback:
  - `class_sections` (`lib/data/repositories/class_section_repository.dart:21`).
  - `academy_settings` (`lib/data/remote/academic_structure_service.dart:8`).
  - `class_reports` (`lib/data/repositories/class_report_repository.dart:11`).
- Numerous screens use the current user's `uid` as `academyId` (`class_management_screen.dart:40`, `class_sections_screen.dart:41`, `challan_generation_screen.dart:47`). This works only because an admin's `uid` equals the academy id in the current data model; it is an implicit convention, not a typed guarantee.

---

## 9. Attendance

This module is substantially broken.

- **Saving fails before the request is sent.** `AttendanceRepository.saveAll` puts `first.logDate` (a `DateTime`) directly into the JSON map (`lib/data/repositories/attendance_repository.dart:10-20`). Dart's `jsonEncode` rejects `DateTime`; verified with a standalone snippet: `Converting object to an encodable object failed: Instance of 'DateTime'`. `AttendanceProvider.save` catches this and returns false with an error (`lib/logic/attendance_provider.dart:74-108`).
- **Reloading class attendance parses the wrong shape.** `GET /attendance/class` returns raw Prisma rows (`classId`, `studentId`, `logDate`, uppercase `status`, `recordedAt`) at `src/controllers/attendanceController.js:113`. `AttendanceRecord.fromMap` expects snake_case and lowercase status (`lib/data/models/attendance_record.dart:54-68`). Existing records therefore load with empty ids/dates and `status == 'PRESENT'`, which fails `isPresent` (`attendance_record.dart:28-30`). A teacher reopening a saved day sees an inaccurate sheet.
- `getAllForAcademy` is a hard stub returning `[]` (`attendance_repository.dart:41-43`). This breaks:
  - Teacher “Marked Today” (`lib/widgets/teacher_stats_row.dart:38-52`).
  - Admin attendance stats (`lib/widgets/admin_extra_stats_row.dart:53`).
  - Parent attendance stats (`lib/widgets/parent_stats_row.dart:56`).
  - Class report aggregation (`lib/features/admin/screens/class_reports_screen.dart:308`).
- Student attendance history does work: `/attendance/student/:id` returns formatted snake_case and lowercase status (`attendanceController.js:77-88`), and the student dashboard subscribes to it (`student_dashboard.dart:372-374`).
- Backend marking itself is plausible (upserts by class/student/date, uppercases status), but it cannot be reached from the current client because of the encoding failure.

Impact: online attendance is effectively non-functional, and all attendance-derived analytics are unreliable.

---

## 10. Fees, Challans and Payments

Working:

- Payment settings GET/PUT are real and used by the admin settings screen and challan PDFs (`src/routes/feeRoutes.js`, `lib/data/remote/payment_service.dart`).
- Payment proof submission/review endpoints exist and the parent challan screen calls them (`lib/features/parent/screens/student_challan_screen.dart:509`).
- Admin payment-proof review and settings screens are wired to REST.
- `GET /fees/challans` and `GET /fees/challans/student/:id` return real data; pay-status update works (`feeController.js:57-76`, `138-204`).
- `getLatestForStudent` filters by `billingPeriod`, which is a string and therefore unaffected by the date bug (`lib/data/repositories/fee_challan_repository.dart:43-54`).

Broken or partial:

- **Dates are discarded on read.** Backend sends `issue_date`, `due_date`, `created_at` as ISO strings (`feeController.js:70-73`, `154-174`). `FeeChallanModel.fromMap` accepts only Firestore `Timestamp` and otherwise defaults to `DateTime.now()` (`lib/data/models/fee_challan_model.dart:91-108`). Consequences:
  - `isOverdue` is effectively always false (`fee_challan_model.dart:52-53`).
  - The ledger month filter compares `issueDate` and therefore groups everything under the current month (`lib/features/admin/fee_ledger_screen.dart:81-95`).
  - Ledger overdue totals and the unpaid-students warning icon are wrong (`fee_ledger_screen.dart:225-260`, `unpaid_students_screen.dart:184-195`).
  - Printed/downloaded challans show the wrong issue/due dates.
- **Bulk generation is unreachable.** The generation screen owns its class-section list through Firestore `ClassSectionProvider` (`challan_generation_screen.dart:47`, `99-115`, `261-263`). With placeholder Firebase the section list is empty, so the Generate button never receives a section.
- `createChallan` itself is correctly shaped for the backend (student, amounts, due date, billing period), so manual/bulk creation would work if the UI could reach it (`fee_challan_repository.dart:8-21`).
- Student fee reads swallow all errors and return `[]` (`fee_challan_repository.dart:23-34`), hiding failures.
- The backend also exposes a `/fees/challans/generate` endpoint that is not used by the current generation screen; the screen creates challans one by one.

Impact: fee records can exist and be marked paid, but date-dependent behavior, reporting and bulk generation are not trustworthy.

---

## 11. Quizzes, Marks and AI

Working:

- Quiz creation posts valid fields and succeeds against the backend (`lib/data/remote/quiz_service.dart:8-18`, `src/controllers/quizController.js:48-84`).
- Individual mark upsert posts to `/quizzes/marks` and stores correct grade data (`quiz_service.dart:56-63`, `quizController.js:95-150`).
- Student mark history reads from `/quizzes/marks/student/:id` and parses safely because `updated_at` uses an `is Timestamp` guard (`quiz_service.dart:65-76`, `lib/data/models/test_mark_model.dart:79-82`).

Broken:

- **Quiz listing is broken by a type cast.** The backend returns `created_at` as an ISO string (`quizController.js:30`). `QuizModel.fromMap` unconditionally casts it to Firestore `Timestamp` (`lib/data/models/quiz_model.dart:156-158`). When at least one quiz exists, parsing throws, the stream's catch swallows it and yields `[]` (`quiz_service.dart:25-36`, `38-50`). Therefore teacher quiz lists, admin quiz lists and class quiz dropdowns show nothing even after successful creation.
- `updateQuestions` is an empty method that reports no error (`quiz_service.dart:20-23`), so keyword edits in the AI grader are silently lost.
- `deleteQuiz` is empty (`quiz_service.dart:52-54`) but the teacher list shows “Test deleted.” (`teacher_quiz_list_screen.dart:442-448`). The results screen simply pops (`quiz_results_screen.dart:355-359`).
- `deleteMark` is empty (`quiz_service.dart:88-90`); the results screen performs no success feedback, so delete appears to do nothing.
- `watchMarksByQuiz` and `watchClassMarks` always yield `[]` (`quiz_service.dart:92-100`), so quiz results are always empty and monthly class reports have no data.
- `getAllAcademyMarks` always returns `[]` (`quiz_service.dart:78-80`), so admin AI insights have no input.
- The backend has no routes for marks by quiz/class, quiz update or quiz/mark deletion (`src/routes/quizRoutes.js`), so these stubs cannot be fixed client-side alone.
- Dates: the backend omits `test_date` and `created_by_name` from quiz responses (`quizController.js:17-40`); the model defaults `testDate` to now and leaves creator blank. `toMap` still writes Firestore `Timestamp`/`FieldValue` values, but that map is not used by the REST create path.

AI claims:

- “AI quiz generation” is **offline TextRank sentence ranking**, not an LLM call (`create_quiz_screen.dart:16`, `368-371`).
- The paper grader is offline TF-IDF/TextRank logic (`lib/logic/tfidf_grader.dart`, `lib/logic/text_rank_summarizer.dart`).
- The Python ML service and `/api/v2/admin/ml/*` endpoints are not used by any of these quiz flows; they require `ML_SERVICE_URL`/`ML_INTERNAL_TOKEN` and return 503 when unset (`src/services/mlServiceClient.js:1-8`).

Impact: quiz creation succeeds into a void; review, grading analytics, deletion and report screens cannot work.

---

## 12. Timetable

- The entire timetable feature is Firestore-only (`lib/data/remote/timetable_service.dart:5-6`, collection `timetables`).
- Admin management, teacher “My Timetable”, student timetable and parent child timetable all read through `TimetableProvider`, which wraps that service (`lib/features/admin/screens/timetable_management_screen.dart:145`, `lib/features/teacher/screens/my_timetable_screen.dart:18`, `lib/features/student/screens/my_timetable_screen.dart:46`, `lib/features/parent/screens/child_timetable_screen.dart:46`).
- With placeholder Firebase these lists fail or remain empty, and teacher dashboard “Today's Classes” stays `--` (`teacher_stats_row.dart:71-82`).
- A real backend timetable API exists (`src/routes/timetableRoutes.js`) but is not called anywhere in the client.
- If wired later, note a contract mismatch: the backend stores `dayOfWeek` as a `String` (`prisma/schema.prisma:386`) and returns raw camelCase rows (`timetableController.js:10-19`), while the client model/service assumes Firestore types and an integer weekday (`timetable_slot.dart:120-127`, `teacher_stats_row.dart:74-76`).

---

## 13. Classroom, Resources, Announcements, Notifications and Academic Structure

All of these are Firestore-only on the client:

| Feature | Client dependency | Backend exists? | Runtime status |
|---|---|---|---|
| Classroom resources | `learning_resources` (`lib/data/remote/classroom_service.dart:10-24`) | Yes, but mounted under doubled paths (`app.js:80`, `resourceRoutes.js:9-12`) | Broken |
| Student/teacher queries | `student_queries` (`classroom_service.dart:26-58`) | Yes, same path issue | Broken |
| OCR publish to classroom | `ClassroomService.uploadResource` (`lib/features/ocr/services/ocr_publish_service.dart:60`) | Yes, unused | Broken |
| Announcements | `announcements` (`lib/data/remote/announcement_service.dart:21`) | Yes, `/api/v2/announcements` (`notificationRoutes.js`) | Broken |
| Notifications | `notifications` (`lib/data/remote/notification_service.dart:5-30`) | Yes, `/api/v2/notifications` | Broken |
| Academic structure | `academy_settings` (`academic_structure_service.dart:8`) | No equivalent | Broken |
| Class reports | `class_reports` (`class_report_repository.dart:11`) | No equivalent | Broken |

Concrete consequences:

- Every dashboard notification bell subscribes to Firestore and shows an error (`admin_dashboard.dart:975`, `teacher_dashboard.dart:630`, `student_dashboard.dart:593`, `parent_dashboard.dart:205`).
- Notifications screen shows “Error loading notifications” (`lib/features/shared/notifications_screen.dart:25`).
- Announcement cards/lists are empty; admin announcement counts show `--`; creating announcements fails.
- Approval flows fail after the backend succeeds because they attempt Firestore notification writes (`approval_requests_screen.dart:73`, `155`).
- Admin academic structure, class sections and class reports screens cannot load or save.
- Teacher and student classroom hubs (resources, questions, answers) are unusable.

The backend already has usable notification/announcement/resource/query controllers; these modules are primarily a wiring problem, except academic structure and class reports, which need new backend models/endpoints or a deliberate Firestore decision.

---

## 14. OCR, PDF and Document Generation

OCR:

- On-device text recognition uses `google_mlkit_text_recognition` and is real (`lib/features/ocr/services/ocr_service.dart`).
- Persistence/history/view/delete use Firestore `ocr_documents` (`lib/features/ocr/services/ocr_firestore_service.dart:5-78`), so saving, history and document view fail with placeholder Firebase.
- Publishing OCR-derived resources to a classroom goes through Firestore `ClassroomService` and therefore fails (`ocr_publish_service.dart:60`).

PDFs:

- **Test paper print/share is broken.** `PdfGeneratorService._buildDocument` reads the academy from Firestore `users/{academyId}` before building the PDF (`lib/data/remote/pdf_generator_service.dart:29-45`). Print/share actions in the teacher quiz list (`teacher_quiz_list_screen.dart:334`, `354`) will throw.
- Challan PDFs use `PaymentService` and a passed `AppUser`, not Firestore (`challan_pdf_service.dart:13-38`), so the PDF pipeline works; however, the dates printed come from `FeeChallanModel`, which currently defaults them to `now` (section 10), so printed due dates are wrong.
- Academic result PDFs use the passed student and marks data (`academic_report_pdf_service.dart`), so they can work when marks exist.

---

## 15. Platform, Security, CI/CD and Documentation

Platform:

- Web release build succeeds and is deployable as static output.
- Android debug APK builds successfully.
- **Release Android is misconfigured for networking.** `android/app/src/main/AndroidManifest.xml` declares only `CAMERA`; `INTERNET` exists only in the debug and profile manifests. A release build therefore cannot reach the API. There is also no `usesCleartextTraffic`/network-security config for the current HTTP dev endpoint (`http://192.168.10.9:5000`), and `ApiClient` defaults to that HTTP URL on Android (`api_client.dart:44-46`).
- `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist` are absent. The Google Services Gradle plugin is commented out (`android/app/build.gradle.kts`), which is why the debug build succeeds; release Firebase behavior remains unimplemented.

Security:

- Positive: bcrypt, short-lived access tokens, rotating refresh tokens, role middleware, tenant scoping, Helmet, CORS allowlist, body-size limit, secrets required at startup, `.env` not tracked in the current index.
- Negative: no login/registration rate limiting or account lockout; client-side security-question/password-reset/academy-lookup stubs give a false sense of implemented recovery; placeholder Firebase credentials are committed; release networking is broken; several catch-all streams hide authorization/network failures as empty data.

CI/CD:

- Workflows exist for Flutter, Android, backend, container, Vercel and a combined pipeline (`.github/workflows/`).
- Backend CI provisions PostgreSQL and runs migrations/tests.
- Flutter CI runs analyze, tests and both web/APK builds.
- The workflows do not run the Python ML tests, and the Android release workflow does not detect the missing `INTERNET` permission because building is not the same as runtime networking.

Documentation:

- `README.md`, `Architecture.md`, `API_V2.md`, `CHANGELOG.md`, `CI_CD_SETUP.md`, `PROJECT_AUDIT.md`, `TEST_REPORT.md`, `AI_ML_AUDIT_REPORT.md` and others exist. Several predate the current migration state (for example, older reports claim a release APK failure caused by Google Services and describe different branch/commit snapshots). Treat them as historical, not authoritative.

---

## Summary Table

| Component | Status | Evidence | Main issues |
|---|---|---|---|
| Flutter build/analyze/tests | Working | Analyze clean; 12 tests pass; web build and debug APK succeed | No runtime UI/device verification |
| Backend build/tests/health | Working | 17 tests pass; `/health` DB connected; migrations present | Missing seed; no auth rate limiting |
| Authentication (login/refresh/me) | Working | REST + JWT/refresh; 401 probes correct; pending gate | Client recovery/lookup stubs; no brute-force protection |
| Signup/approval | Partial | Backend pending → approve works; UI pending flow correct | Approval UI reports failure when Firestore notify throws |
| User management | Partial | Create/approve/reject/by-role/link-child endpoints real | Edit no-op with false success; roll number dropped; add false failure; delete = reject |
| Classes (create/list/delete) | Working | REST endpoints and class list contract match | Errors swallowed as empty list |
| Class editing/enrollment | Broken | `updateClassDetails` empty; enrollment add-only; create ignores students | Silent data loss |
| Class sections | Broken | Firestore `class_sections` | No backend fallback; blocks challans/member assignment |
| Attendance | Broken | `DateTime` in JSON; wrong class-response shape; `getAllForAcademy` stub | Save fails; reload inaccurate; all stats zero |
| Fees (add/list/pay) | Partial | REST endpoints work; billing-period filtering works | Dates discarded; overdue/month analytics wrong; bulk generation blocked |
| Payments/settings/proofs | Working | REST settings/proofs; parent submit wired | Parent reachability depends on broken child linking |
| Quizzes (create) | Partial | POST succeeds | Cannot list/parse; delete/update stubs |
| Quiz results/marks analytics | Broken | Marks-by-quiz/class return `[]`; admin marks `[]` | Results, monthly reports and AI insights empty |
| Quiz delete/update | Broken | Empty methods; false success message | No backend endpoints |
| AI quiz generation/grading | Partial (offline only) | TextRank/TF-IDF; no LLM/network | Marketing label overstates capability |
| Parent child linking | Broken | `watchProfile` cached; `getProfilesByIds`/`findStudentByEmail` stubs | Parent role has no children; link UI unusable |
| Timetable | Broken | Firestore `timetables` everywhere; backend unused | All timetable screens and teacher stat fail |
| Classroom/resources/queries | Broken | Firestore services; backend path duplication | Teacher/student classroom unusable |
| Announcements | Broken | Firestore `announcements`; backend unused | Lists/counts/create fail |
| Notifications | Broken | Firestore `notifications`; backend unused | Bell/screen error; breaks approval UX |
| Academic structure | Broken | Firestore `academy_settings`; no backend model | Admin structure screen unusable |
| Class reports | Broken | Firestore `class_reports`; attendance stub | Reports unusable |
| OCR extraction | Working | ML Kit service present | Device/camera not tested |
| OCR persistence/history/publish | Broken | Firestore `ocr_documents`; classroom Firestore | Save/history/view/publish fail |
| Test paper PDF | Broken | Firestore academy lookup | Print/share throws |
| Challan/result PDFs | Partial | API/passed data based | Challan dates wrong |
| Android release networking | Broken | Release manifest lacks `INTERNET`; HTTP URL | Release build cannot reach API |
| CI/CD | Partial | Workflows for Flutter/Android/backend/Vercel | No runtime config checks; ML tests not run |
| Documentation | Partial | Many reports exist | Several are stale relative to current code |

---

## Honest Assessment

### Demo readiness

Not ready for a full academy-management demo. A defensible demo could cover:

- Login and role-based dashboard shells.
- Backend health and authenticated `/me`.
- Class list/creation against REST (with enrollment/edit caveats).
- Fee challan list and mark-paid (with date caveats).
- Student attendance history (if seeded) and student test marks (if seeded).
- Payment settings and parent proof submission (only after child linking is fixed or seeded).

It should not claim working attendance marking, quizzes, timetable, notifications, announcements, classroom, class sections, class reports, OCR history or test-paper PDFs.

### FYP readiness

The engineering foundation is present: clean Flutter architecture, typed models, a real multi-tenant backend, migrations, role middleware, tests and CI. The project is suitable for an FYP narrative about migrating a Firebase app to PostgreSQL/REST, **provided the report is honest about the incomplete migration**. It is not production-ready, and a demo that depends on the broken modules would fail.

### Functional vs UI-only

Functional (backend + client):

- Authentication core, signup pending flow, admin create/approve/reject, class list/create/delete, student attendance history, student marks history, fee list/create logic, payment settings/proofs, OCR text extraction, offline summarizer/grader.

UI-only or effectively UI-only:

- Attendance marking, class editing/enrollment, quiz list/results/deletion, quiz keyword updates, announcements, notifications, timetable, classroom resources/queries, academic structure, class sections, class reports, parent linking, OCR history/publish, test-paper PDF.

---

## Top 10 Problems (by user impact)

1. **Attendance save and reload are broken.** Requests cannot be encoded, and saved records are parsed incorrectly. This invalidates a core daily workflow and all attendance analytics.
2. **Quiz listing cannot parse backend dates.** One bad cast hides all quizzes, which also blocks results, grading, reports and admin AI insights.
3. **Firestore-only modules under placeholder Firebase.** Notifications, announcements, timetable, classroom, sections, academic structure, class reports, OCR persistence and test-paper PDFs cannot run.
4. **Fee dates are discarded.** Overdue status, month filters, ledger analytics and printed challans are wrong even though the fee API works.
5. **Bulk challan generation is blocked by Firestore sections.** Admins cannot bill a whole section.
6. **User management silently loses data or reports false failures.** Member edits never persist; roll numbers are dropped; add/approve can show failure after success.
7. **Parent role cannot load children.** Linked-child lookup and profile watching are stubs, making the parent dashboard and fee/attendance/alerts views unreachable.
8. **Quiz delete/update and marks-by-quiz/class are stubs.** The UI reports success for deletions that never happen and shows empty results.
9. **Release Android cannot use the network.** `INTERNET` is missing from the main manifest, and the app targets cleartext HTTP.
10. **Authentication recovery and brute-force protection are incomplete.** Password reset/security-question/academy lookup are client stubs, and there is no login rate limiting.

---

## Recommended Fix Order

1. **Attendance contract and encoding.** Send `logDate` as `YYYY-MM-DD`; parse the class response into the model shape; implement `getAllForAcademy` with a real backend endpoint or remove the dependent stats.
2. **Quiz parsing and endpoints.** Guard `created_at` like the other date fields; add backend routes for marks-by-quiz/class, quiz update/delete and mark delete; wire the stubs or remove the success messages.
3. **Decide Firebase vs REST for the remaining modules.** Either configure real Firebase and keep those features, or fully migrate notifications, announcements, timetable, classroom/resources, sections, academic structure, reports and OCR persistence to REST. Do not leave the current half-state.
4. **Fee date parsing.** Accept ISO strings in `FeeChallanModel.fromMap`; recompute ledger month filters and overdue logic.
5. **Replace class sections in billing/member flows.** Use the REST class + enrollment APIs (and add unenroll/update endpoints) until a section backend exists.
6. **User management honesty.** Implement a backend update endpoint, send/persist roll numbers, move non-critical notifications outside success paths, and replace “delete” with a real deactivate/delete policy.
7. **Parent linking end to end.** Implement `getProfilesByIds`, `findStudentByEmail`, `getSecurityQuestion`/reset or remove those screens, and use `/users/link-child`.
8. **Release networking.** Add `INTERNET` to the main manifest, configure HTTPS for release, and set the API URL per build flavor.
9. **Security hardening.** Add login/register rate limiting and account lockout; remove fabricated client-side verification; audit catch-all error swallowing.
10. **Onboarding seed and demo data.** Add `prisma/seed.js` (referenced but missing) with representative academy/users/classes/fees/quizzes so the repaired flows can be demonstrated and regression-tested.

---

## Evidence Limits and Reproducibility Notes

- The audit intentionally did not create users, classes, fees, quizzes or any other database rows. Empty tables are why several working REST paths could not be shown end to end.
- The backend was started only for health and negative probes and stopped by PID. No unrelated Node processes were running.
- The one-off Dart check used a temporary file outside the repository and removed it afterward.
- Builds produced normal `build/` artifacts; no source files were changed.
- Secrets from `.env`/`.env.local` are not reproduced in this document.
- Re-run the following to reproduce the positive checks:

```powershell
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug
cd taleemplus_backend
npm test
```

- The most important contract checks to add as automated tests are: attendance request encoding, `AttendanceRecord.fromMap` against the class endpoint payload, `QuizModel.fromMap` against the quiz endpoint payload, `FeeChallanModel.fromMap` against fee endpoint payloads, and role-based access for every dashboard data source.
