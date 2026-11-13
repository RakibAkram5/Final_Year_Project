# Machine learning in TaleemPlus

## What is (and is not) machine learning here

| Feature | Technique | Trained ML? | Where |
|---|---|---|---|
| **Fee payment risk** | Supervised classification: logistic regression / random forest / gradient boosting, best chosen on a temporal hold-out | **Yes** — per academy, from its own records | `ml_service/` |
| **Academic performance forecast** | Supervised regression: linear / random forest / gradient boosting | **Yes** — per academy | `ml_service/` |
| OCR (scan to text) | Google ML Kit text recognition | Pre-trained by Google; not trained here | Flutter, on device |
| AI answer grading | TF-IDF keyword similarity | No (deterministic) | `lib/logic/tfidf_grader.dart` |
| Notes summariser | TextRank extractive summary | No (deterministic) | `lib/logic/text_rank_summarizer.dart` |
| Test question extraction | Rules over OCR text | No | quiz screens |
| Revenue estimate on the AI screen | fixed 85 % collection assumption | No (heuristic, labelled as such in the UI) | `admin_ai_prediction_screen.dart` |
| At-risk students / weakest subject | averages and thresholds over marks | No (statistics) | `admin_ai_provider.dart` |

Removed in this release: `lib/logic/fee_risk_model.dart` and
`lib/logic/performance_index_model.dart` — unused Dart classes whose weights
came from synthetic data and cited a training script that did not exist.

## Architecture

```
Flutter (admin) ──JWT──▶ Express /api/v2/admin/ml/*  ──Bearer ML_INTERNAL_TOKEN──▶ FastAPI ml_service
                          (ADMIN only, academyId from                              │ read-only SQL (psycopg)
                           the token, rate-limited)                                ▼
                                                                          PostgreSQL (academy rows)
                                                         artifacts ──▶ local dir  ⇄  private HF Hub repo
```

- The academy is never chosen by the client; Express derives it from the JWT.
- The ML service stores artifacts under `sha256(academyId)`; no names, emails
  or student ids are written to artifacts or training history.
- Training runs in a **background thread** (`202 TRAINING`); clients poll
  `GET /models/status`. A scheduler retrains every `ML_RETRAIN_INTERVAL_HOURS`.

## Data, features and labels

**Fee risk** — one example per fee challan, as of its issue date:

| Feature | Definition (only information available before the issue date) |
|---|---|
| `attendance_pct` | present+late ÷ marked days in the previous 90 days |
| `late_count` | earlier challans paid after their due date |
| `delay_avg` | mean days late of earlier paid challans |
| `consistency` | on-time ÷ paid among earlier challans |
| `outstanding` | this bill + earlier bills still unpaid at issue time (from `paidAt`) |
| **label** | paid after the due date, or unpaid > 30 days past due |

**Performance** — one example per dated test mark: `prior_avg` (same subject,
earlier tests), `prior_count`, `attendance_pct` (90 days before); label = the
mark percentage.

Leakage controls: features use strictly earlier timestamps; validation uses
the **latest 20 % of dates** (never a random split); a model needs ≥ 100
labelled rows (configurable) and both classes for classification.

## Evaluation and promotion

| Model | Metrics reported | Promoted to production only if |
|---|---|---|
| Fee risk | ROC-AUC, PR-AUC, precision, recall, F1, accuracy, confusion matrix | ROC-AUC ≥ 0.60, F1 > 0, and not worse than the current production model on the same validation period |
| Performance | MAE, RMSE, R² | RMSE below a training-mean baseline and not worse than production |

Probabilities are not calibrated; risk bands use fixed cut-offs 0.40 / 0.70.
Every version is kept (`<model>/<version>/pipeline.joblib + metadata.json`) and
`POST /models/rollback` can restore an earlier promoted version.

## Results — be precise about what they mean

**Real academy data:** none of the inspected databases contained enough dated,
labelled records, so **no model has been trained or validated on real data**.
The admin screen shows `Not enough data yet` / `Enough data – ready to train`
until then. No real-data accuracy is claimed anywhere.

**Synthetic demonstration (local test database only, 2026-11-09):**
`taleemplus_backend/scripts/seed-ml-synthetic.js` created
"[SYNTHETIC] ML Demo Academy" (60 artificial students, 720 challans, 7,200
attendance rows, 1,440 marks; a hidden per-student "diligence" variable drives
behaviour). Training through the real API path (`POST /admin/ml/retrain` →
background job → promotion) produced:

| Model | Selected | Hold-out metrics (synthetic) |
|---|---|---|
| Fee risk | logistic regression | ROC-AUC 0.738, PR-AUC 0.680, F1 0.687, precision 0.636, recall 0.747, accuracy 0.717 |
| Performance | gradient boosting | MAE 7.70, RMSE 9.79, R² 0.640 |

These numbers only show that the pipeline trains, evaluates, promotes and
serves predictions end to end. They say nothing about real academies, because
the data was generated by a formula the models are partly able to recover.

## Code map

| File | Purpose |
|---|---|
| `ml_service/app/data/extractor.py` | academy-scoped SQL extraction + feature/label construction |
| `ml_service/app/training/pipeline.py` | preprocessing (median imputation, scaling), candidates, temporal split, metrics, versioned save, promotion |
| `ml_service/app/models.py` | loading the production artifact |
| `ml_service/app/main.py` | FastAPI: health, status, metrics, history, train (background), rollback, predict |
| `ml_service/app/training/scheduler.py` | periodic retraining |
| `ml_service/app/artifact_store.py` | persistence to a private Hugging Face Hub repo |
| `taleemplus_backend/src/controllers/mlController.js` | admin proxy; builds live feature rows for scoring |
| `lib/logic/admin_ai_provider.dart`, `lib/features/admin/admin_ai_prediction_screen.dart` | UI: status, metrics, train/retrain with polling, predictions |

Tests: `ml_service/tests` (18), backend `mlFeatureService`/`mlServiceClient`.

## Analytics dashboard (added 2026-11-13)

`GET /api/v2/admin/ml/analytics?from=YYYY-MM-DD&to=YYYY-MM-DD&sectionId=&level=` (admin) returns chart series computed from the academy's **own** rows (attendance rate, fee collection by billing month, marks by subject) plus model predictions only when a model is in `PRODUCTION`. Dates are validated as real calendar dates. The Flutter screen (`ml_analytics_screen.dart`) shows honest empty states — it never fabricates predictions. Prediction endpoints are not rate-limited by the training limiter (3/min applies to `train/*`, `retrain`, `rollback` only).

## Deployment copies

`ml_service/app/` is the single source of truth. The Hugging Face Space bundle (`ml_service/hf_space/build/`) is **generated** by `python ml_service/hf_space/prepare_space.py` and is git-ignored, so it can no longer drift from the service code. Production currently runs the same `app/` on Vercel (`ml_service/api/index.py`).
