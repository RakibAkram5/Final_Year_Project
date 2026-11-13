# Credential rotation & git-history clean-up plan

Status: **prepared, not executed** — every step below changes production
credentials or rewrites shared history and therefore needs the project
owner's explicit go-ahead. Nothing in this document contains a secret value.

## 1. What the 2026-11-13 audit found in git history

| Item | Where (historic) | Current risk |
|---|---|---|
| Firebase web API key | `lib/firebase_options.dart` (file deleted later) | Low: Firebase is no longer used by the app; a web API key is a project identifier, but the Google Cloud project should still be checked and the key restricted or deleted. |
| Dev backend `.env` (localhost DB URL, dev JWT/refresh secrets) | `taleemplus_backend/.env`, removed in commit `921ea16` | Low–medium: only dangerous if the same secret values were ever reused in production. |
| Local PostgreSQL data directory | `taleemplus_backend/.pgdata` (1,367 blobs), now git-ignored | Medium: may contain local test rows; bloats the repository. |
| Current Neon / Vercel / JWT secrets | **not** in history (verified) | — |

## 2. Rotation steps (owner)

1. **JWT + refresh secrets (backend, Vercel project `taleemplus`)**
   - Generate two new 48+ character random values.
   - `vercel env rm JWT_SECRET production` / `vercel env add JWT_SECRET production` (same for `REFRESH_TOKEN_SECRET`), then `vercel deploy --prod`.
   - Effect: every user is signed out once (access tokens and stored refresh tokens stop validating). Do it outside school hours and announce it.
2. **Firebase web API key** — Google Cloud Console → APIs & Services → Credentials: delete the key (nothing uses it) or restrict it to no APIs.
3. **ML internal token** — set one new value on BOTH the ML Vercel project (`final-year-project`) and the backend (`ML_INTERNAL_TOKEN`), plus the GitHub secret for `ml-monitor.yml`; redeploy both.
4. **Database** — the Neon owner password was never committed; rotate only if the owner wants a clean slate (Neon console → Roles → reset password → update `DATABASE_URL`/`DATABASE_URL_UNPOOLED` in Vercel and local `.env.local`). The ML read-only role `taleemplus_ml_reader` likewise.
5. **Demo accounts** — change the shared demo password after the viva (`DEMO_SEED_CREDENTIALS.csv` is git-ignored; keep it out of any submission archive).

## 3. History clean-up (owner; destructive, coordinate with every clone)

```bash
# 1. Fresh mirror clone
git clone --mirror https://github.com/RakibAkram5/Final_Year_Project.git tp-mirror && cd tp-mirror
# 2. Remove the offending paths from every commit
pip install git-filter-repo
git filter-repo --invert-paths \
  --path taleemplus_backend/.pgdata \
  --path taleemplus_backend/.env \
  --path lib/firebase_options.dart
# 3. Push the rewritten history (requires temporarily disabling branch protection)
git push --force --mirror
```

After the push: every collaborator re-clones (old clones will re-introduce the
blobs if they push), existing PR diffs are recomputed, release tags must be
re-pushed (`git push --force --tags`), and GitHub support can be asked to run
garbage collection so cached blobs disappear.

## 4. Preventive controls already in place

- `.gitignore`: `.env*`, `*.keystore`, `key.properties`, `backups/`, `.pgdata/`, demo credentials CSV.
- Backend refuses weak/example secrets in production (`src/config/env.js`).
- Refresh tokens are stored hashed (SHA-256) and rotated on every refresh.
- Release keystore lives outside the repository (`~/.taleemplus/`); CI reads it only from secrets.
