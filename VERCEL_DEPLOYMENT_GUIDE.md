# Backend on Vercel

Project: `taleemplus` (`.vercel/project.json`). Production: https://taleemplus.vercel.app

## How it is wired (verified 2026-11-09, read-only)

| Check | Result |
|---|---|
| `GET /health` | 200, `database: connected` |
| `GET /api/v2/version` | 200 |
| Nested route `POST /api/v2/auth/login` with `{}` | 400 `VALIDATION_ERROR` from zod → routing to Express works and `zod` is bundled |

- `api/v2/[...path].js` and `api/v1/[...path].js` re-export the Express app;
  `vercel.json` rewrites `/api/v2/(.*)` → that function (fixes the old 404 on
  nested paths). Functions: 1024 MB, 30 s.
- Vercel installs the **root** `package.json`. Every module required by
  `taleemplus_backend/src` must be listed there; a check in this release
  confirmed none are missing (`@vercel/blob`, `exceljs` added).
- `npm run vercel-build` generates the Prisma client and (by default) builds
  Flutter web into `vercel_web/`.

## New in this release

### 1. Private Blob store (required for uploads)

Without it, upload endpoints answer `503 STORAGE_UNAVAILABLE` (nothing is ever
written to the function's temporary disk).

1. Vercel dashboard → Storage → **Create** → Blob → access **Private** → connect to project `taleemplus` (Production + Preview).
   CLI alternative: `vercel blob create-store taleemplus-files --access private`.
2. Connecting injects the credentials (`BLOB_STORE_ID` with OIDC, or `BLOB_READ_WRITE_TOKEN`). Confirm with `vercel env ls`.
3. Redeploy. Free (Hobby) quotas apply; check https://vercel.com/docs/vercel-blob/usage-and-pricing.

### 2. Environment variables

| Variable | Required | Notes |
|---|---|---|
| `DATABASE_URL` | yes | Neon pooled URL (already set) |
| `JWT_SECRET`, `REFRESH_TOKEN_SECRET` | yes | ≥ 32 random chars each; the server refuses weak secrets in production |
| `CORS_ORIGINS` | yes for browsers on other origins | e.g. the Netlify site URL (same-origin proxy needs none) |
| `ML_SERVICE_URL`, `ML_INTERNAL_TOKEN` | for AI Insights | see `HUGGINGFACE_DEPLOYMENT_GUIDE.md` |
| `STORAGE_DRIVER` | optional | leave unset (auto-detects Blob); never `local` on Vercel |
| `GEOCODER_USER_AGENT` | optional | identifying UA for OpenStreetMap Nominatim |
| `SKIP_FLUTTER_WEB_BUILD` | optional | `1` = API-only deploys (Netlify serves the web app); add `WEB_APP_URL` for the landing link |

### 3. Order of operations (needs your approval — nothing was deployed)

1. Back up and migrate the production DB (`DATABASE_MIGRATION_GUIDE.md`).
2. Create/connect the Blob store.
3. Commit, push, and deploy (the `vercel.yml` workflow runs migrations then
   `vercel build` / `vercel deploy --prebuilt --prod` and checks `/health`),
   or locally: `vercel deploy --prod`.
4. Smoke test: `node taleemplus_backend/scripts/smoke-e2e.js https://taleemplus.vercel.app/api/v2`.

### Avoiding the double Flutter build

Netlify builds the web app itself. Setting `SKIP_FLUTTER_WEB_BUILD=1` on Vercel
skips the Flutter compile (several minutes per deploy). Only do this if
nobody uses `taleemplus.vercel.app` as the app URL — it then shows a small API
landing page.
