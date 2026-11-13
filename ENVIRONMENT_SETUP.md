# Environment setup

## Tool versions used for verification

| Tool | Version |
|---|---|
| Flutter / Dart | 3.47.9 (stable) |
| Node.js | 22.x required by Vercel (`package.json` engines); developed on 26.x |
| PostgreSQL (local tests) | 18 |
| Python (ML) | 3.11–3.13 for deployment (3.15 works for tests; `huggingface_hub` lacks a 3.15 wheel on Windows) |
| Java (Android) | 17+ (JDK 21 present) |

## Environment files (never commit real values)

| File | Template | Used by |
|---|---|---|
| `taleemplus_backend/.env` | `taleemplus_backend/.env.example` | Express API |
| `ml_service/.env` or process env | `ml_service/.env.example` | FastAPI ML service |
| Vercel project env | `vercel env pull` → `.env.local` (git-ignored) | production API |
| Flutter | `--dart-define=API_BASE_URL=…` only | mobile release builds (web uses its own origin) |

No secret is compiled into the Flutter app. Generate secrets with
`node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"`.

## Local run (all components)

```powershell
# 1) API  (http://localhost:5000)
cd taleemplus_backend
npm install
npx prisma migrate deploy      # against YOUR dev database only
npm run prisma:seed            # optional demo academy (prints/uses SEED_PASSWORD)
npm start

# 2) ML service (optional, http://127.0.0.1:8100) — see ML_TRAINING_GUIDE.md

# 3) Flutter
cd ..
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5000/api/v2
# Android device on the same Wi-Fi:
flutter run --dart-define=API_BASE_URL=http://<PC-LAN-IP>:5000/api/v2
```

## Tests

```powershell
# Backend (needs a throwaway database; see DATABASE_MIGRATION_GUIDE.md)
cd taleemplus_backend
$env:TEST_DATABASE_URL = 'postgresql://postgres@localhost:5434/taleemplus_test?schema=public'
$env:DATABASE_URL = $env:TEST_DATABASE_URL
npx prisma migrate deploy; npx jest --runInBand          # 16 suites

# Flutter (unit, widget, responsive layout across 12 viewport/theme configs)
cd ..; flutter analyze; flutter test

# ML
ml_service/.venv/Scripts/python.exe -m pytest ml_service/tests -q
```

Re-record the UI fixtures after API changes (local seeded API only):
`node tool/record_ui_fixtures.js http://localhost:5055/api/v2 '<seed password>'`.

## External accounts / configuration still needed

| What | Why | Free? |
|---|---|---|
| Private Vercel Blob store connected to `taleemplus` | file uploads in production | Hobby quota |
| Hugging Face account, write token, private model repo, Docker Space | ML deployment | CPU basic free |
| Neon read-only role `ml_reader` | ML service database access | yes |
| Release signing keystore — generated 2026-11-13 at `~/.taleemplus/taleemplus-release.jks` (+ `key.properties`, copied to `android/key.properties`, both git-ignored). Back it up: losing it means Play updates are impossible. | Play-installable signed APK/AAB | yes |
| Backend env `ML_SERVICE_URL` + `ML_INTERNAL_TOKEN` on the Vercel project `taleemplus` (token identical on the ML project) | admin AI screens show live model status instead of "ML service not available" | yes |
| GitHub secrets `VERCEL_TOKEN`, `KEYSTORE_*`, `ML_SERVICE_URL`, `ML_INTERNAL_TOKEN` | continuous deploy, signed CI builds, ML monitor cron (see `CI_CD_SETUP.md`) | yes |
| Rotate any secret that was ever shared, and the old Firebase web key in git history | hygiene — see `SECURITY_ROTATION_PLAN.md` | — |
