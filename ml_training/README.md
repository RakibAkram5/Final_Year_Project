# ml_training (synthetic test data only)

`generate_synthetic_data.py` writes `data/synthetic_dataset.csv`, a
**synthetic** dataset. It is not real academy data and was never used to
train a deployed model. It is kept only as an example input shape.

The real machine-learning code — data extraction from an academy's own
records, preprocessing, training, evaluation, model versioning and the
prediction API — lives in [`../ml_service`](../ml_service). See
`ML_DOCUMENTATION.md` and `ML_TRAINING_GUIDE.md` in the repository root.
