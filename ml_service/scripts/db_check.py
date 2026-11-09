"""Read-only diagnostic for the TaleemPlus ML database.

Safe by design: opens a READ ONLY transaction (default_transaction_read_only=on)
so it can never INSERT/UPDATE/DELETE, and it NEVER prints the connection string,
passwords, or any student identifiers. It reports table/column availability and
the real number of *usable labeled* records the models would actually train on,
computed with the project's own extractor (not re-implemented here).

Usage (DATABASE_URL must be in the environment, never on the command line):
    cd ml_service && DATABASE_URL="<url>" python scripts/db_check.py
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from urllib.parse import parse_qsl, urlsplit, urlunsplit, urlencode

# Make the `app` package importable when run from ml_service/.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import psycopg
from psycopg.rows import dict_row

from app.data.extractor import extract_fee_rows, extract_performance_rows

REQUIRED = {
    "academies": ["id"],
    "users": ["id", "role", "accountStatus", "academyId"],
    "fee_challans": ["id", "academyId", "studentId", "issueDate", "dueDate",
                     "paidAt", "status", "totalAmount"],
    "attendance_records": ["academyId", "studentId", "logDate", "status", "recordedAt"],
    "test_marks": ["academyId", "studentId", "quizId", "subject", "percentage", "updatedAt"],
    "quizzes": ["id", "academyId", "testDate"],
}


def _read_only_connect(database_url: str):
    """Connect forcing a read-only session; mirrors extractor schema handling."""
    parts = urlsplit(database_url)
    params = parse_qsl(parts.query, keep_blank_values=True)
    schema = next((v for k, v in params if k == "schema"), None)
    query = urlencode([(k, v) for k, v in params if k != "schema"])
    dsn = urlunsplit((parts.scheme, parts.netloc, parts.path, query, parts.fragment))
    opts = ["-c default_transaction_read_only=on"]
    if schema:
        opts.append(f"-c search_path={schema}")
    return psycopg.connect(dsn, row_factory=dict_row, options=" ".join(opts))


def _date_span(values):
    vals = sorted(v for v in values if v is not None)
    if not vals:
        return None
    return {"earliest": str(vals[0]), "latest": str(vals[-1]), "distinct_dates": len(set(vals))}


def main() -> int:
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        print(json.dumps({"connection": "BLOCKED", "reason": "DATABASE_URL not set"}, indent=2))
        return 2

    report: dict = {"connection": "FAIL", "tables": {}, "academies": {}}
    try:
        with _read_only_connect(url) as conn, conn.cursor() as cur:
            cur.execute("SHOW server_version")
            report["server_version"] = cur.fetchone()["server_version"]
            cur.execute("SELECT current_user AS u, current_database() AS d")
            who = cur.fetchone()
            report["connected_as_role"] = who["u"]      # role name only, no secret
            report["database"] = who["d"]
            report["read_only_session"] = True
            report["connection"] = "PASS"

            # Table + column availability (information_schema, read-only).
            for table, cols in REQUIRED.items():
                cur.execute(
                    "SELECT column_name FROM information_schema.columns "
                    "WHERE table_schema = current_schema() AND table_name = %s",
                    (table,),
                )
                present = {r["column_name"] for r in cur.fetchall()}
                if not present:
                    report["tables"][table] = "MISSING_TABLE"
                else:
                    missing = [c for c in cols if c not in present]
                    report["tables"][table] = "PASS" if not missing else {"MISSING_COLUMNS": missing}

            cur.execute("SELECT id FROM academies")
            academy_ids = [r["id"] for r in cur.fetchall()]
            report["academy_count"] = len(academy_ids)
    except Exception as exc:  # pragma: no cover - diagnostic
        report["connection"] = "FAIL"
        report["error_type"] = type(exc).__name__   # no message -> no secret leakage
        print(json.dumps(report, indent=2))
        return 1

    # Real usable-record counts via the project's own extractor (SELECT-only).
    fee_total = perf_total = 0
    fee_late = fee_ontime = 0
    fee_missing_attendance = perf_missing_attendance = perf_missing_prior = 0
    fee_dates: list = []
    perf_dates: list = []
    perf_students: set = set()
    per_academy = {}
    for idx, aid in enumerate(academy_ids):
        label = f"academy_{idx+1}"   # never expose the real id
        try:
            fee_rows = extract_fee_rows(url, aid)
        except Exception as exc:
            fee_rows = []
            per_academy.setdefault(label, {})["fee_error"] = type(exc).__name__
        try:
            perf_rows = extract_performance_rows(url, aid)
        except Exception as exc:
            perf_rows = []
            per_academy.setdefault(label, {})["perf_error"] = type(exc).__name__

        f_late = sum(1 for r in fee_rows if r.get("label") == 1)
        f_on = sum(1 for r in fee_rows if r.get("label") == 0)
        fee_total += len(fee_rows); fee_late += f_late; fee_ontime += f_on
        fee_missing_attendance += sum(1 for r in fee_rows if r.get("attendance_pct") is None)
        fee_dates += [r.get("issue_date") for r in fee_rows]

        perf_total += len(perf_rows)
        perf_missing_attendance += sum(1 for r in perf_rows if r.get("attendance_pct") is None)
        perf_missing_prior += sum(1 for r in perf_rows if r.get("prior_avg") is None)
        perf_dates += [r.get("target_date") for r in perf_rows]

        per_academy[label] = {**per_academy.get(label, {}),
                              "fee_usable": len(fee_rows), "fee_late": f_late, "fee_ontime": f_on,
                              "performance_usable": len(perf_rows)}

    def readiness(total, minimum, extra_ok=True):
        if total == 0:
            return "INSUFFICIENT DATA"
        if total >= minimum and extra_ok:
            return "READY_TO_TRAIN"
        return "INSUFFICIENT DATA"

    fee_both_classes = fee_late > 0 and fee_ontime > 0
    report["fee_risk"] = {
        "usable_labeled_records": fee_total,
        "late_count": fee_late,
        "ontime_count": fee_ontime,
        "both_classes_present": fee_both_classes,
        "missing_attendance_pct": fee_missing_attendance,
        "date_coverage": _date_span(fee_dates),
        "minimum_required": int(os.environ.get("ML_MIN_FEE_SAMPLES", "100")),
        "readiness": readiness(fee_total, int(os.environ.get("ML_MIN_FEE_SAMPLES", "100")), fee_both_classes),
    }
    report["performance"] = {
        "usable_target_records": perf_total,
        "records_with_prior_marks": perf_total - perf_missing_prior,
        "missing_prior_marks": perf_missing_prior,
        "missing_attendance_pct": perf_missing_attendance,
        "date_coverage": _date_span(perf_dates),
        "minimum_required": int(os.environ.get("ML_MIN_PERFORMANCE_SAMPLES", "100")),
        "readiness": readiness(perf_total, int(os.environ.get("ML_MIN_PERFORMANCE_SAMPLES", "100"))),
    }
    report["academies"] = per_academy
    print(json.dumps(report, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
