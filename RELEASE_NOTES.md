# TaleemPlus v1.1.0 — Production Release

**Release date:** 2026-11-09
**Package ID:** `com.taleemplus.app` · **Production API:** `https://taleemplus.vercel.app/api/v2`

TaleemPlus is an offline-first, AI-assisted academy-management system. The **Android**
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
