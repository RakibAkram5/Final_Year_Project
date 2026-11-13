# TaleemPlus – Complete Project Audit & Remaining Development Analysis

**Audit date:** 2026-11-13
**Audited revision:** branch `fix/parent-link-child-search` at `4321569` (6 commits ahead of `origin/main`) **plus the uncommitted working tree** (21 modified + 19 untracked files: academy branding, ML analytics dashboard, challan PDF rewrite, ML controller rewrite).
**Method:** read every backend controller/route/middleware/schema file, the Flutter data layer, dashboards and feature screens, the ML service, CI workflows and hosting configs; ran `flutter analyze`, `flutter test`, `flutter build web --release`, `prisma validate`, `prisma migrate deploy` + `prisma migrate diff` and the full Jest suite against a throwaway local PostgreSQL 18 cluster, and `pytest` for the ML service; probed the **live** production API read-only with the seeded demo teacher/student/parent accounts; pulled GitHub Actions and release history with `gh`. No repository file was modified except the creation of this report. No production data was written (logins only).

> Honesty note: percentages below are estimates derived from the evidence cited next to them, not measurements. Anything marked **UNVERIFIED** could not be tested from this machine (reason given).

---

## 1. Executive Summary

**Overall condition:** TaleemPlus is a *real*, substantially built system, not a UI shell. The Express/Prisma backend exposes ~110 authenticated, tenant-scoped endpoints that the Flutter client actually calls (111 client calls checked against routes); the four portals read and write through that API (no Firestore, no dummy-data paths found in `lib/`); production backend, web app and ML service are all live and healthy today. The backend test suite (153/154 passing locally) is unusually thorough for an FYP.

**But the project is not releasable in its current state**, for five concrete reasons found during this audit:

1. **The working tree does not compile.** `flutter analyze` reports a hard error in the new (uncommitted) branding screen; `flutter build web --release` fails and three Flutter test files cannot load. Every Android/Web build from this tree fails until that one line is fixed.
2. **Production database is behind the code.** The `parent_link_requests` table (migration `20261110120000`) and the branding columns (`20261110200000`) are not applied to Neon. Verified live: a parent calling `GET /users/link-requests/mine` gets **HTTP 500**. The live web app (Netlify bundle) *does* contain the link-request screens, so this feature is broken for real users right now.
3. **Expired access tokens are never refreshed.** The backend answers an expired/invalid JWT with **403**, but the Flutter client only attempts a refresh on **401**. After the 15-minute access-token lifetime, every call fails with "Token expired or invalid" until the user logs out and in again. (Partly masked on mobile by the 5-minute inactivity auto-logout; fully exposed on web and during any session longer than 15 minutes.)
4. **A privacy leak:** a PARENT can download the whole student directory (`GET /users/directory?role=STUDENT` returned all 53 students, with emails, phones and roll numbers, to a parent in production).
5. **CI is red and the release pipeline cannot produce a production artifact.** Flutter CI / Android CI / main release workflow all failed on the `v1.1.2` tag (unformatted files + one layout-overflow test); the ML monitor cron has failed every 6 hours since 2026-11-10 because no GitHub secrets exist; no release keystore exists, so all published APKs are debug-signed; the backend has (last known) no `ML_SERVICE_URL`/`ML_INTERNAL_TOKEN`, so every ML screen shows "ML service not available".

### Completion estimates (evidence-based)

| Area | Estimate | Basis |
|---|---|---|
| **Overall** | **~74 %** | weighted from the rows below |
| Frontend (Flutter Android + Web) | ~78 % | all 4 portals wired to REST; responsive web shell; but tree does not compile, 403/401 refresh defect, quiz attempt is a placeholder, 13 files fail `dart format`, 1 layout overflow |
| Backend (Express + Prisma) | ~86 % | 20 controllers, zod validation on auth/attendance/resources, tenant scoping everywhere, 153/154 Jest tests; gaps: directory leak, 403 code, in-memory rate limiter on serverless, teacher-wide announcement/query edits, no pagination |
| Database (PostgreSQL/Neon + Prisma) | ~85 % | schema valid, 13 migrations == schema (`migrate diff`: no difference), good indexes/uniques/cascades; **prod is 2 migrations behind** |
| AI/ML | ~60 % | ML service: 55/55 tests, live `/health` ok, training/promotion/rollback/HF persistence implemented; on-device OCR/TextRank/TF-IDF/exam generator work offline; **backend→ML wiring absent in prod (unverified today, last known missing)**, LLM question generation unconfigured (501 by design), no trained production model confirmed |
| Testing | ~65 % | backend 153/154, Flutter 58 passed + 3 files failed to compile (CI at tag: 122/123), ML 55/55; **no end-to-end or integration run on prod**, no Flutter test for challan PDF/branding/ML analytics screens |
| Deployment | ~70 % | web (Netlify) + API (Vercel) + ML (Vercel Python) live and healthy; but CI failing, no secrets/keystore, prod DB drift, stale `/version` metadata, manual-CLI-only deploys |

---

## 2. Feature Completion Matrix

Status legend: ✅ working · 🟡 partial · 🔵 UI only · 🟠 backend only · 🐞 implemented but buggy · ❌ not implemented · ❔ unable to verify

### Admin Portal

| Module | Feature | Status | Completion % | Problem | Required Action |
|---|---|---|---|---|---|
| Admin | Dashboard & statistics | ✅ | 90 | Stats computed client-side from full lists (no pagination) | Fine at academy scale; consider a summary endpoint later |
| Admin | Student management | ✅ | 90 | `/users/create`, `/users/:id`, deactivate/reactivate, roll-number uniqueness all tested | — |
| Admin | Teacher management | ✅ | 90 | same endpoints; `assignedSections` stored on user | — |
| Admin | Parent management | ✅ | 85 | creation + approval work; parent list via `/users/by-role` | — |
| Admin | Parent–child linking (admin) | ✅ | 90 | `/users/link-child` + unlink, contract-tested | — |
| Admin | Parent approval (link requests) | 🐞 | 70 | Backend + UI complete and tested locally, **prod table missing → 500** | Apply `20261110120000_parent_link_requests` to Neon |
| Admin | Account approval (pending users) | ✅ | 90 | `/users/pending`, approve/reject, notification created | — |
| Admin | Class & section management | ✅ | 90 | sections ↔ subject offerings kept in sync in transactions | — |
| Admin | Subject management | ✅ | 85 | subject = a `Class` offering row; no standalone subject catalogue | Acceptable; document the model |
| Admin | Timetable management | ✅ | 85 | CRUD + collision detection (teacher/class overlap) | — |
| Admin | Attendance management | ✅ | 85 | academy-wide read, filters, future-date guard | — |
| Admin | Fee management (ledger, mark paid, proofs) | ✅ | 85 | ledger stats, overdue derivation, payment-proof review | — |
| Admin | Fee challan generation | 🟡 | 75 | Flutter generates challans **one POST per student** (`/fees/challans`) instead of the bulk, duplicate-safe `/fees/challans/generate` | Switch UI to the bulk endpoint (atomic, skips existing periods) |
| Admin | Challan printing / download / share | ✅ | 85 | `ChallanPdfService` (status, month, bank, QR, logo); print via `printing` on web + Android | Add a widget/unit test |
| Admin | Bank QR code on challans | ✅ | 85 | QR + bank/IBAN block rendered when payment settings are enabled | — |
| Admin | Reports & Excel exports | ✅ | 85 | 3 xlsx endpoints (attendance/results/fees), contract-tested; UI in `reports_screen` | Prod run UNVERIFIED (no admin credentials) |
| Admin | Course materials management | ✅ | 85 | resources + private file storage (Vercel Blob), strict type sniffing | — |
| Admin | Academy info + map | ✅ | 85 | **OpenStreetMap/flutter_map + Nominatim**, not Google Maps | Rename in docs ("Google Maps" is inaccurate) |
| Admin | Academy branding (logo/identity) | 🐞 | 60 | New, uncommitted; **compile error** `academy_branding_screen.dart:90`; prod returns 404 (not deployed) | Fix `contentAsBase64`, commit, migrate, deploy |
| Admin | User management screen | ✅ | 85 | create/edit/reset password/deactivate | — |
| Admin | Settings & permissions | 🟡 | 70 | Role matrix is fixed in code (no admin-configurable permissions); payment settings + academic structure editable | Acceptable for FYP; document |
| Admin | AI insights / ML dashboard | 🟡 | 55 | Screens honest about model state; **in prod shows "ML service not available"**; new analytics screen uncommitted | Wire env vars; merge analytics work |

### Teacher Portal

| Module | Feature | Status | Completion % | Problem | Required Action |
|---|---|---|---|---|---|
| Teacher | Dashboard | ✅ | 85 | — | — |
| Teacher | Assigned classes & subjects | ✅ | 90 | `primaryTeacherId` scoping on every teacher query | — |
| Teacher | Student lists | ✅ | 90 | roster from `/classes` | — |
| Teacher | Attendance marking | ✅ | 90 | upsert per day, enrollment + ownership checks, verified live read | — |
| Teacher | Attendance history | ✅ | 85 | `/attendance/class?classId&logDate` + `/attendance` filters | — |
| Teacher | Quiz / test management | ✅ | 85 | CRUD, answer key hidden from students, exam-paper layout in `paperMeta` | — |
| Teacher | Test (exam paper) generation | ✅ | 85 | Offline curriculum bank + optional LLM (`/quizzes/ai-generate` → 501 when no key) | Optional: configure `AI_API_KEY` |
| Teacher | Student performance / marks | ✅ | 85 | mark entry, bulk upload, per-quiz/class/student views, grades | — |
| Teacher | Course materials | ✅ | 85 | share + upload files to own classes | — |
| Teacher | Assignments & grading | ✅ | 85 | create, student submit before deadline, grade with max-marks check | — |
| Teacher | Reports | ✅ | 80 | attendance/results xlsx for own classes | — |

### Student Portal

| Module | Feature | Status | Completion % | Problem | Required Action |
|---|---|---|---|---|---|
| Student | Dashboard | ✅ | 85 | — | — |
| Student | Attendance records | ✅ | 90 | live-verified (200, records returned) | — |
| Student | Fee information | ✅ | 90 | live-verified; payment settings + proof upload | — |
| Student | Challans (view/PDF) | ✅ | 85 | shared `ChallanActions` | — |
| Student | Quiz & tests (attempt online) | ❌ | 10 | `TakeQuizScreen` is a static "Physical Test Module" notice; no submission endpoint/table | Decide: keep paper-based (document it) or implement online attempts (`quiz_submissions`, grading) |
| Student | Results & performance | ✅ | 85 | marks + progress chart | — |
| Student | Course materials / assignments | ✅ | 85 | enrolled-class scoping verified in tests | — |
| Student | AI learning (summariser, OCR) | ✅ | 80 | TextRank summariser offline; OCR ML Kit (mobile) / Tesseract.js (web) | Web OCR loads from a CDN (needs internet); note in docs |

### Parent Portal

| Module | Feature | Status | Completion % | Problem | Required Action |
|---|---|---|---|---|---|
| Parent | Registration & login | ✅ | 90 | pending → admin approval → login; lockout; live-verified | — |
| Parent | Child linking (request) | 🐞 | 65 | UI + API done, tested locally; **500 in prod** (missing table) | Apply migration |
| Parent | Child approval by admin | 🐞 | 65 | same root cause | same |
| Parent | Multiple children | ✅ | 90 | live parent has 3 linked children, each readable | — |
| Parent | Child attendance | ✅ | 90 | live-verified 200 | — |
| Parent | Fee records / challans | ✅ | 90 | live-verified 200; proof submission allowed for linked child | — |
| Parent | Academic performance | ✅ | 85 | `/quizzes/marks/student/:id` scoped via `canReadStudent` | — |
| Parent | Notifications & updates | ✅ | 80 | in-app notifications + announcement fan-out; **no push/e-mail** | Document as in-app only |
| Parent | Data isolation | 🐞 | 70 | linked-child checks are correct, **but `/users/directory` leaks all students** | Restrict directory for PARENT |

### AI / ML

| Module | Feature | Status | Completion % | Problem | Required Action |
|---|---|---|---|---|---|
| AI | Notes summarisation | ✅ | 85 | on-device TextRank (unsupervised) | Already labelled "OFFLINE AI"; keep |
| AI | Test/question generation | ✅ | 85 | offline bank + optional LLM via Vercel AI Gateway | — |
| AI | OCR / document scanning | ✅ | 85 | ML Kit (Android), Tesseract.js (web, Urdu web-only), saved via `/ocr` | — |
| AI | AI paper grader | 🟡 | 70 | TF-IDF keyword similarity, teacher confirms marks | Document as an assistive heuristic |
| ML | Student performance prediction | 🟡 | 55 | FastAPI model + batch scoring + holdout check implemented; **no evidence of a trained production model; backend wiring absent in prod** | Set env vars, train on seeded data, confirm `PRODUCTION` status |
| ML | Fee-payment risk prediction | 🟡 | 55 | same | same |
| ML | Training / retraining / rollback | ✅ | 80 | eligibility gates, HF persistence, rollback endpoint; 55 tests | GitHub cron needs secrets |
| ML | ML API integration (backend client) | 🟠 | 60 | client with retries/timeouts, admin-only routes, 3 req/min limiter | Prod config missing (UNVERIFIED today) |
| ML | ML dashboard & error handling | 🟡 | 65 | honest empty states; new analytics screen uncommitted; limiter also throttles predictions | Merge; exempt `predict/*` from the training limiter |

---

## 3. Critical Bugs

| # | Bug | Affected files | Root cause | User impact | Recommended solution | Priority |
|---|---|---|---|---|---|---|
| B1 | **App does not compile** (`The method 'contentAsBase64' isn't defined for the type 'Uri'`) | `lib/features/admin/screens/academy_branding_screen.dart:90` | `Uri.dataFromBytes(...)` returns `Uri`; `contentAsBase64` does not exist on it | `flutter build web/apk` fail; 3 test files fail to load; nothing from this tree can ship | Use `base64Encode(_newLogo!)` from `dart:convert` (or `Uri.dataFromBytes(bytes).data!.contentAsBase64`) | **Critical** |
| B2 | **Parent link-request flow returns 500 in production** | `taleemplus_backend/prisma/migrations/20261110120000_parent_link_requests`, `userController.js` (`createLinkRequest`/`getMyLinkRequests`/`listLinkRequests`) | Migration committed but never run on Neon; live web bundle already ships the screens | Parents cannot request a link; admin "Parent Approval" screen errors | `npx prisma migrate deploy` with the unpooled URL (additive only), then re-test `GET /users/link-requests/mine` → 200 | **Critical** |
| B3 | **Session never recovers after access-token expiry** | `taleemplus_backend/src/middleware/authMiddleware.js` (returns 403 when `jwt.verify` throws), `lib/data/remote/api_client.dart` (`mayRefresh` only on 401) | Status-code contract mismatch between server and client | After 15 min every request fails with "Token expired or invalid."; web users who return to the app are stuck until a manual logout | Return **401** with code `TOKEN_EXPIRED` for invalid/expired tokens (keep 403 for inactive accounts) **and** make the client refresh on 401 (or on 403 + `UNAUTHENTICATED`); refresh proactively on app resume | **Critical** |
| B4 | **Parent can enumerate all students** | `src/routes/userRoutes.js` (`/directory` allows PARENT), `src/controllers/userController.js#getDirectory` (no parent scoping) | Directory endpoint never got the scoping applied to `/by-role` and `/search` | PII of every student (email, phone, roll no.) exposed to any parent account — verified live (53 rows) | Scope `getDirectory` for PARENT to staff + linked children (reuse the `getUsersByRole` filter) or remove PARENT from the route; add a contract test | **High** |
| B5 | **CI pipelines failing; release workflow cannot ship** | `.github/workflows/{flutter-ci,android-ci,main}.yml`; 13 unformatted files (`dart format` gate); `test/responsive_layout_test.dart:423` (parent AllChallans `RenderFlex` overflow) | Code pushed without running the format gate; overflow in the challan row at a narrow viewport | Every push/tag is red; no CI artifacts; v1.1.2 was hand-built | Run `dart format lib test integration_test`; fix the overflow (wrap/flex the challan row); re-run CI | **High** |
| B6 | **ML features inert in production** | Vercel env (backend project): `ML_SERVICE_URL`, `ML_INTERNAL_TOKEN`; GitHub secrets for `ml-monitor.yml` | Config never set (ML monitor logs: "ML_SERVICE_URL repository secret is not set", every run since 2026-11-10) | Admin AI screens show "ML service not available"; no scheduled training | Set both vars on the backend project (token identical on the ML project), redeploy; add the two GitHub secrets | **High** |
| B7 | **Route-contract check fails on a false positive** | `taleemplus_backend/scripts/check-client-routes.js`, `lib/data/remote/ml_analytics_service.dart:506` | Checker treats `'/admin/ml/analytics$suffix'` literally | Backend CI will go red once the analytics service is committed | Strip `$name` interpolations in the checker (it already handles `${…}`), or build the URL from a constant path | Medium |
| B8 | **Backend accepts impossible dates in analytics filters** (`from=2026-13-01` → 200) | `src/controllers/mlController.js` (`DATE` regex); failing test `tests/mlAnalytics.contract.test.js:141` | Regex-only validation | Wrong/empty analytics instead of 400 | Reuse `isValidDateOnly` from `utils/validation.js` | Medium |
| B9 | **Rate limiter is per-instance and IP-blind behind Vercel's proxy** | `src/middleware/rateLimit.js`, `app.js` (no `trust proxy`) | `req.ip` is the proxy for every client; limiter state lives in function memory | Possible shared 429s on `/auth/academy-lookup` and `/academy/branding/public` (10 hits / 15 min per warm instance for *all* users); little real brute-force protection (DB lockout compensates) | `app.set('trust proxy', 1)`; key by forwarded IP; consider a DB/Upstash-backed limiter | Medium (UNVERIFIED on prod – not load-tested to avoid locking out users) |
| B10 | **Any teacher can edit/delete any announcement and answer any query** | `notificationController.js#updateAnnouncement/deleteAnnouncement`, `resourceController.js#answerQuery` | Role check only, no ownership/class check | A teacher can delete admin announcements | Restrict to creator or ADMIN; restrict query answers to the class's teacher | Medium |
| B11 | **ML prediction endpoints throttled by the training limiter** | `src/routes/mlRoutes.js` (`limitTraining` on `predict/*`) | Same limiter applied to reads | Dashboard refreshes can 429 after 3 calls/minute | Apply the limiter only to `train/*`, `retrain`, `rollback` | Low |
| B12 | **Stale metadata / docs** | `app.js` `/api/v2/version` (`app_version: 1.0.1`, `release_date 2026-11-09`); `API_DOCUMENTATION.md`, `API_V2.md`, `DATABASE_SCHEMA.md` (no mention of link-requests, branding, ML analytics) | Not updated with releases | Misleading to examiners/ops | Read version from `package.json`; update docs | Low |
| B13 | **Duplicate ML code drifting** | `ml_service/hf_space/build/app/{config,main}.py` differ from `ml_service/app/` | Hand-copied Hugging Face Space build | Risk of deploying old logic | Generate the Space from `app/` in CI or delete the copy | Low |

---

## 4. Pending Development

**Completely missing**
- Online quiz attempt + auto-grading (student side): no screen logic, no `quiz_submissions`/`quiz_answers` tables, no endpoint. (If tests stay paper-based, remove the "take quiz" entry point and state it explicitly in the docs.)
- Offline-first synchronisation: `pubspec.yaml` and `RELEASE_NOTES.md` describe the app as offline-first, but only a legacy SQLite `members` table (`db_helper.dart`, `member_repository.dart`) remains; there is no queue or sync. Either implement a minimal offline read cache or remove the claim.
- Push/e-mail notifications (in-app only).
- Production-signed Android release (no keystore anywhere; CI falls back to debug signing).

**Partially implemented**
- Academy branding (new): backend + migration + tests exist; Flutter screen has a compile error; not committed, not migrated, not deployed.
- ML analytics dashboard (new): backend controller + service + tests and a 1,248-line Flutter screen exist; uncommitted; one contract test fails (B8); route checker false positive (B7).
- Challan bulk generation: backend bulk endpoint exists; UI still loops per student.
- Revenue "forecast" on the AI screen is a labelled 85 % heuristic (honest, but not ML).

**Requires backend integration**
- Nothing in the client calls a missing route except the `$suffix` false positive; the gaps are configuration (ML env vars, AI key) rather than code.

**Requires frontend integration**
- Challan generation → `/fees/challans/generate`.
- Client handling of 401/403 + `code` fields (B3); surface `ACCOUNT_LOCKED` (423) consistently.

**Requires database changes**
- Apply the two pending migrations to production (no new schema needed).
- If online quizzes are built: `quiz_submissions`, `quiz_answers` (+ indexes, cascade on quiz).

**Requires testing**
- Flutter: widget tests for challan PDF, branding screen, ML analytics screen, and the token-refresh path in `ApiClient` (mock 401/403).
- Backend: directory scoping for parents; announcement ownership; date validation; `trust proxy` + limiter behaviour.
- End-to-end run of the 17 journeys on a staging academy (see §7).

---

## 5. Security Audit (no secret values reproduced)

**Strengths observed**
- JWT access (15 m) + rotating refresh tokens (7 d) stored **hashed**; random `jti`; refresh re-derives role/academy from DB; logout/reset/deactivate revoke tokens.
- bcrypt (cost 10–12), password policy, account lockout after 5 failures (DB-backed, so it works on serverless).
- Every query filtered by `req.academyId`; tenant isolation is contract-tested across academies; parent/student access funnels through `canReadStudent`; file downloads return 404 (not 403) to prevent probing; uploads are type-sniffed, size-capped, stored privately (Vercel Blob) and served only through authenticated routes.
- `helmet`, pinned CORS allow-list in production, JSON body limit, zod validation on auth/attendance/resources/assignments, sanitised error logging (no query args), production hides stack traces.
- Env validation refuses weak/example secrets in production; `.env*`, the credentials CSV, backups and `.pgdata` are git-ignored **now**.

**Issues and fixes**

| # | Issue | Severity | Fix |
|---|---|---|---|
| S1 | Parent can read the full student directory (B4) | High | Scope or remove PARENT on `/users/directory` |
| S2 | Expired token → 403 (B3) also conflates "not authenticated" with "forbidden" | High (availability) | 401 + `TOKEN_EXPIRED`; client refresh |
| S3 | **Git history contains**: a Firebase web API key (`lib/firebase_options.dart`, later removed), a committed `taleemplus_backend/.env` (localhost DB + dev JWT secrets, removed in `921ea16`), and the **entire local PostgreSQL data directory** (`taleemplus_backend/.pgdata`, 1,367 blobs, now ignored). The current Neon/JWT secrets were **not** found in history. | Medium | Rotate/restrict the Firebase key in Google Cloud (if that project still exists); rotate `JWT_SECRET`/`REFRESH_TOKEN_SECRET` if they ever matched the committed dev values; purge `.pgdata` from history (`git filter-repo`) before the final hand-in, as it may hold local test data |
| S4 | Rate limiter per instance, no `trust proxy` (B9) | Medium | `trust proxy`, forwarded-IP key, shared store |
| S5 | Teacher-wide announcement edit/delete and query answering (B10) | Medium | Ownership checks |
| S6 | No `Content-Security-Policy` on the web app; Tesseract.js is loaded from a CDN at runtime | Low | Add CSP in `netlify.toml` allowing that CDN, or self-host the worker |
| S7 | `morgan('dev')` logs every path including query strings (e.g. `?email=` on `/auth/security-question`) in production | Low | Use `combined`/`tiny` and skip sensitive query params |
| S8 | Database access: a single owner role for the app; ML service has its own read-only role (`taleemplus_ml_reader`, good). No row-level security; tenant isolation is enforced in application code only. | Info | Acceptable for this architecture; keep the contract tests as the guard; consider a least-privilege app role (no DDL) |
| S9 | Demo credentials with a shared password live in a git-ignored CSV and `DEMO_LOGIN_CREDENTIALS.md` in the repo folder | Info | Keep out of any submission archive; rotate after the viva |
| S10 | Android: `INTERNET` permission present; cleartext only when `API_BASE_URL` is `http://`; release builds throw if `API_BASE_URL` is missing (good fail-fast) | Info | Keep the dart-define in every release command |

---

## 6. Deployment Status

| Target | State | Evidence | Gaps |
|---|---|---|---|
| **Flutter Web (Netlify, `taleemplus-111.netlify.app`)** | 🟢 Live, serves the v1.1.2-era bundle; proxies `/api/*` to Vercel (same-origin, no CORS) | HTTP 200 root; `/api/v2/version` 200 through the proxy; bundle contains `link-requests` screens but not branding/analytics | Deploys are manual (`netlify deploy`); `_redirects`/`_headers` recreated by hand after each build; current source does not build (B1) |
| **Android APK** | 🟡 Published (`v1.1.2`: universal + 3 ABI splits, SHA256SUMS) | `gh release view v1.1.2` | **Debug-signed** (no keystore); CI builds fail (B5); any APK built without `--dart-define=API_BASE_URL=https://taleemplus.vercel.app/api/v2` throws on every call (by design); `base.archivesName` still `Final_Year_Project-version-1` |
| **Backend (Vercel `taleemplus`)** | 🟢 Live, DB connected | `/health` 200 `database:connected` (4.5 s cold start); `/api/v2/version` 200; auth 401/403 paths behave as coded | Running `main` (branding/analytics routes → 404); `vercel.yml` skips because the `VERCEL_TOKEN` secret is absent; `/version` metadata stale; ML env vars absent (last known) |
| **Database (Neon)** | 🟡 Reachable, 11/13 migrations applied | live 500 on link requests; earlier `migrate status` | Apply 2 migrations; add a least-privilege app role; keep `backups/` out of the repo folder |
| **ML service (Vercel Python, `final-year-project-flax-two`)** | 🟢 Live, DB connected, token-protected | `/health` 200 (10.9 s cold start); `/docs` 200; 55 tests | Backend not pointed at it; GitHub cron has no secrets (fails every run); trained-model state UNVERIFIED (needs the internal token); Docker/Render/HF paths duplicated and drifting |
| **CI/CD** | 🔴 Red | last 15 runs: all Flutter/Android/release jobs failed, ML monitor failed ×8; Backend CI + ML tests green | Fix B5; add secrets (`VERCEL_TOKEN`, `KEYSTORE_*`, `ML_SERVICE_URL`, `ML_INTERNAL_TOKEN`); `check:routes` false positive (B7) |

---

## 7. Testing & Verification Results

### Automated checks run in this audit

| Check | Result |
|---|---|
| `flutter analyze` | **1 error**, 1 warning, 13 infos (error = B1) |
| `flutter test` | 58 passed; **3 test files failed to compile** (`location_payment_ui_test`, `parent_portal_test`, `responsive_layout_test`) because of B1. At tag `v1.1.2` in CI: 122 passed, 1 failed (AllChallans overflow) |
| `flutter build web --release` | **Failed** (B1) |
| `dart format --set-exit-if-changed lib test integration_test` | **Fails** (13 files would change) – this is the CI gate that is red |
| `prisma validate` | OK |
| `prisma migrate deploy` → local PostgreSQL 18 | 13 migrations applied cleanly |
| `prisma migrate diff --from-url … --to-schema-datamodel` | **No difference** (migrations ≡ schema) |
| Backend Jest (local PG) | **153 passed, 1 failed** (B8) across 23 suites |
| `npm run check:routes` | 111 client calls checked, 1 "missing" (false positive, B7) |
| ML `pytest` | **55 passed** |
| Android release build | Not run (would fail at B1; the last successful hand-build on 2026-11-10 is debug-signed) |

### User-journey verification

Production was probed **read-only** with the seeded demo teacher, student and parent accounts. No admin account for the live academy was available to me, so admin write journeys are marked as covered by local contract tests only.

| # | Journey | Verified how | Result |
|---|---|---|---|
| 1 | Admin creates a student | Jest `repair.contract` ("persists roll numbers…", "updates another user profile…") | ✅ local |
| 2 | Admin creates a parent | Jest (`createUserByAdmin` role matrix) | ✅ local |
| 3 | Admin links student ↔ parent | Jest "links and unlinks children; parents only see their own children" | ✅ local |
| 4 | Parent requests a link | Jest `parentLinkRequest.contract` ✅ local; **prod `GET /users/link-requests/mine` → 500** | ❌ prod (B2) |
| 5 | Admin approves the request | Jest "parent submits, admin sees the match and approves → link is created" | ✅ local / ❌ prod (B2) |
| 6 | Parent views linked child | Prod: parent login → 3 children; `/users/<child>`, attendance, challans, marks all 200 | ✅ prod |
| 7 | Teacher marks attendance | Jest "prevents a teacher from marking a class they do not teach" + round-trip test; prod teacher read 200 | ✅ local (write not exercised on prod) |
| 8 | Student & parent view attendance | Prod 200 with records for both roles | ✅ prod |
| 9 | Admin generates a fee challan | Jest "creates challans…", "bulk-generates challans for a class…" | ✅ local |
| 10 | Admin prints/distributes challan | Code review of `ChallanPdfService` + `printing`; no automated test | ❔ needs a manual run |
| 11 | Student/parent view fee details | Prod 200 (1 challan each), payment settings 200 | ✅ prod |
| 12 | Teacher creates a test | Jest "creates and lists a quiz with full metadata…" | ✅ local |
| 13 | Student attempts the test | Placeholder screen | ❌ not implemented |
| 14 | Results generated correctly | Jest "updates questions, saves marks, reads them every way…" (percentage/grade computed server-side) | ✅ local |
| 15 | Admin exports Excel | Jest `reports.contract` (3 workbooks, role checks) | ✅ local / ❔ prod |
| 16 | Course materials upload & access | Jest `files.contract` (15 cases incl. exact-bytes download by student/parent) | ✅ local / ❔ prod upload |
| 17 | AI/ML returns valid responses | ML `/health` 200 + 55 tests; on-device generators unit-tested (`exam_paper_generator_test`, `core_logic_test`); backend→ML in prod | 🟡 service OK; integration ❔/❌ (B6) |

---

## 8. Final Completion Estimate

**Honest overall: ~74 %.** The architecture and most features are genuinely implemented and tested; what is missing is mostly *finishing work* (one compile error, two migrations, one auth status code, one authorization scope, CI hygiene, configuration) plus two product decisions (online quiz attempts, offline mode).

**To reach 80 %** (1–2 days): fix B1, run the two migrations on Neon, fix B3 (401 + client refresh), fix B4, format the tree and fix the overflow so CI is green, commit the branding/analytics work, redeploy backend + web, update `/version`.

**To reach 90 %** (about 1 week): set ML env vars + GitHub secrets and confirm a trained `PRODUCTION` model on the seeded academy; fix B7–B11; switch challan generation to the bulk endpoint; add the missing Flutter tests (token refresh, challan PDF, branding, analytics); generate a release keystore and store it as CI secrets so `main.yml` produces signed APK/AAB; update API/DB docs; run all 17 journeys on a staging academy and record the results.

**To reach 100 %** (per the definition in the brief): decide and close the online-quiz gap (implement or formally scope out), remove or implement the offline-first claim, add CSP / `trust proxy` / shared rate limiting, purge and rotate the historical secrets, add an end-to-end smoke suite that runs against a preview deployment on every PR, and re-verify every journey on production with a dedicated test academy.

---

## 9. Development Roadmap

| Phase | Task | Priority | Dependencies | Expected Result |
|---|---|---|---|---|
| **1 – Critical bugs** | Fix `contentAsBase64` compile error (B1) | Critical | — | `flutter analyze` 0 errors; web/APK build |
| 1 | Apply `parent_link_requests` + `academy_branding` migrations to Neon (B2) | Critical | user approval (prod DB) | `/users/link-requests/mine` → 200 |
| 1 | Return 401 for expired/invalid JWT; client refresh on 401 (and tolerate 403 + `UNAUTHENTICATED`); refresh on resume (B3) | Critical | — | Sessions survive >15 min; returning web users not stuck |
| 1 | Scope `/users/directory` for PARENT (B4) + contract test | High | — | No student PII leak |
| 1 | `dart format` all files; fix AllChallans overflow; make CI green (B5) | High | B1 | Green checks on PR #4 |
| **2 – Core functionality** | Commit & deploy branding + ML analytics work; update `/api/v2/version` | High | Phase 1 | Prod has every route the client calls |
| 2 | Challan generation via bulk endpoint | Medium | — | Atomic, duplicate-safe generation |
| 2 | Announcement/query ownership checks (B10) | Medium | — | Teachers edit only their own |
| 2 | Decide quiz-attempt scope; implement or remove the entry point | Medium | product decision | No dead "take quiz" screen |
| 2 | Decide offline scope; remove the claim or add a read cache | Low | product decision | Docs match behaviour |
| **3 – AI/ML integration** | Set `ML_SERVICE_URL`/`ML_INTERNAL_TOKEN` on backend; GitHub secrets for the cron (B6) | High | user (Vercel/GitHub access) | AI screens show real model status |
| 3 | Train fee-risk + performance on the seeded academy; confirm `PRODUCTION`; check metrics | High | above | Predictions visible in analytics |
| 3 | Fix date validation (B8), route checker (B7), limiter scope (B11) | Medium | — | Backend CI green with analytics |
| 3 | Remove/regenerate `hf_space/build` copy (B13); optional `AI_API_KEY` | Low | — | Single ML code path |
| **4 – UI/UX** | Resolve analyzer warnings/infos (`use_build_context_synchronously`, deprecated `value`) | Low | — | Clean analyzer |
| 4 | Verify responsive layouts on phone/tablet/desktop for new screens (branding, analytics) | Medium | Phase 2 | No overflows in tests |
| **5 – Security & optimisation** | `trust proxy` + forwarded-IP rate limiting (B9); CSP header; quieter prod logging | Medium | — | Predictable throttling; hardened web |
| 5 | Rotate Firebase key / dev JWT secrets; purge `.pgdata` from history | Medium | user decision | Clean history before hand-in |
| 5 | Pagination on large list endpoints; summary stats endpoint | Low | — | Faster dashboards at scale |
| **6 – Testing** | Flutter tests: ApiClient refresh, ChallanPdf, branding, analytics; backend tests for B4/B10 | High | Phases 1–3 | Regression guard |
| 6 | Staging academy + scripted 17-journey smoke run (extend `scripts/smoke-e2e.js`) | High | Phase 2 | Recorded pass evidence |
| **7 – Deployment & final verification** | Release keystore as CI secrets; `VERCEL_TOKEN` secret; tag-driven signed release | High | user (secrets) | `main.yml` produces signed APK/AAB/Web ZIP |
| 7 | Automate the Netlify deploy (git-connected or CI step) with `_redirects`/`_headers` kept in `web/` | Medium | — | Reproducible web deploys |
| 7 | Update README/API/DB/user guides; final prod verification of all journeys | High | all above | Documentation matches the shipped system |

---

*End of report. Awaiting approval before any implementation work begins.*
