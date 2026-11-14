"""Parameterized academy-scoped extraction of minimum necessary ML fields."""
from datetime import date, datetime, timezone
import re
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import psycopg
from psycopg.rows import dict_row


def _connect(database_url: str):
    if not database_url:
        raise RuntimeError("DATABASE_URL is not configured")
    parts = urlsplit(database_url)
    params = parse_qsl(parts.query, keep_blank_values=True)
    schema_values = [value for key, value in params if key == "schema"]
    if len(schema_values) > 1:
        raise ValueError("DATABASE_URL contains multiple schema parameters")
    schema = schema_values[0] if schema_values else None
    if schema is not None and not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", schema):
        raise ValueError("DATABASE_URL schema must be a simple PostgreSQL identifier")
    query = urlencode([(key, value) for key, value in params if key != "schema"])
    dsn = urlunsplit((parts.scheme, parts.netloc, parts.path, query, parts.fragment))
    options = f"-c search_path={schema}" if schema else None
    return psycopg.connect(dsn, row_factory=dict_row, options=options)


def list_academy_ids(database_url: str):
    """Return tenant keys only; callers must never log these values."""
    with _connect(database_url) as conn, conn.cursor() as cur:
        cur.execute('SELECT "id" FROM academies')
        return [row["id"] for row in cur.fetchall()]


def database_is_healthy(database_url: str) -> bool:
    try:
        with _connect(database_url) as conn, conn.cursor() as cur:
            cur.execute("SELECT 1 AS health_check")
            return cur.fetchone()["health_check"] == 1
    except Exception:
        return False


def extract_fee_rows(database_url: str, academy_id: str, as_of: date | None = None):
    """Return dated candidate snapshots; updatedAt is an imperfect paid-date proxy.

    Target: payment after due date through 30 days after due date. Pending rows are
    labelable only after the full window has elapsed. Features use prior challans
    and attendance strictly before the current challan issue date.
    """
    with _connect(database_url) as conn, conn.cursor() as cur:
        cur.execute("""
          SELECT f."id", f."studentId" AS student_id, f."issueDate"::date AS issue_date,
                 f."dueDate"::date AS due_date, f."totalAmount"::float8 AS amount,
                 (f."totalAmount" - COALESCE(f."fine", 0) + COALESCE((SELECT sum(p."totalAmount")
                    FROM fee_challans p WHERE p."academyId"=f."academyId"
                     AND p."studentId"=f."studentId" AND p."issueDate" < f."issueDate"
                     AND (p."paidAt" IS NULL OR p."paidAt" >= f."issueDate")), 0))::float8 AS outstanding_snapshot,
                 f."status"::text AS status, f."paidAt"::date AS paid_date,
                 (SELECT count(*) FROM fee_challans p
                   WHERE p."academyId"=f."academyId" AND p."studentId"=f."studentId"
                     AND p."issueDate" < f."issueDate" AND p."status"='PAID'
                     AND p."paidAt" IS NOT NULL AND p."paidAt" < f."issueDate"
                     AND p."paidAt"::date > p."dueDate"::date) AS prior_late_count,
                 (SELECT count(*) FROM fee_challans p
                   WHERE p."academyId"=f."academyId" AND p."studentId"=f."studentId"
                     AND p."issueDate" < f."issueDate" AND p."status"='PAID'
                     AND p."paidAt" IS NOT NULL AND p."paidAt" < f."issueDate") AS prior_paid_count,
                 (SELECT count(*) FROM fee_challans p
                   WHERE p."academyId"=f."academyId" AND p."studentId"=f."studentId"
                     AND p."issueDate" < f."issueDate" AND p."status"='PAID'
                     AND p."paidAt" IS NOT NULL
                     AND p."paidAt" < f."issueDate"
                     AND p."paidAt"::date <= p."dueDate"::date) AS prior_ontime_count,
                 (SELECT avg(greatest(0, p."paidAt"::date-p."dueDate"::date))
                    FROM fee_challans p WHERE p."academyId"=f."academyId"
                     AND p."studentId"=f."studentId" AND p."issueDate" < f."issueDate"
                     AND p."status"='PAID' AND p."paidAt" IS NOT NULL
                     AND p."paidAt" < f."issueDate") AS prior_delay_avg,
                 (SELECT count(*) FROM attendance_records a
                   WHERE a."academyId"=f."academyId" AND a."studentId"=f."studentId"
                     AND CASE WHEN pg_input_is_valid(a."logDate", 'date') THEN a."logDate"::date END < f."issueDate"::date
                     AND CASE WHEN pg_input_is_valid(a."logDate", 'date') THEN a."logDate"::date END >= f."issueDate"::date - 90
                     AND a."recordedAt" < f."issueDate") AS att_count,
                 (SELECT count(*) FROM attendance_records a
                   WHERE a."academyId"=f."academyId" AND a."studentId"=f."studentId"
                     AND CASE WHEN pg_input_is_valid(a."logDate", 'date') THEN a."logDate"::date END < f."issueDate"::date
                     AND CASE WHEN pg_input_is_valid(a."logDate", 'date') THEN a."logDate"::date END >= f."issueDate"::date - 90
                     AND a."recordedAt" < f."issueDate"
                     AND a."status" IN ('PRESENT','LATE')) AS att_present
            FROM fee_challans f JOIN users u ON u."id"=f."studentId"
           WHERE f."academyId"=%s AND u."academyId"=f."academyId"
             AND u."role"='STUDENT' AND u."accountStatus"='ACTIVE'
             AND f."issueDate" IS NOT NULL AND f."dueDate" > f."issueDate"
             AND f."totalAmount" > 0 AND f."issueDate" <= CURRENT_TIMESTAMP
             AND (f."paidAt" IS NULL OR f."paidAt" >= f."issueDate")
           ORDER BY f."studentId", f."issueDate"
        """, (academy_id,))
        rows = cur.fetchall()
    cutoff = as_of or datetime.now(timezone.utc).date()
    result = []
    for row in rows:
        due = row["due_date"]
        if row["status"] == "PAID":
            labelable = row["paid_date"] is not None and row["paid_date"] <= cutoff
            late = row["paid_date"] is not None and row["paid_date"] > due
        else:
            labelable = cutoff > due.replace() and (cutoff - due).days > 30
            late = True
        if not labelable:
            continue
        attended = row.pop("att_present")
        count = row.pop("att_count")
        row.pop("paid_date", None)
        row.pop("student_id", None)
        row.pop("id", None)
        row["attendance_pct"] = (100.0 * attended / count) if count else None
        row["late_count"] = int(row.pop("prior_late_count") or 0)
        row["delay_avg"] = float(row.pop("prior_delay_avg") or 0)
        row["consistency"] = None
        # A fine on the current bill is assessed after the due date, i.e. it
        # encodes the label, so it is excluded from the current bill's amount.
        # Snapshot balance includes this bill plus prior bills still open at
        # issue date, reconstructed only from payment timestamps.
        row["outstanding"] = float(row.pop("outstanding_snapshot"))
        paid_count = int(row.pop("prior_paid_count") or 0)
        ontime_count = int(row.pop("prior_ontime_count") or 0)
        row["consistency"] = ontime_count / paid_count if paid_count else None
        row["label"] = int(late)
        for key in ("status", "due_date", "amount"):
            row.pop(key, None)
        result.append(row)
    return result


def extract_performance_rows(database_url: str, academy_id: str):
    """Dated assessment target rows with only marks/attendance before target date."""
    with _connect(database_url) as conn, conn.cursor() as cur:
        cur.execute("""
          SELECT m."studentId" AS student_id, q."testDate"::date AS target_date,
                 m."percentage"::float8 AS target,
                 (SELECT avg(p."percentage")::float8 FROM test_marks p
                    JOIN quizzes pq ON pq."id"=p."quizId"
                   WHERE p."academyId"=m."academyId" AND p."studentId"=m."studentId"
                     AND p."subject"=m."subject" AND pq."testDate" < q."testDate"
                     AND p."updatedAt" < q."testDate") AS prior_avg,
                 (SELECT count(*) FROM test_marks p JOIN quizzes pq ON pq."id"=p."quizId"
                   WHERE p."academyId"=m."academyId" AND p."studentId"=m."studentId"
                     AND p."subject"=m."subject" AND pq."testDate" < q."testDate"
                     AND p."updatedAt" < q."testDate") AS prior_count,
                 (SELECT avg(CASE WHEN a."status" IN ('PRESENT','LATE') THEN 100.0 ELSE 0.0 END)
                    FROM attendance_records a WHERE a."academyId"=m."academyId"
                     AND a."studentId"=m."studentId"
                     AND CASE WHEN pg_input_is_valid(a."logDate", 'date') THEN a."logDate"::date END < q."testDate"::date
                     AND CASE WHEN pg_input_is_valid(a."logDate", 'date') THEN a."logDate"::date END >= q."testDate"::date - 90
                     AND a."recordedAt" < q."testDate")::float8 AS attendance_pct
            FROM test_marks m JOIN quizzes q ON q."id"=m."quizId"
              JOIN users u ON u."id"=m."studentId"
           WHERE m."academyId"=%s AND q."academyId"=m."academyId"
             AND u."academyId"=m."academyId" AND u."role"='STUDENT'
             AND u."accountStatus"='ACTIVE' AND q."testDate" IS NOT NULL
             AND q."testDate" <= CURRENT_TIMESTAMP
             AND m."percentage" >= 0 AND m."percentage" <= 100
           ORDER BY q."testDate", m."studentId"
        """, (academy_id,))
        rows = cur.fetchall()
    # Identifiers are removed before returning to the model layer.
    for row in rows:
        row.pop("student_id", None)
        row["prior_avg"] = float(row["prior_avg"]) if row["prior_avg"] is not None else None
        row["attendance_pct"] = float(row["attendance_pct"]) if row["attendance_pct"] is not None else None
        row["target"] = float(row["target"])
        row["prior_count"] = int(row["prior_count"] or 0)
    return rows
