const mlClient = require('../services/mlServiceClient');
const prisma = require('../config/db');
const { buildFeeFeatures, buildPerformanceFeatures } = require('../services/mlFeatureService');

const batchSize = 10;
async function predictRows(rows, model, academyId) {
  const predictions = [];
  for (let index = 0; index < rows.length; index += batchSize) {
    const batch = rows.slice(index, index + batchSize);
    const values = await Promise.all(batch.map((row) => mlClient.request(`/predict/${model}`, {
      method: 'POST', academyId, body: { features: row.features || row },
    })));
    predictions.push(...values);
  }
  return predictions;
}

const predictFee = async (req, res, next) => {
  try {
    const now = new Date();
    const today = now.toISOString().slice(0, 10);
    const since = new Date(now.getTime() - 90 * 86400000).toISOString().slice(0, 10);
    const students = await prisma.user.findMany({
      where: { academyId: req.academyId, role: 'STUDENT', accountStatus: 'ACTIVE' },
      select: { id: true },
    });
    const ids = students.map((student) => student.id);
    if (!ids.length) return res.json({ success: true, data: { status: 'NO_DATA', scored: 0 } });
    const [challans, attendance] = await Promise.all([
      prisma.feeChallan.findMany({
        where: { academyId: req.academyId, studentId: { in: ids }, issueDate: { lt: now } },
        select: { studentId: true, issueDate: true, dueDate: true, paidAt: true, status: true, totalAmount: true },
      }),
      prisma.attendanceRecord.findMany({
        where: { academyId: req.academyId, studentId: { in: ids }, logDate: { gte: since, lt: today }, recordedAt: { lt: now } },
        select: { studentId: true, status: true },
      }),
    ]);
    const features = buildFeeFeatures(ids, challans, attendance, now);
    const results = await predictRows([...features.values()].map((features) => ({ features })), 'fee-risk', req.academyId);
    const counts = { 'Low Risk': 0, 'Medium Risk': 0, 'High Risk': 0 };
    let probabilitySum = 0;
    for (const prediction of results) {
      counts[prediction.risk_category] = (counts[prediction.risk_category] || 0) + 1;
      probabilitySum += prediction.probability;
    }
    res.json({ success: true, data: { status: 'PRODUCTION', scored: results.length,
      risk_counts: counts, average_probability: results.length ? probabilitySum / results.length : null,
      version: results[0]?.version || null } });
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
          student: { academyId: req.academyId, role: 'STUDENT', accountStatus: 'ACTIVE' } },
        select: { studentId: true, subject: true, percentage: true },
      }),
      prisma.attendanceRecord.findMany({
        where: { academyId: req.academyId, logDate: { gte: since, lt: today }, recordedAt: { lt: now },
          student: { academyId: req.academyId, role: 'STUDENT', accountStatus: 'ACTIVE' } },
        select: { studentId: true, status: true },
      }),
    ]);
    const rows = buildPerformanceFeatures(marks, attendance);
    if (!rows.length) return res.json({ success: true, data: { status: 'NO_DATA', scored: 0 } });
    const predictions = await predictRows(rows, 'performance', req.academyId);
    const mean = predictions.reduce((sum, item) => sum + item.predicted_marks, 0) / predictions.length;
    res.json({ success: true, data: { status: 'PRODUCTION', scored: predictions.length,
      average_predicted_marks: mean, version: predictions[0]?.version || null } });
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
};
