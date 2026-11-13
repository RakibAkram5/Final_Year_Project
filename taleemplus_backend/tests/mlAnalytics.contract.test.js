/**
 * Admin ML analytics dashboard: every series is derived from this academy's
 * own records; model-dependent sections appear only when the ML service
 * reports a production model, and ML outages are surfaced per section.
 * Runs only with TEST_DATABASE_URL. The ML service is mocked at fetch level.
 */
const request = require('supertest');
const app = require('../src/app');
const prisma = require('../src/config/db');
const { createAcademyTeam, createClass, enrollStudent } = require('./helpers/contractFixtures');

const describeWithDatabase = process.env.TEST_DATABASE_URL ? describe : describe.skip;
const api = (method, url, token) => request(app)[method](`/api/v2${url}`).set('Authorization', `Bearer ${token}`);

const jsonResponse = (body, status = 200) => ({ ok: status < 400, status, json: async () => body });

describeWithDatabase('Admin ML analytics (real records + genuine model outputs)', () => {
  jest.setTimeout(120000);
  const originalFetch = global.fetch;
  const originalEnv = { url: process.env.ML_SERVICE_URL, token: process.env.ML_INTERNAL_TOKEN };
  let T; let O; let cls; let quizId;

  beforeAll(async () => {
    T = await createAcademyTeam('Analytics');
    O = await createAcademyTeam('AnalyticsOther');
    cls = await createClass(T.tokens.admin, { className: 'Analytics 9', section: 'A', subject: 'Mathematics' });
    await enrollStudent(T.tokens.admin, cls.id, T.student.user.id);
    const quiz = await prisma.quiz.create({ data: {
      academyId: T.academy.id, classId: cls.id, classLabel: 'Analytics 9 - A', title: 'Unit test', subject: 'Mathematics',
      totalMarks: 50, testDate: new Date('2026-10-05T00:00:00Z'), createdById: T.teacher.user.id,
    } });
    quizId = quiz.id;
    const quiz2 = await prisma.quiz.create({ data: {
      academyId: T.academy.id, classId: cls.id, classLabel: 'Analytics 9 - A', title: 'Unit test 2', subject: 'Mathematics',
      totalMarks: 50, testDate: new Date('2026-11-02T00:00:00Z'), createdById: T.teacher.user.id,
    } });
    for (const [q, pct] of [[quiz.id, 40], [quiz2.id, 44]]) {
      await prisma.testMark.create({ data: {
        academyId: T.academy.id, quizId: q, studentId: T.student.user.id, studentName: T.student.user.fullName,
        classId: cls.id, subject: 'Mathematics', marksObtained: pct / 2, totalMarks: 50, percentage: pct, gradeLetter: 'F',
      } });
    }
    await prisma.feeChallan.createMany({ data: [
      { academyId: T.academy.id, challanNumber: `AN-${Date.now()}-1`, studentId: T.student.user.id, studentName: T.student.user.fullName,
        classLabel: 'Analytics 9 - A', issueDate: new Date('2026-10-01'), dueDate: new Date('2026-10-10'), monthlyFee: 3000, totalAmount: 3000,
        status: 'PAID', paidAt: new Date('2026-10-08'), billingPeriod: '2026-10' },
      { academyId: T.academy.id, challanNumber: `AN-${Date.now()}-2`, studentId: T.student.user.id, studentName: T.student.user.fullName,
        classLabel: 'Analytics 9 - A', issueDate: new Date('2026-11-01'), dueDate: new Date('2026-11-10'), monthlyFee: 3000, totalAmount: 3000,
        status: 'PENDING', billingPeriod: '2026-11' },
    ] });
  });
  afterAll(async () => {
    global.fetch = originalFetch;
    process.env.ML_SERVICE_URL = originalEnv.url; process.env.ML_INTERNAL_TOKEN = originalEnv.token;
    for (const t of [T, O]) await prisma.academy.delete({ where: { id: t.academy.id } }).catch(() => {});
  });

  const mockMl = (handler) => {
    process.env.ML_SERVICE_URL = 'http://ml.test';
    process.env.ML_INTERNAL_TOKEN = 'x'.repeat(40);
    jest.resetModules();
    global.fetch = jest.fn(async (url, options) => handler(new URL(url).pathname, options ? JSON.parse(options.body || '{}') : {}));
  };

  it('reports real aggregates and honest empty predictions when no model exists', async () => {
    mockMl((path) => jsonResponse(path === '/models/status'
      ? { fee_risk: { status: 'INSUFFICIENT_DATA', usable_records: 1, minimum_records: 100 },
          performance: { status: 'INSUFFICIENT_DATA', usable_records: 2, minimum_records: 100 } }
      : {}));
    const r = await api('get', '/admin/ml/analytics', T.tokens.admin);
    expect(r.statusCode).toBe(200);
    const d = r.body.data;
    expect(d.services.ml.ok).toBe(true);
    expect(d.performance.total_marks).toBe(2);
    expect(d.performance.trend).toEqual([
      { month: '2026-10', average: 40, count: 1, students: 1 },
      { month: '2026-11', average: 44, count: 1, students: 1 },
    ]);
    expect(d.performance.classes[0]).toMatchObject({ label: 'Analytics 9 - A', average: 42 });
    expect(d.revenue.months.map((m) => m.period)).toEqual(['2026-10', '2026-11']);
    expect(d.revenue.months[0]).toMatchObject({ billed: 3000, collected: 3000, collection_rate: 100 });
    expect(d.predictions.fee_risk.available).toBe(false);
    expect(d.predictions.performance.available).toBe(false);
    expect(d.models.fee_risk.status).toBe('INSUFFICIENT_DATA');
    // Rule-based at-risk student (average 42 < 50) is listed with its reason.
    expect(d.at_risk.students).toHaveLength(1);
    expect(d.at_risk.students[0].reasons[0]).toMatch(/below 50%/);
    expect(d.errors).toEqual({});
  });

  it('surfaces an unconfigured ML service per section instead of failing the dashboard', async () => {
    delete process.env.ML_SERVICE_URL; delete process.env.ML_INTERNAL_TOKEN;
    jest.resetModules();
    const r = await api('get', '/admin/ml/analytics', T.tokens.admin);
    expect(r.statusCode).toBe(200);
    expect(r.body.data.services.ml).toMatchObject({ configured: false, ok: false });
    expect(r.body.data.errors.ml_status).toMatch(/not configured/);
    expect(r.body.data.performance.total_marks).toBe(2);
    expect(r.body.data.models.fee_risk.status).toBe('NOT_READY');
  });

  it('uses genuine batch model outputs when a production model exists', async () => {
    const calls = [];
    mockMl((path, body) => {
      calls.push(path); console.log('DEBUG mock call', path, Date.now());
      if (path === '/models/status') {
        return jsonResponse({ fee_risk: { status: 'PRODUCTION', version: 'v-fee' }, performance: { status: 'PRODUCTION', version: 'v-perf' } });
      }
      if (path === '/predict/fee-risk/batch') {
        return jsonResponse({ version: 'v-fee', metrics: { roc_auc: 0.81 }, results: body.rows.map(() => ({ version: 'v-fee', probability: 0.8, risk_category: 'High Risk' })) });
      }
      if (path === '/predict/performance/batch') {
        return jsonResponse({ version: 'v-perf', metrics: { mae: 6.5 }, results: body.rows.map((row) => ({ version: 'v-perf', predicted_marks: row.prior_avg + 2 })) });
      }
      return jsonResponse({ detail: 'unknown' }, 404);
    });
    const r = await api('get', '/admin/ml/analytics', T.tokens.admin);
    expect(r.statusCode).toBe(200);
    const d = r.body.data;
    expect(d.predictions.fee_risk).toMatchObject({ available: true, version: 'v-fee', scored: 1, distribution: { 'High Risk': 1 } });
    expect(d.predictions.fee_risk.metrics.roc_auc).toBe(0.81);
    expect(d.predictions.performance.available).toBe(true);
    // Forecast from all marks: prior_avg 42 + 2; holdout: latest (44) predicted from the earlier mark (40 + 2).
    expect(d.predictions.performance.forecast[0]).toMatchObject({ subject: 'Mathematics', latest_actual: 44, predicted_next: 44 });
    expect(d.predictions.performance.holdout.rows[0]).toMatchObject({ actual: 44, predicted: 42 });
    expect(d.predictions.performance.holdout.mae).toBe(2);
    expect(d.performance.trend[1].predicted).toBe(42);
    // Model-based revenue expectation: 3000 outstanding × (1 − 0.8).
    expect(d.revenue.estimate.expected_on_time_model).toBe(600);
    expect(d.at_risk.students[0].reasons).toEqual(expect.arrayContaining([expect.stringMatching(/High fee-delay risk/)]));
    // Scoring went through the batch endpoints (one call per model use), not per-row calls.
    expect(calls.filter((c) => c === '/predict/fee-risk/batch')).toHaveLength(1);
    expect(calls.filter((c) => c === '/predict/performance/batch')).toHaveLength(2);
  });

  it('isolates tenants and validates filters', async () => {
    const calls2 = []; mockMl((p) => { calls2.push(p); return jsonResponse({ fee_risk: { status: 'NOT_READY' }, performance: { status: 'NOT_READY' } }); });
    const other = await api('get', '/admin/ml/analytics', O.tokens.admin); if (!other.body.data) console.log('DEBUG other', other.statusCode, other.text, JSON.stringify(calls2));
    expect(other.body.data.performance.total_marks).toBe(0);
    expect(other.body.data.revenue.months).toEqual([]);
    expect((await api('get', '/admin/ml/analytics?from=2026-13-01', T.tokens.admin)).statusCode).toBe(400);
    expect((await api('get', '/admin/ml/analytics?from=2026-11-01&to=2026-10-01', T.tokens.admin)).statusCode).toBe(400);
    expect((await api('get', `/admin/ml/analytics?sectionId=${O.academy.id}`, T.tokens.admin)).statusCode).toBe(404);
    expect((await api('get', '/admin/ml/analytics', T.tokens.teacher)).statusCode).toBe(403);
    const scoped = await api('get', '/admin/ml/analytics?from=2026-11-01&to=2026-11-30', T.tokens.admin);
    expect(scoped.body.data.performance.trend).toEqual([{ month: '2026-11', average: 44, count: 1, students: 1 }]);
    expect(scoped.body.data.revenue.months.map((m) => m.period)).toEqual(['2026-11']);
  });
});
