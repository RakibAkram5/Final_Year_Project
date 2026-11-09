# Bug fix report (2026-11-08 → 11-09)

Every fix below has an automated test or a recorded reproduction. "Before" is
what the original code did.

| # | Area | Severity | Before | Root cause | Fix | Evidence |
|---|---|---|---|---|---|---|
| 1 | Class Management card | High | Class title crushed to **10 px** at 320 px (50 lines), words split at 360 px | Leading icon + 4 fixed 48 px icon buttons in one `Row` | Reusable `ResponsiveActionTile`: text keeps ≥ 168 px, extra actions move to a "⋮" menu | `responsive_layout_test.dart` fails on old file, passes now |
| 2 | Parent portal refresh | **Critical** | Pull-to-refresh made **0 API calls**; a child linked after sign-in never appeared until restart | `syncWithUser` returned early when a subscription existed | `ParentProvider.refresh()` re-fetches `/auth/me` + profiles; 2-min re-check | `parent_portal_test.dart` |
| 3 | Parent portal errors | High | Network failure shown as "No children linked yet" | errors swallowed | error card with Retry | `parent_portal_test.dart` |
| 4 | Parent self-linking | **Critical (security)** | Any parent could link to any student and read their attendance/fees/marks | `link-child` and `users/search` allowed PARENT | admin-only | `parentPortal.contract.test.js` |
| 5 | Class rosters | High (privacy) | Students/parents received all classmates' names, ids, roll numbers | `formatClass` always included full roster | roster scoped; `enrollment_count` added | `parentPortal.contract.test.js` |
| 6 | Resources authorisation | High | Any teacher could post/edit/delete in any class; students could read other classes' materials by id | only academy was checked | class-teacher / enrolment checks | `files.contract.test.js`, `contract.test.js` |
| 7 | Academy Support (parent) | High | Always "Academy profile unavailable" | looked up a **user** whose id was the academy id | uses the signed-in user's academy data | layout + location tests |
| 8 | Fee Ledger on phones | High | Layout exception | `Spacer` inside an unbounded `Column` in `WebStatCard` | fixed spacing, amounts scale down | layout suite |
| 9 | Dashboard grids | Medium | Tile text clipped at 320 px / large fonts | `childAspectRatio: 1.3` | `ResponsiveTileGrid` (rows size to content) | layout suite |
| 10 | Dashboard app bars | Medium | "Admin Portal" truncated to **18 px** | 5 action icons | collapsible actions (`dashboardAppBarActions`) | layout suite (title check) |
| 11 | Many screens | Medium | Overflows/mid-word breaks (timetable filters, tabs, challan rows, hub badges, login at 130 % font, emails) | fixed rows without `Expanded`/wrap | `ResponsiveRow`, `DropdownLabel`, `Wrap`, ellipsis for single-token emails | layout suite |
| 12 | Teacher stats | Medium | framework assertion "setState during build" | provider notified in `initState` | post-frame callback | layout suite |
| 13 | Hidden ripples | Low | Tap feedback invisible in 4 screens | `ListTile` inside coloured `Container` | transparent `Material` wrapper | layout suite |
| 14 | Light theme | Medium | White text on white (e.g. security questions **1.07:1**) and dark cards in light mode | ~540 hard-coded dark tokens | theme-aware tokens; light text ≥ 4.5:1; `accentText` | contrast check in layout suite |
| 15 | Theme preference | Low | A quick theme change could be overwritten by the saved preference loading late | async load race | `_userChoseTheme` guard | covered by light-mode tests |
| 16 | Attendance | Medium | Could be marked for future dates (2027 accepted) | no date check | 400 for dates beyond tomorrow | `reports.contract.test.js` |
| 17 | API errors | Medium | Malformed JSON / oversized body → **500** | error handler ignored body-parser status | 400 / 413 with clear messages | `files.contract.test.js` (413) |
| 18 | ML training | High | Training ran inside the HTTP request (backend timeout 10 s, Vercel 30 s) | synchronous endpoint | background job, `202 TRAINING`, client polls | `ml_service/tests/test_api.py` |
| 19 | ML status | Low | "Insufficient data" shown with 720 rows (min 100) | any untrained state labelled insufficient | `READY_TO_TRAIN` | `test_api.py` |
| 20 | Browser geolocation | Low | Blocked on Netlify | `Permissions-Policy: geolocation=()` | `geolocation=(self)` | config |
| 21 | Misleading ML code | Academic honesty | Dart "models" with synthetic weights citing a non-existent script | dead code | removed; docs clarified | `ML_DOCUMENTATION.md` |
| 22 | Android release build | Build | `package dev.flutter.plugins.integration_test does not exist` | registrant regenerated with dev plugins by a concurrent `flutter test` | rebuild without concurrent test runs (see `FINAL_TEST_REPORT.md`) | build log |
