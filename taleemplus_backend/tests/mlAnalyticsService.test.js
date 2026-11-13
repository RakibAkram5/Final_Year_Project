const a = require('../src/services/mlAnalyticsService');

const cls = (className, section, classSectionId = 'sec-1', program = '') =>
  ({ className, section, program, classSectionId });
const mark = (studentId, subject, percentage, date, c = cls('9th', 'A'), studentName = `S ${studentId}`) =>
  ({ studentId, studentName, subject, percentage, updatedAt: new Date(date), quiz: { testDate: new Date(date), createdAt: new Date(date) }, class: c });

describe('ML analytics aggregation (real-record based)', () => {
  const marks = [
    mark('s1', 'Math', 80, '2026-09-10'), mark('s1', 'Math', 60, '2026-10-12'),
    mark('s2', 'Math', 40, '2026-09-10'), mark('s2', 'Math', 45, '2026-10-12'),
    mark('s3', 'Urdu', 90, '2026-10-20', cls('10th', 'B', 'sec-2')),
  ];

  it('builds a monthly trend from assessment dates', () => {
    expect(a.performanceTrend(marks)).toEqual([
      { month: '2026-09', average: 60, count: 2, students: 2 },
      { month: '2026-10', average: 65, count: 3, students: 3 },
    ]);
  });

  it('compares class sections and subjects', () => {
    expect(a.classComparison(marks)).toEqual([
      { sectionId: 'sec-1', label: '9th - A', average: 56.3, count: 4, students: 2 },
      { sectionId: 'sec-2', label: '10th - B', average: 90, count: 1, students: 1 },
    ]);
    expect(a.subjectComparison(marks).map((s) => s.subject)).toEqual(['Math', 'Urdu']);
  });

  it('returns empty aggregates (not placeholders) with no records', () => {
    expect(a.performanceTrend([])).toEqual([]);
    expect(a.classComparison([])).toEqual([]);
    expect(a.studentAverages([])).toEqual([]);
    expect(a.revenueByMonth([])).toEqual([]);
    const estimate = a.revenueEstimate([], [], null, new Date('2026-11-10'));
    expect(estimate.expected_collection_historical).toBeNull();
    expect(estimate.expected_on_time_model).toBeNull();
    expect(estimate.historical_collection_rate).toBeNull();
  });

  it('computes monthly revenue and a history-based estimate', () => {
    const now = new Date('2026-11-10T00:00:00Z');
    const challans = [
      { studentId: 's1', billingPeriod: '2026-10', dueDate: new Date('2026-10-10'), status: 'PAID', totalAmount: '1000' },
      { studentId: 's2', billingPeriod: '2026-10', dueDate: new Date('2026-10-10'), status: 'PENDING', totalAmount: '1000' },
      { studentId: 's1', billingPeriod: '2026-11', dueDate: new Date('2026-11-20'), status: 'PENDING', totalAmount: '1200' },
      { studentId: 's2', billingPeriod: '2026-11', dueDate: new Date('2026-11-20'), status: 'PAID', totalAmount: '1200' },
    ];
    const months = a.revenueByMonth(challans, now);
    expect(months).toEqual([
      expect.objectContaining({ period: '2026-10', billed: 2000, collected: 1000, overdue: 1000, pending: 0, collection_rate: 50 }),
      expect.objectContaining({ period: '2026-11', billed: 2400, collected: 1200, pending: 1200, overdue: 0, collection_rate: 50 }),
    ]);
    const estimate = a.revenueEstimate(months, challans, null, now);
    expect(estimate.historical_collection_rate).toBe(50);
    expect(estimate.outstanding_amount).toBe(2200);
    expect(estimate.expected_collection_historical).toBe(1100);
    expect(estimate.expected_on_time_model).toBeNull();
    // With model scores the expectation uses (1 - P(late)) per outstanding challan.
    const scores = new Map([['s1', { probability: 0.25 }], ['s2', { probability: 0.5 }]]);
    const withModel = a.revenueEstimate(months, challans, scores, now);
    expect(withModel.expected_on_time_model).toBe(1200 * 0.75 + 1000 * 0.5);
    expect(withModel.model_scored_challans).toBe(2);
  });

  it('orders mark groups chronologically for holdout checks', () => {
    const groups = a.markGroups(marks);
    const s1 = groups.find((g) => g.studentId === 's1');
    expect(s1.marks.map((m) => m.percentage)).toEqual([80, 60]);
    expect(a.featureRow([80], [{ status: 'PRESENT' }, { status: 'ABSENT' }])).toEqual({ prior_avg: 80, prior_count: 1, attendance_pct: 50 });
    expect(a.featureRow([80, 60], undefined).attendance_pct).toBeNull();
  });

  it('combines rule and model signals in the at-risk list', () => {
    const averages = a.studentAverages(marks);
    const list = a.atRiskStudents({
      averages,
      performanceForecast: [{ studentId: 's1', studentName: 'S s1', subject: 'Math', classLabel: '9th - A', predicted_next: 48 }],
      feeScores: new Map([['s3', { risk_category: 'High Risk', probability: 0.9, studentName: 'S s3', classLabel: '10th - B' }]]),
    });
    expect(list.map((s) => s.studentId).sort()).toEqual(['s1', 's2', 's3']);
    expect(list.find((s) => s.studentId === 's2').reasons[0]).toMatch(/below 50%/);
    expect(list.find((s) => s.studentId === 's1').predicted_min).toBe(48);
    expect(list.find((s) => s.studentId === 's3').fee_probability).toBe(0.9);
  });
});
