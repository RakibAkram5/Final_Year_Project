/**
 * Excel exports (Phase 7G/9): verifies the workbook contents against data
 * created through the API, and the access rules.
 */
const request = require('supertest');
const ExcelJS = require('exceljs');
const app = require('../src/app');
const prisma = require('../src/config/db');
const { createAcademyTeam, createClass, enrollStudent } = require('./helpers/contractFixtures');

const describeWithDatabase = process.env.TEST_DATABASE_URL ? describe : describe.skip;
const api = (method, url, token) =>
  request(app)[method](`/api/v2${url}`).set('Authorization', `Bearer ${token}`);
const binary = (req) => req.buffer(true).parse((res, cb) => {
  const chunks = [];
  res.on('data', (c) => chunks.push(c));
  res.on('end', () => cb(null, Buffer.concat(chunks)));
});
const readBook = async (buf) => {
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(buf);
  return wb;
};
const rows = (sheet) => {
  const out = [];
  sheet.eachRow((row, i) => { if (i > 1) out.push(row.values.slice(1)); });
  return out;
};

describeWithDatabase('Excel reports', () => {
  jest.setTimeout(120000);
  let T; let O; let cls;

  beforeAll(async () => {
    T = await createAcademyTeam('Reports');
    O = await createAcademyTeam('ReportsOther');
    cls = await createClass(T.tokens.admin, { className: 'Rep 6', section: 'R', primaryTeacherId: T.teacher.user.id });
    await enrollStudent(T.tokens.admin, cls.id, T.student.user.id);
    for (const [logDate, status] of [['2026-10-01', 'present'], ['2026-10-02', 'absent'], ['2026-10-03', 'late']]) {
      const r = await api('post', '/attendance/mark', T.tokens.teacher)
        .send({ classId: cls.id, logDate, records: [{ studentId: T.student.user.id, status }] });
      expect(r.statusCode).toBe(200);
    }
    const quiz = await api('post', '/quizzes', T.tokens.teacher).send({
      classId: cls.id, title: 'Unit test 1', subject: 'Maths', totalMarks: 20,
      testDate: '2026-10-05T00:00:00.000Z', questions: [{ text: 'Q1', type: 'short', marks: 20 }]
    });
    expect(quiz.statusCode).toBe(201);
    const mark = await api('post', '/quizzes/marks', T.tokens.teacher)
      .send({ quizId: quiz.body.data.id, studentId: T.student.user.id, marksObtained: 15 });
    expect(mark.statusCode).toBe(200);
    const ch = await api('post', '/fees/challans', T.tokens.admin).send({
      studentId: T.student.user.id, classLabel: 'Rep 6 - R', monthlyFee: 3000,
      dueDate: '2026-10-10', billingPeriod: '2026-10'
    });
    expect(ch.statusCode).toBe(201);
  });

  afterAll(async () => {
    for (const t of [T, O]) await prisma.academy.delete({ where: { id: t.academy.id } }).catch(() => {});
  });

  it('attendance workbook has correct counts and percentage', async () => {
    const r = await binary(api('get', `/reports/attendance.xlsx?classId=${cls.id}&from=2026-10-01&to=2026-10-31`, T.tokens.teacher));
    expect(r.statusCode).toBe(200);
    expect(r.headers['content-type']).toContain('spreadsheetml');
    const wb = await readBook(r.body);
    const [summary] = rows(wb.getWorksheet('Summary'));
    // [roll, name, present, late, leave, absent, total, pct]
    expect(summary.slice(2)).toEqual([1, 1, 0, 1, 3, 66.7]);
    const daily = rows(wb.getWorksheet('Daily'))[0];
    expect(daily.slice(2)).toEqual(['PRESENT', 'ABSENT', 'LATE']);
  });

  it('results workbook carries marks, percentage and grade', async () => {
    const r = await binary(api('get', `/reports/results.xlsx?classId=${cls.id}`, T.tokens.teacher));
    expect(r.statusCode).toBe(200);
    const wb = await readBook(r.body);
    const [row] = rows(wb.getWorksheet('Results'));
    expect(row[0]).toBe('Unit test 1');
    expect(row[4]).toBe(15);
    expect(row[5]).toBe(20);
    expect(row[6]).toBe(75);
    expect(typeof row[7]).toBe('string');
    const [tot] = rows(wb.getWorksheet('Student totals'));
    expect(tot[4]).toBe(75);
  });

  it('fee workbook is admin-only and academy-scoped', async () => {
    expect((await api('get', '/reports/fees.xlsx', T.tokens.teacher)).statusCode).toBe(403);
    const r = await binary(api('get', '/reports/fees.xlsx?period=2026-10', T.tokens.admin));
    expect(r.statusCode).toBe(200);
    const list = rows((await readBook(r.body)).getWorksheet('Fee records'));
    expect(list).toHaveLength(1);
    expect(list[0][6]).toBe(3000);
    const other = await binary(api('get', '/reports/fees.xlsx?period=2026-10', O.tokens.admin));
    expect(rows((await readBook(other.body)).getWorksheet('Fee records'))).toHaveLength(0);
  });

  it('rejects other teachers, students, parents, other academies and bad input', async () => {
    const otherTeacherClass = await createClass(T.tokens.admin, { className: 'Rep 7', section: 'Q' });
    expect((await api('get', `/reports/attendance.xlsx?classId=${otherTeacherClass.id}`, T.tokens.teacher)).statusCode).toBe(403);
    expect((await api('get', `/reports/attendance.xlsx?classId=${cls.id}`, T.tokens.student)).statusCode).toBe(403);
    expect((await api('get', `/reports/results.xlsx?classId=${cls.id}`, T.tokens.parent)).statusCode).toBe(403);
    expect((await api('get', `/reports/results.xlsx?classId=${cls.id}`, O.tokens.admin)).statusCode).toBe(404);
    expect((await api('get', `/reports/attendance.xlsx?classId=${cls.id}&from=2026-02-30&to=2026-03-05`, T.tokens.admin)).statusCode).toBe(400);
  });
});

describeWithDatabase('Attendance date rules', () => {
  jest.setTimeout(60000);
  let T; let cls;
  beforeAll(async () => {
    T = await createAcademyTeam('AttDates');
    cls = await createClass(T.tokens.admin, { className: 'Att 1', section: 'D', primaryTeacherId: T.teacher.user.id });
    await enrollStudent(T.tokens.admin, cls.id, T.student.user.id);
  });
  afterAll(async () => {
    await prisma.academy.delete({ where: { id: T.academy.id } }).catch(() => {});
  });

  it('rejects future dates and keeps one record per student per day', async () => {
    const future = new Date(Date.now() + 5 * 86400000).toISOString().slice(0, 10);
    const today = new Date().toISOString().slice(0, 10);
    const mark = (logDate, status) => api('post', '/attendance/mark', T.tokens.teacher)
      .send({ classId: cls.id, logDate, records: [{ studentId: T.student.user.id, status }] });
    expect((await mark(future, 'present')).statusCode).toBe(400);
    expect((await mark(today, 'present')).statusCode).toBe(200);
    expect((await mark(today, 'absent')).statusCode).toBe(200); // correction
    const rows = await prisma.attendanceRecord.findMany({ where: { classId: cls.id, logDate: today } });
    expect(rows).toHaveLength(1);
    expect(rows[0].status).toBe('ABSENT');
  });
});
