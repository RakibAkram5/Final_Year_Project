/**
 * Database-backed contract tests for the TaleemPlus repair work.
 *
 * Runs only when TEST_DATABASE_URL is set (see tests/setupEnv.js). Every
 * test creates its own clearly-labelled academies ("Contract A/B Academy
 * <timestamp>") and never reads or modifies other academies' rows.
 */
const request = require('supertest');
const app = require('../src/app');
const prisma = require('../src/config/db');
const {
  TEST_PASSWORD,
  createAcademyTeam,
  createClass,
  enrollStudent
} = require('./helpers/contractFixtures');

const describeWithDatabase = process.env.TEST_DATABASE_URL
  ? describe
  : describe.skip;

const auth = (token) => ({ Authorization: `Bearer ${token}` });
const api = (method, path, token) => {
  const req = request(app)[method](`/api/v2${path}`);
  return token ? req.set(auth(token)) : req;
};
const today = () => new Date().toISOString().slice(0, 10);

describeWithDatabase('Repair contract: auth, users, classes, attendance, fees, quizzes, modules', () => {
  jest.setTimeout(120000);

  let A;
  let B;
  let classA;
  let classB;

  beforeAll(async () => {
    A = await createAcademyTeam('A');
    B = await createAcademyTeam('B');
    classA = await createClass(A.tokens.admin, { className: 'Repair 9', section: 'R' });
    classB = await createClass(B.tokens.admin, { className: 'Repair 9', section: 'R' });
    await enrollStudent(A.tokens.admin, classA.id, A.student.user.id);
    await enrollStudent(B.tokens.admin, classB.id, B.student.user.id);
    // Assign A's teacher to classA so teacher-scoped checks are meaningful.
    const assigned = await api('put', `/classes/${classA.id}`, A.tokens.admin)
      .send({ primaryTeacherId: A.teacher.user.id });
    expect(assigned.statusCode).toBe(200);
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  // ---------------------------------------------------------------- Auth
  describe('authentication', () => {
    it('logs in with real DB records, case-insensitively, and serves /auth/me', async () => {
      const res = await api('post', '/auth/login')
        .send({ email: A.admin.email.toUpperCase(), password: TEST_PASSWORD });
      expect(res.statusCode).toBe(200);
      expect(res.body.data.user.academyId).toBe(A.academy.id);
      const me = await api('get', '/auth/me', res.body.data.tokens.accessToken);
      expect(me.statusCode).toBe(200);
      expect(me.body.data.email).toBe(A.admin.email);
      expect(me.body.data).not.toHaveProperty('passwordHash');
    });

    it('rejects invalid credentials with 401 and never leaks the hash', async () => {
      const res = await api('post', '/auth/login')
        .send({ email: A.teacher.email, password: 'Wrong-password-1' });
      expect(res.statusCode).toBe(401);
      expect(JSON.stringify(res.body)).not.toMatch(/\$2[aby]\$/);
    });

    it('issues unique tokens for back-to-back logins (no same-second collision)', async () => {
      const [one, two] = await Promise.all([
        api('post', '/auth/login').send({ email: A.student.email, password: TEST_PASSWORD }),
        api('post', '/auth/login').send({ email: A.student.email, password: TEST_PASSWORD })
      ]);
      expect(one.statusCode).toBe(200);
      expect(two.statusCode).toBe(200);
      expect(one.body.data.tokens.refreshToken).not.toBe(two.body.data.tokens.refreshToken);
    });

    it('rotates refresh tokens and revokes them on logout', async () => {
      const login = await api('post', '/auth/login')
        .send({ email: A.parent.email, password: TEST_PASSWORD });
      const { refreshToken } = login.body.data.tokens;
      const refreshed = await api('post', '/auth/refresh').send({ refreshToken });
      expect(refreshed.statusCode).toBe(200);
      // The old token was rotated away.
      const reuse = await api('post', '/auth/refresh').send({ refreshToken });
      expect(reuse.statusCode).toBe(403);
      const logout = await api('post', '/auth/logout')
        .send({ refreshToken: refreshed.body.data.refreshToken });
      expect(logout.statusCode).toBe(200);
      const afterLogout = await api('post', '/auth/refresh')
        .send({ refreshToken: refreshed.body.data.refreshToken });
      expect(afterLogout.statusCode).toBe(403);
    });

    it('locks an account after 5 failed attempts and blocks the correct password', async () => {
      const victim = await api('post', '/users/create', A.tokens.admin).send({
        email: `lock-${Date.now()}@test.taleemplus`,
        password: TEST_PASSWORD,
        fullName: 'Lockout Victim',
        role: 'teacher'
      });
      expect(victim.statusCode).toBe(201);
      const email = victim.body.data.email;
      const statuses = [];
      for (let i = 0; i < 5; i += 1) {
        const r = await api('post', '/auth/login').send({ email, password: 'Nope-12345' });
        statuses.push(r.statusCode);
      }
      expect(statuses.slice(0, 4)).toEqual([401, 401, 401, 401]);
      expect(statuses[4]).toBe(423);
      const locked = await api('post', '/auth/login').send({ email, password: TEST_PASSWORD });
      expect(locked.statusCode).toBe(423);
      expect(locked.body.code).toBe('ACCOUNT_LOCKED');
    });

    it('looks up academies by code and rejects unknown codes', async () => {
      const ok = await api('get', `/auth/academy-lookup?code=${encodeURIComponent(A.academy.code.toLowerCase())}`);
      expect(ok.statusCode).toBe(200);
      expect(ok.body.data).toEqual({ id: A.academy.id, name: A.academy.name, code: A.academy.code });
      const bad = await api('get', '/auth/academy-lookup?code=NOPE-404');
      expect(bad.statusCode).toBe(404);
    });

    it('resets a password through the security question and revokes sessions', async () => {
      const email = `recover-${Date.now()}@test.taleemplus`;
      const created = await api('post', '/users/create', A.tokens.admin)
        .send({ email, password: TEST_PASSWORD, fullName: 'Recover Me', role: 'parent' });
      expect(created.statusCode).toBe(201);
      const login = await api('post', '/auth/login').send({ email, password: TEST_PASSWORD });
      const token = login.body.data.tokens.accessToken;
      const set = await api('put', '/auth/security-question', token)
        .send({ question: 'First school?', answer: 'Model High' });
      expect(set.statusCode).toBe(200);

      const q = await api('get', `/auth/security-question?email=${encodeURIComponent(email)}`);
      expect(q.body.data.question).toBe('First school?');

      const wrong = await api('post', '/auth/reset-password')
        .send({ email, securityAnswer: 'wrong', newPassword: 'NewPassw0rd!x' });
      expect(wrong.statusCode).toBe(403);
      const reset = await api('post', '/auth/reset-password')
        .send({ email, securityAnswer: '  model high ', newPassword: 'NewPassw0rd!x' });
      expect(reset.statusCode).toBe(200);
      const oldRefresh = await api('post', '/auth/refresh')
        .send({ refreshToken: login.body.data.tokens.refreshToken });
      expect(oldRefresh.statusCode).toBe(403);
      const relogin = await api('post', '/auth/login').send({ email, password: 'NewPassw0rd!x' });
      expect(relogin.statusCode).toBe(200);
    });

    it('lets an admin reset a member password (same academy only)', async () => {
      const email = `adminreset-${Date.now()}@test.taleemplus`;
      const created = await api('post', '/users/create', A.tokens.admin)
        .send({ email, password: TEST_PASSWORD, fullName: 'Forgetful', role: 'student' });
      const id = created.body.data.id;
      const session = await api('post', '/auth/login').send({ email, password: TEST_PASSWORD });
      expect((await api('put', `/users/${id}/password`, B.tokens.admin)
        .send({ newPassword: 'Fresh-Passw0rd!' })).statusCode).toBe(404);
      expect((await api('put', `/users/${id}/password`, A.tokens.teacher)
        .send({ newPassword: 'Fresh-Passw0rd!' })).statusCode).toBe(403);
      expect((await api('put', `/users/${id}/password`, A.tokens.admin)
        .send({ newPassword: 'short' })).statusCode).toBe(400);
      expect((await api('put', `/users/${id}/password`, A.tokens.admin)
        .send({ newPassword: 'Fresh-Passw0rd!' })).statusCode).toBe(200);
      expect((await api('post', '/auth/refresh')
        .send({ refreshToken: session.body.data.tokens.refreshToken })).statusCode).toBe(403);
      expect((await api('post', '/auth/login')
        .send({ email, password: 'Fresh-Passw0rd!' })).statusCode).toBe(200);
    });

    it('refuses self-registration as ADMIN into an existing academy', async () => {
      const res = await api('post', '/auth/register-user').send({
        email: `sneaky-${Date.now()}@test.taleemplus`,
        password: TEST_PASSWORD,
        fullName: 'Sneaky',
        role: 'admin',
        academyCode: A.academy.code
      });
      expect(res.statusCode).toBe(400);
    });
  });

  // ---------------------------------------------------------------- Users
  describe('user management', () => {
    it('persists roll numbers and enforces per-academy uniqueness', async () => {
      const roll = `R-${Date.now()}`;
      const first = await api('post', '/users/create', A.tokens.admin).send({
        email: `roll1-${Date.now()}@test.taleemplus`, password: TEST_PASSWORD,
        fullName: 'Roll One', role: 'student', rollNumber: roll
      });
      expect(first.statusCode).toBe(201);
      expect(first.body.data.rollNumber).toBe(roll);

      const taken = await api('get', `/users/roll-number-available?rollNumber=${roll.toLowerCase()}`, A.tokens.admin);
      expect(taken.body.data.available).toBe(false);
      const self = await api('get', `/users/roll-number-available?rollNumber=${roll}&excludeId=${first.body.data.id}`, A.tokens.admin);
      expect(self.body.data.available).toBe(true);
      // Single-character roll numbers are checked too (old search ignored them).
      const one = await api('get', '/users/roll-number-available?rollNumber=7', A.tokens.admin);
      expect(one.statusCode).toBe(200);

      const dup = await api('post', '/users/create', A.tokens.admin).send({
        email: `roll2-${Date.now()}@test.taleemplus`, password: TEST_PASSWORD,
        fullName: 'Roll Two', role: 'student', rollNumber: roll
      });
      expect(dup.statusCode).toBe(409);
      // Same roll number in another academy is fine.
      const other = await api('get', `/users/roll-number-available?rollNumber=${roll}`, B.tokens.admin);
      expect(other.body.data.available).toBe(true);
    });

    it('updates another user profile and rejects cross-academy edits', async () => {
      const ok = await api('put', `/users/${A.teacher.user.id}`, A.tokens.admin)
        .send({ fullName: 'A Teacher Renamed', subject: 'Physics' });
      expect(ok.statusCode).toBe(200);
      expect(ok.body.data.subject).toBe('Physics');
      const cross = await api('put', `/users/${B.teacher.user.id}`, A.tokens.admin)
        .send({ fullName: 'Hijacked' });
      expect(cross.statusCode).toBe(404);
    });

    it('deactivates and reactivates accounts without deleting data', async () => {
      const email = `deact-${Date.now()}@test.taleemplus`;
      const created = await api('post', '/users/create', A.tokens.admin)
        .send({ email, password: TEST_PASSWORD, fullName: 'Deact Me', role: 'teacher' });
      const id = created.body.data.id;
      const session = await api('post', '/auth/login').send({ email, password: TEST_PASSWORD });

      expect((await api('put', `/users/${A.admin.user.id}/deactivate`, A.tokens.admin)).statusCode).toBe(400);
      expect((await api('put', `/users/${B.teacher.user.id}/deactivate`, A.tokens.admin)).statusCode).toBe(404);
      expect((await api('put', `/users/${id}/deactivate`, A.tokens.teacher)).statusCode).toBe(403);

      const off = await api('put', `/users/${id}/deactivate`, A.tokens.admin);
      expect(off.statusCode).toBe(200);
      expect(off.body.data.accountStatus).toBe('INACTIVE');

      const login = await api('post', '/auth/login').send({ email, password: TEST_PASSWORD });
      expect(login.statusCode).toBe(403);
      expect(login.body.code).toBe('ACCOUNT_INACTIVE');
      const oldToken = await api('get', '/auth/me', session.body.data.tokens.accessToken);
      expect(oldToken.statusCode).toBe(403);

      const row = await prisma.user.findUnique({ where: { id } });
      expect(row).not.toBeNull();

      const on = await api('put', `/users/${id}/reactivate`, A.tokens.admin);
      expect(on.statusCode).toBe(200);
      expect((await api('post', '/auth/login').send({ email, password: TEST_PASSWORD })).statusCode).toBe(200);
    });

    it('links and unlinks children; parents only see their own children', async () => {
      const link = await api('post', '/users/link-child', A.tokens.admin)
        .send({ parentId: A.parent.user.id, studentId: A.student.user.id });
      expect(link.statusCode).toBe(200);
      const crossLink = await api('post', '/users/link-child', A.tokens.admin)
        .send({ parentId: A.parent.user.id, studentId: B.student.user.id });
      expect(crossLink.statusCode).toBe(404);

      const profiles = await api('post', '/users/profiles', A.tokens.parent)
        .send({ ids: [A.student.user.id, B.student.user.id] });
      expect(profiles.statusCode).toBe(200);
      expect(profiles.body.data.map((u) => u.id)).toEqual([A.student.user.id]);

      const me = await api('get', '/auth/me', A.tokens.parent);
      expect(me.body.data.linkedChildren.map((c) => c.id)).toContain(A.student.user.id);

      // by-role: a parent must not enumerate every student in the academy.
      const extra = await api('post', '/users/create', A.tokens.admin).send({
        email: `unlinked-${Date.now()}@test.taleemplus`, password: TEST_PASSWORD,
        fullName: 'Unlinked Kid', role: 'student'
      });
      const students = await api('get', '/users/by-role?role=student', A.tokens.parent);
      expect(students.statusCode).toBe(200);
      const ids = students.body.data.map((u) => u.id);
      expect(ids).toContain(A.student.user.id);
      expect(ids).not.toContain(extra.body.data.id);
      expect(students.body.data[0]).not.toHaveProperty('accountStatus');

      const forbidden = await api('get', '/users/by-role?role=student', A.tokens.student);
      expect(forbidden.statusCode).toBe(403);

      const unlink = await api('delete', `/users/link-child/${A.student.user.id}?parentId=${A.parent.user.id}`, A.tokens.admin);
      expect(unlink.statusCode).toBe(200);
      const after = await api('post', '/users/profiles', A.tokens.parent)
        .send({ ids: [A.student.user.id] });
      expect(after.body.data).toEqual([]);
      // Relink for later tests.
      await api('post', '/users/link-child', A.tokens.admin)
        .send({ parentId: A.parent.user.id, studentId: A.student.user.id });
    });
  });

  // ---------------------------------------------------------------- Classes
  describe('classes and sections', () => {
    it('creates classes with students and blocks cross-academy students/teachers', async () => {
      const ok = await api('post', '/classes', A.tokens.admin).send({
        className: 'Repair 10', section: 'S', subject: 'Chemistry',
        primaryTeacherId: A.teacher.user.id, studentIds: [A.student.user.id]
      });
      expect(ok.statusCode).toBe(201);
      expect(ok.body.data.student_ids).toEqual([A.student.user.id]);

      const crossStudent = await api('post', '/classes', A.tokens.admin).send({
        className: 'Repair 10', section: 'T', subject: 'Chemistry', studentIds: [B.student.user.id]
      });
      expect(crossStudent.statusCode).toBe(403);
      const crossTeacher = await api('post', '/classes', A.tokens.admin).send({
        className: 'Repair 10', section: 'U', subject: 'Chemistry', primaryTeacherId: B.teacher.user.id
      });
      expect(crossTeacher.statusCode).toBe(403);
      const crossEnroll = await api('post', `/classes/${classA.id}/enroll`, A.tokens.admin)
        .send({ studentId: B.student.user.id });
      expect(crossEnroll.statusCode).toBe(403);
    });

    it('updates class details and unenrolls students', async () => {
      const created = await api('post', '/classes', A.tokens.admin).send({
        className: 'Repair 11', section: 'V', subject: 'Biology', studentIds: [A.student.user.id]
      });
      const id = created.body.data.id;
      const upd = await api('put', `/classes/${id}`, A.tokens.admin).send({ subject: 'Botany' });
      expect(upd.statusCode).toBe(200);
      expect(upd.body.data.subject).toBe('Botany');
      const un = await api('delete', `/classes/${id}/enroll/${A.student.user.id}`, A.tokens.admin);
      expect(un.statusCode).toBe(200);
      const list = await api('get', '/classes', A.tokens.admin);
      expect(list.body.data.find((c) => c.id === id).student_ids).toEqual([]);
    });

    it('manages sections, cascades enrollment, and generates server-side reports', async () => {
      const sec = await api('post', '/class-sections', A.tokens.admin)
        .send({ className: 'Repair 12', program: 'Pre-Eng', section: 'W' });
      expect(sec.statusCode).toBe(201);
      const sectionId = sec.body.data.id;
      const offering = await api('post', '/classes', A.tokens.admin).send({
        className: 'Repair 12', program: 'Pre-Eng', section: 'W', subject: 'Maths'
      });
      expect(offering.body.data.class_section_id).toBe(sectionId);

      const cross = await api('put', `/class-sections/${sectionId}/enrollment`, A.tokens.admin)
        .send({ studentIds: [B.student.user.id] });
      expect(cross.statusCode).toBe(403);

      const roster = await api('put', `/class-sections/${sectionId}/enrollment`, A.tokens.admin)
        .send({ studentIds: [A.student.user.id] });
      expect(roster.statusCode).toBe(200);
      const classes = await api('get', '/classes', A.tokens.admin);
      expect(classes.body.data.find((c) => c.id === offering.body.data.id).student_ids)
        .toEqual([A.student.user.id]);

      const report = await api('post', '/class-reports', A.tokens.admin)
        .send({ sectionId, logDate: today() });
      expect(report.statusCode).toBe(201);
      expect(report.body.data.class_label).toBe('Repair 12 - Pre-Eng - W');
      expect(report.body.data.total_students).toBe(1);
      const badDate = await api('post', '/class-reports', A.tokens.admin)
        .send({ sectionId, logDate: '08/11/2026' });
      expect(badDate.statusCode).toBe(400);
      const otherAcademy = await api('get', '/class-reports', B.tokens.admin);
      expect(otherAcademy.body.data.find((r) => r.id === report.body.data.id)).toBeUndefined();
    });

    it('stores the academic structure per academy', async () => {
      const structure = { levels: [{ name: 'Repair Level', groups: ['G1', 'G2'] }] };
      const put = await api('put', '/academic-structure', A.tokens.admin).send(structure);
      expect(put.statusCode).toBe(200);
      expect((await api('get', '/academic-structure', A.tokens.teacher)).body.data).toEqual(structure);
      expect((await api('get', '/academic-structure', B.tokens.admin)).body.data).not.toEqual(structure);
      expect((await api('put', '/academic-structure', A.tokens.teacher).send(structure)).statusCode).toBe(403);
      expect((await api('put', '/academic-structure', A.tokens.admin).send({ levels: 'x' })).statusCode).toBe(400);
    });
  });

  // ---------------------------------------------------------------- Attendance
  describe('attendance', () => {
    it('upserts without duplicates and feeds academy-wide analytics', async () => {
      const day = today();
      const mark = (status) => api('post', '/attendance/mark', A.tokens.teacher)
        .send({ classId: classA.id, logDate: day, records: [{ studentId: A.student.user.id, status }] });
      expect((await mark('absent')).statusCode).toBe(200);
      expect((await mark('present')).statusCode).toBe(200);

      const rows = await prisma.attendanceRecord.findMany({
        where: { classId: classA.id, studentId: A.student.user.id, logDate: day }
      });
      expect(rows).toHaveLength(1);
      expect(rows[0].status).toBe('PRESENT');

      const academy = await api('get', `/attendance?from=${day}&to=${day}`, A.tokens.admin);
      expect(academy.statusCode).toBe(200);
      expect(academy.body.data.some((r) => r.class_id === classA.id && r.status === 'present')).toBe(true);

      const parent = await api('get', '/attendance', A.tokens.parent);
      expect(parent.body.data.every((r) => r.student_id === A.student.user.id)).toBe(true);
      const studentHistory = await api('get', `/attendance/student/${A.student.user.id}`, A.tokens.student);
      expect(studentHistory.body.data.length).toBeGreaterThan(0);
      const otherStudent = await api('get', `/attendance/student/${A.student.user.id}`, B.tokens.student);
      expect(otherStudent.statusCode).not.toBe(200);
    });

    it('prevents a teacher from marking a class they do not teach', async () => {
      const otherTeacher = await api('post', '/users/create', A.tokens.admin).send({
        email: `t2-${Date.now()}@test.taleemplus`, password: TEST_PASSWORD, fullName: 'Other Teacher', role: 'teacher'
      });
      const login = await api('post', '/auth/login')
        .send({ email: otherTeacher.body.data.email, password: TEST_PASSWORD });
      const res = await api('post', '/attendance/mark', login.body.data.tokens.accessToken)
        .send({ classId: classA.id, logDate: today(), records: [{ studentId: A.student.user.id, status: 'absent' }] });
      expect(res.statusCode).toBe(403);
    });
  });

  // ---------------------------------------------------------------- Fees
  describe('fees and payments', () => {
    let overdue;
    it('creates challans with correct ISO dates and derives overdue status', async () => {
      const res = await api('post', '/fees/challans', A.tokens.admin).send({
        studentId: A.student.user.id, classLabel: 'Repair 9 - R',
        monthlyFee: 2500, fine: 100, dueDate: '2020-01-10', billingPeriod: '2020-01'
      });
      expect(res.statusCode).toBe(201);
      overdue = res.body.data;
      expect(overdue.due_date).toBe('2020-01-10T00:00:00.000Z');
      expect(overdue.status).toBe('overdue');
      expect(overdue.total_amount).toBe(2600);
      expect(typeof overdue.created_at).toBe('string');

      const dup = await api('post', '/fees/challans', A.tokens.admin).send({
        studentId: A.student.user.id, monthlyFee: 1, dueDate: '2020-01-15', billingPeriod: '2020-01'
      });
      expect(dup.statusCode).toBe(409);
      const cross = await api('post', '/fees/challans', A.tokens.admin).send({
        studentId: B.student.user.id, monthlyFee: 1, dueDate: '2020-01-15'
      });
      expect(cross.statusCode).toBe(404);
    });

    it('computes ledger stats with overdue amounts and monthly grouping', async () => {
      const stats = await api('get', '/fees/ledger/stats', A.tokens.admin);
      expect(stats.statusCode).toBe(200);
      expect(stats.body.data.overdue_count).toBeGreaterThanOrEqual(1);
      expect(stats.body.data.total_overdue).toBeGreaterThanOrEqual(2600);
      const jan = stats.body.data.monthly.find((m) => m.billing_period === '2020-01');
      expect(jan).toMatchObject({ billed: 2600, overdue: 2600 });
    });

    it('protects fee data by role and marks challans paid', async () => {
      expect((await api('get', '/fees/challans', A.tokens.parent)).statusCode).toBe(403);
      const own = await api('get', `/fees/challans/student/${A.student.user.id}`, A.tokens.parent);
      expect(own.statusCode).toBe(200);
      expect(own.body.data.map((c) => c.id)).toContain(overdue.id);
      const foreign = await api('get', `/fees/challans/student/${B.student.user.id}`, A.tokens.parent);
      expect(foreign.statusCode).toBe(403);

      const crossPay = await api('put', `/fees/challans/${overdue.id}/pay`, B.tokens.admin);
      expect(crossPay.statusCode).toBe(404);
      const paid = await api('put', `/fees/challans/${overdue.id}/pay`, A.tokens.admin);
      expect(paid.statusCode).toBe(200);
      expect(paid.body.data.status).toBe('paid');
      expect(typeof paid.body.data.paid_at).toBe('string');
    });

    it('bulk-generates challans for a class and skips existing periods', async () => {
      const body = { classId: classA.id, monthlyFee: 3000, dueDate: '2099-03-10', billingPeriod: '2099-03' };
      const first = await api('post', '/fees/challans/generate', A.tokens.admin).send(body);
      expect(first.statusCode).toBe(201);
      expect(first.body.meta.created).toBe(1);
      expect(first.body.data[0].status).toBe('pending');
      const again = await api('post', '/fees/challans/generate', A.tokens.admin).send(body);
      expect(again.body.meta).toMatchObject({ created: 0, skipped_existing: 1 });
    });
  });

  // ---------------------------------------------------------------- Quizzes
  describe('quizzes and marks', () => {
    let quiz;
    let otherTeacherToken;

    beforeAll(async () => {
      const t = await api('post', '/users/create', A.tokens.admin).send({
        email: `qt-${Date.now()}@test.taleemplus`, password: TEST_PASSWORD, fullName: 'Quiz Outsider', role: 'teacher'
      });
      otherTeacherToken = (await api('post', '/auth/login')
        .send({ email: t.body.data.email, password: TEST_PASSWORD })).body.data.tokens.accessToken;
    });

    it('creates and lists a quiz with full metadata and ISO dates', async () => {
      const res = await api('post', '/quizzes', A.tokens.teacher).send({
        classId: classA.id, title: 'Repair Quiz', subject: 'Maths', totalMarks: 20,
        month: 'November', session: '2026', chapter: 'Ch 3', difficulty: 'Hard',
        testDate: '2026-11-20T00:00:00.000Z', instructions: 'No calculators',
        questions: [{ text: 'Q1', type: 'short', marks: 2.6, grading_keywords: ['x'] }]
      });
      expect(res.statusCode).toBe(201);
      quiz = res.body.data;
      expect(quiz).toMatchObject({ month: 'November', session: '2026', chapter: 'Ch 3', difficulty: 'Hard' });
      expect(quiz.test_date).toBe('2026-11-20T00:00:00.000Z');
      expect(quiz.questions[0].marks).toBe(3);

      const list = await api('get', `/quizzes?classId=${classA.id}`, A.tokens.student);
      expect(list.statusCode).toBe(200);
      const listed = list.body.data.find((q) => q.id === quiz.id);
      expect(typeof listed.created_at).toBe('string');
      expect(listed.questions[0]).not.toHaveProperty('grading_keywords');
    });

    it('enforces quiz ownership for other teachers and other academies', async () => {
      expect((await api('get', `/quizzes/${quiz.id}`, otherTeacherToken)).statusCode).toBe(403);
      expect((await api('get', `/quizzes/${quiz.id}`, B.tokens.student)).statusCode).toBe(404);
      expect((await api('put', `/quizzes/${quiz.id}/questions`, otherTeacherToken)
        .send({ questions: [] })).statusCode).toBe(403);
      expect((await api('post', '/quizzes/marks', otherTeacherToken)
        .send({ quizId: quiz.id, studentId: A.student.user.id, marksObtained: 5 })).statusCode).toBe(403);
      expect((await api('delete', `/quizzes/${quiz.id}`, otherTeacherToken)).statusCode).toBe(403);
    });

    it('updates questions, saves marks, reads them every way, and deletes', async () => {
      const upd = await api('put', `/quizzes/${quiz.id}/questions`, A.tokens.teacher)
        .send({ questions: [{ text: 'Q1 new', type: 'short', marks: 20 }] });
      expect(upd.statusCode).toBe(200);
      expect(upd.body.data.questions[0].text).toBe('Q1 new');

      const tooMany = await api('post', '/quizzes/marks', A.tokens.teacher)
        .send({ quizId: quiz.id, studentId: A.student.user.id, marksObtained: 25 });
      expect(tooMany.statusCode).toBe(400);
      const saved = await api('post', '/quizzes/marks', A.tokens.teacher)
        .send({ quizId: quiz.id, studentId: A.student.user.id, marksObtained: 17 });
      expect(saved.statusCode).toBe(200);
      expect(saved.body.data).toMatchObject({ percentage: 85, grade_letter: 'A' });
      const markId = saved.body.data.id;

      for (const path of [`/quizzes/marks/quiz/${quiz.id}`, `/quizzes/marks/class/${classA.id}`, '/quizzes/marks/academy']) {
        const r = await api('get', path, A.tokens.teacher);
        expect(r.statusCode).toBe(200);
        expect(r.body.data.map((m) => m.id)).toContain(markId);
      }
      const parentView = await api('get', `/quizzes/marks/student/${A.student.user.id}`, A.tokens.parent);
      expect(parentView.body.data.map((m) => m.id)).toContain(markId);
      expect((await api('get', '/quizzes/marks/academy', A.tokens.student)).statusCode).toBe(403);

      expect((await api('delete', `/quizzes/marks/${markId}`, A.tokens.teacher)).statusCode).toBe(200);
      expect(await prisma.testMark.findUnique({ where: { id: markId } })).toBeNull();
      expect((await api('delete', `/quizzes/${quiz.id}`, A.tokens.teacher)).statusCode).toBe(200);
      expect((await api('get', `/quizzes/${quiz.id}`, A.tokens.teacher)).statusCode).toBe(404);
    });
  });

  // ---------------------------------------------------------------- Other modules
  describe('timetable, announcements, notifications, OCR', () => {
    it('serves timetable slots to the right roles only', async () => {
      const slot = await api('post', '/timetable', A.tokens.admin).send({
        classId: classA.id, teacherId: A.teacher.user.id, dayOfWeek: 1,
        startTime: '09:00', endTime: '09:40', subject: 'Maths'
      });
      expect(slot.statusCode).toBe(201);
      const student = await api('get', `/timetable?classIds=${classA.id}`, A.tokens.student);
      expect(student.body.data.map((s) => s.id)).toContain(slot.body.data.id);
      const teacher = await api('get', `/timetable?teacherId=${A.teacher.user.id}`, A.tokens.teacher);
      expect(teacher.body.data.map((s) => s.id)).toContain(slot.body.data.id);
      const other = await api('get', '/timetable', B.tokens.admin);
      expect(other.body.data.map((s) => s.id)).not.toContain(slot.body.data.id);
      expect((await api('post', '/timetable', A.tokens.teacher).send({})).statusCode).toBe(403);
      expect((await api('delete', `/timetable/${slot.body.data.id}`, A.tokens.admin)).statusCode).toBe(200);
    });

    it('targets announcements by role and allows update/delete', async () => {
      const created = await api('post', '/announcements', A.tokens.admin)
        .send({ title: 'Parents only', message: 'PTM Friday', targetRoles: ['parent'] });
      expect(created.statusCode).toBe(201);
      const id = created.body.data.id;
      const ids = async (token) => (await api('get', '/announcements', token)).body.data.map((a) => a.id);
      expect(await ids(A.tokens.parent)).toContain(id);
      expect(await ids(A.tokens.student)).not.toContain(id);
      expect(await ids(B.tokens.parent)).not.toContain(id);
      expect((await api('put', `/announcements/${id}`, A.tokens.admin)
        .send({ title: 'Parents only', message: 'PTM Saturday', targetRoles: ['parent'] })).statusCode).toBe(200);
      expect((await api('delete', `/announcements/${id}`, A.tokens.admin)).statusCode).toBe(200);
    });

    it('creates an approval notification and marks it read', async () => {
      const email = `pending-${Date.now()}@test.taleemplus`;
      const reg = await api('post', '/auth/register-user').send({
        email, password: TEST_PASSWORD, fullName: 'Pending Person', role: 'student', academyCode: A.academy.code
      });
      expect(reg.statusCode).toBe(201);
      const pendingLogin = await api('post', '/auth/login').send({ email, password: TEST_PASSWORD });
      expect(pendingLogin.statusCode).toBe(403);
      expect(pendingLogin.body.code).toBe('ACCOUNT_PENDING');

      expect((await api('put', `/users/${reg.body.data.user.id}/approve`, B.tokens.admin)).statusCode).toBe(404);
      expect((await api('put', `/users/${reg.body.data.user.id}/approve`, A.tokens.admin)).statusCode).toBe(200);
      const login = await api('post', '/auth/login').send({ email, password: TEST_PASSWORD });
      const token = login.body.data.tokens.accessToken;
      const list = await api('get', '/notifications', token);
      const note = list.body.data.find((n) => n.type === 'approval');
      expect(note).toBeDefined();
      expect((await api('put', `/notifications/${note.id}/read`, token)).statusCode).toBe(200);
    });

    it('keeps OCR documents private to their author', async () => {
      const saved = await api('post', '/ocr', A.tokens.teacher)
        .send({ title: 'Scan 1', extractedText: 'Photosynthesis is…' });
      expect(saved.statusCode).toBe(201);
      const id = saved.body.data.id;
      expect((await api('get', '/ocr', A.tokens.teacher)).body.data.map((d) => d.id)).toContain(id);
      expect((await api('get', `/ocr/${id}`, A.tokens.admin)).statusCode).toBe(404);
      expect((await api('put', `/ocr/${id}`, A.tokens.teacher)
        .send({ title: 'Scan 1b', extractedText: 'edited' })).statusCode).toBe(200);
      expect((await api('delete', `/ocr/${id}`, A.tokens.teacher)).statusCode).toBe(200);
      expect((await api('get', `/ocr/${id}`, A.tokens.teacher)).statusCode).toBe(404);
    });
  });
});
