/**
 * Regression tests for the security/availability defects found in the
 * 2026-11-13 audit (B3, B4, B9, B10, B11, B12).
 *
 * Runs only when TEST_DATABASE_URL is set (see tests/setupEnv.js). Creates
 * its own clearly-labelled academy and never touches other academies' rows.
 */
const request = require('supertest');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const app = require('../src/app');
const prisma = require('../src/config/db');
const {
  TEST_PASSWORD,
  createAcademyTeam,
  createClass,
  enrollStudent
} = require('./helpers/contractFixtures');

const describeWithDatabase = process.env.TEST_DATABASE_URL ? describe : describe.skip;
const api = (method, path, token) => {
  const req = request(app)[method](`/api/v2${path}`);
  return token ? req.set('Authorization', `Bearer ${token}`) : req;
};

const addUser = async (academyId, role, label) => {
  const email = `${role.toLowerCase()}-${label}-${crypto.randomBytes(4).toString('hex')}@test.taleemplus`;
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

describe('app hardening (no database)', () => {
  it('trusts exactly one proxy hop so req.ip is the real client behind Vercel (B9)', () => {
    expect(app.get('trust proxy')).toBe(1);
  });

  it('reports the backend version from package.json instead of a stale literal (B12)', async () => {
    const pkg = require('../package.json');
    const res = await request(app).get('/api/v2/version');
    expect(res.statusCode).toBe(200);
    expect(res.body.data.app_version).toBe(pkg.version);
    expect(res.body.data.release_date).toBe(pkg.releaseDate);
  });

  it('answers an expired access token with 401 + TOKEN_EXPIRED (B3)', async () => {
    const expired = jwt.sign(
      { userId: '00000000-0000-0000-0000-000000000000', role: 'ADMIN' },
      process.env.JWT_SECRET,
      { expiresIn: -10 }
    );
    const res = await request(app)
      .get('/api/v2/auth/me')
      .set('Authorization', `Bearer ${expired}`);
    expect(res.statusCode).toBe(401);
    expect(res.body.code).toBe('TOKEN_EXPIRED');
  });

  it('answers a malformed access token with 401 + UNAUTHENTICATED, never 403 (B3)', async () => {
    const res = await request(app)
      .get('/api/v2/auth/me')
      .set('Authorization', 'Bearer not-a-jwt');
    expect(res.statusCode).toBe(401);
    expect(res.body.code).toBe('UNAUTHENTICATED');
  });
});

describeWithDatabase('security regressions (database)', () => {
  jest.setTimeout(120000);
  let T;
  let otherTeacher;
  let cls;

  beforeAll(async () => {
    T = await createAcademyTeam('Sec');
    otherTeacher = await addUser(T.academy.id, 'TEACHER', 'other-teacher');
    cls = await createClass(T.tokens.admin, {
      className: 'Sec 10',
      section: 'S',
      primaryTeacherId: T.teacher.user.id
    });
    await enrollStudent(T.tokens.admin, cls.id, T.student.user.id);
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('a deactivated account gets 403 + ACCOUNT_INACTIVE (not a refreshable 401)', async () => {
    await prisma.user.update({ where: { id: T.student.user.id }, data: { accountStatus: 'INACTIVE' } });
    try {
      const res = await api('get', '/auth/me', T.tokens.student);
      expect(res.statusCode).toBe(403);
      expect(res.body.code).toBe('ACCOUNT_INACTIVE');
    } finally {
      await prisma.user.update({ where: { id: T.student.user.id }, data: { accountStatus: 'ACTIVE' } });
    }
  });

  describe('parent directory scoping (B4)', () => {
    it('a parent with no linked children sees NO students in the directory', async () => {
      const res = await api('get', '/users/directory?role=STUDENT', T.tokens.parent);
      expect(res.statusCode).toBe(200);
      expect(res.body.data).toEqual([]);
    });

    it('a linked parent sees only their own children, plus staff when unfiltered', async () => {
      await prisma.parentStudent.create({
        data: { parentId: T.parent.user.id, studentId: T.student.user.id }
      });
      // A second, unrelated student in the same academy must stay hidden.
      const stranger = await addUser(T.academy.id, 'STUDENT', 'stranger');

      const students = await api('get', '/users/directory?role=STUDENT', T.tokens.parent);
      expect(students.statusCode).toBe(200);
      expect(students.body.data.map((u) => u.id)).toEqual([T.student.user.id]);

      const all = await api('get', '/users/directory', T.tokens.parent);
      const ids = all.body.data.map((u) => u.id);
      expect(ids).toContain(T.admin.user.id);
      expect(ids).toContain(T.teacher.user.id);
      expect(ids).toContain(T.student.user.id);
      expect(ids).not.toContain(stranger.user.id);

      const parents = await api('get', '/users/directory?role=PARENT', T.tokens.parent);
      expect(parents.body.data.map((u) => u.id)).toEqual([T.parent.user.id]);

      // Admin and teacher views are unchanged (full roster).
      const adminView = await api('get', '/users/directory?role=STUDENT', T.tokens.admin);
      expect(adminView.body.data.map((u) => u.id)).toEqual(
        expect.arrayContaining([T.student.user.id, stranger.user.id])
      );
      const teacherView = await api('get', '/users/directory?role=STUDENT', T.tokens.teacher);
      expect(teacherView.body.data.map((u) => u.id)).toContain(stranger.user.id);
    });
  });

  describe('announcement ownership (B10)', () => {
    it('a teacher cannot edit or delete an admin announcement, but can manage their own', async () => {
      const adminPost = await api('post', '/announcements', T.tokens.admin)
        .send({ title: 'From admin', message: 'Holiday', targetRoles: ['all'] });
      expect(adminPost.statusCode).toBe(201);
      const adminId = adminPost.body.data.id;

      expect((await api('put', `/announcements/${adminId}`, T.tokens.teacher)
        .send({ message: 'Hijacked' })).statusCode).toBe(403);
      expect((await api('delete', `/announcements/${adminId}`, T.tokens.teacher)).statusCode).toBe(403);
      const still = await prisma.announcement.findUnique({ where: { id: adminId } });
      expect(still.message).toBe('Holiday');

      const teacherPost = await api('post', '/announcements', T.tokens.teacher)
        .send({ title: 'From teacher', message: 'Quiz Monday', targetRoles: ['student'] });
      expect(teacherPost.statusCode).toBe(201);
      const teacherId = teacherPost.body.data.id;
      expect((await api('put', `/announcements/${teacherId}`, otherTeacher.token)
        .send({ message: 'Not yours' })).statusCode).toBe(403);
      expect((await api('put', `/announcements/${teacherId}`, T.tokens.teacher)
        .send({ message: 'Quiz Tuesday' })).statusCode).toBe(200);
      expect((await api('delete', `/announcements/${teacherId}`, T.tokens.teacher)).statusCode).toBe(200);
      // Admin can still remove anything in the academy.
      expect((await api('delete', `/announcements/${adminId}`, T.tokens.admin)).statusCode).toBe(200);
    });
  });

  describe('query answer ownership (B10)', () => {
    it('only the class teacher or an admin may answer a student query', async () => {
      const q = await api('post', '/queries', T.tokens.student)
        .send({ classId: cls.id, question: 'When is the test?' });
      expect(q.statusCode).toBe(201);
      const id = q.body.data.id;

      const stranger = await api('put', `/queries/${id}/answer`, otherTeacher.token)
        .send({ answer: 'I do not teach you' });
      expect(stranger.statusCode).toBe(403);

      const owner = await api('put', `/queries/${id}/answer`, T.tokens.teacher)
        .send({ answer: 'Friday' });
      expect(owner.statusCode).toBe(200);
      expect(owner.body.data.answer).toBe('Friday');

      const q2 = await api('post', '/queries', T.tokens.student)
        .send({ classId: cls.id, question: 'Second question' });
      const admin = await api('put', `/queries/${q2.body.data.id}/answer`, T.tokens.admin)
        .send({ answer: 'Admin answer' });
      expect(admin.statusCode).toBe(200);
    });
  });

  describe('ML route limiter scope (B11)', () => {
    it('does not throttle prediction reads with the training limiter', async () => {
      // Without an ML service the controller answers with a non-429 status;
      // four rapid calls used to trip the 3/min training limiter.
      const statuses = [];
      for (let i = 0; i < 4; i += 1) {
        const r = await api('post', '/admin/ml/predict/fee-risk', T.tokens.admin).send({});
        statuses.push(r.statusCode);
      }
      expect(statuses).not.toContain(429);
    });

    it('still throttles training requests after three attempts in a minute', async () => {
      const statuses = [];
      for (let i = 0; i < 4; i += 1) {
        const r = await api('post', '/admin/ml/retrain', T.tokens.admin).send({});
        statuses.push(r.statusCode);
      }
      expect(statuses[3]).toBe(429);
    });
  });
});
