# REST API Gap Analysis

Status: Phase 0 analysis, read-only  
Repository: `H:\Final Version`  
Baseline commit: `9d42d9ff01d1a9abde914f8e61858aae2f2bd5a8`  
Date: 2026-11-05

This document compares the current Flutter client and Firestore behavior with the Express/Prisma/PostgreSQL API. It identifies the work required before Firebase can be removed. It does not authorize source changes.

## 1. Objective and Assumptions

Objective: make the REST API the complete, authoritative data path for the app while preserving existing tenant isolation, role rules, and user workflows.

Assumptions:

- PostgreSQL is the system of record.
- JWT authentication remains the application authentication mechanism.
- Firestore is removed from runtime use after migration.
- Additive Prisma changes are preferred over destructive table redesign.
- Real-time behavior may be replaced by refresh/one-shot reads unless a later decision requires polling or another live mechanism.
- Historical Firestore data may or may not exist; the data-import phase is gated on a real export and identity mapping.

## 2. Current API Baseline

The v2 API exposes 58 route handlers across these modules:

| Module | Existing v2 routes | Current state |
|---|---|---|
| Auth | 9 | Login/refresh/me/password/academy profile work; recovery and academy-code mutation are incomplete. |
| Users | 6 | Create/approve/reject/by-role/link-child exist; update/delete/search/roll-number support are missing. |
| Classes | 4 | List/create/delete/enroll exist; update and unenroll are missing. |
| Attendance | 3 | Mark/student history/class-by-date exist; academy-wide query is missing. |
| Fees | 11 | Settings/proofs/challan CRUD/pay/ledger exist; bulk generation is inconsistent; date/overdue handling is weak. |
| Quizzes | 4 | List/create/mark upsert/student marks exist; update/delete/results/submissions are missing. |
| Resources and queries | 5 | Endpoints exist under doubled paths; tenant/role validation and deletes are incomplete. |
| Notifications and announcements | 4 | List/read/create exist; update/delete/fan-out/mark-all and recipient filtering are missing. |
| Timetable | 3 | List/create/delete exist but are unused by Flutter and have a different contract. |
| Admin ML | 9 | Endpoints exist behind an external service; the service is unconfigured and not part of the Flutter quiz flow. |

All non-ML modules are mounted under both `/api/v2` and `/api/v1`. New work should target v2 only.

### 2.1 Positive baseline

- Tenant scoping through `req.academyId` is used on most queries.
- Privileged writes are usually role-guarded.
- Passwords use bcrypt; access and refresh token separation exists.
- Backend health, auth, role middleware, password policy, and ML client tests pass.
- Class list, student attendance history, student marks history, fee list/pay, payment settings, and payment proofs have real implementations.
- API envelopes are consistently `{ success, data, message }`.

## 3. Cross-Cutting Contract Gaps

These issues affect multiple modules and should be fixed centrally before or alongside module work.

| Gap | Current evidence | Impact | Required direction |
|---|---|---|---|
| Inconsistent casing | Auth/user responses are camelCase; class/attendance/fee/quiz-list/resource/notification responses are snake_case; create-quiz/resource and timetable return raw Prisma rows | Client parsers fail silently or default values | Standardize response DTOs, preferably snake_case for collection resources and a single mapped auth DTO. |
| Date types | Flutter models expect Firestore `Timestamp`; REST returns ISO strings; attendance sends `DateTime` directly | Parsing crashes or defaults to `DateTime.now()`; attendance POST cannot encode | Backend emits ISO-8601; Flutter parses strings centrally; attendance sends `YYYY-MM-DD`. |
| Enum casing | Prisma returns uppercase `PRESENT`, fee `PENDING`; models expect lowercase | Incorrect status and analytics | Backend serializes lowercase statuses or client normalizes once, not per screen. |
| Missing denormalized fields | Class attendance lacks `student_name`; quiz lacks `created_by_name`, `test_date`; user lists lack roll/subject/extra/joining date | Blank UI and broken joins | Add DTO fields from relations instead of client-side lookups. |
| One-shot streams | `watchAll`, `watchForTeacher`, `watchForStudent`, quiz, and attendance “watch” methods are `async*` that yield once | UI assumes realtime but never refreshes | Explicitly document and implement refresh-after-mutation; add polling only where required. |
| Swallowed errors | Many repositories return `[]` on any exception | Authorization/network failures look like empty data | Preserve errors; show retry/error states. |
| No pagination | Lists return all rows | Scaling and performance risk | Add bounded results or pagination for notifications, marks, audit-style lists. |
| No shared validation layer | Controllers use ad hoc checks; `zod` is installed but not consistently used | Inconsistent status codes and validation | Introduce reusable validators. |
| Weak route organization | Resource router mounted at `/api/v2/resources` and then declares `/resources` and `/queries` | Doubled paths; effectively dead API | Mount at `/api/v2` or change route paths; keep one canonical surface. |
| Duplicate v1/v2 surfaces | Same handlers mounted twice | Ambiguous ownership and tests | Deprecate v1 or document v1 as compatibility-only. |
| Firestore-shaped payloads | Models still build `Timestamp`/`FieldValue` maps | REST cannot serialize or use them | Replace model serialization with plain JSON parse/serialize. |

## 4. Module-by-Module Gap Analysis

### 4.1 Authentication, session, and recovery

Current working paths:

- Admin registration, user registration with academy code, login, refresh, logout, `/me`, verify-password, change-password, academy profile update.
- Login rejects non-`ACTIVE` accounts.
- `/auth/me` includes linked children objects.

Gaps:

| Priority | Gap | Evidence | Required work |
|---|---|---|---|
| P0 | Login does not include linked children; only `/me` does | `authController.login` omits `linkedChildren`; `/me` includes them | Include linked children in login or force profile hydration before parent provider sync. |
| P0 | Parent child lookup is stubbed | `getProfilesByIds` returns `[]`, `findStudentByEmail` returns `null` | Add backend profile-by-IDs/search endpoint or map `/me` children directly. |
| P1 | Profile fields dropped | `AuthService._mapApiUser` omits `rollNumber`, `subject`, `extraInfo`, `joiningDate`, `createdAt` | Add fields to API DTO and mapper. |
| P1 | User profile update is a no-op | `updateUserProfile` has an empty body; UI reports success | Add `PATCH /users/me` or admin update endpoint and wire it. |
| P1 | Remove child is a no-op | `removeLinkedChild` is empty | Add `DELETE /users/link-child` or `DELETE /users/:id/children/:studentId`. |
| P1 | Roll-number uniqueness check always false | `isRollNumberTaken` returns `false` | Persist roll number in enrollment and add uniqueness validation. |
| P1 | Security question/password reset are fake | `getSecurityQuestion` returns `null`; `verifySecurityAnswer` returns `true`; `sendPasswordReset` is empty; `saveSecurityQuestion` is empty | Either implement a real recovery flow or remove the UI and document the unsupported feature. |
| P2 | Academy-code lookup is fabricated | `findAcademyByCode` returns a success for any code | Remove client-side verification; rely on backend registration validation. |
| P2 | Academy code cannot be persisted by profile update | `PUT /auth/academy` accepts name/address/phone/logo only; dashboard generates a code and writes Firestore | Add validated code update to backend, or remove code regeneration UI. |
| P2 | Relink academy is local-only | `relinkAcademy` mutates the cached user | Implement a backend operation with admin/security checks or remove the feature. |
| P2 | No login/register rate limiting | No limiter except ML training | Add IP/account rate limiting and lockout. |

### 4.2 Users, members, roles, and parents

Current working paths:

- Admin create, approve, reject, pending list, active users by role, link child.
- Backend approval creates a notification.

Gaps:

| Priority | Gap | Evidence | Required work |
|---|---|---|---|
| P0 | Member editing is silent data loss | `updateUserProfile` no-op, UI shows success | Backend update endpoint plus client persistence. |
| P0 | Roll numbers are not persisted | Admin-create UI collects roll number; client does not send it; backend ignores it | Store roll number on `StudentEnrollment`; return it in roster/profile DTOs. |
| P0 | Parent linking cannot find students | Search/profile stubs; parent UI cannot resolve a student | Add directory/search endpoint scoped to academy and role, and remove-child support. |
| P1 | `getUsersByRole` is available to every authenticated user | Route has no role guard; any role can enumerate active users | Restrict by role or limit returned fields to what the caller needs. |
| P1 | Role list omits needed fields | Response lacks rollNumber, subject, extraInfo, joiningDate, linked children | Expand DTO or add dedicated roster endpoints. |
| P1 | Parent link trusts body `parentId` | A parent can attempt to link any parentId/studentId pair | If caller is PARENT, force `parentId = req.user.id`; otherwise admin-only. |
| P1 | Add member can report failure after success | Account creation succeeds, then Firestore section enrollment throws | Move all notification/enrollment work out of the success-critical path. |
| P1 | Approve can report failure after success | Backend approval succeeds, then Firestore notification write throws; backend already created the notification | Remove duplicate Firestore notification and separate non-critical work. |
| P1 | Reject does not create a notification | Backend only updates status; UI Firestore write throws | Add backend rejection notification if product requires it. |
| P2 | Delete is reject | No delete/deactivate endpoint; UI uses reject | Define deactivate vs reject and expose a real lifecycle operation. |
| P2 | Member provider still merges SQLite | `MemberProvider` reads local SQLite and REST role lists | Remove local member source of truth after REST parity. |

### 4.3 Classes, sections, and enrollment

Current working paths:

- Class list, create, delete, enroll student.
- REST class list shape matches `ClassEntity` for core fields.

Gaps:

| Priority | Gap | Evidence | Required work |
|---|---|---|---|
| P0 | No class update endpoint | `updateClassDetails` is empty; UI reports success | Add `PUT /classes/:id` and persist name/section/subject/teacher. |
| P0 | No unenroll endpoint | Enrollment is add-only | Add `DELETE /classes/:id/enroll/:studentId`. |
| P0 | `createClassWithStudents` ignores selected students | Repository creates the class only | Enroll selected students after create or add a transactional create-with-roster endpoint. |
| P0 | Class sections have no backend model/API | `class_sections` Firestore only; sections drive billing and member assignment | Add `ClassSection` and roster endpoints. |
| P0 | Academic structure has no backend model/API | `academy_settings` Firestore only | Add academy academic-structure storage and endpoints. |
| P1 | Enrollment does not validate student | Backend upserts any `studentId`; no academy/role check | Validate student belongs to the academy and has role STUDENT. |
| P1 | No section enrollment sync to subject offerings | Firestore sections mirror rosters; backend has per-class enrollment only | Define canonical roster and synchronization/cascade behavior. |
| P1 | Tenant IDs are supplied inconsistently by admin screens | Screens pass `user.uid`; backend expects academy UUID | Use authenticated tenant from backend; remove academy arguments where possible. |
| P2 | Class list has no teacher/student server-side filtering | Client fetches all academy classes and filters | Add role-scoped filters for scale and privacy. |
| P2 | Class read errors become empty lists | `watchAll`/`watchForTeacher`/`watchForStudent` swallow errors | Surface errors. |

### 4.4 Attendance

Current working paths:

- Student attendance history works and is formatted.
- Backend mark uses an upsert keyed by class/student/date.

Gaps:

| Priority | Gap | Evidence | Required work |
|---|---|---|---|
| P0 | Attendance POST cannot be encoded | `saveAll` puts `DateTime` in JSON; `jsonEncode` rejects it | Send `logDate` as `YYYY-MM-DD`. |
| P0 | Class attendance reload parses the wrong shape | Backend returns raw Prisma rows with camelCase, uppercase status, nested student; model expects snake_case/lowercase `student_name` | Add a formatted class DTO matching the client model. |
| P0 | Academy-wide attendance is a stub | `getAllForAcademy` returns `[]`; no academy endpoint | Add scoped aggregate/history endpoint or remove dependent stats. |
| P0 | Attendance-derived dashboards are therefore wrong | Teacher/admin/parent stats and class reports use the stub | Fix after the academy endpoint and parsing are stable. |
| P1 | Mark does not validate roster/status | Arbitrary student IDs/status strings are accepted until Prisma rejects | Validate enrollment, role, and allowed status. |
| P1 | No bulk-edit audit trail | `markedById` overwritten on update | Preserve last editor/time or add an audit record. |
| P2 | Date range/report queries absent | Only class+date and student history | Add date-range filters for reporting. |

### 4.5 Fees and payments

Current working paths:

- Payment settings and proof review are REST-backed.
- Per-student challan creation supports `billingPeriod`, duplicate checks, and amount validation.
- Challan list/student list/pay and ledger stats exist.

Gaps:

| Priority | Gap | Evidence | Required work |
|---|---|---|---|
| P0 | Fee dates are discarded | Backend returns ISO; model accepts only Firestore `Timestamp` and defaults to now | Parse ISO dates in the model/client. |
| P0 | Bulk generation is blocked by Firestore sections | Generation screen reads Firestore sections; placeholder Firebase makes the list empty | Move generation to REST section/roster data. |
| P0 | Bulk endpoint is inconsistent and unused | `/fees/challans/generate` has no `billingPeriod`, no transaction, no duplicate handling, and random challan numbers | Either make it atomic/idempotent or remove it in favor of per-student create. |
| P1 | Overdue status is not maintained | Ledger counts `OVERDUE` only if already stored; client computes `isOverdue` from broken dates | Add due-date-based status derivation or a scheduled update. |
| P1 | No challan update/delete | Only mark-paid exists | Add safe correction/void flow. |
| P1 | Student fee reads hide errors | `getForStudent` returns `[]` on failure | Surface errors. |
| P1 | Parent fees depend on broken parent linking | Child list/profile stubs | Fix parent identity path first. |
| P2 | Ledger filters are client-side | Ledger fetches all challans | Add server-side filtering/pagination. |
| P2 | Proof data size/type validation is basic | Base64 image body and MIME checks | Add explicit size/type validation and storage strategy. |

### 4.6 Quizzes, marks, and submissions

Current working paths:

- Quiz create and individual mark upsert work.
- Student mark history is formatted and parsed safely.

Gaps:

| Priority | Gap | Evidence | Required work |
|---|---|---|---|
| P0 | Quiz listing crashes on ISO `created_at` | `QuizModel.fromMap` casts to Firestore `Timestamp`; stream catches and returns `[]` | Guard/parse ISO strings. |
| P0 | Quiz role scoping is missing | Any authenticated user can fetch all academy quizzes, including `correct_index` | Scope by teacher/admin/student and omit answer keys from student/parent payloads. |
| P0 | Quiz update/delete endpoints missing | Client methods are empty; UI reports success | Add `PUT /quizzes/:id`, `DELETE /quizzes/:id`, and question replacement or dedicated update. |
| P0 | Marks-by-quiz/class endpoints missing | Client streams always `[]`; backend has no routes | Add results endpoints scoped to teacher/admin. |
| P0 | Delete mark missing | Client method empty; no backend route | Add `DELETE /quizzes/marks/:id`. |
| P1 | Create drops metadata | `month`, `session`, `chapter`, `difficulty`, `testDate` not sent | Send and persist fields. |
| P1 | GET omits `test_date` and `created_by_name` | Formatter does not include them | Add fields to list DTO. |
| P1 | Admin academy marks is a stub | `getAllAcademyMarks` returns `[]` | Add admin-scoped marks endpoint or remove AI insight input. |
| P1 | Quiz submissions have no backend | `QuizSubmissionModel` unused | Implement submission storage/routes or remove the model and workflow. |
| P1 | No enrollment validation for marks | Backend checks student exists in academy, not enrollment in quiz class | Validate student is enrolled and role STUDENT. |
| P2 | Create returns raw Prisma shape | Different from list DTO | Return the same quiz DTO. |
| P2 | No pagination/filtering for marks | Full lists | Add filters/pagination. |

### 4.7 Timetable

Current state: Flutter is entirely Firestore-backed; backend API is unused.

Gaps:

| Priority | Gap | Evidence | Required work |
|---|---|---|---|
| P0 | No client REST integration | `TimetableProvider` uses `TimetableService` Firestore | Replace service with REST adapter and refresh behavior. |
| P0 | Contract mismatch | Flutter uses integer `dayOfWeek`, minute offsets, room, semester, break flag, effective dates; Prisma uses string day/start/end and omits most fields | Align schema/DTO and client model. |
| P0 | Break slots cannot be represented | Backend requires `teacherId` and `subject` | Make teacher optional for breaks and model break type explicitly. |
| P1 | No update endpoint | Client supports update via Firestore | Add `PUT /timetable/:id`. |
| P1 | No bulk create | Calendar editing may need batches | Add bulk endpoint or transactional client operation. |
| P1 | Collision logic is incomplete | Checks only teacher+day+start | Check time ranges, class, and optionally room; define break behavior. |
| P1 | Cascading class deletion not represented | Firestore deletes slots for class | Add DB cascade or backend cleanup. |
| P2 | No date/semester filtering | Client filters locally | Add backend filters. |

### 4.8 Resources and student queries

Current state: Flutter uses Firestore. Existing REST routes are unreachable at the intended paths.

Gaps:

| Priority | Gap | Evidence | Required work |
|---|---|---|---|
| P0 | Doubled resource paths | Router mounted at `/api/v2/resources`, routes start with `/resources` and `/queries` | Mount router at `/api/v2` or change route paths. |
| P0 | No client REST integration | `ClassroomService` is Firestore-only | Implement REST resource/query service. |
| P0 | Resource create cannot accept OCR text-only content | Backend requires `fileUrl`; OCR publish has no file URL | Make `fileUrl` nullable and add `contentText`. |
| P0 | No resource delete/update | Firestore supports at least create/read; product likely needs delete | Add delete and optional update. |
| P1 | Teacher query filter missing | REST supports only classId/academy | Add teacherId/role filter. |
| P1 | Query answer is not tenant-scoped | `answerQuery` updates by ID only | Filter by `id` and `req.academyId`; reject cross-tenant IDs. |
| P1 | Class IDs are not tenant-validated | Create resource/query accepts arbitrary classId | Validate class belongs to academy; validate student enrollment for queries. |
| P1 | Resource/query role scoping is coarse | Any academy user can list all class resources/queries | Scope by enrollment/teacher assignment. |
| P2 | No attachment storage strategy | `fileUrl` may point to Firebase Storage | Decide external URL retention vs new storage service. |
| P2 | No pagination | Full class lists | Add pagination if volume grows. |

### 4.9 Announcements and notifications

Current state: Flutter uses Firestore; REST controllers are partially implemented.

Gaps:

| Priority | Gap | Evidence | Required work |
|---|---|---|---|
| P0 | Client does not use REST | Announcement/notification services and dashboard bells subscribe to Firestore | Replace both services with REST. |
| P0 | Announcement update/delete missing | Client supports both on Firestore | Add update/delete endpoints. |
| P1 | Target-role filtering is client-side | GET returns all academy announcements; client filters | Filter by caller role server-side or exclude unauthorized targets. |
| P1 | No server-side fan-out on announcement create | Firestore service notifies each target; REST create only stores the announcement | Add transactional notification fan-out or a documented client fetch model. |
| P1 | Mark-all-read missing | Firestore supports batch update | Add endpoint. |
| P1 | No admin/generic notification creation | UI needs approval/rejection and possibly system notices | Add admin-only creation endpoint or keep notifications system-generated only. |
| P1 | Rejection notification missing | Backend reject has no notification | Add if product requires it. |
| P1 | Approve flow writes a duplicate Firestore notification | Backend already creates approval notification; UI writes again | Remove duplicate and false-failure path. |
| P2 | Notification list unbounded | REST has no limit | Add pagination or cap. |
| P2 | Notification creation uses tenant-key inconsistencies | Firestore sends admin UID in several screens | Remove client tenant arguments after REST switch. |

### 4.10 Academic structure and class reports

Current state: Firestore-only, no backend equivalent.

Gaps:

| Priority | Gap | Required work |
|---|---|---|
| P0 | Academic structure cannot load/save without Firebase | Add `Academy.academicStructure` JSON plus GET/PUT endpoints and defaults. |
| P0 | Class sections cannot load/save without Firebase | Add section model and CRUD/roster endpoints. |
| P0 | Class reports cannot load/save without Firebase | Add report model, generate/list/delete endpoints, or explicitly remove the feature. |
| P1 | Report generation depends on attendance stub | Fix attendance aggregate before report generation. |
| P1 | Report snapshots have no server-side consistency | Generate server-side from roster, attendance, and fees in one request/transaction. |
| P1 | Tenant keys use admin UID | Normalize to academy UUID. |

### 4.11 OCR, classroom publishing, and PDF

Current state:

- OCR text extraction is on-device and works.
- OCR persistence/history/view/delete uses Firestore.
- OCR publish creates a Firestore learning resource.
- Test-paper PDF reads a Firestore `users/{quiz.academyId}` document.

Gaps:

| Priority | Gap | Required work |
|---|---|---|
| P0 | OCR history is Firestore-only | Add OCR CRUD routes and client REST service. |
| P0 | OCR schema lacks audit/tenant fields | Add `academyId`, `createdByName`, `updatedAt`; backfill/migrate if required. |
| P0 | OCR publish cannot use resource API | Add text-only resource support. |
| P0 | Test-paper PDF uses Firestore and wrong document key | Use authenticated academy/user profile data from REST. |
| P1 | No OCR owner/tenant policy on backend | Enforce owner or admin scope. |
| P1 | No file/attachment model for OCR | Keep extracted text only unless attachments are required. |

### 4.12 ML service

Current state:

- Nine admin ML endpoints exist.
- `ML_SERVICE_URL` and `ML_INTERNAL_TOKEN` are unset, so endpoints return 503.
- Flutter quiz generation/grading uses offline TextRank/TF-IDF, not the ML service.

Gaps and decisions:

| Priority | Gap | Required work |
|---|---|---|
| P2 | External ML service is unconfigured | Keep endpoints optional; do not block Firebase migration. |
| P2 | No Flutter integration | Treat ML as a separate future feature unless required. |
| P2 | Admin insights depend on missing marks endpoints | Fix marks/results first if AI insights are in scope. |

### 4.13 Platform, security, and operations

| Priority | Gap | Current state | Required work |
|---|---|---|---|
| P0 | Release Android cannot reach the API | `INTERNET` absent from main manifest; HTTP dev URL | Add permission, define HTTPS/production base URL, and network-security policy. |
| P0 | Firebase startup is unconditional | App always initializes placeholder Firebase | Remove initialization after Firestore removal or make it migration-only. |
| P1 | No login rate limiting/lockout | Only ML training is limited | Add rate limit and lockout. |
| P1 | Client hides API failures | Catch-all empty lists | Surface errors and add tests. |
| P1 | No response contract tests | Existing tests cover auth/role utilities only | Add controller/client fixture tests for each DTO. |
| P1 | No seed data | `prisma/seed.js` referenced but missing; database has no domain rows | Add a repeatable seed for demos/tests. |
| P2 | No API pagination/standard validation | Ad hoc controllers | Add shared validation and pagination. |
| P2 | No migration rollback runbook | None | Add documented backup/restore and rollback. |
| P2 | v1 remains exposed | Duplicate mounts | Deprecate or document. |

## 5. Required Schema Changes

The following changes are the minimum likely schema work. They are additive unless a later decision approves a redesign.

### 5.1 New or changed models

| Model | Change | Reason |
|---|---|---|
| `Academy` | Add `academicStructure Json?` or normalized structure tables | Replaces `academy_settings`. |
| `User` | Add optional `legacyFirebaseUid String? @unique`; add `subject String?`, `extraInfo String?`, maybe `joiningDate DateTime?` | Identity mapping and profile parity. Roll number should generally live on enrollment. |
| `ClassSection` | New: `id`, `academyId`, `className`, `program`, `section`, timestamps, unique academy/class/program/section | Canonical section roster. |
| `ClassSectionEnrollment` | New: `sectionId`, `studentId`, roll number, timestamps, unique section/student | One roster per section, independent of subject offerings. |
| `Class` | Add optional `program`, `classSectionId`; keep subject offering model | Link subject offerings to canonical sections without destructive redesign. |
| `StudentEnrollment` | Ensure `rollNumber` is validated and returned; add update support | Roll-number persistence and roster editing. |
| `ClassReport` | New snapshot model with existing Firestore fields | Replaces `class_reports`. |
| `TimetableSlot` | Align fields: integer day, minute offsets or normalized times, room, semester, break flag, effective dates, optional teacher for breaks | Replaces Firestore timetable schema. |
| `FeeChallan` | Make `billingPeriod` required after backfill; review unique constraint with nullable periods | Duplicate prevention and reporting. |
| `SharedResource` | Make `fileUrl` nullable; add `contentText`, optional `fileName`/`mimeType`, `updatedAt` | OCR text publishing and metadata. |
| `OcrDocument` | Add `academyId`, `createdByName`, `updatedAt`; indexes | REST persistence and audit. |
| `Notification` | Add indexes for `(academyId, recipientId, createdAt)` and read state | List performance. |
| `Announcement` | Add index `(academyId, createdAt)` and consider target-role representation | Filtering and ordering. |
| `AttendanceRecord` | Add indexes for `(academyId, logDate)` and reporting | Academy-wide stats. |
| `Quiz` | Add indexes for `(academyId, classId, createdAt)` | Scoped listing. |
| `StudentQuery` | Add teacher/status indexes | Teacher queues. |
| `TimetableSlot` | Add `(academyId, classId, dayOfWeek)` and teacher conflict indexes | Queries/collision checks. |

### 5.2 Data integrity rules

- All academy-owned rows must be checked against `req.academyId`, not trusted from the body.
- All foreign IDs supplied by a client (class, student, teacher, parent, quiz) must be validated inside the caller's academy.
- Parent linking must prevent a parent from linking an arbitrary parent ID.
- Resource/query creation must validate class membership.
- Attendance and marks must validate student enrollment.
- Cross-tenant update-by-ID bugs must be removed.

## 6. Missing Endpoint Summary

| Area | Missing endpoints / operations |
|---|---|
| Auth/users | Profile update; linked-child removal; student/parent directory search; roll uniqueness; academy code update; real password recovery or removal of recovery UI. |
| Classes/sections | Class update; student unenroll; create-with-roster; section CRUD; section roster update. |
| Attendance | Academy-wide/date-range attendance; report-oriented queries. |
| Fees | Safe challan correction/void; atomic/idempotent bulk generation; overdue derivation. |
| Quizzes | Quiz update/delete; question update; marks by quiz/class; admin marks; delete mark; submissions. |
| Timetable | Update; bulk; break slots; aligned filters. |
| Resources/queries | Correct mount paths; delete/update; teacher filter; ContentText; tenant/role validation. |
| Announcements/notifications | Announcement update/delete; server-side target filtering; fan-out; mark-all-read; optional admin notification creation. |
| Academic structure/reports | Structure GET/PUT; report generate/list/delete. |
| OCR/PDF | OCR CRUD; text-only resource; REST academy lookup for PDF. |
| Platform | Release networking; seed; contract tests; migration/reconciliation tooling. |

## 7. Security and Privacy Findings

| Severity | Finding | Consequence | Fix |
|---|---|---|---|
| High | `GET /users/by-role` has no role guard | Any authenticated user can enumerate active users across roles | Restrict to staff/admin or return minimal fields for specific workflows. |
| High | Quiz list exposes `correct_index` to all authenticated roles and all academy quizzes | Students/parents can obtain answer keys and quizzes outside their classes | Role/class scope and student-safe DTO. |
| High | Query answer updates by ID without academy filter | Cross-tenant update possible if an ID is known | Add tenant filter/authorization. |
| High | Parent link trusts body `parentId` | A parent can attempt to link another parent | Force self or admin-only. |
| High | Resource/query/attendance/mark writes do not validate related records | Cross-academy or unenrolled data can be attached | Validate all foreign IDs in tenant scope. |
| Medium | Announcement reads return all target roles | Role-targeted content leaks to other roles | Server-side role filtering. |
| Medium | Approval/rejection UI can report failure after backend success | Users retry or assume failure | Remove non-critical Firestore writes from success paths. |
| Medium | No auth rate limiting/lockout | Brute-force risk | Add limiter and lockout. |
| Medium | Firestore rules depend on absent Firebase Auth session/profile docs | False confidence in client-side security | Remove Firestore or implement real Firebase Auth before retaining it. |
| Medium | Release Android lacks network permission | Release functionality fails | Add `INTERNET` and production HTTPS config. |
| Low | Catch-all client errors hide failures | Operational blindness | Surface/log errors and add retries. |

## 8. Priority Order

### P0: Required before calling migration complete

1. Fix the response/date contract and attendance encoding.
2. Add canonical class-section and academic-structure APIs; align enrollment.
3. Add quiz update/delete and marks/results endpoints, and scope quiz data.
4. Add academy-wide attendance and make reports agnostic of the stub.
5. Add user profile update, roll-number persistence, parent directory/search/remove-child, and profile hydration.
6. Add REST timetable contract and client integration.
7. Add OCR persistence routes and text-only resource support.
8. Add announcement/notification update/delete/filter/fan-out and mark-all.
9. Fix resource/query route mounting and tenant validation.
10. Remove unconditional Firebase initialization and dead Firestore services.

### P1: Needed for a defensible, usable system

1. Security hardening: by-role restriction, tenant checks, parent self-link, rate limiting.
2. Error propagation and retry/empty-state distinction.
3. Server-side target filtering and pagination.
4. Fee correction/void and overdue derivation.
5. PDF academy profile via REST.
6. Contract tests for every DTO.

### P2: Operational and scale work

1. v1 deprecation, validation library, pagination, seed data, ML integration, and legacy cleanup.

## 9. Exit Criteria for the Gap Phase

The gap phase is complete when:

- Every Firestore collection has a REST destination or an explicit removal decision.
- Every P0 client stub has a matching backend route or a documented feature removal.
- No client screen passes `user.uid` as an academy key.
- Response DTOs are consistent and covered by contract tests.
- All cross-tenant ID paths are filtered by `req.academyId`.
- The migration plan can be executed incrementally without a big-bang cutover.
