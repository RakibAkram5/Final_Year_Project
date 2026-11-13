const mlClient = require('../services/mlServiceClient');
const prisma = require('../config/db');
const { buildFeeFeatures, buildPerformanceFeatures } = require('../services/mlFeatureService');
const analytics = require('../services/mlAnalyticsService');

const { isValidDateOnly } = require('../utils/validation');

// Real calendar dates only: `2026-13-01` and `2026-02-30` must be rejected,
// not silently produce an empty analytics window.
const DATE = { test: (value) => isValidDateOnly(String(value)) };
const MAX_BATCH = 2000;

/** One batch request per model: the ML service scores all rows in one call. */
async function predictBatch(rows, model, academyId) {
  if (!rows.length) return { version: null, metrics: null, results: [] };
  const results = [];
  let meta = null;
  for (let index = 0; index < rows.length; index += MAX_BATCH) {
    const slice = rows.slice(index, index + MAX_BATCH);
    const response = await mlClient.request(`/predict/${model}/batch`, {
      method: 'POST', academyId, body: { rows: slice.map((row) => row.features || row) },
    });
    meta = meta || response;
    results.push(...(response.results || []));
  }
  return { version: meta?.version || null, metrics: meta?.metrics || null, trained_at: meta?.trained_at || null,
    records: meta?.records || null, results };
}

const activeStudentsWhere = (academyId) => ({ academyId, role: 'STUDENT', accountStatus: 'ACTIVE' });

const loadFeeInputs = async (academyId, studentIds, now) => {
  const today = now.toISOString().slice(0, 10);
  const since = new Date(now.getTime() - 90 * 86400000).toISOString().slice(0, 10);
  const [challans, attendance] = await Promise.all([
    prisma.feeChallan.findMany({
      where: { academyId, studentId: { in: studentIds }, issueDate: { lt: now } },
      select: { studentId: true, issueDate: true, dueDate: true, paidAt: true, status: true, totalAmount: true },
    }),
    prisma.attendanceRecord.findMany({
      where: { academyId, studentId: { in: studentIds }, logDate: { gte: since, lt: today }, recordedAt: { lt: now } },
      select: { studentId: true, status: true },
    }),
  ]);
  return { challans, attendance };
};

const predictFee = async (req, res, next) => {
  try {
    const now = new Date();
    const students = await prisma.user.findMany({ where: activeStudentsWhere(req.academyId), select: { id: true } });
    const ids = students.map((student) => student.id);
    if (!ids.length) return res.json({ success: true, data: { status: 'NO_DATA', scored: 0 } });
    const { challans, attendance } = await loadFeeInputs(req.academyId, ids, now);
    const features = buildFeeFeatures(ids, challans, attendance, now);
    const batch = await predictBatch([...features.values()], 'fee-risk', req.academyId);
    const counts = { 'Low Risk': 0, 'Medium Risk': 0, 'High Risk': 0 };
    let probabilitySum = 0;
    for (const prediction of batch.results) {
      counts[prediction.risk_category] = (counts[prediction.risk_category] || 0) + 1;
      probabilitySum += prediction.probability;
    }
    res.json({ success: true, data: { status: 'PRODUCTION', scored: batch.results.length,
      risk_counts: counts, average_probability: batch.results.length ? probabilitySum / batch.results.length : null,
      version: batch.version } });
  } catch (error) {
    if (error.status) return res.status(error.status).json({ success: false, message: error.message });
    next(error);
  }
};

const predictPerformance = async (req, res, next) => {
  try {
    const now = new Date();
    const today = now.toISOString().slice(0, 10);
    const since = new Date(now.getTime() - 90 * 86400000).toISOString().slice(0, 10);
    const [marks, attendance] = await Promise.all([
      prisma.testMark.findMany({
        where: { academyId: req.academyId, percentage: { gte: 0, lte: 100 }, updatedAt: { lt: now },
          quiz: { academyId: req.academyId, testDate: { lt: now } },
          student: activeStudentsWhere(req.academyId) },
        select: { studentId: true, subject: true, percentage: true },
      }),
      prisma.attendanceRecord.findMany({
        where: { academyId: req.academyId, logDate: { gte: since, lt: today }, recordedAt: { lt: now },
          student: activeStudentsWhere(req.academyId) },
        select: { studentId: true, status: true },
      }),
    ]);
    const rows = buildPerformanceFeatures(marks, attendance);
    if (!rows.length) return res.json({ success: true, data: { status: 'NO_DATA', scored: 0 } });
    const batch = await predictBatch(rows, 'performance', req.academyId);
    const mean = batch.results.reduce((sum, item) => sum + item.predicted_marks, 0) / (batch.results.length || 1);
    res.json({ success: true, data: { status: 'PRODUCTION', scored: batch.results.length,
      average_predicted_marks: batch.results.length ? mean : null, version: batch.version } });
  } catch (error) {
    if (error.status) return res.status(error.status).json({ success: false, message: error.message });
    next(error);
  }
};

/**
 * GET /admin/ml/analytics?from&to&sectionId&level
 *
 * Real-data dashboard: every chart series comes from this academy's own
 * records; model-based series appear only when the ML service reports a
 * validated production model, and each service failure is reported in
 * `errors` instead of hiding it or inventing values.
 */
const analyticsDashboard = async (req, res, next) => {
  try {
    const academyId = req.academyId;
    const now = new Date();
    const { from, to, sectionId, level } = req.query;
    if ((from && !DATE.test(String(from))) || (to && !DATE.test(String(to)))) {
      return res.status(400).json({ success: false, message: 'from and to must be YYYY-MM-DD dates.' });
    }
    if (from && to && String(from) > String(to)) {
      return res.status(400).json({ success: false, message: 'from must not be after to.' });
    }
    const errors = {};

    const [sections, students] = await Promise.all([
      prisma.classSection.findMany({
        where: { academyId },
        select: { id: true, className: true, program: true, section: true, enrollments: { select: { studentId: true } } },
        orderBy: [{ className: 'asc' }, { program: 'asc' }, { section: 'asc' }],
      }),
      prisma.user.findMany({ where: activeStudentsWhere(academyId), select: { id: true, fullName: true } }),
    ]);
    const levelFilter = level ? String(level).trim().toLowerCase() : null;
    const matchedSections = sections.filter((s) =>
      (!sectionId || s.id === sectionId) &&
      (!levelFilter || [s.program, s.className].some((v) => String(v || '').trim().toLowerCase() === levelFilter)));
    if (sectionId && !matchedSections.length) {
      return res.status(404).json({ success: false, message: 'Class section not found in this academy.' });
    }
    const scopedToSections = Boolean(sectionId || levelFilter);
    const scopedStudentIds = new Set(matchedSections.flatMap((s) => s.enrollments.map((e) => e.studentId)));
    const studentIds = students.map((s) => s.id).filter((id) => !scopedToSections || scopedStudentIds.has(id));
    const nameById = new Map(students.map((s) => [s.id, s.fullName]));

    const fromDate = from ? new Date(`${from}T00:00:00.000Z`) : null;
    const toDate = to ? new Date(`${to}T23:59:59.999Z`) : null;
    const inRange = (date) => {
      if (!date) return true;
      const d = new Date(date);
      return (!fromDate || d >= fromDate) && (!toDate || d <= toDate);
    };

    // --- Real records ------------------------------------------------------
    const [allMarks, allChallans] = await Promise.all([
      prisma.testMark.findMany({
        where: { academyId, percentage: { gte: 0, lte: 100 }, studentId: { in: studentIds } },
        select: { studentId: true, studentName: true, subject: true, percentage: true, updatedAt: true,
          quiz: { select: { testDate: true, createdAt: true } },
          class: { select: { className: true, section: true, program: true, classSectionId: true } } },
      }),
      prisma.feeChallan.findMany({
        where: { academyId, studentId: { in: studentIds } },
        select: { id: true, studentId: true, studentName: true, classLabel: true, billingPeriod: true,
          issueDate: true, dueDate: true, paidAt: true, status: true, totalAmount: true },
      }),
    ]);
    const marks = allMarks.filter((m) => inRange(analytics.markDate(m)));
    const challans = allChallans.filter((c) => {
      const period = c.billingPeriod || analytics.monthKey(c.dueDate);
      return (!from || period >= String(from).slice(0, 7)) && (!to || period <= String(to).slice(0, 7));
    });

    const trend = analytics.performanceTrend(marks);
    const classes = analytics.classComparison(marks);
    const subjects = analytics.subjectComparison(marks);
    const averages = analytics.studentAverages(marks);
    const revenueMonths = analytics.revenueByMonth(challans, now);

    // --- Model status (genuine; never assumed) ---------------------------
    let models = { fee_risk: { status: 'NOT_READY' }, performance: { status: 'NOT_READY' } };
    let mlOk = false;
    try {
      models = await mlClient.request('/models/status', { academyId });
      mlOk = true;
    } catch (error) {
      errors.ml_status = error.message || 'ML service unavailable.';
      const reason = error.status === 503 ? 'ML service is not configured on the backend.' : 'ML service unavailable.';
      models = { fee_risk: { status: 'NOT_READY', reason }, performance: { status: 'NOT_READY', reason } };
    }

    // --- Fee-risk predictions (only with a production model) --------------
    let feeScores = null;
    let feeRisk = { available: false, reason: models.fee_risk?.reason || null, status: models.fee_risk?.status || 'NOT_READY' };
    if (mlOk && models.fee_risk?.status === 'PRODUCTION' && studentIds.length) {
      try {
        const { challans: history, attendance } = await loadFeeInputs(academyId, studentIds, now);
        const features = buildFeeFeatures(studentIds, history, attendance, now);
        const ids = [...features.keys()];
        const batch = await predictBatch(ids.map((id) => features.get(id)), 'fee-risk', academyId);
        feeScores = new Map();
        const distribution = { 'Low Risk': 0, 'Medium Risk': 0, 'High Risk': 0 };
        const latestLabel = new Map(allChallans.map((c) => [c.studentId, c.classLabel]));
        batch.results.forEach((result, index) => {
          const studentId = ids[index];
          distribution[result.risk_category] = (distribution[result.risk_category] || 0) + 1;
          feeScores.set(studentId, { ...result, studentName: nameById.get(studentId) || 'Student',
            classLabel: latestLabel.get(studentId) || '', outstanding: features.get(studentId).outstanding });
        });
        feeRisk = {
          available: true, status: 'PRODUCTION', version: batch.version, metrics: batch.metrics,
          trained_at: batch.trained_at, records: batch.records, scored: batch.results.length,
          distribution,
          average_probability: analytics.round(analytics.mean(batch.results.map((r) => r.probability)), 3),
          students: [...feeScores.entries()]
            .map(([studentId, s]) => ({ studentId, studentName: s.studentName, classLabel: s.classLabel,
              probability: analytics.round(s.probability, 3), risk_category: s.risk_category,
              outstanding: analytics.round(s.outstanding, 2) }))
            .sort((a, b) => b.probability - a.probability),
        };
      } catch (error) {
        errors.fee_risk = error.message || 'Fee-risk scoring failed.';
        feeRisk = { available: false, status: models.fee_risk.status, reason: errors.fee_risk };
      }
    }

    // --- Performance predictions (holdout check + next-assessment forecast) -
    let performanceForecast = [];
    let performance = { available: false, status: models.performance?.status || 'NOT_READY', reason: models.performance?.reason || null };
    if (mlOk && models.performance?.status === 'PRODUCTION' && marks.length) {
      try {
        const today = now.toISOString().slice(0, 10);
        const since = new Date(now.getTime() - 90 * 86400000).toISOString().slice(0, 10);
        const attendance = await prisma.attendanceRecord.findMany({
          where: { academyId, studentId: { in: studentIds }, logDate: { gte: since, lt: today } },
          select: { studentId: true, status: true },
        });
        const attendanceByStudent = new Map();
        for (const row of attendance) {
          if (!attendanceByStudent.has(row.studentId)) attendanceByStudent.set(row.studentId, []);
          attendanceByStudent.get(row.studentId).push(row);
        }
        const groups = analytics.markGroups(marks);
        const nextRows = groups.map((g) => analytics.featureRow(g.marks.map((m) => m.percentage), attendanceByStudent.get(g.studentId)));
        const holdoutGroups = groups.filter((g) => g.marks.length >= 2);
        const holdoutRows = holdoutGroups.map((g) =>
          analytics.featureRow(g.marks.slice(0, -1).map((m) => m.percentage), attendanceByStudent.get(g.studentId)));
        const [nextBatch, holdoutBatch] = await Promise.all([
          predictBatch(nextRows, 'performance', academyId),
          predictBatch(holdoutRows, 'performance', academyId),
        ]);
        performanceForecast = groups.map((g, i) => ({
          studentId: g.studentId, studentName: g.studentName, subject: g.subject, classLabel: g.classLabel,
          assessments: g.marks.length,
          latest_actual: analytics.round(g.marks[g.marks.length - 1].percentage),
          prior_avg: analytics.round(analytics.mean(g.marks.map((m) => m.percentage))),
          predicted_next: analytics.round(nextBatch.results[i]?.predicted_marks ?? null),
        }));
        const holdout = holdoutGroups.map((g, i) => ({
          studentId: g.studentId, studentName: g.studentName, subject: g.subject, classLabel: g.classLabel,
          actual: analytics.round(g.marks[g.marks.length - 1].percentage),
          predicted: analytics.round(holdoutBatch.results[i]?.predicted_marks ?? null),
        })).filter((h) => h.predicted !== null);
        const residuals = holdout.map((h) => Math.abs(h.actual - h.predicted));
        const trendPredicted = new Map();
        holdoutGroups.forEach((g, i) => {
          const key = analytics.monthKey(g.marks[g.marks.length - 1].date);
          const predicted = holdoutBatch.results[i]?.predicted_marks;
          if (!key || predicted === undefined) return;
          const bucket = trendPredicted.get(key) || [];
          bucket.push(predicted);
          trendPredicted.set(key, bucket);
        });
        for (const point of trend) {
          const values = trendPredicted.get(point.month);
          point.predicted = values ? analytics.round(analytics.mean(values)) : null;
        }
        performance = {
          available: true, status: 'PRODUCTION', version: nextBatch.version, metrics: nextBatch.metrics,
          trained_at: nextBatch.trained_at, records: nextBatch.records,
          forecast: performanceForecast.sort((a, b) => (a.predicted_next ?? 101) - (b.predicted_next ?? 101)),
          holdout: { rows: holdout, count: holdout.length,
            mae: residuals.length ? analytics.round(analytics.mean(residuals), 2) : null,
            note: 'Each latest actual mark predicted only from that student\'s earlier marks and attendance.' },
          average_predicted_next: analytics.round(analytics.mean(performanceForecast.map((f) => f.predicted_next).filter((v) => v !== null))),
        };
      } catch (error) {
        errors.performance = error.message || 'Performance scoring failed.';
        performance = { available: false, status: models.performance.status, reason: errors.performance };
      }
    }

    const atRisk = analytics.atRiskStudents({ averages, performanceForecast, feeScores });

    res.json({ success: true, data: {
      generated_at: now.toISOString(),
      filters: {
        from: from || null, to: to || null, sectionId: sectionId || null, level: level || null,
        available: {
          sections: sections.map((s) => ({ id: s.id, label: analytics.sectionLabel(s), students: s.enrollments.length })),
          levels: [...new Set(sections.flatMap((s) => [s.program, s.className]).filter((v) => v && String(v).trim()))],
        },
        students_in_scope: studentIds.length,
      },
      services: {
        ml: { configured: !(errors.ml_status || '').includes('not configured'), ok: mlOk, error: errors.ml_status || null },
      },
      models,
      performance: { total_marks: marks.length, students: averages.length, trend, classes, subjects,
        academy_average: analytics.round(analytics.mean(marks.map((m) => Number(m.percentage)))) },
      revenue: { months: revenueMonths, estimate: analytics.revenueEstimate(revenueMonths, challans, feeScores, now),
        total_challans: challans.length },
      predictions: { fee_risk: feeRisk, performance },
      at_risk: { threshold: 50, students: atRisk,
        rule: 'Average below 50%, a model forecast below 50%, or a High fee-delay risk score.' },
      errors,
    } });
  } catch (error) {
    if (error.status) return res.status(error.status).json({ success: false, message: error.message });
    next(error);
  }
};

const handle = (path, method = 'GET') => async (req, res, next) => {
  try {
    const data = await mlClient.request(path, {
      method,
      academyId: req.academyId,
      body: method === 'POST' ? {} : undefined,
    });
    res.json({ success: true, data });
  } catch (error) {
    if (error.status) return res.status(error.status).json({ success: false, message: error.message });
    next(error);
  }
};

module.exports = {
  status: handle('/models/status'),
  dashboard: handle('/models/dashboard'),
  metrics: handle('/models/metrics'),
  history: handle('/models/history'),
  trainFee: handle('/models/train/fee-risk', 'POST'),
  trainPerformance: handle('/models/train/performance', 'POST'),
  retrain: handle('/models/retrain', 'POST'),
  rollback: async (req, res, next) => {
    try {
      const { model, version } = req.body || {};
      if (!['fee-risk', 'performance'].includes(model) || typeof version !== 'string') {
        return res.status(400).json({ success: false, message: 'A valid model and version are required.' });
      }
      const data = await mlClient.request('/models/rollback', {
        method: 'POST', academyId: req.academyId, body: { model, version },
      });
      res.json({ success: true, data });
    } catch (error) {
      if (error.status) return res.status(error.status).json({ success: false, message: error.message });
      next(error);
    }
  },
  predictFee,
  predictPerformance,
  analytics: analyticsDashboard,
};
