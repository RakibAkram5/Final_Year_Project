# Implementation report

What was built in this release, where the code is, and how it was verified.

## Phase 2 — Responsive UI

New: `lib/widgets/responsive/` (`responsive_action_tile.dart`, `responsive_grid.dart`, `responsive_row.dart`), `lib/widgets/dashboard_app_bar_actions.dart`.
Applied to Class Management, Class Sections, User Management, all four dashboards, Timetable, Student/Parent screens, Login.
Tests: `test/responsive_layout_test.dart`, `test/responsive_widgets_test.dart`. Details: `RESPONSIVE_UI_TEST_REPORT.md`.

## Phase 5 — Parent portal

`lib/logic/parent_provider.dart` rewritten (real refresh, error state, periodic re-check, stable child order); dashboard error card + retry; Academy Support uses the signed-in profile.
Backend: admin-only linking/search, roster scoping (`classController.js`), `enrollment_count`.
Tests: `test/parent_portal_test.dart`, `tests/parentPortal.contract.test.js` (two parents, multiple children, isolation).

## Phase 6 — Academy location (OpenStreetMap)

Schema: `academies.latitude/longitude/locationLabel`. API: `PUT /auth/academy`, `/auth/me`, `/geo/search`, `/geo/reverse` (Nominatim proxy).
Flutter: `lib/features/shared/academy_location.dart` — editor (search, tap-to-pin, device GPS with permission handling), card with map + directions for every role; Android location permissions.
Tests: `tests/academySettings.contract.test.js`, `test/location_payment_ui_test.dart`.

## Phase 7 — Files, materials, documents, assignments, reports

| Piece | Backend | Flutter |
|---|---|---|
| Storage | `services/fileStorage.js` (Blob/local), `utils/fileTypes.js`, `services/fileAccess.js`, `controllers/fileController.js` | `data/remote/file_service.dart`, `widgets/attachments_section.dart`, `features/shared/file_viewer_screen.dart` |
| Materials | `resourceController.js` (authz, attachments, cleanup) | `features/shared/course_materials_view.dart` |
| Documents | categories `STUDENT_DOCUMENT`, `TEACHER_DOCUMENT` | `features/shared/documents_screen.dart`, admin member action |
| Assignments | `assignmentController.js` | `data/remote/assignment_service.dart`, `features/shared/assignments_screen.dart` |
| Excel | `reportController.js` (exceljs) | `features/shared/reports_screen.dart` |
| Class PDFs | — | `data/remote/class_report_pdf.dart` |

Migration `20261109090000_files_assignments_location_bank` (additive, `down.sql`).
Tests: `tests/files.contract.test.js` (15), `tests/reports.contract.test.js`, `test/files_ui_test.dart`, `test/class_report_pdf_test.dart`.

## Phase 8 — Bank details and QR

`paymentController.js`: bank name, account number, IBAN (mod-97), instructions; QR (existing, Postgres `bytea`). Admin form fields; payment sheet shows selectable values.

## Phase 9 — Attendance / timetable / results

Future-date attendance rejected; duplicate prevention, corrections, marks range and timetable clashes verified.

## Phase 10 — ML

Background training jobs, `READY_TO_TRAIN`, Hub artifact persistence (`app/artifact_store.py`), HF Space package (`ml_service/hf_space/`), client polling + readable statuses, synthetic demo generator, removal of misleading Dart models. See `ML_DOCUMENTATION.md`.

## Theme / accessibility

Theme-aware colour tokens across `lib/`, AA light text colours, `accentText` token, theme-load race fix, contrast check in tests.

## Not done

Exam-document UI, cursor pagination, Android device run and signing, deployment (needs approval). See `PROJECT_PROGRESS.md`.
