# Project audit report

Audit date: 2026-11-08/09. Baseline at commit `b47ac5d`. Classification:
Critical / High / Medium / Low. "Status" is the state after this session.

## Baseline

| Check | Baseline result |
|---|---|
| Backend tests (isolated DB) | 81 / 81 pass |
| Flutter tests / analyze | 31 pass / 0 issues |
| Production `/health`, nested `/api/v2/auth/login` | OK (earlier Vercel fixes hold) |
| Databases | separate Neon dev and production databases; repo `.pgdata` is not a valid cluster |

## Module audit

| Module | Existing status | Problems | Severity | Required fix | Status / verification |
|---|---|---|---|---|---|
| Class Management UI | works | title squeezed to 10 px, mid-word breaks | High | responsive tile + overflow menu | Fixed — layout suite |
| Global responsive UI | works on large phones | overflows, mid-word breaks, truncated app-bar titles, fixed-ratio grids, hidden ripples on 9+ screens | High | reusable responsive widgets | Fixed — 60 screens × 12 configs |
| Light theme | partial | dark-only tokens: white-on-white text, dark cards | Medium | theme-aware tokens, AA text colours | Fixed (residual cyan buttons/status colours documented) |
| Parent portal | broken in practice | refresh no-op; errors shown as "no children"; academy support always "unavailable" | Critical | provider refresh, error state, correct data source | Fixed — widget + contract tests |
| Parent–child linking (API) | insecure | parents could self-link to any student | Critical | admin-only | Fixed |
| Class roster privacy | leaking | classmates exposed | High | scope roster | Fixed |
| Course materials | text/links only | no files; teachers could edit other classes; students could read other classes | High | file storage + authz | Implemented + fixed |
| Student/teacher documents | missing | — | High | private documents | Implemented |
| Assignments | missing | — | High | create, submit, deadline, grade | Implemented |
| Exams & results | exists | no Excel export; no class PDF; exam documents UI missing | Medium | exports, PDFs | Exports/PDFs done; exam-document UI pending (backend ready) |
| Attendance | exists | future dates accepted | Medium | date check | Fixed |
| Timetable | exists | clash detection already correct | — | — | Verified |
| Fees & payments | exists | no structured bank details; proof never auto-pays (correct) | Medium | bank fields + IBAN validation | Implemented |
| Academy location | missing | text address only | Medium | map, search, directions | Implemented (OpenStreetMap, free) |
| File storage | missing | — | High | private persistent storage | Vercel Blob driver + local driver |
| ML service | implemented, never trained | synchronous training; misleading status; ephemeral artifacts on HF | High | background jobs, status, Hub persistence | Fixed; deployed? **No** (prepared) |
| On-device "ML" | misleading | synthetic weights, missing script, unused | High (honesty) | remove | Removed |
| Error handling | mostly good | body-parser errors → 500 | Medium | map 400/413 | Fixed |
| Deployment | working | Flutter compiled on both Netlify and Vercel; Netlify blocked geolocation | Low | opt-in API-only Vercel build; header | Done |
| Pagination | partial | fixed caps, no cursors | Low | cursor pagination | Open |
| Android build | builds | `applicationId` is `com.example.*`; no release signing; no device test | Medium | real id + signing; device run | Open |

## Data and environment facts

- The production and dev databases were **not** read or modified in this session.
- No real academy has enough dated records to train ML models; synthetic data was used only on a local test database and is labelled as such.
- Several older root-level reports contradict each other and the code; they are superseded by this report set.
