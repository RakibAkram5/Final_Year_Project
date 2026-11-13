# TaleemPlus — AI Academy Management System

BSCS Final Year Project. Flutter app (Android + web) for running an academy,
with four portals — **Admin, Teacher, Student, Parent** — a Node.js/Express
REST API on PostgreSQL, and a Python machine-learning service.

## Live

- **Web app:** https://taleemplus-111.netlify.app
- **Downloads:** [GitHub Releases](https://github.com/RakibAkram5/Final_Year_Project/releases) — Android APK (universal + per-ABI), AAB, and the Web build ZIP, with SHA-256 checksums (latest published: v1.1.2; v1.2.0 is built and awaiting release).

## Architecture

```
Flutter app (Android, Web on Netlify)
        │  HTTPS, JWT
        ▼
Express API (Vercel, /api/v2) ── Prisma ──▶ PostgreSQL (Neon)
        │                         └──────▶ Vercel Blob (private files)
        │  internal token
        ▼
FastAPI ML service (Vercel serverless) ── read-only SQL ──▶ PostgreSQL
```

| Part | Folder | Tech |
|---|---|---|
| App | `lib/` | Flutter 3.47, provider, http, pdf/printing, flutter_map (OpenStreetMap), file_picker, share_plus |
| API | `taleemplus_backend/` (served by `api/*.js` on Vercel) | Express 4, Prisma 5, zod, JWT + rotating refresh tokens, bcrypt, @vercel/blob, exceljs |
| ML | `ml_service/` (deployed on Vercel) | FastAPI, scikit-learn, pandas, psycopg, joblib, huggingface_hub |
| Web hosting | `netlify.toml` | Netlify, proxies `/api/*` to Vercel |

## Features

| Area | Highlights |
|---|---|
| Academy | registration with approval, academy profile, **map location (OpenStreetMap) with directions**, payment QR and **bank details (IBAN-validated)** |
| People | admin creates/approves teachers, students, parents; **parent → child linking (a parent requests, an academy admin approves)**; per-person **documents** (admission papers, CVs) |
| Classes | sections, subject classes, enrolment, timetable with clash detection |
| Teaching | attendance (one record per student/day, corrections, no future dates), **course materials with PDF/Word/image files**, **assignments with submissions, deadlines and grading**, tests and marks (validated against max marks), **online tests** (students attempt in the portal with a timer and autosave; MCQs graded automatically, written answers graded by the teacher, results published as marks), exam-paper generator with answer key, **cross-platform OCR (PDF + multi-page images, web via Tesseract.js with Urdu, Android via ML Kit)**, student questions |
| Fees | **bulk monthly challans per section (one atomic, duplicate-safe call)**, PDF vouchers with bank details and QR, admin print/download, payment-proof upload → admin verification (upload never marks a fee paid), ledger, overdue tracking |
| Reports | per-student PDFs; **class attendance and results PDFs**; **Excel exports** of attendance, results and fee records |
| Parents | all linked children, attendance, results, timetable, fees, assignments, documents, academy contact and map |
| Academy identity | **branding (name, contact e-mail, logo)** shown in every portal, on the login screen and on generated PDFs |
| AI | fee-payment-risk and performance models trained per academy, **ML analytics dashboard** on real academy data (see `ML_DOCUMENTATION.md` for what is and is not ML) |
| Offline | **read cache**: the last loaded data of every screen stays available offline with a clear banner; writes require a connection (see `KNOWN_LIMITATIONS.md`) |

## Quick start (local)

```powershell
cd taleemplus_backend; npm install; npx prisma migrate deploy; npm start   # API on :5000
cd ..; flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5000/api/v2
```

Full instructions: `ENVIRONMENT_SETUP.md`.

## Tests (2026-11-13, v1.2.0)

| Suite | Result |
|---|---|
| Backend contract/unit (Jest, throwaway PostgreSQL 18, 26 suites) | 178 / 178 |
| Backend route contract (`npm run check:routes`: every Flutter API call has a route) | 117 / 117 |
| Flutter unit + widget + responsive layout (65 screens × 12 viewport/theme configs) | 133 / 133, `flutter analyze` 0 errors / 0 warnings |
| ML service (pytest) | 55 / 55 |
| End-to-end smoke over HTTP (`taleemplus_backend/scripts/smoke-e2e.js`, all four roles, 41 journeys incl. link requests, online quiz, bulk challans, branding) | 41 / 41 |

Details: `FINAL_TEST_REPORT.md`, `RESPONSIVE_UI_TEST_REPORT.md`, `TALEEMPLUS_COMPLETE_PROJECT_AUDIT.md` (2026-11-13 audit that drove this release).

## Documentation

| Topic | File |
|---|---|
| Audit, what was built and fixed | `PROJECT_AUDIT_REPORT.md`, `IMPLEMENTATION_REPORT.md`, `BUG_FIX_REPORT.md` |
| Testing | `FINAL_TEST_REPORT.md`, `RESPONSIVE_UI_TEST_REPORT.md` |
| Security | `SECURITY_AUDIT_REPORT.md`, `SECURITY_ROTATION_PLAN.md` |
| Known limitations | `KNOWN_LIMITATIONS.md` |
| API / database | `API_DOCUMENTATION.md`, `DATABASE_SCHEMA.md`, `DATABASE_MIGRATION_GUIDE.md` |
| ML | `ML_DOCUMENTATION.md`, `ML_TRAINING_GUIDE.md`, `HUGGINGFACE_DEPLOYMENT_GUIDE.md` |
| Deployment / setup | `VERCEL_DEPLOYMENT_GUIDE.md`, `NETLIFY_DEPLOYMENT_GUIDE.md`, `ENVIRONMENT_SETUP.md` |
| User guides | `USER_GUIDE_ADMIN.md`, `USER_GUIDE_TEACHER.md`, `USER_GUIDE_STUDENT.md`, `USER_GUIDE_PARENT.md` |
| Live progress / next steps | `PROJECT_PROGRESS.md` |

Older reports in the repository root (`TALEEMPLUS_*`, `FINAL_TALEEMPLUS_VERIFICATION_REPORT.md`, `PROJECT_AUDIT.md`, …) describe earlier states and are superseded by the files above.

## Deployment status

v1.1.2 is **live**; v1.2.0 is built, tested and documented in this repository and waits for the owner to (1) apply the three pending Prisma migrations to the production database, (2) redeploy the backend, (3) deploy the web build — in that order (see `DEPLOYMENT.md`).

| Component | Where |
|---|---|
| Web app | https://taleemplus-111.netlify.app (Netlify, proxies `/api/*` to the Vercel backend) |
| Backend API | `https://taleemplus.vercel.app/api/v2` (Vercel, Neon PostgreSQL) |
| ML service | FastAPI on Vercel serverless (`/health` public, all other endpoints require the internal token) |
| Android / Web builds | [GitHub Release v1.1.1](https://github.com/RakibAkram5/Final_Year_Project/releases/tag/v1.1.1) |

To finish ML in the admin UI, set `ML_SERVICE_URL` + `ML_INTERNAL_TOKEN` on the
backend project and redeploy. See `VERCEL_DEPLOYMENT_GUIDE.md`.
