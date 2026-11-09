# TaleemPlus — Project Progress (FYP final repair)

Last updated: 2026-11-09 · Branch: `main` · **All changes are uncommitted** (nothing committed, pushed or deployed).

## How work is being verified

| What | How | Result |
|---|---|---|
| Backend API | Jest + Supertest against an **isolated throwaway PostgreSQL 18** on `localhost:5434` (never Neon) | **114 / 114 pass** (16 suites) |
| Flutter unit/widget | `flutter test` | **117 / 117 pass** |
| Responsive layout | `test/responsive_layout_test.dart`: 60 real screens × 12 configs, driven by **recorded real API responses** | **all pass** |
| Static analysis | `flutter analyze` | **0 issues** |

Environments found (verified, values never printed):

| Env | Database host | Used by |
|---|---|---|
| Local backend `.env` | Neon dev branch | `npm start` locally |
| Vercel `.env.local` (pulled) | Neon production database (**production**) | taleemplus.vercel.app |
| Tests in this session | local PG 18 `localhost:5434/taleemplus_test` | jest, fixture recording |

Neither Neon database has been read from or written to in this session.

---

## Phase 1 — Audit (summary; full report to follow in PROJECT_AUDIT_REPORT.md)

| Module | Existing status | Problem | Severity | Fix / status |
|---|---|---|---|---|
| Class Management card | Works functionally | 4 icon buttons + icon in one `Row` → title gets **10 px at 320 px**, words split at 360 px (the screenshot bug) | High | **Fixed** with reusable `ResponsiveActionTile`; test proves old code fails, new passes |
| Dashboards (admin/teacher) | Works | Fixed `childAspectRatio: 1.3` grid → tile text clipped at 320 px / large fonts | Medium | **Fixed** with reusable `ResponsiveTileGrid` |
| Dashboard app bars (4 portals) | Works | 4–5 actions → "Admin Portal" truncated to **18 px** on 320 px | Medium | **Fixed** with `responsiveAppBarActions` (overflow menu) |
| Class Sections tile | Works | 3 trailing icons in `ListTile` | Medium | **Fixed** (same tile component) |
| Timetable filters | Works | Two dropdowns side by side → names wrapped mid-word in 89 px | Medium | **Fixed** `ResponsiveRow` + `DropdownLabel` |
| Student attendance/fee/report, classroom hub, challan preview | Works | Row overflows on small phones / 130 % font | Medium | **Fixed** |
| Teacher details tabs | Works | "ATTENDANCE" split mid-word | Low | **Fixed** (scrollable tabs on phones) |
| Login | Works | Remember-me row overflows at 130 % font | Low | **Fixed** |
| `WebStatCard` | Works on web | `Spacer` in unbounded column → layout exception on phone widths (Fee Ledger) | High | **Fixed** |
| `TeacherStatsRow` | Works | Provider notified during build (framework assertion) | Medium | **Fixed** (post-frame) |
| ExpansionTile/ListTile in coloured containers (3 screens) | Works | Tap ripples hidden (framework warning) | Low | **Fixed** |
| **Parent portal – refresh** | Broken | Pull-to-refresh made **0 API calls**; a child linked by the admin after parent sign-in never appeared until app restart | **Critical** | **Fixed** (`ParentProvider.refresh`, 2-min re-check); regression test |
| **Parent portal – errors** | Broken | A failed load displayed "No children linked yet" | High | **Fixed** (error card + Retry); test |
| **Parent self-linking (API)** | Security hole | `POST /users/link-child` and `/users/search` allowed PARENT → a parent could attach to **any** student and read their attendance, fees and marks | **Critical** | **Fixed**: admin-only; contract test |
| **Class roster leak (API)** | Privacy hole | `GET /classes` returned every classmate's id, name and roll number to students and parents | High | **Fixed**: rosters scoped; `enrollment_count` added; contract test |
| Light theme | Partial | 101 uses of dark-only `AppColors.textPrimary` → white text on light surfaces | Medium | Open (new components use theme-aware colours) |
| File uploads | **Missing** | Course materials are text/links only; no storage, no PDF viewer, no documents for students/teachers, no assignment submissions | High | Open — needs storage decision (see below) |
| Academy location / maps | **Missing** | Only a free-text address | Medium | Open — needs decision (see below) |
| Payment QR / bank details | Exists | QR stored as bytes in Postgres; admin settings screen exists | — | To verify end to end |
| Fee risk "ML" | Misleading | Dart weights trained on **synthetic** data; referenced `ml_training/train_risk_model.py` **does not exist** | High (academic honesty) | Open — Phase 10 |
| ML service (`ml_service/`) | Exists | FastAPI + scikit-learn training/prediction with safeguards; never deployed; `ML_SERVICE_URL` unset | Medium | Open — Phase 10 |
| AI grader / summarizer / OCR | Exists | TF-IDF grading, TextRank summary, ML Kit OCR — rule/statistical, **not** trained ML | Info | Must be documented accurately |
| `.pgdata` local cluster | Broken | Not a valid cluster (`db:start` fails) | Low | Open (tests use a scratch cluster) |

## Files changed so far

New:
- `lib/widgets/responsive/responsive_action_tile.dart` — `ResponsiveActionTile`, `TileAction`, `OverflowActionsButton`, `responsiveAppBarActions`
- `lib/widgets/responsive/responsive_grid.dart` — `ResponsiveTileGrid`
- `lib/widgets/responsive/responsive_row.dart` — `ResponsiveRow`, `DropdownLabel`
- `lib/widgets/dashboard_app_bar_actions.dart` — shared portal app-bar actions + theme picker
- `test/responsive_layout_test.dart`, `test/responsive_widgets_test.dart`, `test/parent_portal_test.dart`
- `test/support/fake_api.dart`, `test/fixtures/ui_api_fixtures.json` (recorded from local seeded API; tokens redacted)
- `tool/record_ui_fixtures.js` (refuses non-local APIs)
- `taleemplus_backend/tests/parentPortal.contract.test.js`

Modified:
- Flutter: `class_management_screen`, `class_sections_screen`, `academic_structure_screen`, `unpaid_students_screen`, `timetable_management_screen`, `user_management_screen`, `admin_dashboard`, `teacher_dashboard`, `student_dashboard`, `parent_dashboard`, `child_overview_screen`, `student_challan_screen`, `my_classroom_hub`, `teacher_details_screen`, `login_screen`, `ai_paper_grader_screen`, `web_cards`, `teacher_stats_row`, `parent_provider`, `class_entity`
- Backend: `src/controllers/classController.js` (roster scoping), `src/routes/userRoutes.js` (admin-only linking/search)

## Phases 6–8 (done this session)

| Feature | Backend | Flutter | Tests |
|---|---|---|---|
| Private file storage (Vercel Blob in prod, local folder in dev) | `StoredFile` table, `/files` upload (raw bytes ≤ 4 MB) / list / download / replace / delete, magic-byte type checks, per-category authorization, 404 for unauthorised ids | `FileService`, `AttachmentsSection`, `FileViewerScreen` (PDF pages + zoom, image pan/zoom, download/share) | 15 contract + 9 widget |
| Course materials with files | resources: class-teacher-only create/edit/delete (was: any teacher), students/parents only for enrolled classes, file cleanup on delete | `CourseMaterialsView` (teacher share sheet, student read-only) | ✓ |
| Student / teacher documents | `STUDENT_DOCUMENT`, `TEACHER_DOCUMENT` | admin "Documents" action, student "My Documents", parent "Documents" | ✓ |
| Assignments | `assignments`, `assignment_submissions`, deadlines, resubmission rule, grading ≤ max marks | `AssignmentsScreen` + detail for teacher / student / parent | ✓ |
| Excel exports | `/reports/attendance.xlsx`, `/results.xlsx`, `/fees.xlsx` (exceljs) | `ReportsScreen` | 4 contract (workbook contents verified) |
| Class PDFs | — | daily/range attendance PDF, class results PDF | 3 unit |
| Academy location (OSM) | lat/lng/label on academy, `/geo/search` + `/geo/reverse` proxy to Nominatim (UA, 1 req/s, cache) | editor (search, tap map, device GPS with permission handling), map card + directions for all roles | 9 contract + widget |
| Bank details | bankName, account number, IBAN (mod-97 checked), instructions | admin form, shown in parent/student payment sheet | ✓ |

Migration added: `prisma/migrations/20261109090000_files_assignments_location_bank` (additive; `down.sql` documented). **Not applied to any Neon database.**

Extra bugs fixed on the way: body-parser errors returned 500 (now 400/413); parent "Academy Support" always showed "profile unavailable" (looked up a user by academy id); Netlify header blocked browser geolocation.

## Pending (in order)

1. Phase 3/9 functional audit of attendance, timetable, exams/results flows (duplicate prevention, marks validation, grading).
2. Exam documents UI (backend category exists), teacher 'My documents' entry.
3. **Vercel Blob store must be created and connected** before uploads work in production (see VERCEL_DEPLOYMENT_GUIDE).
4. Phase 10 ML: real training script for the fee-risk model, honest data documentation, HF Space — **HF deploy needs a token**.
5. Light-theme contrast pass.
6. Phase 14 deployment checks (read-only verification of live URLs; no deploys without approval).
7. Phase 16 documentation set.

## Exact next steps to resume

```bash
# isolated test DB (scratch cluster created this session; recreate if gone)
"C:/Program Files/PostgreSQL/18/bin/initdb" -D <scratch>/pgtest -U postgres --auth=trust
"C:/Program Files/PostgreSQL/18/bin/pg_ctl" -D <scratch>/pgtest -o "-p 5434" start
createdb -h localhost -p 5434 -U postgres taleemplus_test
cd taleemplus_backend
DATABASE_URL=postgresql://postgres@localhost:5434/taleemplus_test npx prisma migrate deploy
DATABASE_URL=... TEST_DATABASE_URL=... npx jest --runInBand
cd .. && flutter test && flutter analyze
```

---

## Checkpoint 2026-11-09 (end of session — usage limit)

### Done since the previous checkpoint
- **Phase 9:** attendance future-date bug fixed (400); duplicate prevention and marks/timetable validation verified by tests/probes.
- **Phase 10 (ML):** training moved to background jobs (202 + polling); `READY_TO_TRAIN` status; Flutter polls and shows readable labels; artifacts persist to a private HF Hub repo (`ml_service/app/artifact_store.py`); HF Space package in `ml_service/hf_space/` (prepared, **not deployed**); unused synthetic Dart "models" removed; synthetic demo generator `taleemplus_backend/scripts/seed-ml-synthetic.js` (local DB only). End-to-end run through backend → ML service verified **on synthetic data only** (fee ROC-AUC 0.738; performance MAE 7.70).
- **Light theme:** ~540 dark-only colour tokens made theme-aware (dark mode unchanged); light text tokens darkened to WCAG AA; `accentText` token; theme-load race fixed; contrast check added to the layout suite.
- **Deployment:** production verified read-only (health, nested routes, zod); root `package.json` covers all backend requires; opt-in `SKIP_FLUTTER_WEB_BUILD=1`; Netlify allows same-origin geolocation.
- **Docs written:** API_DOCUMENTATION, DATABASE_SCHEMA (generated), DATABASE_MIGRATION_GUIDE, ML_DOCUMENTATION, ML_TRAINING_GUIDE, HUGGINGFACE_DEPLOYMENT_GUIDE, VERCEL_DEPLOYMENT_GUIDE, NETLIFY_DEPLOYMENT_GUIDE, ENVIRONMENT_SETUP; `.env.example` files extended.

### Latest test results
Backend **115/115** (16 suites, isolated local DB) · Flutter **114/114** + `flutter analyze` clean · ML **18/18**.

### Still to do (exact next steps)
1. Check the Android release build started at the end of the session: `build/app/outputs/flutter-apk/app-release.apk` (command: `flutter build apk --release --dart-define=API_BASE_URL=https://taleemplus.vercel.app/api/v2`). Install on a phone, time cold start, walk through the four roles.
2. Write remaining docs: README.md (rewrite — current one is outdated: Firebase/migration claims, removed Dart models), PROJECT_AUDIT_REPORT, IMPLEMENTATION_REPORT, BUG_FIX_REPORT, RESPONSIVE_UI_TEST_REPORT, SECURITY_AUDIT_REPORT, FINAL_TEST_REPORT, USER_GUIDE_ADMIN/TEACHER/STUDENT/PARENT. Source material: the tables in this file.
3. Exam-document UI (backend category `EXAM_DOCUMENT` exists); teacher "My documents" entry.
4. Known limitations to document: no cursor pagination; light-mode cyan button/tab foregrounds and green/amber status text below 3:1; `zod` advisory (mitigated by 1.5 MB body limit, fix = zod v4); Android `applicationId` is `com.example.taleem_plus`; manual browser pass not done (Chrome extension unavailable).
5. With your approval only: back up + `prisma migrate deploy` on production Neon, create/connect private Vercel Blob store, commit/push/deploy, deploy HF Space, then run `scripts/smoke-e2e.js` against production.

## Checkpoint 2026-11-09 (session resumed)

Done:
- Android release APK builds: `build/app/outputs/flutter-apk/app-release.apk` (96.5 MB, API = production URL). The earlier failure was caused by running `flutter test` during the Gradle build (it regenerated the plugin registrant with dev-only plugins). **Do not run Flutter commands while a release build is in progress.**
- Exam documents UI: teacher test card → folder icon (category `EXAM_DOCUMENT`, teacher/admin only). Teacher "My Documents" tile.
- All 20 requested documents now exist (README rewritten; audit, implementation, bug-fix, responsive-UI, security, final-test reports; four user guides).

Tests: backend 115/115 · Flutter 114/114, analyze clean · ML 18/18.

Remaining (needs you / hardware / accounts):
1. Install the APK on a phone; run the four role walkthroughs; time cold start.
2. Manual browser pass of the web app.
3. With approval: back up + migrate production DB → connect private Vercel Blob store → commit/push/deploy → deploy HF Space → smoke test.
4. Optional hardening: cursor pagination, zod v4, release signing + real `applicationId`, remaining light-mode accent/status contrast.
