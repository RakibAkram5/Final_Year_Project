# ML training guide

## 1. Install (Python 3.11–3.13 recommended)

```powershell
py -m venv ml_service/.venv
ml_service/.venv/Scripts/python.exe -m pip install -r ml_service/requirements-dev.txt
ml_service/.venv/Scripts/python.exe -m pytest ml_service/tests -q      # 18 tests
```

## 2. Run the service locally

Use a **read-only** database role for the ML service (see §5).

```powershell
$env:DATABASE_URL     = 'postgresql://ml_reader:<pw>@<host>/<db>?sslmode=require'
$env:ML_INTERNAL_TOKEN = '<64 random hex chars>'   # node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
$env:ML_ARTIFACT_DIR   = 'ml_service/artifacts'     # git-ignored
cd ml_service
.venv/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8100
```

Point the backend at it (same token):

```powershell
$env:ML_SERVICE_URL = 'http://127.0.0.1:8100'
$env:ML_INTERNAL_TOKEN = '<same token>'
cd taleemplus_backend; npm start
```

## 3. Train from the app

Admin → **AI Insights** → *Train / Retrain*. The request returns immediately;
the screen polls until each model shows one of:

| Status | Meaning |
|---|---|
| Validated model active | promoted; predictions are shown with metrics |
| Enough data – ready to train | ≥ minimum rows, no model yet |
| Not enough data yet | fewer than `ML_MIN_FEE_SAMPLES` / `ML_MIN_PERFORMANCE_SAMPLES` (default 100) labelled rows |
| Trained, not promoted | a candidate failed the promotion gate; production unchanged |
| Training failed | see service logs; production unchanged |

API equivalents: `POST /api/v2/admin/ml/retrain` then `GET /api/v2/admin/ml/status`.
Training is rate-limited (3/min per admin) and admin-only; students, teachers
and parents get 403.

## 4. Demonstrating with synthetic data (local only)

```powershell
cd taleemplus_backend
$env:DATABASE_URL = 'postgresql://postgres@localhost:5434/taleemplus_test?schema=public'
$env:SYNTH_PASSWORD = '<choose one>'
node scripts/seed-ml-synthetic.js      # refuses non-localhost databases
```

Sign in as `synthetic-admin@ml-demo.test`, open AI Insights, train. Always say
"synthetic" when presenting these metrics (see `ML_DOCUMENTATION.md`).

## 5. Read-only database role (production)

Run once in the Neon SQL editor (adjust names):

```sql
CREATE ROLE ml_reader LOGIN PASSWORD '<strong password>';
GRANT CONNECT ON DATABASE neondb TO ml_reader;
GRANT USAGE ON SCHEMA public TO ml_reader;
GRANT SELECT ON academies, users, fee_challans, attendance_records, quizzes, test_marks TO ml_reader;
```

## 6. Tuning

| Variable | Default | Effect |
|---|---|---|
| `ML_MIN_FEE_SAMPLES` / `ML_MIN_PERFORMANCE_SAMPLES` | 100 | minimum labelled rows; lowering it does not make a weak validation meaningful |
| `ML_RETRAIN_INTERVAL_HOURS` | 24 | scheduled retraining |
| `ML_TIMEOUT_MS` (backend) | 25000 | proxy timeout (fits Vercel's 30 s) |
