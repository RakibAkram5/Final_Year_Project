from app import monitoring


def _fee_rows(n, late_every=2):
    return [{"attendance_pct": 90.0, "late_count": 0, "delay_avg": 0.0,
             "consistency": 1.0, "outstanding": 1000.0, "label": i % late_every}
            for i in range(n)]


def test_below_minimum_is_insufficient_with_shortfall_message():
    out = monitoring.evaluate_eligibility("fee-risk", _fee_rows(40), minimum=100,
                                          last_trained_records=None, new_record_threshold=50)
    assert out["data_state"] == monitoring.INSUFFICIENT_DATA
    assert out["should_train"] is False
    assert "need 60 more" in out["reason"]


def test_minimum_reached_without_model_is_ready_to_train():
    out = monitoring.evaluate_eligibility("fee-risk", _fee_rows(120), minimum=100,
                                          last_trained_records=None, new_record_threshold=50)
    assert out["data_state"] == monitoring.READY_TO_TRAIN
    assert out["should_train"] is True


def test_single_class_is_insufficient_even_above_minimum():
    rows = [{**r, "label": 1} for r in _fee_rows(120)]
    out = monitoring.evaluate_eligibility("fee-risk", rows, minimum=100,
                                          last_trained_records=None, new_record_threshold=50)
    assert out["data_state"] == monitoring.INSUFFICIENT_DATA
    assert "both" in out["reason"]


def test_severe_class_imbalance_is_rejected():
    base = _fee_rows(1)[0]
    rows = [{**base, "label": 0} for _ in range(95)] + [{**base, "label": 1} for _ in range(5)]
    out = monitoring.evaluate_eligibility("fee-risk", rows, minimum=50,
                                          last_trained_records=None, new_record_threshold=50,
                                          min_minority_fraction=0.1)
    assert out["data_state"] == monitoring.INSUFFICIENT_DATA
    assert "imbalance" in out["reason"].lower()


def test_waits_until_enough_new_records_accumulate():
    out = monitoring.evaluate_eligibility("fee-risk", _fee_rows(120), minimum=100,
                                          last_trained_records=100, new_record_threshold=50)
    assert out["data_state"] == monitoring.WAITING_FOR_DATA
    assert out["should_train"] is False
    assert out["new_records_since_training"] == 20


def test_retrains_once_new_record_threshold_crossed():
    out = monitoring.evaluate_eligibility("fee-risk", _fee_rows(160), minimum=100,
                                          last_trained_records=100, new_record_threshold=50)
    assert out["should_train"] is True
    assert out["new_records_since_training"] == 60


def test_class_balance_ignores_unlabeled_rows():
    rows = _fee_rows(10) + [{"label": None}, {}]
    balance = monitoring.class_balance(rows)
    assert balance["late"] + balance["ontime"] == 10


def test_feature_distribution_reports_mean_and_missing():
    rows = [{"attendance_pct": 80.0}, {"attendance_pct": 100.0}, {"attendance_pct": None}]
    dist = monitoring.feature_distribution(rows, ["attendance_pct"])
    assert dist["attendance_pct"]["mean"] == 90.0
    assert dist["attendance_pct"]["missing_fraction"] > 0


def test_drift_detection():
    base = {"x": {"mean": 10.0}}
    assert monitoring.detect_drift(None, {"x": {"mean": 10.0}}, 0.5)["drifted"] is False
    assert monitoring.detect_drift(base, {"x": {"mean": 10.4}}, 0.5)["drifted"] is False
    shifted = monitoring.detect_drift(base, {"x": {"mean": 20.0}}, 0.5)
    assert shifted["drifted"] is True and "x" in shifted["features"]
