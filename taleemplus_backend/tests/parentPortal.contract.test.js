/**
 * Parent Portal contract tests (Phase 5).
 *
 * Two parents in one academy: P1 is linked to two children (S1, S2), P2 to
 * S3 only. Verifies each parent sees exactly their own children's data,
 * cannot link themselves to other students, and that class rosters are not
 * leaked to students or parents. Runs only when TEST_DATABASE_URL is set and
 * creates its own clearly labelled academy.
 */
const request = require('supertest');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const app = require('../src/app');
const prisma = require('../src/config/db');
const { TEST_PASSWORD, createAcademyTeam, createClass, enrollStudent } =
  require('./helpers/contractFixtures');

const describeWithDatabase = process.env.TEST_DATABASE_URL ? describe : describe.skip;
const api = (method, path, token) => {
  const req = request(app)[method](`/api/v2${path}`);
  return token ? req.set('Authorization', `Bearer ${token}`) : req;
};

const addUser = async (academyId, role, label) => {
  const email = `${role.toLowerCase()}-${label.replace(/\W+/g, '').toLowerCase()}-${crypto.randomBytes(4).toString('hex')}@test.taleemplus`;
  const user = await prisma.user.create({
    data: {
      email,
      passwordHash: await bcrypt.hash(TEST_PASSWORD, 4),
      fullName: `[TEST] ${label}`,
      role,
      accountStatus: 'ACTIVE',
      academyId,
      studentCode: role === 'STUDENT' ? crypto.randomBytes(8).toString('hex') : null
    }
  });
  const login = await api('post', '/auth/login').send({ email, password: TEST_PASSWORD });
  return { user, token: login.body.data.tokens.accessToken };
};

describeWithDatabase('Parent portal: linked children, isolation, rosters', () => {
  jest.setTimeout(120000);
  let T; let S2; let S3; let P2; let cls; const today = new Date().toISOString().slice(0, 10);

  beforeAll(async () => {
    T = await createAcademyTeam('Parent');
    S2 = await addUser(T.academy.id, 'STUDENT', 'Second Child');
    S3 = await addUser(T.academy.id, 'STUDENT', 'Other Family Child');
    P2 = await addUser(T.academy.id, 'PARENT', 'Second Parent');
    cls = await createClass(T.tokens.admin, { className: 'Parent 8', section: 'P' });
    for (const s of [T.student.user, S2.user, S3.user]) {
      await enrollStudent(T.tokens.admin, cls.id, s.id).catch(async () => {
        // enrollStudent fixes roll 01; give later students unique rolls.
        await api('post', `/classes/${cls.id}/enroll`, T.tokens.admin)
          .send({ studentId: s.id, rollNumber: s.id.slice(0, 6) });
      });
    }
    for (const [parentId, studentId] of [
      [T.parent.user.id, T.student.user.id],
      [T.parent.user.id, S2.user.id],
      [P2.user.id, S3.user.id]
    ]) {
      const r = await api('post', '/users/link-child', T.tokens.admin).send({ parentId, studentId });
      expect(r.statusCode).toBe(200);
    }
    const mark = await api('post', '/attendance/mark', T.tokens.admin).send({
      classId: cls.id,
      logDate: today,
      records: [T.student.user, S2.user, S3.user].map((s) => ({ studentId: s.id, status: 'present' }))
    });
    expect(mark.statusCode).toBe(200);
  });

  afterAll(async () => {
    await prisma.academy.delete({ where: { id: T.academy.id } }).catch(() => {});
  });

  it('a parent with two children receives both, in /auth/me and /users/profiles', async () => {
    const me = await api('get', '/auth/me', T.tokens.parent);
    const ids = me.body.data.linkedChildren.map((c) => c.id).sort();
    expect(ids).toEqual([T.student.user.id, S2.user.id].sort());
    const profiles = await api('post', '/users/profiles', T.tokens.parent).send({ ids: [...ids, S3.user.id] });
    expect(profiles.body.data.map((p) => p.id).sort()).toEqual(ids);
  });

  it('a second parent only sees their own child', async () => {
    const me = await api('get', '/auth/me', P2.token);
    expect(me.body.data.linkedChildren.map((c) => c.id)).toEqual([S3.user.id]);
    const att = await api('get', '/attendance', P2.token);
    expect(att.body.data.length).toBeGreaterThan(0);
    expect(att.body.data.every((r) => r.student_id === S3.user.id)).toBe(true);
    for (const path of [
      `/attendance/student/${T.student.user.id}`,
      `/fees/challans/student/${T.student.user.id}`,
      `/quizzes/marks/student/${T.student.user.id}`,
      `/users/${T.student.user.id}`
    ]) {
      const r = await api('get', path, P2.token);
      expect([403, 404]).toContain(r.statusCode);
    }
  });

  it('parents cannot link themselves to students or search the student directory', async () => {
    const link = await api('post', '/users/link-child', P2.token).send({ studentId: T.student.user.id });
    expect(link.statusCode).toBe(403);
    const search = await api('get', '/users/search?role=STUDENT&q=test', P2.token);
    expect(search.statusCode).toBe(403);
    const me = await api('get', '/auth/me', P2.token);
    expect(me.body.data.linkedChildren.map((c) => c.id)).toEqual([S3.user.id]);
  });

  it('class rosters are limited to self (student) or linked children (parent)', async () => {
    const asParent = (await api('get', '/classes', P2.token)).body.data.find((c) => c.id === cls.id);
    expect(asParent.student_ids).toEqual([S3.user.id]);
    expect(Object.keys(asParent.student_names)).toEqual([S3.user.id]);
    expect(asParent.enrollment_count).toBe(3);

    const asStudent = (await api('get', '/classes', S2.token)).body.data.find((c) => c.id === cls.id);
    expect(asStudent.student_ids).toEqual([S2.user.id]);
    expect(asStudent.enrollment_count).toBe(3);

    const asAdmin = (await api('get', '/classes', T.tokens.admin)).body.data.find((c) => c.id === cls.id);
    expect(asAdmin.student_ids.length).toBe(3);
  });

  it('a parent can unlink their own child but nobody else\'s', async () => {
    const foreign = await api('delete', `/users/link-child/${S3.user.id}`, T.tokens.parent);
    expect(foreign.statusCode).toBe(404);
    const own = await api('delete', `/users/link-child/${S2.user.id}`, T.tokens.parent);
    expect(own.statusCode).toBe(200);
    const me = await api('get', '/auth/me', T.tokens.parent);
    expect(me.body.data.linkedChildren.map((c) => c.id)).toEqual([T.student.user.id]);
  });
});
