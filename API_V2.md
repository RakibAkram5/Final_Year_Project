# TaleemPlus API v2 Specification

> **Base URL:** `/api/v2`  
> **Protocol:** HTTPS / HTTP REST JSON  
> **Authentication:** Bearer JWT Access Token (`Authorization: Bearer <token>`)

---

## 1. System Endpoints

### Health Check
* **GET `/health`**
* **Response (200 OK):**
  ```json
  {
    "status": "ok",
    "service": "TaleemPlus Backend Service",
    "timestamp": "2026-10-30T00:00:00.000Z"
  }
  ```

### API Version & Metadata
* **GET `/api/v2/version`**
* **Response (200 OK):**
  ```json
  {
    "success": true,
    "data": {
      "api_version": "2.0.0",
      "service": "TaleemPlus Enterprise Backend",
      "environment": "production",
      "database": "PostgreSQL + Prisma",
      "release_date": "2026-10-30",
      "supported_roles": ["ADMIN", "TEACHER", "STUDENT", "PARENT"]
    }
  }
  ```

---

## 2. Authentication (`/api/v2/auth`)

* **POST `/api/v2/auth/register-admin`** — Register new academy tenant & admin account.
* **POST `/api/v2/auth/register-user`** — Join academy using unique academy code (`TP-XXXXX`).
* **POST `/api/v2/auth/login`** — Authenticate email/password. Returns JWT access token (15m) + refresh token (7d).
* **POST `/api/v2/auth/refresh`** — Rotate a refresh token (the old token stops working). Role and academy are re-read from the database.
* **POST `/api/v2/auth/logout`** — Revoke a refresh token.
* **GET `/api/v2/auth/me`** — Fetch current authenticated user profile (includes `linkedChildren` / `linkedParents`).
* **GET `/api/v2/auth/academy-lookup?code=`** — Public, rate-limited. Case-insensitive academy code → `{ id, name, code }`, 404 if unknown.
* **PUT `/api/v2/auth/security-question`** — Set `{ question, answer }` for self-service recovery (answer stored as a bcrypt hash).
* **GET `/api/v2/auth/security-question?email=`** / **POST `/api/v2/auth/reset-password`** — Recovery: `{ email, securityAnswer, newPassword }`; revokes all sessions.

Login behaviour: email matching is case-insensitive; after 5 consecutive wrong passwords the account is locked for 15 minutes (HTTP 423, `code: ACCOUNT_LOCKED`; tunable via `MAX_FAILED_LOGINS` / `LOCKOUT_MINUTES`). Non-active accounts get HTTP 403 with `code` `ACCOUNT_PENDING`, `ACCOUNT_REJECTED` or `ACCOUNT_INACTIVE`.

---

## 3. Core Modules

All academy data is scoped to the caller's academy from the access token; client-supplied academy IDs are ignored. Every related student, teacher, class and section is verified to belong to that academy (cross-academy IDs return 403/404).

| Module | Endpoints | Notes |
|---|---|---|
| Users | `GET /users/pending`, `PUT /users/:id/approve` · `reject` · `deactivate` · `reactivate`, `POST /users/create`, `PUT /users/:id`, `PUT /users/me`, `GET /users/by-role` · `directory` · `search` · `:id`, `POST /users/profiles`, `GET /users/roll-number-available?rollNumber=&excludeId=` | Deactivation keeps all history and revokes sessions. Parents listing students see only linked children. |
| Parent links | `POST /users/link-child`, `DELETE /users/link-child/:studentId[?parentId=]` | Admin passes `parentId`; parents act on themselves. |
| Link requests | `POST /users/link-requests` (parent), `GET /users/link-requests/mine`, `GET /users/link-requests[?status=]` (admin), `POST /users/link-requests/:id/approve` · `reject` | A parent asks; the link exists only after an admin approves. |
| Academy branding | `GET /academy/branding`, `PUT /academy/branding` (admin), `GET /academy/branding/public?code=` (public, rate-limited) | Name, address, phone, e-mail and a validated logo image (data URI); the logo is rendered in every portal and on PDFs. |
| Classes | `GET/POST /classes`, `PUT/DELETE /classes/:id`, `POST /classes/:id/enroll`, `DELETE /classes/:id/enroll/:studentId` | `studentIds` accepted on create. |
| Class sections | `GET/POST /class-sections`, `PUT/DELETE /class-sections/:id`, `PUT /class-sections/:id/enrollment`, `POST /class-sections/:id/enroll`, `DELETE /class-sections/:id/enroll/:studentId` | Roster changes cascade to linked subject classes. Deleting a section keeps its classes. |
| Academic structure | `GET/PUT /academic-structure` | `{ levels: [{ name, groups[] }] }` |
| Class reports | `GET/POST /class-reports`, `DELETE /class-reports/:id` | Generated server-side from `{ sectionId, logDate }`. |
| Attendance | `POST /attendance/mark`, `GET /attendance[?classId&from&to]`, `GET /attendance/class?classId&logDate`, `GET /attendance/student/:id` | One record per class/student/day (upsert). Teachers only for their own classes. |
| Fees | `POST /fees/challans`, `POST /fees/challans/generate`, `GET /fees/challans`, `GET /fees/challans/student/:id`, `PUT /fees/challans/:id/pay`, `GET /fees/ledger/stats` | Status is `overdue` once the due day has passed. Ledger includes `total_overdue` and a `monthly` breakdown by billing period. |
| Payments | `GET/PUT /fees/payment-settings`, `POST /fees/challans/:id/proof`, `GET /fees/payment-proofs/pending`, `PUT /fees/payment-proofs/:id/review` | |
| Quizzes & marks | `GET/POST /quizzes`, `GET/PUT/DELETE /quizzes/:id`, `PUT /quizzes/:id/questions`, `POST /quizzes/marks`, `DELETE /quizzes/marks/:id`, `GET /quizzes/marks/quiz/:id` · `class/:id` · `student/:id` · `academy` | Teachers manage only their own classes' quizzes. Students/parents never receive answer keys. Quizzes carry `attempt_mode` (`PAPER` \| `ONLINE`), `available_from/until`, `duration_minutes`. |
| Online attempts | `POST /quizzes/:id/attempt`, `PUT /quizzes/:id/attempt/answers`, `POST /quizzes/:id/attempt/submit`, `GET /quizzes/:id/attempt[?studentId=]`, `GET /quizzes/:id/submissions`, `PUT /quizzes/:id/submissions/:sid/grade` | One submission per student per quiz (idempotent submit). MCQs auto-graded on the server; written answers graded by the class teacher; result published as a TestMark when complete. |
| ML (admin) | `GET /admin/ml/status` · `dashboard` · `analytics` · `metrics` · `history`, `POST /admin/ml/predict/*`, `train/*`, `retrain`, `rollback` | Proxy to the ML service with the internal token; training calls limited to 3/min. |
| Resources & queries | `GET/POST /resources`, `PUT/DELETE /resources/:id`, `GET/POST /queries`, `PUT /queries/:id/answer` | Create body: `{ classId, title, description?, fileUrl? or contentText? }`. |
| Timetable | `GET /timetable[?teacherId&classIds&dayOfWeek]`, `POST /timetable`, `PUT/DELETE /timetable/:id` | `dayOfWeek` 1 = Monday … 7 = Sunday. |
| Notifications | `GET /notifications`, `POST /notifications`, `PUT /notifications/:id/read`, `PUT /notifications/read-all`, `DELETE /notifications/:id` | Approvals create a notification automatically. |
| Announcements | `GET/POST /announcements`, `PUT/DELETE /announcements/:id` | Filtered by `targetRoles` for the caller. |
| OCR documents | `GET/POST /ocr`, `GET/PUT/DELETE /ocr/:id` | Private to the author. Text extraction runs on-device (ML Kit). |

The repository check `npm run check:routes` (in `taleemplus_backend/`) fails CI if the Flutter client calls a path the backend does not serve.

---

## 4. Response Contract

Successful responses:

```json
{ "success": true, "message": "Optional message", "data": {} }
```

Error responses include a stable machine-readable code:

```json
{
  "success": false,
  "code": "VALIDATION_ERROR",
  "message": "Request validation failed.",
  "details": [{ "path": "logDate", "message": "Must be a valid calendar date in YYYY-MM-DD format.", "code": "custom" }]
}
```

Codes: `VALIDATION_ERROR`, `UNAUTHENTICATED`, `TOKEN_EXPIRED` (401 — refresh the access token and retry), `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `RATE_LIMITED`, `INTERNAL_ERROR`, plus account-state codes `ACCOUNT_LOCKED` (423), `ACCOUNT_PENDING`, `ACCOUNT_REJECTED`, `ACCOUNT_INACTIVE` (403 — a refresh will not help; sign the user out).

Collection DTOs use snake_case. Auth/profile DTOs use camelCase. Dates are ISO-8601 strings; date-only fields use `YYYY-MM-DD`. Enum values in collection DTOs are lowercase.

Login, registration, and refresh endpoints are rate limited and return HTTP 429 with `RATE_LIMITED` when the limit is exceeded.

## 5. Versioning

`/api/v1` remains mounted for already-released clients only. All v1 responses include `Deprecation: true` and a `Link` header pointing at `/api/v2`. New work targets v2 exclusively.
