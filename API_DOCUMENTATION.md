# TaleemPlus API documentation (v2)

Base URL: `https://<backend-host>/api/v2` (production backend: `https://taleemplus.vercel.app/api/v2`; the Netlify site proxies `/api/*` to it).
Health: `GET /health` → `{ status, database }` (no auth).

## Conventions

| Topic | Rule |
|---|---|
| Auth | `Authorization: Bearer <accessToken>` (JWT, 15 min). Refresh with `POST /auth/refresh {refreshToken}` (rotated, 7 days, revocable). |
| Tenancy | The academy is **always** taken from the signed-in user, never from the request. Every query is scoped to it. |
| Success | `{ "success": true, "data": … , "message"? }` |
| Error | `{ "success": false, "code"?: "VALIDATION_ERROR" \| "FORBIDDEN" \| "NOT_FOUND" \| …, "message": "…", "details"?: [...] }` |
| Status codes | 400 validation · 401 no/expired token · 403 role/relationship not allowed · 404 not found **or not visible to you** · 409 conflict/duplicate · 413 too large · 415 unsupported file · 423 account locked · 429 rate limited · 503 dependency (storage, ML, geocoder) unavailable |
| Body size | JSON ≤ 1.5 MB; raw file uploads ≤ 4 MB (Vercel caps requests at 4.5 MB) |
| Roles | `ADMIN`, `TEACHER`, `STUDENT`, `PARENT` |
| v1 | `/api/v1/*` is a deprecated alias of a subset of v2 (sends `Deprecation: true`). |

## Endpoint inventory

Generated from `taleemplus_backend/src/routes/*.js`. "Roles" is the route-level gate; controllers apply finer relationship checks (class teacher, enrolled student, linked parent).

| Method | Path | Roles |
|---|---|---|
| POST | `/api/v2/auth/register-admin` | public (no token) |
| POST | `/api/v2/auth/register-user` | public (no token) |
| POST | `/api/v2/auth/login` | public (no token) |
| POST | `/api/v2/auth/refresh` | public (no token) |
| POST | `/api/v2/auth/logout` | public (no token) |
| GET | `/api/v2/auth/security-question` | public (no token) |
| POST | `/api/v2/auth/reset-password` | public (no token) |
| GET | `/api/v2/auth/academy-lookup` | public (no token) |
| GET | `/api/v2/auth/me` | any signed-in user |
| PUT | `/api/v2/auth/security-question` | any signed-in user |
| POST | `/api/v2/auth/verify-password` | any signed-in user |
| PUT | `/api/v2/auth/password` | any signed-in user |
| PUT | `/api/v2/auth/academy` | ADMIN |
| GET | `/api/v2/users/pending` | ADMIN |
| PUT | `/api/v2/users/:id/approve` | ADMIN |
| PUT | `/api/v2/users/:id/reject` | ADMIN |
| GET | `/api/v2/users/by-role` | ADMIN, TEACHER, PARENT |
| GET | `/api/v2/users/directory` | ADMIN, TEACHER, PARENT |
| GET | `/api/v2/users/search` | ADMIN, TEACHER |
| POST | `/api/v2/users/profiles` | ADMIN, TEACHER, PARENT |
| GET | `/api/v2/users/roll-number-available` | ADMIN |
| PUT | `/api/v2/users/me` | any signed-in user |
| PUT | `/api/v2/users/:id/password` | ADMIN |
| PUT | `/api/v2/users/:id/deactivate` | ADMIN |
| PUT | `/api/v2/users/:id/reactivate` | ADMIN |
| POST | `/api/v2/users/link-child` | ADMIN |
| DELETE | `/api/v2/users/link-child/:studentId` | ADMIN, PARENT |
| POST | `/api/v2/users/create` | ADMIN |
| PUT | `/api/v2/users/:id` | ADMIN |
| GET | `/api/v2/users/:id` | ADMIN, TEACHER, PARENT |
| GET | `/api/v2/classes` | any signed-in user |
| POST | `/api/v2/classes` | ADMIN |
| PUT | `/api/v2/classes/:id` | ADMIN |
| DELETE | `/api/v2/classes/:id` | ADMIN |
| POST | `/api/v2/classes/:id/enroll` | ADMIN |
| DELETE | `/api/v2/classes/:id/enroll/:studentId` | ADMIN |
| GET | `/api/v2/class-sections` | any signed-in user |
| POST | `/api/v2/class-sections` | ADMIN |
| PUT | `/api/v2/class-sections/:id` | ADMIN |
| DELETE | `/api/v2/class-sections/:id` | ADMIN |
| PUT | `/api/v2/class-sections/:id/enrollment` | ADMIN |
| POST | `/api/v2/class-sections/:id/enroll` | ADMIN |
| DELETE | `/api/v2/class-sections/:id/enroll/:studentId` | ADMIN |
| GET | `/api/v2/class-reports` | any signed-in user |
| POST | `/api/v2/class-reports` | ADMIN |
| DELETE | `/api/v2/class-reports/:id` | ADMIN |
| GET | `/api/v2/academic-structure` | any signed-in user |
| PUT | `/api/v2/academic-structure` | ADMIN |
| GET | `/api/v2/ocr` | any signed-in user |
| GET | `/api/v2/ocr/:id` | any signed-in user |
| POST | `/api/v2/ocr` | any signed-in user |
| PUT | `/api/v2/ocr/:id` | any signed-in user |
| DELETE | `/api/v2/ocr/:id` | any signed-in user |
| GET | `/api/v2/attendance` | any signed-in user |
| POST | `/api/v2/attendance/mark` | ADMIN, TEACHER |
| GET | `/api/v2/attendance/student/:studentId` | any signed-in user |
| GET | `/api/v2/attendance/class` | ADMIN, TEACHER |
| GET | `/api/v2/fees/payment-settings` | any signed-in user |
| PUT | `/api/v2/fees/payment-settings` | ADMIN |
| POST | `/api/v2/fees/challans/:id/proof` | STUDENT, PARENT |
| GET | `/api/v2/fees/payment-proofs/pending` | ADMIN |
| PUT | `/api/v2/fees/payment-proofs/:id/review` | ADMIN |
| POST | `/api/v2/fees/challans/generate` | ADMIN |
| POST | `/api/v2/fees/challans` | ADMIN |
| GET | `/api/v2/fees/challans` | ADMIN |
| GET | `/api/v2/fees/challans/student/:studentId` | any signed-in user |
| PUT | `/api/v2/fees/challans/:id/pay` | ADMIN |
| GET | `/api/v2/fees/ledger/stats` | ADMIN |
| GET | `/api/v2/quizzes` | any signed-in user |
| GET | `/api/v2/quizzes/marks/academy` | ADMIN, TEACHER |
| GET | `/api/v2/quizzes/marks/quiz/:quizId` | ADMIN, TEACHER |
| GET | `/api/v2/quizzes/marks/class/:classId` | ADMIN, TEACHER |
| GET | `/api/v2/quizzes/marks/student/:studentId` | any signed-in user |
| POST | `/api/v2/quizzes/marks` | ADMIN, TEACHER |
| DELETE | `/api/v2/quizzes/marks/:id` | ADMIN, TEACHER |
| GET | `/api/v2/quizzes/:id` | any signed-in user |
| POST | `/api/v2/quizzes` | ADMIN, TEACHER |
| PUT | `/api/v2/quizzes/:id` | ADMIN, TEACHER |
| PUT | `/api/v2/quizzes/:id/questions` | ADMIN, TEACHER |
| DELETE | `/api/v2/quizzes/:id` | ADMIN, TEACHER |
| GET | `/api/v2/files` | any signed-in user |
| POST | `/api/v2/files` | any signed-in user |
| GET | `/api/v2/files/:id/content` | any signed-in user |
| PUT | `/api/v2/files/:id/content` | any signed-in user |
| DELETE | `/api/v2/files/:id` | any signed-in user |
| GET | `/api/v2/assignments` | any signed-in user |
| POST | `/api/v2/assignments` | ADMIN, TEACHER |
| PUT | `/api/v2/assignments/:id` | ADMIN, TEACHER |
| DELETE | `/api/v2/assignments/:id` | ADMIN, TEACHER |
| GET | `/api/v2/assignments/:id/submissions` | ADMIN, TEACHER |
| PUT | `/api/v2/assignments/:id/submissions/:submissionId/grade` | ADMIN, TEACHER |
| POST | `/api/v2/assignments/:id/submission` | STUDENT |
| GET | `/api/v2/reports/attendance.xlsx` | any signed-in user |
| GET | `/api/v2/reports/results.xlsx` | any signed-in user |
| GET | `/api/v2/reports/fees.xlsx` | any signed-in user |
| GET | `/api/v2/geo/search` | any signed-in user |
| GET | `/api/v2/geo/reverse` | any signed-in user |
| GET | `/api/v2/resources` | any signed-in user |
| POST | `/api/v2/resources` | ADMIN, TEACHER |
| PUT | `/api/v2/resources/:id` | ADMIN, TEACHER |
| DELETE | `/api/v2/resources/:id` | ADMIN, TEACHER |
| GET | `/api/v2/queries` | any signed-in user |
| POST | `/api/v2/queries` | STUDENT |
| PUT | `/api/v2/queries/:id/answer` | ADMIN, TEACHER |
| GET | `/api/v2/notifications` | any signed-in user |
| POST | `/api/v2/notifications` | ADMIN |
| PUT | `/api/v2/notifications/read-all` | any signed-in user |
| PUT | `/api/v2/notifications/:id/read` | any signed-in user |
| DELETE | `/api/v2/notifications/:id` | any signed-in user |
| GET | `/api/v2/announcements` | any signed-in user |
| POST | `/api/v2/announcements` | ADMIN, TEACHER |
| PUT | `/api/v2/announcements/:id` | ADMIN, TEACHER |
| DELETE | `/api/v2/announcements/:id` | ADMIN, TEACHER |
| GET | `/api/v2/timetable` | any signed-in user |
| POST | `/api/v2/timetable` | ADMIN |
| PUT | `/api/v2/timetable/:id` | ADMIN |
| DELETE | `/api/v2/timetable/:id` | ADMIN |
| GET | `/api/v2/admin/ml/status` | any signed-in user |
| GET | `/api/v2/admin/ml/metrics` | any signed-in user |
| GET | `/api/v2/admin/ml/history` | any signed-in user |
| POST | `/api/v2/admin/ml/predict/fee-risk` | any signed-in user |
| POST | `/api/v2/admin/ml/predict/performance` | any signed-in user |
| POST | `/api/v2/admin/ml/train/fee-risk` | any signed-in user |
| POST | `/api/v2/admin/ml/train/performance` | any signed-in user |
| POST | `/api/v2/admin/ml/retrain` | any signed-in user |
| POST | `/api/v2/admin/ml/rollback` | any signed-in user |

## Endpoints added in this release

### Files — `/files` (private storage)

| Call | Notes |
|---|---|
| `POST /files?category=<C>&ownerId=<uuid>&filename=<name>[&description=]` | Body: raw bytes, `Content-Type: application/octet-stream`, ≤ 4 MB. Type detected from content (PDF, PNG, JPEG, DOCX/XLSX/PPTX, DOC/XLS/PPT, TXT) and must match the extension. → `201 {id, originalName, mimeType, sizeBytes, contentPath, …}` |
| `GET /files?category=<C>&ownerId=<uuid>` | List metadata for one owner record. |
| `GET /files/:id/content[?disposition=inline]` | Streams the bytes. `Cache-Control: private, no-store`. Unauthorised callers get **404** (ids cannot be probed). |
| `PUT /files/:id/content?filename=` | Replace (new id; old object deleted). |
| `DELETE /files/:id` | Delete metadata and object. |

Categories and who may do what:

| Category | ownerId | Upload / replace / delete | Read |
|---|---|---|---|
| `COURSE_MATERIAL` | resource id | admin, class teacher, uploading teacher | + students enrolled in the class, their linked parents |
| `ASSIGNMENT_INSTRUCTION` | assignment id | admin, class teacher | + enrolled students, linked parents |
| `ASSIGNMENT_SUBMISSION` | submission id | the student, before the deadline (replace only if resubmission allowed) | + admin, class teacher, linked parents |
| `EXAM_DOCUMENT` | quiz id | admin, class teacher | admin, class teacher |
| `STUDENT_DOCUMENT` | student id | admin | admin, that student, linked parents |
| `TEACHER_DOCUMENT` | teacher id | admin | admin, that teacher |

### Assignments — `/assignments`

| Call | Body / notes |
|---|---|
| `GET /assignments[?classId=]` | Scoped to the caller's classes. Staff get `submissionCount`; students/parents get `mySubmissions[]` (own / linked children). |
| `POST /assignments` | `{classId, title, instructions?, dueAt (ISO), maxMarks?, allowResubmission?}` — class teacher or admin. |
| `PUT /assignments/:id`, `DELETE /assignments/:id` | Class teacher or admin. Delete removes submissions and files. |
| `GET /assignments/:id/submissions` | Staff: `{enrolledCount, submissions[] (late flag)}` |
| `POST /assignments/:id/submission` | Student (enrolled): `{note?}` → creates/updates own submission; 409 after the deadline or when resubmission is not allowed. |
| `PUT /assignments/:id/submissions/:submissionId/grade` | `{marks (0..maxMarks), feedback?}` |

### Reports (Excel) — `/reports`

| Call | Who |
|---|---|
| `GET /reports/attendance.xlsx?classId=&from=YYYY-MM-DD&to=YYYY-MM-DD` | admin, class teacher. Sheets: Summary (present/late/leave/absent, %), Daily, About. |
| `GET /reports/results.xlsx?classId=[&quizId=]` | admin, class teacher. Sheets: Results, Student totals. |
| `GET /reports/fees.xlsx?[period=YYYY-MM][&status=PENDING\|PAID\|OVERDUE]` | admin |

### Academy location & geocoding

| Call | Notes |
|---|---|
| `PUT /auth/academy` | Adds `latitude`, `longitude` (validated ranges, set/cleared together) and `locationLabel`. |
| `GET /auth/me` | Returns `academyLatitude`, `academyLongitude`, `academyLocationLabel` for every role. |
| `GET /geo/search?q=` / `GET /geo/reverse?lat=&lng=` | Admin only. Proxy to OpenStreetMap Nominatim with identifying User-Agent, 1 request/second, 24 h cache. 503 `GEOCODER_UNAVAILABLE` when upstream fails. |

### Payment settings additions

`GET/PUT /fees/payment-settings` now include `bankName`, `bankAccountNumber` (digits, spaces, dashes), `bankIban` (ISO 13616 mod-97 checked, PK = 24 chars, stored normalised) and `paymentInstructions`. Uploading payment proof never marks a challan paid; only `PUT /fees/payment-proofs/:id/review` by an admin does.

### ML proxy — `/admin/ml` (admin only)

`GET /status|/metrics|/history`, `POST /train/fee-risk|/train/performance|/retrain` (**202, runs in the background — poll `/status`**), `POST /predict/fee-risk|/predict/performance`, `POST /rollback`. Statuses: `PRODUCTION`, `READY_TO_TRAIN`, `INSUFFICIENT_DATA`, `TRAINING`, `TRAINING_FAILED`, `VALIDATED`, `NOT_READY`. See `ML_DOCUMENTATION.md`.

## Behaviour changes in this release (clients must know)

| Change | Why |
|---|---|
| `POST /users/link-child` is **admin only**; `GET /users/search` is admin/teacher only | Parents could previously attach themselves to any student. |
| `GET /classes` returns only the caller's own (student) or linked children's (parent) roster rows; `enrollment_count` gives the class size | Classmates' names and ids were exposed. |
| Teachers can create/edit/delete resources only for classes they teach; students/parents get 403 for `GET /resources?classId=` of other classes | Authorisation gaps. |
| `POST /attendance/mark` rejects future dates (400) | Data integrity. |
| Malformed JSON / oversized bodies return 400 / 413 instead of 500 | Error handling. |

## Pagination

List endpoints return at most a fixed window (e.g. 200–500 rows, newest first). Cursor pagination is **not** implemented; see Known limitations in `FINAL_TEST_REPORT.md`.
