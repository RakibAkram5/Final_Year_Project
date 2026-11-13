/**
 * Bulk challan generation by class SECTION (the enrollment unit the admin UI
 * uses). One challan per active student per billing period, duplicate-safe,
 * inactive students skipped, tenant-scoped. Runs only with TEST_DATABASE_URL.
 */
const request = require('supertest');
const app = require('../src/app');
const prisma = require('../src/config/db');
const { TEST_PASSWORD, createAcademyTeam } = require('./helpers/contractFixtures');

const describeWithDatabase = process.env.TEST_DATABASE_URL ? describe : describe.skip;
const api = (method, path, token) => {
  const req = request(app)[method](`/api/v2${path}`);
  return token ? req.set('Authorization', `Bearer ${token}`) : req;
};

describeWithDatabase('bulk challan generation by section', () => {
  jest.setTimeout(120000);
  let A; let B; let sectionId; let second; let inactive;

  beforeAll(async () => {
    A = await createAcademyTeam('FeeA');
    B = await createAcademyTeam('FeeB');
    const sec = await api('post', '/class-sections', A.tokens.admin)
      .send({ className: 'Fee 9', program: '', section: 'F' });
    expect(sec.statusCode).toBe(201);
    sectionId = sec.body.data.id;
    const mk = async (label) => {
      const r = await api('post', '/users/create', A.tokens.admin).send({
        email: `${label}-${Date.now()}@test.taleemplus`, password: TEST_PASSWORD,
        fullName: `Fee ${label}`, role: 'student'
      });
      expect(r.statusCode).toBe(201);
      return r.body.data;
    };
    second = await mk('second');
    inactive = await mk('inactive');
    const roster = await api('put', `/class-sections/${sectionId}/enrollment`, A.tokens.admin)
      .send({ studentIds: [A.student.user.id, second.id, inactive.id] });
    expect(roster.statusCode).toBe(200);
    await prisma.user.update({ where: { id: inactive.id }, data: { accountStatus: 'INACTIVE' } });
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('creates one pending challan per active student, labelled with the section, and skips repeats', async () => {
    const body = { sectionId, monthlyFee: 2500, examFee: 500, dueDate: '2099-05-10', billingPeriod: '2099-05' };
    const first = await api('post', '/fees/challans/generate', A.tokens.admin).send(body);
    expect(first.statusCode).toBe(201);
    expect(first.body.meta.created).toBe(2);
    expect(first.body.meta.skipped_existing).toBe(1); // the inactive account
    const ids = first.body.data.map((c) => c.student_id).sort();
    expect(ids).toEqual([A.student.user.id, second.id].sort());
    expect(first.body.data[0].class_label).toBe('Fee 9 - F');
    expect(first.body.data[0].total_amount).toBe(3000);
    expect(first.body.data[0].status).toBe('pending');

    const again = await api('post', '/fees/challans/generate', A.tokens.admin).send(body);
    expect(again.statusCode).toBe(201);
    expect(again.body.meta).toMatchObject({ created: 0, skipped_existing: 3 });

    const all = await prisma.feeChallan.count({ where: { academyId: A.academy.id, billingPeriod: '2099-05' } });
    expect(all).toBe(2);
  });

  it('is tenant-scoped and validates input', async () => {
    const cross = await api('post', '/fees/challans/generate', B.tokens.admin)
      .send({ sectionId, monthlyFee: 100, dueDate: '2099-06-10' });
    expect(cross.statusCode).toBe(404);
    const missing = await api('post', '/fees/challans/generate', A.tokens.admin)
      .send({ monthlyFee: 100, dueDate: '2099-06-10' });
    expect(missing.statusCode).toBe(400);
    const teacher = await api('post', '/fees/challans/generate', A.tokens.teacher)
      .send({ sectionId, monthlyFee: 100, dueDate: '2099-06-10' });
    expect(teacher.statusCode).toBe(403);
  });
});
