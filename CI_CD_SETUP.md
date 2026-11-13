# TaleemPlus CI/CD Setup Guide

TaleemPlus utilizes GitHub Actions for continuous integration, automated testing, static analysis, and APK artifact building.

---

## 1. Workflow Files (`.github/workflows/`)

* **`backend-ci.yml`**: Triggers on push/PR to `feature/api-v2-cicd` or `main`. Sets up PostgreSQL service container, runs Prisma migrations, and executes Jest API integration tests.
* **`flutter-ci.yml`**: Triggers on push/PR. Sets up Flutter stable, checks formatting (`dart format`), runs static analysis (`flutter analyze`), and executes unit test suite (`flutter test`).
* **`android-apk.yml`**: Triggers on version tags (`v*`) or manual workflow dispatch. Builds signed/unsigned split release APKs and uploads them as GitHub Actions artifacts.

---

## 2. Required GitHub Secrets
To enable production deployments and secure builds, configure the following repository secrets under **Settings > Secrets and variables > Actions**:
| Secret / variable | Used by | Purpose |
|---|---|---|
| `VERCEL_TOKEN` (secret) | `vercel.yml` | Continuous deployment of the backend to Vercel on pushes to `main` (runs `prisma migrate deploy` first). Without it the job is skipped, not failed. |
| `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` (secrets) | `main.yml` | Release signing of the APK/AAB. `KEYSTORE_BASE64` = `base64 -w0 taleemplus-release.jks`. Without them the APK is debug-signed and the log says so. The keystore itself lives outside the repository (`~/.taleemplus/`). |
| `API_BASE_URL` (variable) | `main.yml`, `flutter-ci.yml` | Production API origin baked into Android builds (`https://taleemplus.vercel.app/api/v2`). |
| `ML_SERVICE_URL`, `ML_INTERNAL_TOKEN` (secrets) | `ml-monitor.yml` | Six-hourly eligibility-gated training sweep. `ML_INTERNAL_TOKEN` must equal the value configured on the ML Vercel project. |

Backend CI (`backend-ci.yml`) needs **no** secrets: it provisions a disposable PostgreSQL service container and uses throwaway JWT values.

Setting them (owner): `gh secret set VERCEL_TOKEN`, `gh secret set KEYSTORE_BASE64 < <(base64 -w0 ~/.taleemplus/taleemplus-release.jks)`, … or Settings → Secrets and variables → Actions.
