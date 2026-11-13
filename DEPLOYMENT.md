iguration
Create a production `.env` file inside `taleemplus_backend/`:
```env
PORT=5000
NODE_ENV=production
DATABASE_URL="postgresql://db_user:secure_password@your-postgres-host:5432/taleemplus_prod?schema=public"
JWT_SECRET="your_strong_production_jwt_secret_key"
JWT_EXPIRES_IN="15m"
REFRESH_TOKEN_SECRET="your_strong_production_refresh_secret"
REFRESH_TOKEN_EXPIRES_IN="7d"
```

---

## 3. Database Migration & Initialization
Run Prisma migrations against the production database:
```bash
cd taleemplus_backend
npx prisma migrate deploy
```

---

## 4. Starting the Production Server
Using PM2 process manager for zero-downtime clustering:
```bash
npm install -g pm2
pm2 start src/server.js --name "taleemplus-api" -i max
pm2 save
pm2 startup
```

---

## 5. Rollback Strategy
If a deployment fails:
1. Revert to previous Git tag/commit.
2. If database schema was updated, run the corresponding Prisma down-migration or restore from automated daily PostgreSQL snapshot backup.

---

## 6. Production release order for the hosted stack (Vercel + Netlify + Neon) — v1.2.0

The hosted deployment does **not** use PM2; it is Vercel serverless for the API, Netlify for the web app and Neon for PostgreSQL. Release in this order, because the new backend selects columns that only exist after the migrations:

| # | Step | Command (owner, from the repository root) | Reversible? |
|---|---|---|---|
| 1 | Apply pending migrations (`parent_link_requests`, `academy_branding`, `quiz_online_attempts` — all additive, no data touched) | `cd taleemplus_backend && DATABASE_URL="<DATABASE_URL_UNPOOLED>" npx prisma migrate deploy && npx prisma migrate status` | Additive; roll back only by dropping the new tables/columns |
| 2 | Backend | `vercel deploy --prod --yes` then `curl https://taleemplus.vercel.app/api/v2/version` → `app_version 1.2.0` | Vercel instant rollback to the previous deployment |
| 3 | Backend env for ML (optional but recommended) | `vercel env add ML_SERVICE_URL production`, `vercel env add ML_INTERNAL_TOKEN production` (same token as the ML project), redeploy | yes |
| 4 | Web | `flutter build web --release && netlify deploy --prod --dir build/web` (netlify.toml + `web/_headers`/`_redirects` carry the proxy, SPA fallback, security headers and CSP) | Netlify rollback to the previous deploy |
| 5 | Android | upload `build/app/outputs/bundle/release/TaleemPlus-release.aab` / the signed APKs from `build/app/outputs/flutter-apk/` to the GitHub release (or tag `v1.2.0` after adding the `KEYSTORE_*` secrets so `main.yml` signs in CI) | — |
| 6 | Verify | `node taleemplus_backend/scripts/smoke-e2e.js https://taleemplus.vercel.app/api/v2` (creates a clearly labelled "Smoke Test Academy", never touches real academies) and a manual login per role on the web app | — |

Never deploy step 2 before step 1: the Prisma client would select `quizzes.attemptMode` etc. and every quiz endpoint would return 500.
