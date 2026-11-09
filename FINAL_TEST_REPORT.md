# Final test report (2026-11-09)

All automated tests run against an **isolated local PostgreSQL 18** database
or recorded API responses. Neither Neon database was used.

## Summary

| Suite | Command | Result |
|---|---|---|
| Backend (Jest + Supertest, 16 suites) | `npx jest --runInBand` with `TEST_DATABASE_URL` | **115 / 115 pass** |
| Flutter unit + widget + responsive layout | `flutter test` | **114 / 114 pass** (60 screens × 12 viewport/theme configs inside) |
| Flutter static analysis | `flutter analyze` | **No issues** |
| ML service | `pytest ml_service/tests` | **18 / 18 pass** |
| Android release APK | `flutter build apk --release --dart-define=API_BASE_URL=https://taleemplus.vercel.app/api/v2` | **Builds** (≈97 MB universal APK, ~10 min). Not installed on a device. |
| Production (read-only) | `/health`, `/api/v2/version`, nested `POST /api/v2/auth/login` | 200 / 200 / 400 (validation) — routing and DB OK |

## Role workflows covered by automated tests

| Role | Covered |
|---|---|
| Admin | login, lockout, user CRUD/approval/deactivation, parent–child linking, classes/sections/enrolment, timetable clashes, fees (challans, generation, proofs, ledger), student/teacher documents, academy location, bank details + IBAN, Excel exports, ML proxy auth |
| Teacher | attendance (own classes only, duplicates → upsert, future dates rejected), quizzes and marks (range-validated), materials with files, assignments (create, brief files, review, grade ≤ max), reports |
| Student | own attendance/marks/fees only, materials of enrolled classes only, submit/replace before deadline, deadline closes submission, single-submission rule |
| Parent | multiple children, two parents isolated, no self-linking, no directory search, child documents/assignments read-only, refresh picks up new links, error + retry |

## Negative cases

| Case | Expected | Verified by |
|---|---|---|
| invalid credentials / lockout | 401 / 423 | `repair.contract.test.js` |
| no / invalid token | 401 / 403 | several suites |
| other academy's ids | 403 / 404 | `contract`, `files`, `reports`, `parentPortal` |
| unlinked child | 403 / 404 | `parentPortal.contract.test.js` |
| spoofed or disallowed file, oversized file | 415 / 413 | `files.contract.test.js` |
| duplicate attendance | single record (upsert) | `reports.contract.test.js` |
| marks above maximum / negative | 400 | assignment + quiz tests |
| storage not configured | 503 `STORAGE_UNAVAILABLE` | `files.contract.test.js` |
| geocoder down | 503 `GEOCODER_UNAVAILABLE` | `academySettings.contract.test.js` |
| ML service missing / no model / training running | 503 / 409 / 409 | `ml_service/tests`, live run |
| network error in app | error state with Retry, not empty data | `parent_portal_test.dart`, `files_ui_test.dart` |

## End-to-end runs over real HTTP (local)

- Seeded demo academy → assignment created, brief uploaded, student submission uploaded, course material and admission form uploaded, all fetched back with the correct role permissions.
- Backend ↔ ML service: synthetic academy trained in the background, promoted, 60 students scored; another academy correctly had no model; a parent got 403.

## Not verified (environment limits)

| Item | Why | How to verify |
|---|---|---|
| Physical Android device (startup time, camera OCR, GPS, file picker, share sheet) | no device connected (`adb devices` empty) | install `build/app/outputs/flutter-apk/app-release.apk`, run the four role walkthroughs, time cold start |
| Manual browser pass of Flutter web | Chrome extension not connected | `flutter run -d chrome` or the Netlify preview |
| Vercel Blob in production, HF Space | not deployed (needs approval / accounts) | follow the deployment guides, then `scripts/smoke-e2e.js` |
| WCAG AA everywhere in light mode | cyan button/tab foregrounds, green/amber status text remain below 3:1 | `CONTRAST_MIN=4.5 flutter test test/responsive_layout_test.dart` |

## Known limitations

No cursor pagination (fixed caps); in-memory rate limits per serverless instance; `zod` advisory mitigated not fixed; Android `applicationId` placeholder and no release signing; ML has no real-data model yet.
