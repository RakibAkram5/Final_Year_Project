# Responsive UI test report

## Method

`test/responsive_layout_test.dart` renders **60 real screens** of the four
portals with **recorded real API responses** (`test/fixtures/ui_api_fixtures.json`,
recorded from a locally seeded backend, including deliberately long `[TEST]`
class and student names) using the real Roboto and Material Icons fonts from
the Flutter SDK (the default test font is ~2× wider and gives false results).

Configurations (12 per screen):

| Config | Size (logical px) | Theme | Text scale |
|---|---|---|---|
| small-android | 320 × 568 | dark | 1.0 |
| android | 360 × 800 | dark | 1.0 |
| android | 390 × 844 | dark | 1.0 |
| large-android | 412 × 915 | dark | 1.0 |
| tablet portrait | 768 × 1024 | dark | 1.0 |
| tablet landscape | 1024 × 768 | dark | 1.0 |
| laptop | 1366 × 768 | dark | 1.0 |
| desktop | 1920 × 1080 | dark | 1.0 |
| large desktop | 2560 × 1440 | dark | 1.0 |
| phone landscape | 800 × 360 | dark | 1.0 |
| accessibility | 360 × 800 | **light** | **1.3** |
| accessibility | 412 × 915 | **light** | **1.3** |

A screen fails if it reports any layout error (RenderFlex overflow, unbounded
constraints, build exceptions), breaks a word mid-word (more laid-out lines
than words — the Class Management bug), truncates an app-bar title below
110 px, or (light configs) shows text below 1.5:1 contrast.

## Results

| Run | Failing screens |
|---|---|
| Original code (first run, real fonts) | 9 screens failing (Fee Ledger, Class Sections, Academic Structure, Unpaid Students, Admin/Teacher/Student dashboards, Classroom Hub, Student Challan) + framework warnings |
| Original Class Management alone | title at **10 px / 50 lines** (320), mid-word breaks (360) |
| After fixes, all 60 screens × 12 configs | **0 failures** |

Regression proof: the test was run against the original
`class_management_screen.dart` and `admin_dashboard.dart` and fails; it
passes on the fixed files.

## Reusable components introduced

| Component | Use |
|---|---|
| `ResponsiveActionTile` / `OverflowActionsButton` | list cards with actions; text keeps ≥ 168 px; overflow menu |
| `responsiveAppBarActions` / `dashboardAppBarActions` | app bars keep ≥ 150 px for the title |
| `ResponsiveTileGrid` | content-height dashboard grids, 2–4 columns by width |
| `ResponsiveRow` / `DropdownLabel` | side-by-side ≥ 480 px, stacked below; single-line dropdown labels |
| `AttachmentsSection` | file lists with the same responsive tile |

## Limits of this verification

- Web layouts (`kIsWeb` desktop shell) are not exercised by VM tests; they use the same content widgets. A manual browser pass was not possible (extension not connected).
- No physical Android device was connected; Android was verified by widget tests and a release build only.
- Contrast check uses a 1.5:1 threshold by default. At a stricter 3:1 audit, remaining light-mode items are cyan button/tab foregrounds and green/amber status text (dark mode unaffected).

Run: `flutter test test/responsive_layout_test.dart` (≈1 min). Debug output:
`LAYOUT_DEBUG=1`; stricter contrast: `CONTRAST_MIN=4.5`.
