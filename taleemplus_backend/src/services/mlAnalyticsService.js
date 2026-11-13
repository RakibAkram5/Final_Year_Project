/**
 * Pure aggregation helpers for the admin ML analytics dashboard.
 *
 * Everything here is computed from real records passed in by the controller
 * (marks, challans, attendance) or from genuine model outputs. No function
 * fabricates a value: when there is nothing to aggregate it returns empty
 * lists / nulls so the client can render an honest empty state.
 */

const round = (value, digits = 1) =>
  value === null || value === undefined || Number.isNaN(value) ? null
    : Math.round(value * 10 ** digits) / 10 ** digits;

const mean = (values) => (values.length ? values.reduce((s, v) => s + v, 0) / values.length : null);

/** YYYY-MM for a Date (UTC), or null. */
const monthKey = (date) => {
  if (!date) return null;
  const d = date instanceof Date ? date : new Date(date);
  return Number.isNaN(d.getTime()) ? null : d.toISOString().slice(0, 7);
};

/** The date an assessment counts for: the quiz test date, else the mark's own timestamp. */
const markDate = (mark) => mark.quiz?.testDate || mark.quiz?.createdAt || mark.updatedAt;

const sectionLabel = (cls) => {
  if (!cls) return 'Unassigned';
  const parts = [cls.className, cls.program, cls.section].filter((p) => p && String(p).trim());
  return parts.join(' - ');
};

/** Monthly academy-wide average percentage (actual results only). */
function performanceTrend(marks) {
  const buckets = new Map();
  for (const mark of marks) {
    const key = monthKey(markDate(mark));
    if (!key) continue;
    const bucket = buckets.get(key) || { month: key, values: [], students: new Set() };
    bucket.values.push(Number(mark.percentage));
    bucket.students.add(mark.studentId);
    buckets.set(key, bucket);
  }
  return [...buckets.values()]
    .sort((a, b) => a.month.localeCompare(b.month))
    .map((b) => ({ month: b.month, average: round(mean(b.values)), count: b.values.length, students: b.students.size }));
}

/** Average percentage per class section (uses the mark's class → section link). */
function classComparison(marks) {
  const buckets = new Map();
  for (const mark of marks) {
    const cls = mark.class;
    const key = cls?.classSectionId || (cls ? `${cls.className}|${cls.section}` : 'unassigned');
    const bucket = buckets.get(key) || { sectionId: cls?.classSectionId || null, label: sectionLabel(cls), values: [], students: new Set() };
    bucket.values.push(Number(mark.percentage));
    bucket.students.add(mark.studentId);
    buckets.set(key, bucket);
  }
  return [...buckets.values()]
    .map((b) => ({ sectionId: b.sectionId, label: b.label, average: round(mean(b.values)), count: b.values.length, students: b.students.size }))
    .sort((a, b) => a.label.localeCompare(b.label, undefined, { numeric: true }));
}

function subjectComparison(marks) {
  const buckets = new Map();
  for (const mark of marks) {
    const bucket = buckets.get(mark.subject) || { subject: mark.subject, values: [] };
    bucket.values.push(Number(mark.percentage));
    buckets.set(mark.subject, bucket);
  }
  return [...buckets.values()]
    .map((b) => ({ subject: b.subject, average: round(mean(b.values)), count: b.values.length }))
    .sort((a, b) => (a.average ?? 0) - (b.average ?? 0));
}

/** Per-student overall average and latest class label (for the at-risk list). */
function studentAverages(marks) {
  const buckets = new Map();
  for (const mark of marks) {
    const bucket = buckets.get(mark.studentId) || { studentId: mark.studentId, studentName: mark.studentName, values: [], classLabel: sectionLabel(mark.class), latest: null };
    bucket.values.push(Number(mark.percentage));
    const date = markDate(mark);
    if (!bucket.latest || (date && new Date(date) > new Date(bucket.latest))) {
      bucket.latest = date; bucket.classLabel = sectionLabel(mark.class);
    }
    buckets.set(mark.studentId, bucket);
  }
  return [...buckets.values()].map((b) => ({
    studentId: b.studentId, studentName: b.studentName, classLabel: b.classLabel,
    average: round(mean(b.values)), assessments: b.values.length,
  }));
}

/**
 * Monthly billed / collected / pending / overdue from challans.
 * `now` decides which unpaid challans count as overdue.
 */
function revenueByMonth(challans, now = new Date()) {
  const buckets = new Map();
  for (const c of challans) {
    const period = c.billingPeriod || monthKey(c.dueDate);
    if (!period) continue;
    const amount = Number(c.totalAmount) || 0;
    const bucket = buckets.get(period) || { period, billed: 0, collected: 0, pending: 0, overdue: 0, challans: 0, paid: 0 };
    bucket.billed += amount; bucket.challans += 1;
    if (c.status === 'PAID') { bucket.collected += amount; bucket.paid += 1; }
    else if (c.status === 'OVERDUE' || new Date(c.dueDate) < now) bucket.overdue += amount;
    else bucket.pending += amount;
    buckets.set(period, bucket);
  }
  return [...buckets.values()].sort((a, b) => a.period.localeCompare(b.period)).map((b) => ({
    ...b,
    billed: round(b.billed, 2), collected: round(b.collected, 2), pending: round(b.pending, 2), overdue: round(b.overdue, 2),
    collection_rate: b.billed > 0 ? round((b.collected / b.billed) * 100) : null,
  }));
}

/**
 * Data-driven revenue estimate. Two bases, both reported with their inputs:
 *  - historical: outstanding amount × the academy's own collection rate over
 *    periods whose due dates have fully passed (null without such history);
 *  - model: Σ amount × (1 − P(late)) for outstanding challans of students the
 *    fee-risk model scored (null when no validated model exists).
 */
function revenueEstimate(months, challans, feeScores = null, now = new Date()) {
  const closed = months.filter((m) => m.period < monthKey(now));
  const closedBilled = closed.reduce((s, m) => s + m.billed, 0);
  const closedCollected = closed.reduce((s, m) => s + m.collected, 0);
  const historicalRate = closedBilled > 0 ? closedCollected / closedBilled : null;
  const outstanding = challans.filter((c) => c.status !== 'PAID');
  const outstandingAmount = outstanding.reduce((s, c) => s + (Number(c.totalAmount) || 0), 0);
  const recent = months.slice(-3);
  const expectedBilledNextPeriod = recent.length ? mean(recent.map((m) => m.billed)) : null;

  let modelExpected = null; let scoredAmount = 0; let scoredCount = 0;
  if (feeScores) {
    modelExpected = 0;
    for (const c of outstanding) {
      const score = feeScores.get(c.studentId);
      if (!score) continue;
      const amount = Number(c.totalAmount) || 0;
      modelExpected += amount * (1 - score.probability);
      scoredAmount += amount; scoredCount += 1;
    }
    if (!scoredCount) modelExpected = null;
  }
  return {
    outstanding_amount: round(outstandingAmount, 2),
    outstanding_challans: outstanding.length,
    historical_collection_rate: historicalRate === null ? null : round(historicalRate * 100),
    historical_periods: closed.length,
    expected_collection_historical: historicalRate === null ? null : round(outstandingAmount * historicalRate, 2),
    expected_on_time_model: modelExpected === null ? null : round(modelExpected, 2),
    model_scored_amount: scoredCount ? round(scoredAmount, 2) : null,
    model_scored_challans: scoredCount,
    expected_billed_next_period: expectedBilledNextPeriod === null ? null : round(expectedBilledNextPeriod, 2),
    basis: {
      historical: 'outstanding amount × collection rate of fully elapsed billing periods',
      model: 'Σ outstanding amount × (1 − predicted late-payment probability) from the validated fee-risk model',
      next_period: 'average billed amount of the last three billing periods',
    },
  };
}

/**
 * Groups marks per (student, subject) in chronological order so the
 * controller can build both a holdout comparison (predict the latest mark
 * from the earlier ones) and a next-assessment forecast (all marks).
 */
function markGroups(marks) {
  const groups = new Map();
  for (const mark of marks) {
    const key = `${mark.studentId}\u0000${mark.subject}`;
    const group = groups.get(key) || { studentId: mark.studentId, studentName: mark.studentName, subject: mark.subject, classLabel: sectionLabel(mark.class), marks: [] };
    group.marks.push({ percentage: Number(mark.percentage), date: markDate(mark) });
    groups.set(key, group);
  }
  for (const group of groups.values()) {
    group.marks.sort((a, b) => new Date(a.date) - new Date(b.date));
  }
  return [...groups.values()];
}

const attendancePct = (records) => {
  if (!records || !records.length) return null;
  const present = records.filter((r) => ['PRESENT', 'LATE'].includes(r.status)).length;
  return (100 * present) / records.length;
};

const featureRow = (values, attendance) => ({
  prior_avg: mean(values),
  prior_count: values.length,
  attendance_pct: attendancePct(attendance),
});

/** Combines rule-based and model-based signals into one at-risk list. */
function atRiskStudents({ averages, performanceForecast = [], feeScores = null, threshold = 50 }) {
  const byId = new Map();
  const add = (studentId, studentName, classLabel, reason, extra = {}) => {
    const entry = byId.get(studentId) || { studentId, studentName, classLabel, reasons: [], average: null, predicted_min: null, fee_probability: null };
    if (!entry.reasons.includes(reason)) entry.reasons.push(reason);
    Object.assign(entry, extra);
    byId.set(studentId, entry);
  };
  for (const s of averages) {
    if (s.average !== null && s.average < threshold) {
      add(s.studentId, s.studentName, s.classLabel, `Average ${s.average}% is below ${threshold}%`, { average: s.average });
    }
  }
  for (const f of performanceForecast) {
    if (f.predicted_next !== null && f.predicted_next < threshold) {
      const current = byId.get(f.studentId);
      const worst = current?.predicted_min === null || current?.predicted_min === undefined
        ? f.predicted_next : Math.min(current.predicted_min, f.predicted_next);
      add(f.studentId, f.studentName, f.classLabel, `Model forecasts ${round(f.predicted_next)}% in ${f.subject}`, { predicted_min: round(worst) });
    }
  }
  if (feeScores) {
    for (const [studentId, score] of feeScores) {
      if (score.risk_category === 'High Risk') {
        add(studentId, score.studentName, score.classLabel, `High fee-delay risk (${round(score.probability * 100)}%)`, { fee_probability: round(score.probability, 3) });
      }
    }
  }
  return [...byId.values()].sort((a, b) => b.reasons.length - a.reasons.length || (a.average ?? 100) - (b.average ?? 100));
}

module.exports = {
  round, mean, monthKey, markDate, sectionLabel,
  performanceTrend, classComparison, subjectComparison, studentAverages,
  revenueByMonth, revenueEstimate, markGroups, featureRow, attendancePct, atRiskStudents,
};
