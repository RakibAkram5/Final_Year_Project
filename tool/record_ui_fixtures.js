#!/usr/bin/env node
/**
 * Records real API responses for the Flutter responsive-layout tests.
 *
 * Run against a LOCAL backend that was seeded with `prisma/seed.js` (plus any
 * extra long-named [TEST] records you want to exercise). Never point this at
 * production: the output is committed to test/fixtures.
 *
 *   node tool/record_ui_fixtures.js http://localhost:5055/api/v2 '<seed password>'
 *
 * Output: test/fixtures/ui_api_fixtures.json
 *   { "<role>": { "login": {...}, "GET /path": <data>, ... }, ... }
 * Path segments that are ids are recorded as ":id" so the Dart mock can match
 * any id.
 */
const fs = require('fs');
const path = require('path');

const base = process.argv[2] || 'http://localhost:5055/api/v2';
const password = process.argv[3];
if (!password) {
  console.error('Usage: node tool/record_ui_fixtures.js <apiBase> <seedPassword>');
  process.exit(1);
}
if (!/localhost|127\.0\.0\.1/.test(base)) {
  console.error('Refusing to record fixtures from a non-local API.');
  process.exit(1);
}

const roles = {
  admin: 'admin@demo.taleemplus',
  teacher: 'teacher@demo.taleemplus',
  student: 'student@demo.taleemplus',
  parent: 'parent@demo.taleemplus'
};

const call = async (method, url, token, body) => {
  const res = await fetch(`${base}${url}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {})
    },
    body: body ? JSON.stringify(body) : undefined
  });
  const json = await res.json().catch(() => ({}));
  return { status: res.status, data: json.data ?? json };
};

// Replace secrets that must never be committed.
const scrub = (value) => JSON.parse(JSON.stringify(value, (key, v) =>
  (/token|password|hash/i.test(key) && typeof v === 'string') ? 'redacted' : v));

(async () => {
  const out = {};
  for (const [role, email] of Object.entries(roles)) {
    const login = await call('POST', '/auth/login', null, { email, password });
    if (login.status !== 200) throw new Error(`${role} login failed: ${login.status}`);
    const token = login.data.tokens.accessToken;
    const me = (await call('GET', '/auth/me', token)).data;
    const rec = { login: scrub(login.data), 'GET /auth/me': me };

    const classes = (await call('GET', '/classes', token)).data || [];
    const classId = classes[0]?.id;
    const quizzes = (await call('GET', '/quizzes', token)).data || [];
    const studentId = role === 'student' ? me.id
      : role === 'parent' ? me.linkedChildren?.[0]?.id
        : classes.flatMap((c) => c.student_ids || [])[0];

    const gets = [
      ['/classes', '/classes'],
      ['/class-sections', '/class-sections'],
      ['/academic-structure', '/academic-structure'],
      ['/class-reports', '/class-reports'],
      ['/announcements', '/announcements'],
      ['/notifications', '/notifications'],
      ['/timetable', '/timetable'],
      ['/attendance', '/attendance'],
      ['/quizzes', '/quizzes'],
      ['/resources', '/resources'],
      ['/queries', '/queries'],
      ['/ocr', '/ocr'],
      ['/fees/payment-settings', '/fees/payment-settings'],
      ['/fees/challans', '/fees/challans'],
      ['/fees/ledger/stats', '/fees/ledger/stats'],
      ['/fees/payment-proofs/pending', '/fees/payment-proofs/pending'],
      ['/users/pending', '/users/pending'],
      ['/users/directory', '/users/directory'],
      ['/users/by-role', '/users/by-role?role=student'],
      ['/admin/ml/status', '/admin/ml/status'],
      ...(studentId ? [
        ['/attendance/student/:id', `/attendance/student/${studentId}`],
        ['/fees/challans/student/:id', `/fees/challans/student/${studentId}`],
        ['/quizzes/marks/student/:id', `/quizzes/marks/student/${studentId}`]
      ] : []),
      ...(classId ? [
        ['/quizzes/marks/class/:id', `/quizzes/marks/class/${classId}`],
        ['/attendance/class', `/attendance/class?classId=${classId}&logDate=${new Date().toISOString().slice(0, 10)}`]
      ] : []),
      ...(quizzes[0] ? [
        ['/quizzes/:id', `/quizzes/${quizzes[0].id}`],
        ['/quizzes/marks/quiz/:id', `/quizzes/marks/quiz/${quizzes[0].id}`]
      ] : [])
    ];
    for (const [key, url] of gets) {
      const r = await call('GET', url, token);
      if (r.status === 200) rec[`GET ${key}`] = scrub(r.data);
    }
    // Assignments and files (keyed by category so each list is realistic).
    const assignments = (await call('GET', '/assignments', token)).data || [];
    rec['GET /assignments'] = assignments;
    if (assignments[0] && (role === 'teacher' || role === 'admin')) {
      const subs = await call('GET', `/assignments/${assignments[0].id}/submissions`, token);
      if (subs.status === 200) rec['GET /assignments/:id/submissions'] = subs.data;
    }
    const resources = rec['GET /resources'] || [];
    const owners = {
      COURSE_MATERIAL: resources[0]?.id,
      ASSIGNMENT_INSTRUCTION: assignments[0]?.id,
      ASSIGNMENT_SUBMISSION: assignments[0]?.mySubmissions?.[0]?.id,
      STUDENT_DOCUMENT: studentId
    };
    for (const [category, ownerId] of Object.entries(owners)) {
      if (!ownerId) continue;
      const r = await call('GET', `/files?category=${category}&ownerId=${ownerId}`, token);
      if (r.status === 200) rec[`GET /files#${category}`] = r.data;
    }
    if (role === 'parent' && me.linkedChildren?.length) {
      const r = await call('POST', '/users/profiles', token, { ids: me.linkedChildren.map((c) => c.id) });
      rec['POST /users/profiles'] = r.data;
    }
    out[role] = rec;
    console.log(`${role}: ${Object.keys(rec).length} responses`);
  }
  const target = path.resolve(__dirname, '..', 'test', 'fixtures', 'ui_api_fixtures.json');
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, JSON.stringify(out, null, 1));
  console.log(`Wrote ${target}`);
})().catch((e) => { console.error(e); process.exit(1); });
