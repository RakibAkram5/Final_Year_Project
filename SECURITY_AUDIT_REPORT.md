# Security audit report (2026-11-09)

Scope: Express API, data access rules, file handling, secrets, Flutter client,
ML service, deployment configuration. Method: code review plus contract tests
that call the real API with users of different roles and academies.

## Findings fixed in this release

| # | Finding | Severity | Fix | Test |
|---|---|---|---|---|
| S1 | A parent could link themselves to **any** student in the academy (`POST /users/link-child`) after finding them via `GET /users/search`, then read that student's attendance, fees, marks and profile | Critical | linking admin-only; search admin/teacher only | `parentPortal.contract.test.js` |
| S2 | `GET /classes` exposed classmates' names, ids and roll numbers to students and parents | High | roster limited to self / linked children | same |
| S3 | Teachers could create, edit and delete resources in classes they do not teach | High | class-teacher check (`canManageClass`) | `files.contract.test.js`, `contract.test.js` |
| S4 | Students/parents could list materials of any class by passing its id | High | enrolment check → 403 | `files.contract.test.js` |
| S5 | Body-parser errors returned 500 with internal messages in development | Low | mapped to 400/413 | — |

## New surfaces and their controls

| Surface | Controls |
|---|---|
| File upload | auth + per-category relationship checks; content-type **detected from bytes** and must match the extension (spoofed PDF/EXE rejected); 4 MB limit; filename sanitised (no path traversal — names are metadata only; storage keys are random UUIDs) |
| File download | authorised route only, **private** Blob store, `Cache-Control: private, no-store`, `nosniff`; unauthorised ids return 404 (no existence leak) |
| Assignments | class-teacher/admin for management; enrolled student for submissions; deadline and resubmission rules enforced server-side |
| Excel exports | class teacher/admin; fees admin-only; academy-scoped |
| Geocoding proxy | admin-only, input length/range validation, upstream throttled and cached, no user data forwarded |
| Bank details | admin-only write; IBAN checksum; shown only to the academy's own users |
| ML | admin-only proxy; academy from JWT; internal bearer token (≥ 32 chars, constant-time compare); read-only DB role recommended; artifacts keyed by SHA-256 of academy id, no PII |

## Existing controls verified

| Control | Status |
|---|---|
| Passwords | bcrypt; policy (≥ 8, common-password list) |
| Sessions | JWT 15 min + rotating, revocable refresh tokens (7 d); lockout after 5 failures |
| Tenancy | academy taken from the token on every query; cross-academy access tests return 403/404 |
| Roles | `authorizeRoles` per route + relationship checks in controllers |
| SQL injection | Prisma parameterised queries; ML extractor uses psycopg parameters |
| Input validation | zod on most write endpoints; date validation tightened |
| CORS | explicit allowlist in production; same-origin via Netlify proxy |
| Rate limiting | auth endpoints, ML training (in-memory per instance) |
| Secrets | none in Git or in the Flutter build; server refuses weak JWT secrets in production |
| Headers | helmet on the API; HSTS, nosniff, frame-deny on Netlify |

## Open items / recommendations

| Item | Severity | Recommendation |
|---|---|---|
| `zod` < 4.6.6 advisory (memory exhaustion on oversized constrained collections) | Medium (mitigated: 1.5 MB JSON limit) | upgrade to zod v4 in a separate change with full test run |
| `uuid` advisory via exceljs (only affects v3/v5/v6 with caller buffers) | Low | not exploitable as used; track upstream |
| Rate limits are per serverless instance | Low | add Upstash Redis if abuse appears |
| Refresh tokens stored as raw strings | Low | store SHA-256 hashes |
| Firebase web API key remains in Git history | Low–Medium | restrict/rotate in Google Cloud if that project still exists |
| No antivirus scanning of uploads | Low | files are never executed or served inline except PDF/images; add scanning if required |
| List endpoints capped, not paginated | Low (availability) | add cursor pagination |
| Android `applicationId` is `com.example.taleem_plus` and release signing is not configured | Info | **Done**: `com.taleemplus.app`; release keystore generated 2026-11-13 (outside the repo) |

## Update 2026-11-13 (v1.2.0)

Fixed since the table above was written (regression tests in `tests/securityRegressions.contract.test.js`, `tests/quizAttempt.contract.test.js`, `tests/parentPortal.contract.test.js`):

| Finding | Fix |
|---|---|
| Refresh tokens stored as raw strings | Stored as SHA-256 hashes, rotated on every refresh (`5e8727b`). |
| Expired access token answered with 403 → clients never refreshed; sessions broke after 15 min | 401 + `TOKEN_EXPIRED` / `UNAUTHENTICATED`; 403 + `ACCOUNT_INACTIVE` only for disabled accounts. Client refreshes on 401 and proactively on app resume. |
| **Parent could read the whole student directory** (`GET /users/directory?role=STUDENT`) | Scoped to staff + the parent's linked children. |
| Any teacher could edit/delete any announcement and answer any student query | Creator-or-admin for announcements; class teacher-or-admin for query answers. |
| Rate limiter keyed on the proxy address | `trust proxy = 1` (Vercel); production log line without query strings. |
| No Content-Security-Policy on the web app | CSP in `netlify.toml` / `web/_headers` allowing only the origins the app loads (CanvasKit, Tesseract.js, pdf.js, Google Fonts, OpenStreetMap). |
| Answer keys for online tests | New attempt endpoints never return `correct_index` / keywords before submission; grading is server-side; one submission per student (unique constraint). |
| Duplicated ML service code (`ml_service/hf_space/build`) | Generated copy removed from git and ignored; `prepare_space.py` regenerates it. |

Still open and requiring the owner: credential rotation and git-history rewrite (`SECURITY_ROTATION_PLAN.md`), a shared rate-limit store, zod v4 upgrade.
