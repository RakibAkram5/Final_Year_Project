# TaleemPlus v1.2.0 — Release notes

**Release date:** 2026-11-13 (built and verified; production rollout pending the owner's approval — see *Rollout order* below)
**Package ID:** `com.taleemplus.app` · **Version:** 1.2.0 (build 7) · **Production API:** `https://taleemplus.vercel.app/api/v2`

## What's new

### Online tests (new)
- Teachers can mark a test **Students attempt this test online** with an optional time limit and deadline. Students see it under **Online Tests**, answer with a question navigator, autosave and a countdown, and confirm before submitting.
- Multiple-choice questions are graded on the server at submission; written answers go to the teacher's **Submissions & grading** screen. The result is published as a normal test mark (visible to the student and linked parents) once every question has a score.
- One attempt per student; a retried submit after a dropped connection never duplicates or regrades; answer keys are never sent before submission.

### Parent → child link requests
- Parents request a link from the app; admins approve or reject from **Parent Approvals**. (Backend + screens shipped in 1.1.x; the production table is created by migration `20261110120000_parent_link_requests`.)

### Academy branding
- Admin **Academy Branding** screen: name, address, phone, contact e-mail and a logo (PNG/JPEG/WebP) shown on the login screen, in every portal and on challan/report PDFs.

### ML analytics dashboard
- Admin **AI Insights → Analytics**: attendance, fee and marks series from the academy's own records, with model predictions when a model is in production. Dates are validated; prediction calls are no longer throttled by the training limiter.

### Fees
- Bulk challan generation runs as **one atomic, duplicate-safe server call per section**; inactive students and students already billed for the month are skipped. Admin print/download of challans with payment status, month, bank details and QR.

### Reliability & security
- Sessions survive the 15-minute access-token lifetime: expired tokens now return 401 and the app refreshes silently (also when returning from the background).
- Parents can no longer list other students through the user directory; teachers can edit only their own announcements and answer only their own classes' questions.
- Content-Security-Policy on the web app; `trust proxy` for correct rate-limit keys; production logs without query strings; `/api/v2/version` reads the real backend version.
- Android release builds are signed with a dedicated release keystore (kept outside the repository); archive name `TaleemPlus-*.apk/.aab`.

### Offline
- The app keeps the last loaded data of every screen and shows it with an **offline banner** when the server is unreachable. Writes are online-only by design — see `KNOWN_LIMITATIONS.md`. (Earlier notes described the app as "offline-first"; that claim is withdrawn.)

## Rollout order (production)
1. `cd taleemplus_backend && DATABASE_URL=<unpooled Neon URL> npx prisma migrate deploy` — applies `20261110120000_parent_link_requests`, `20261110200000_academy_branding`, `20261113120000_quiz_online_attempts` (all additive).
2. `vercel deploy --prod` from the repository root (backend). Deploying before step 1 would break every quiz endpoint (new columns).
3. `flutter build web --release && netlify deploy --prod --dir build/web` (web).
4. Publish the signed Android APK/AAB from `build/app/outputs/` (or tag `v1.2.0` once the `KEYSTORE_*` secrets exist so CI signs them).

## Verification performed (2026-11-13)
Backend Jest 178/178 · route contract 117/117 · Flutter 133/133 (analyzer clean) · ML pytest 55/55 · HTTP smoke 41/41 journeys on a local backend + throwaway PostgreSQL · `flutter build web --release` and signed Android builds succeed.

---

# TaleemPlus v1.1.0 — Production Release

**Release date:** 2026-11-09
**Package ID:** `com.taleemplus.app` · **Production API:** `https://taleemplus.vercel.app/api/v2`

TaleemPlus is an AI-assisted academy-management system (online, with an offline read cache since 1.2.0). The **Android**
app (APK/AAB) and the **Web** app are compiled from the **same Flutter source tree** in
this release, so every feature below is available on both platforms (camera-based OCR
scanning is the one mobile-only enhancement and degrades gracefully to "paste notes" on
the web). The backend is Node/Express on Vercel; the ML service is FastAPI on Render;
data is Neon PostgreSQL.

## Highlights

### Professional AI Exam-Paper Generator
- Generates genuine Pakistani-academy examination papers: full header (academy, subject,
  class, exam type, student/roll/section lines, time allowed, chapters, total marks,
  date, signature), a **Section A MCQ table**, roman-numbered short-question groups with
  "attempt any N" rules, and a **Part II** of long questions — rendered to A4 with page
  numbers, running headers and footer.
- Produces a **separate teacher answer key** (MCQ answers + model answers / marking
  guidelines) that the student paper never exposes.
- **Live marks validation** always prints the computed total, preventing mismatched
  totals. Dynamic configuration of exam type, time, chapters, counts, marks,
  attempt-any, difficulty and language.
- Hybrid engine: offline curriculum bank (Computer Science / Mathematics / English) plus
  scanned or pasted source material, with an **optional** server LLM path that degrades
  gracefully to fully-offline when no key is configured.
- Preview, print, download paper, download answer key, and save to examination history.
- Bundled Noto Sans font for full-Unicode PDFs on both web and Android.

### Automated ML training lifecycle
- Per-academy eligibility monitoring with configurable thresholds (minimum samples,
  new-record retrain trigger, class-imbalance guard); training is never forced.
- 6-hour / daily scheduler with startup catch-up, a shared lock preventing duplicate or
  concurrent training, and basic feature-drift detection.
- New protected `POST /models/monitor` and `GET /models/dashboard` endpoints.

### Durable, safe model persistence
- Hugging Face Hub artifact store with `HF_REPO_ID`/`HF_REPO_TYPE` support,
  upload/download retries with backoff, startup integrity verification, and
  "activate-only-after-successful-upload" (a failed upload reverts the promotion and
  keeps the previous model active).

### Free ML hosting path
- Render Blueprint (`render.yaml`, native Python — no Docker) plus an eligibility-gated
  GitHub Actions monitor (`ml-monitor.yml`). The HF Hub remains the free artifact store.

### Platform & release hardening
- Android `applicationId` set to the Play-Store-valid `com.taleemplus.app`.
- Release builds refuse to silently fall back to a localhost/LAN API; the production API
  origin is injected at build time. Web auto-targets its own origin's `/api/v2`.
- CI builds the signed **APK** and **AAB**, packages the **Web ZIP**, and publishes this
  release with **SHA-256 checksums** for every asset.

## Release assets
| Asset | Purpose |
|---|---|
| `TaleemPlus-v1.1.0-Android.apk` | Universal APK — direct download & sideload install |
| `TaleemPlus-v1.1.0-Android.aab` | App Bundle — Google Play distribution |
| `TaleemPlus-v1.1.0-Web.zip` | Complete deployable static web build (`index.html` at archive root) |
| `SHA256SUMS.txt` | SHA-256 checksums for all assets |

Verify a download with `sha256sum -c SHA256SUMS.txt`.

## Build & deployment notes
- **Android:** built with `--dart-define=API_BASE_URL=https://taleemplus.vercel.app/api/v2`.
- **Web:** served from the Vercel deployment, which hosts the API at the same origin
  (`/api/v2`), so no rebuild is needed if the backend moves with the frontend.
- **ML service env:** `HF_TOKEN`, `HF_REPO_ID`, `HF_REPO_TYPE`, `DATABASE_URL`
  (read-only role), `ML_INTERNAL_TOKEN` — see `ml_service/RENDER_DEPLOYMENT_GUIDE.md`.

## Full change list
See `CHANGELOG.md` → `[1.1.0] — 2026-11-09`.
