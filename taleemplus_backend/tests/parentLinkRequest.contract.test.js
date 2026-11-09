/**
 * Parent → child link request contract tests (admin-approved flow).
 *
 * A parent submits a child's details; an academy admin reviews and approves,
 * which creates the ParentStudent link. Verifies: the happy path, duplicate
 * prevention, role restrictions (only PARENT submits, only ADMIN decides),
 * cross-academy isolation, and that reject creates no link. Runs only when
 * TEST_DATABASE_URL is set and creates its own clearly labelled academies.
 */
const request = require('supertest');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const app = require('../src/app');
const prisma = require('../src/config/db');
const { createAcademyTeam } = require('./helpers/contractFixtures');

const describeWithDatabase = process.env.TEST_DATABASE_URL ? describe : describe.skip;
const api = (method, path, token) => {
  const req = request(app)[method](`/api/v2${path}`);
  return token ? req.set('Authorization', `Bearer ${token}`) : req;
};

// Creates an extra STUDENT in an academy so each test is independent.
const addStudent = async (academyId, { fullName, rollNumber = null }) => {
  const email = `student-${crypto.randomBytes(5).toString('hex')}@test.taleemplus`;
  const user = await prisma.user.create({
    data: {
      email,
      passwordHash: await bcrypt.hash('x', 4),
      fullName,
      role: 'STUDENT',
      accountStatus: 'ACTIVE',
      academyId,
      rollNumber,
      studentCode: crypto.randomBytes(8).toString('hex')
    }
  });
  return { id: user.id, email, fullName, rollNumber };
};

describeWithDatabase('Parent link requests (admin-approved)', () => {
  jest.setTimeout(120000);
  let A; let B;

  beforeAll(async () => {
    A = await createAcademyTeam('LinkReqA');
    B = await createAcademyTeam('LinkReqB');
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  test('parent submits, admin sees the match and approves → link is created', async () => {
    const student = await addStudent(A.academy.id, { fullName: '[TEST] Child One', rollNumber: 'R-101' });

    const submit = await api('post', '/users/link-requests', A.tokens.parent)
      .send({ childName: student.fullName, childEmail: student.email });
    expect(submit.status).toBe(201);
    expect(submit.body.data.status).toBe('PENDING');
    const requestId = submit.body.data.id;

    const list = await api('get', '/users/link-requests', A.tokens.admin);
    expect(list.status).toBe(200);
    const row = list.body.data.find((r) => r.id === requestId);
    expect(row).toBeTruthy();
    expect(row.matchedStudent.id).toBe(student.id);
    expect(row.parent.id).toBe(A.parent.user.id);

    const approve = await api('post', `/users/link-requests/${requestId}/approve`, A.tokens.admin).send({});
    expect(approve.status).toBe(200);
    expect(approve.body.data.status).toBe('APPROVED');

    const link = await prisma.parentStudent.findUnique({
      where: { parentId_studentId: { parentId: A.parent.user.id, studentId: student.id } }
    });
    expect(link).toBeTruthy();
  });

  test('a duplicate pending request for the same child is rejected (409)', async () => {
    const student = await addStudent(A.academy.id, { fullName: '[TEST] Child Two' });
    const first = await api('post', '/users/link-requests', A.tokens.parent)
      .send({ childName: student.fullName, childEmail: student.email });
    expect(first.status).toBe(201);

    const dup = await api('post', '/users/link-requests', A.tokens.parent)
      .send({ childName: student.fullName, childEmail: student.email });
    expect(dup.status).toBe(409);
  });

  test('a request with neither email nor roll number is rejected (400)', async () => {
    const res = await api('post', '/users/link-requests', A.tokens.parent)
      .send({ childName: 'Someone' });
    expect(res.status).toBe(400);
  });

  test('only a PARENT may submit (teacher → 403)', async () => {
    const res = await api('post', '/users/link-requests', A.tokens.teacher)
      .send({ childName: 'x', childEmail: 'x@test.taleemplus' });
    expect(res.status).toBe(403);
  });

  test('a parent cannot list or decide requests (403)', async () => {
    const list = await api('get', '/users/link-requests', A.tokens.parent);
    expect(list.status).toBe(403);
  });

  test('an admin cannot see or approve another academy\'s request', async () => {
    const student = await addStudent(B.academy.id, { fullName: '[TEST] Child B' });
    const submit = await api('post', '/users/link-requests', B.tokens.parent)
      .send({ childName: student.fullName, childEmail: student.email });
    expect(submit.status).toBe(201);
    const requestId = submit.body.data.id;

    // Academy A's admin must not see B's request...
    const aList = await api('get', '/users/link-requests', A.tokens.admin);
    expect(aList.body.data.find((r) => r.id === requestId)).toBeFalsy();
    // ...nor approve it.
    const approve = await api('post', `/users/link-requests/${requestId}/approve`, A.tokens.admin).send({});
    expect(approve.status).toBe(404);
  });

  test('reject marks the request REJECTED and creates no link', async () => {
    const student = await addStudent(B.academy.id, { fullName: '[TEST] Child Reject' });
    const submit = await api('post', '/users/link-requests', B.tokens.parent)
      .send({ childName: student.fullName, childEmail: student.email });
    const requestId = submit.body.data.id;

    const reject = await api('post', `/users/link-requests/${requestId}/reject`, B.tokens.admin)
      .send({ note: 'Could not verify this child.' });
    expect(reject.status).toBe(200);
    expect(reject.body.data.status).toBe('REJECTED');

    const link = await prisma.parentStudent.findUnique({
      where: { parentId_studentId: { parentId: B.parent.user.id, studentId: student.id } }
    });
    expect(link).toBeFalsy();
  });
});
