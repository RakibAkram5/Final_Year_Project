const request = require('supertest');
const app = require('../src/app');
const {
  createAcademyTeam,
  createClass,
  enrollStudent
} = require('./helpers/contractFixtures');

const describeWithDatabase = process.env.TEST_DATABASE_URL
  ? describe
  : describe.skip;

const auth = (token) => ({ Authorization: `Bearer ${token}` });

describeWithDatabase('API v2 contract foundation', () => {
  jest.setTimeout(60000);

  let academyA;
  let academyB;
  let classA;
  let classB;

  beforeAll(async () => {
    academyA = await createAcademyTeam('A');
    academyB = await createAcademyTeam('B');
    // Teachers may only mark attendance for classes they teach.
    classA = await createClass(academyA.tokens.admin, {
      primaryTeacherId: academyA.teacher.user.id
    });
    // Teachers may only share materials with classes they teach.
    classB = await createClass(academyB.tokens.admin, {
      primaryTeacherId: academyB.teacher.user.id
    });
    await enrollStudent(academyA.tokens.admin, classA.id, academyA.student.user.id);
    await enrollStudent(academyB.tokens.admin, classB.id, academyB.student.user.id);
  });

  it('mounts resources and queries at canonical v2 paths only', async () => {
    const resources = await request(app)
      .get('/api/v2/resources')
      .set(auth(academyA.tokens.teacher));
    const queries = await request(app)
      .get('/api/v2/queries')
      .set(auth(academyA.tokens.teacher));
    const doubled = await request(app)
      .get('/api/v2/resources/resources')
      .set(auth(academyA.tokens.teacher));

    expect(resources.statusCode).toBe(200);
    expect(Array.isArray(resources.body.data)).toBe(true);
    expect(queries.statusCode).toBe(200);
    expect(Array.isArray(queries.body.data)).toBe(true);
    expect(doubled.statusCode).toBe(404);
  });

  it('marks v1 responses as deprecated', async () => {
    const health = await request(app).get('/health');
    expect(health.headers.deprecation).toBeUndefined();
    const v1 = await request(app)
      .get('/api/v1/resources')
      .set(auth(academyA.tokens.teacher));
    expect(v1.statusCode).toBe(200);
    expect(v1.headers.deprecation).toBe('true');
  });

  it('isolates resources between two academies', async () => {
    const createA = await request(app)
      .post('/api/v2/resources')
      .set(auth(academyA.tokens.teacher))
      .send({
        classId: classA.id,
        title: 'Academy A notes',
        fileUrl: 'https://example.test/a.pdf'
      });
    const createB = await request(app)
      .post('/api/v2/resources')
      .set(auth(academyB.tokens.teacher))
      .send({
        classId: classB.id,
        title: 'Academy B notes',
        fileUrl: 'https://example.test/b.pdf'
      });

    expect(createA.statusCode).toBe(201);
    expect(createB.statusCode).toBe(201);

    const listA = await request(app)
      .get('/api/v2/resources')
      .set(auth(academyA.tokens.teacher));
    const listB = await request(app)
      .get('/api/v2/resources')
      .set(auth(academyB.tokens.teacher));

    expect(listA.body.data.map((item) => item.title)).toEqual(['Academy A notes']);
    expect(listB.body.data.map((item) => item.title)).toEqual(['Academy B notes']);
  });

  it('rejects a class ID from another academy', async () => {
    const response = await request(app)
      .post('/api/v2/resources')
      .set(auth(academyA.tokens.teacher))
      .send({
        classId: classB.id,
        title: 'Cross tenant write',
        fileUrl: 'https://example.test/x.pdf'
      });

    expect(response.statusCode).toBe(404);
    expect(response.body.code).toBe('NOT_FOUND');
  });

  it('enforces the role matrix for privileged endpoints', async () => {
    const studentCreatesResource = await request(app)
      .post('/api/v2/resources')
      .set(auth(academyA.tokens.student))
      .send({
        classId: classA.id,
        title: 'Not allowed',
        fileUrl: 'https://example.test/x.pdf'
      });
    const studentCreatesClass = await request(app)
      .post('/api/v2/classes')
      .set(auth(academyA.tokens.student))
      .send({ className: '8', section: 'A', subject: 'Science' });
    const teacherCreatesClass = await request(app)
      .post('/api/v2/classes')
      .set(auth(academyA.tokens.teacher))
      .send({ className: '8', section: 'A', subject: 'Science' });
    const studentReadsClassAttendance = await request(app)
      .get(`/api/v2/attendance/class?classId=${classA.id}&logDate=2026-01-05`)
      .set(auth(academyA.tokens.student));

    expect(studentCreatesResource.statusCode).toBe(403);
    expect(studentCreatesResource.body.code).toBe('FORBIDDEN');
    expect(studentCreatesClass.statusCode).toBe(403);
    expect(teacherCreatesClass.statusCode).toBe(403);
    expect(studentReadsClassAttendance.statusCode).toBe(403);
  });

  it('returns stable validation errors for invalid IDs, dates, and enums', async () => {
    const badId = await request(app)
      .get('/api/v2/attendance/class?classId=not-a-uuid&logDate=2026-01-05')
      .set(auth(academyA.tokens.teacher));
    const badDate = await request(app)
      .get(`/api/v2/attendance/class?classId=${classA.id}&logDate=2026-13-40`)
      .set(auth(academyA.tokens.teacher));
    const badEnum = await request(app)
      .post('/api/v2/attendance/mark')
      .set(auth(academyA.tokens.teacher))
      .send({
        classId: classA.id,
        logDate: '2026-01-05',
        records: [{ studentId: academyA.student.user.id, status: 'banana' }]
      });

    expect(badId.statusCode).toBe(400);
    expect(badId.body.code).toBe('VALIDATION_ERROR');
    expect(badId.body.details.some((item) => item.path === 'classId')).toBe(true);
    expect(badDate.statusCode).toBe(400);
    expect(badDate.body.details.some((item) => item.path === 'logDate')).toBe(true);
    expect(badEnum.statusCode).toBe(400);
    expect(badEnum.body.details.some((item) => item.path === 'records.0.status')).toBe(true);
  });

  it('rejects cross-tenant attendance reads and writes', async () => {
    const read = await request(app)
      .get(`/api/v2/attendance/class?classId=${classB.id}&logDate=2026-01-05`)
      .set(auth(academyA.tokens.teacher));
    const write = await request(app)
      .post('/api/v2/attendance/mark')
      .set(auth(academyA.tokens.teacher))
      .send({
        classId: classB.id,
        logDate: '2026-01-05',
        records: [{ studentId: academyB.student.user.id, status: 'present' }]
      });
    const studentHistory = await request(app)
      .get(`/api/v2/attendance/student/${academyB.student.user.id}`)
      .set(auth(academyA.tokens.teacher));

    expect(read.statusCode).toBe(404);
    expect(write.statusCode).toBe(404);
    expect(studentHistory.statusCode).toBe(404);
  });

  it('round-trips lowercase attendance status and denormalized student names', async () => {
    const mark = await request(app)
      .post('/api/v2/attendance/mark')
      .set(auth(academyA.tokens.teacher))
      .send({
        classId: classA.id,
        logDate: '2026-01-05',
        records: [{ studentId: academyA.student.user.id, status: 'present' }]
      });

    expect(mark.statusCode).toBe(200);
    expect(mark.body.data[0]).toMatchObject({
      class_id: classA.id,
      student_id: academyA.student.user.id,
      student_name: academyA.student.user.fullName,
      log_date: '2026-01-05',
      status: 'present'
    });
    expect(new Date(mark.body.data[0].recorded_at).toISOString())
      .toBe(mark.body.data[0].recorded_at);

    const update = await request(app)
      .post('/api/v2/attendance/mark')
      .set(auth(academyA.tokens.teacher))
      .send({
        classId: classA.id,
        logDate: '2026-01-05',
        records: [{ studentId: academyA.student.user.id, status: 'late' }]
      });
    expect(update.statusCode).toBe(200);

    const reload = await request(app)
      .get(`/api/v2/attendance/class?classId=${classA.id}&logDate=2026-01-05`)
      .set(auth(academyA.tokens.teacher));

    expect(reload.statusCode).toBe(200);
    expect(reload.body.data).toHaveLength(1);
    expect(reload.body.data[0]).toMatchObject({
      student_name: academyA.student.user.fullName,
      status: 'late'
    });
  });

  it('scopes student queries and prevents cross-tenant answers', async () => {
    const queryB = await request(app)
      .post('/api/v2/queries')
      .set(auth(academyB.tokens.student))
      .send({ classId: classB.id, question: 'Academy B question' });
    expect(queryB.statusCode).toBe(201);

    const crossTenantAnswer = await request(app)
      .put(`/api/v2/queries/${queryB.body.data.id}/answer`)
      .set(auth(academyA.tokens.teacher))
      .send({ answer: 'Cross tenant answer' });
    expect(crossTenantAnswer.statusCode).toBe(404);

    const ownAnswer = await request(app)
      .put(`/api/v2/queries/${queryB.body.data.id}/answer`)
      .set(auth(academyB.tokens.teacher))
      .send({ answer: 'Academy B answer' });
    expect(ownAnswer.statusCode).toBe(200);
    expect(ownAnswer.body.data).toMatchObject({
      student_id: academyB.student.user.id,
      answer: 'Academy B answer',
      is_resolved: true
    });

    const listB = await request(app)
      .get('/api/v2/queries')
      .set(auth(academyB.tokens.teacher));
    const listA = await request(app)
      .get('/api/v2/queries')
      .set(auth(academyA.tokens.teacher));

    expect(listB.body.data).toHaveLength(1);
    expect(listA.body.data).toHaveLength(0);
  });
});
