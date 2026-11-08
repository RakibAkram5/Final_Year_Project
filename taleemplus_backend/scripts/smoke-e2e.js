#!/usr/bin/env node
/**
 * End-to-end smoke test against a RUNNING backend over real HTTP.
 *
 *   node scripts/smoke-e2e.js http://localhost:5055/api/v2
 *
 * Registers a fresh, clearly-labelled academy ("Smoke Test Academy <ts>")
 * and exercises every role's main flows. It never touches other academies.
 * Prints one line per check and exits 1 if any check fails.
 */
const BASE = (process.argv[2] || process.env.SMOKE_BASE_URL || 'http://localhost:5055/api/v2')
  .replace(/\/$/, '');
const stamp = Date.now();
const PASSWORD = 'SmokeTest!2026';
const results = [];

const call = async (method, path, { token, body } = {}) => {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {})
    },
    body: body ? JSON.stringify(body) : undefined
  });
  let json = null;
  try { json = await res.json(); } catch (_) { /* empty body */ }
  return { status: res.status, body: json, data: json && json.data };
};

const check = async (role, name, fn) => {
  try {
    const detail = await fn();
    results.push({ role, name, ok: true, detail: detail || '' });
    console.log(`PASS  [${role}] ${name}${detail ? ` — ${detail}` : ''}`);
  } catch (err) {
    results.push({ role, name, ok: false, detail: err.message });
    console.log(`FAIL  [${role}] ${name} — ${err.message}`);
  }
};

const expectStatus = (res, status, what) => {
  if (res.status !== status) {
    throw new Error(`${what}: expected ${status}, got ${res.status} ${JSON.stringify(res.body).slice(0, 200)}`);
  }
  return res;
};

(async () => {
  const health = await fetch(BASE.replace(/\/api\/v2$/, '') + '/health').then((r) => r.json());
  console.log(`Backend ${BASE} — health: ${health.status}, database: ${health.database}\n`);

  const tokens = {};
  const ids = {};
  const emails = {
    admin: `smoke-admin-${stamp}@test.taleemplus`,
    teacher: `smoke-teacher-${stamp}@test.taleemplus`,
    student: `smoke-student-${stamp}@test.taleemplus`,
    parent: `smoke-parent-${stamp}@test.taleemplus`
  };

  // ------------------------------------------------------------ ADMIN
  await check('admin', 'register academy + admin', async () => {
    const r = expectStatus(await call('POST', '/auth/register-admin', {
      body: { email: emails.admin, password: PASSWORD, fullName: 'Smoke Admin',
        academyName: `Smoke Test Academy ${stamp}`, academyAddress: '1 Test Road', academyPhone: '0300-0000000' }
    }), 201, 'register-admin');
    ids.academyCode = r.data.user.academyCode;
    return `code ${ids.academyCode}`;
  });
  await check('admin', 'login (real DB record)', async () => {
    const r = expectStatus(await call('POST', '/auth/login', { body: { email: emails.admin, password: PASSWORD } }), 200, 'login');
    tokens.admin = r.data.tokens.accessToken;
    tokens.adminRefresh = r.data.tokens.refreshToken;
    ids.admin = r.data.user.id;
  });
  await check('admin', 'invalid password rejected', async () => {
    expectStatus(await call('POST', '/auth/login', { body: { email: emails.admin, password: 'wrong-Pass1' } }), 401, 'bad login');
  });
  for (const role of ['teacher', 'student', 'parent']) {
    await check('admin', `create ${role} account`, async () => {
      const r = expectStatus(await call('POST', '/users/create', {
        token: tokens.admin,
        body: { email: emails[role], password: PASSWORD, fullName: `Smoke ${role}`, role,
          ...(role === 'student' ? { rollNumber: `S-${stamp}` } : {}),
          ...(role === 'teacher' ? { subject: 'Mathematics' } : {}) }
      }), 201, `create ${role}`);
      ids[role] = r.data.id;
    });
  }
  await check('admin', 'roll number persisted and uniqueness enforced', async () => {
    const r = expectStatus(await call('GET', `/users/roll-number-available?rollNumber=S-${stamp}`, { token: tokens.admin }), 200, 'roll check');
    if (r.data.available !== false) throw new Error('roll number reported available');
  });
  await check('admin', 'link parent to child', async () => {
    expectStatus(await call('POST', '/users/link-child', { token: tokens.admin, body: { parentId: ids.parent, studentId: ids.student } }), 200, 'link');
  });
  await check('admin', 'create section + class with teacher and student', async () => {
    const sec = expectStatus(await call('POST', '/class-sections', { token: tokens.admin, body: { className: 'Matric - Science', section: 'A' } }), 201, 'section');
    ids.section = sec.data.id;
    const cls = expectStatus(await call('POST', '/classes', { token: tokens.admin, body: {
      className: 'Matric - Science', section: 'A', subject: 'Mathematics',
      primaryTeacherId: ids.teacher, studentIds: [ids.student] } }), 201, 'class');
    ids.class = cls.data.id;
    if (!cls.data.student_ids.includes(ids.student)) throw new Error('student not enrolled');
  });
  await check('admin', 'edit class details', async () => {
    const r = expectStatus(await call('PUT', `/classes/${ids.class}`, { token: tokens.admin, body: { subject: 'Mathematics II' } }), 200, 'update class');
    if (r.data.subject !== 'Mathematics II') throw new Error('subject not saved');
  });
  await check('admin', 'timetable slot (today)', async () => {
    const day = ((new Date().getDay() + 6) % 7) + 1;
    expectStatus(await call('POST', '/timetable', { token: tokens.admin, body: {
      classId: ids.class, teacherId: ids.teacher, dayOfWeek: day, startTime: '09:00', endTime: '09:45', subject: 'Mathematics II' } }), 201, 'timetable');
  });
  await check('admin', 'announcement to students and parents', async () => {
    expectStatus(await call('POST', '/announcements', { token: tokens.admin, body: {
      title: 'Smoke notice', message: 'Hello', targetRoles: ['student', 'parent'] } }), 201, 'announcement');
  });
  await check('admin', 'fee challan (overdue) + ledger stats', async () => {
    const c = expectStatus(await call('POST', '/fees/challans', { token: tokens.admin, body: {
      studentId: ids.student, classLabel: 'Matric - Science - A', monthlyFee: 3000,
      dueDate: '2026-01-10', billingPeriod: '2026-01' } }), 201, 'challan');
    ids.challan = c.data.id;
    if (c.data.status !== 'overdue') throw new Error(`status ${c.data.status}`);
    const s = expectStatus(await call('GET', '/fees/ledger/stats', { token: tokens.admin }), 200, 'ledger');
    return `billed ${s.data.total_billed}, overdue ${s.data.total_overdue}`;
  });

  // ------------------------------------------------------------ TEACHER
  await check('teacher', 'login + /auth/me', async () => {
    const r = expectStatus(await call('POST', '/auth/login', { body: { email: emails.teacher, password: PASSWORD } }), 200, 'login');
    tokens.teacher = r.data.tokens.accessToken;
    expectStatus(await call('GET', '/auth/me', { token: tokens.teacher }), 200, 'me');
  });
  await check('teacher', 'sees own class and timetable', async () => {
    const classes = expectStatus(await call('GET', '/classes', { token: tokens.teacher }), 200, 'classes');
    if (!classes.data.some((c) => c.id === ids.class)) throw new Error('class missing');
    const tt = expectStatus(await call('GET', `/timetable?teacherId=${ids.teacher}`, { token: tokens.teacher }), 200, 'timetable');
    return `${tt.data.length} slot(s)`;
  });
  const today = new Date().toISOString().slice(0, 10);
  await check('teacher', 'mark attendance, re-save (no duplicate), reload', async () => {
    for (const status of ['absent', 'present']) {
      expectStatus(await call('POST', '/attendance/mark', { token: tokens.teacher, body: {
        classId: ids.class, logDate: today, records: [{ studentId: ids.student, status }] } }), 200, 'mark');
    }
    const r = expectStatus(await call('GET', `/attendance/class?classId=${ids.class}&logDate=${today}`, { token: tokens.teacher }), 200, 'reload');
    if (r.data.length !== 1 || r.data[0].status !== 'present') throw new Error(JSON.stringify(r.data));
  });
  await check('teacher', 'create quiz with metadata, enter marks', async () => {
    const q = expectStatus(await call('POST', '/quizzes', { token: tokens.teacher, body: {
      classId: ids.class, title: 'Smoke Quiz', subject: 'Mathematics II', totalMarks: 10,
      month: 'November', chapter: 'Ch 1', difficulty: 'Easy', testDate: new Date().toISOString(),
      questions: [{ text: 'Define a set.', type: 'short', marks: 10, grading_keywords: ['collection'] }] } }), 201, 'quiz');
    ids.quiz = q.data.id;
    expectStatus(await call('POST', '/quizzes/marks', { token: tokens.teacher, body: {
      quizId: ids.quiz, studentId: ids.student, marksObtained: 8 } }), 200, 'mark');
    const byQuiz = expectStatus(await call('GET', `/quizzes/marks/quiz/${ids.quiz}`, { token: tokens.teacher }), 200, 'marks by quiz');
    return `grade ${byQuiz.data[0].grade_letter}`;
  });
  await check('teacher', 'share resource and save OCR scan', async () => {
    expectStatus(await call('POST', '/resources', { token: tokens.teacher, body: {
      classId: ids.class, title: 'Chapter 1 notes', contentText: 'Sets are collections.' } }), 201, 'resource');
    expectStatus(await call('POST', '/ocr', { token: tokens.teacher, body: { title: 'Scan', extractedText: 'OCR text' } }), 201, 'ocr');
  });
  await check('teacher', 'cannot reach admin-only endpoints', async () => {
    expectStatus(await call('GET', '/fees/challans', { token: tokens.teacher }), 403, 'fees');
    expectStatus(await call('POST', '/users/create', { token: tokens.teacher, body: {} }), 403, 'create user');
  });

  // ------------------------------------------------------------ STUDENT
  await check('student', 'login + dashboard data', async () => {
    const r = expectStatus(await call('POST', '/auth/login', { body: { email: emails.student, password: PASSWORD } }), 200, 'login');
    tokens.student = r.data.tokens.accessToken;
    const classes = expectStatus(await call('GET', '/classes', { token: tokens.student }), 200, 'classes');
    const att = expectStatus(await call('GET', `/attendance/student/${ids.student}`, { token: tokens.student }), 200, 'attendance');
    const marks = expectStatus(await call('GET', `/quizzes/marks/student/${ids.student}`, { token: tokens.student }), 200, 'marks');
    const fees = expectStatus(await call('GET', `/fees/challans/student/${ids.student}`, { token: tokens.student }), 200, 'fees');
    const notices = expectStatus(await call('GET', '/announcements', { token: tokens.student }), 200, 'announcements');
    return `${classes.data.length} class, ${att.data.length} attendance, ${marks.data.length} mark, ${fees.data.length} challan, ${notices.data.length} notice`;
  });
  await check('student', 'quiz list hides the answer key', async () => {
    const r = expectStatus(await call('GET', `/quizzes?classId=${ids.class}`, { token: tokens.student }), 200, 'quizzes');
    if (r.data[0].questions[0].grading_keywords) throw new Error('answer key exposed');
  });
  await check('student', 'ask a question, see resources', async () => {
    expectStatus(await call('POST', '/queries', { token: tokens.student, body: { classId: ids.class, question: 'What is a subset?' } }), 201, 'query');
    const res = expectStatus(await call('GET', `/resources?classId=${ids.class}`, { token: tokens.student }), 200, 'resources');
    return `${res.data.length} resource(s)`;
  });
  await check('teacher', 'answer the student question', async () => {
    const q = expectStatus(await call('GET', `/queries?classId=${ids.class}`, { token: tokens.teacher }), 200, 'queries');
    expectStatus(await call('PUT', `/queries/${q.data[0].id}/answer`, { token: tokens.teacher, body: { answer: 'A set inside another set.' } }), 200, 'answer');
  });
  await check('student', 'cannot read another student or admin data', async () => {
    expectStatus(await call('GET', '/fees/challans', { token: tokens.student }), 403, 'all challans');
    expectStatus(await call('GET', '/users/by-role?role=student', { token: tokens.student }), 403, 'by-role');
  });

  // ------------------------------------------------------------ PARENT
  await check('parent', 'login sees linked child', async () => {
    const r = expectStatus(await call('POST', '/auth/login', { body: { email: emails.parent, password: PASSWORD } }), 200, 'login');
    tokens.parent = r.data.tokens.accessToken;
    const me = expectStatus(await call('GET', '/auth/me', { token: tokens.parent }), 200, 'me');
    if (!me.data.linkedChildren.some((c) => c.id === ids.student)) throw new Error('child not linked');
    const profiles = expectStatus(await call('POST', '/users/profiles', { token: tokens.parent, body: { ids: [ids.student] } }), 200, 'profiles');
    return profiles.data[0].fullName;
  });
  await check('parent', "child's attendance, marks, fees, timetable", async () => {
    const att = expectStatus(await call('GET', '/attendance', { token: tokens.parent }), 200, 'attendance');
    expectStatus(await call('GET', `/quizzes/marks/student/${ids.student}`, { token: tokens.parent }), 200, 'marks');
    const fees = expectStatus(await call('GET', `/fees/challans/student/${ids.student}`, { token: tokens.parent }), 200, 'fees');
    const tt = expectStatus(await call('GET', `/timetable?classIds=${ids.class}`, { token: tokens.parent }), 200, 'timetable');
    return `${att.data.length} attendance, ${fees.data.length} challan (${fees.data[0] && fees.data[0].status}), ${tt.data.length} slot`;
  });
  await check('parent', 'cannot list other students', async () => {
    const r = expectStatus(await call('GET', '/users/by-role?role=student', { token: tokens.parent }), 200, 'by-role');
    if (r.data.some((u) => u.id !== ids.student)) throw new Error('foreign students listed');
  });

  // ------------------------------------------------------------ CLEANUP-FREE LIFECYCLE
  await check('admin', 'mark challan paid, deactivate + reactivate parent', async () => {
    const paid = expectStatus(await call('PUT', `/fees/challans/${ids.challan}/pay`, { token: tokens.admin }), 200, 'pay');
    if (paid.data.status !== 'paid') throw new Error('not paid');
    expectStatus(await call('PUT', `/users/${ids.parent}/deactivate`, { token: tokens.admin }), 200, 'deactivate');
    expectStatus(await call('POST', '/auth/login', { body: { email: emails.parent, password: PASSWORD } }), 403, 'inactive login');
    expectStatus(await call('PUT', `/users/${ids.parent}/reactivate`, { token: tokens.admin }), 200, 'reactivate');
  });
  await check('admin', 'session refresh + logout', async () => {
    const r = expectStatus(await call('POST', '/auth/refresh', { body: { refreshToken: tokens.adminRefresh } }), 200, 'refresh');
    expectStatus(await call('POST', '/auth/logout', { body: { refreshToken: r.data.refreshToken } }), 200, 'logout');
    expectStatus(await call('POST', '/auth/refresh', { body: { refreshToken: r.data.refreshToken } }), 403, 'refresh after logout');
  });

  const failed = results.filter((r) => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} checks passed.`);
  process.exit(failed.length ? 1 : 0);
})().catch((err) => {
  console.error('Smoke run aborted:', err.message);
  process.exit(1);
});
