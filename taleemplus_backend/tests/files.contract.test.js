/**
 * File storage, course materials and assignments (Phase 7).
 * Uses the local storage driver in a temporary folder. Runs only when
 * TEST_DATABASE_URL is set; creates its own labelled academies.
 */
const os = require('os');
const path = require('path');
const fs = require('fs');

process.env.LOCAL_UPLOAD_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'tp-uploads-'));
process.env.STORAGE_DRIVER = 'local';

const request = require('supertest');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const app = require('../src/app');
const prisma = require('../src/config/db');
const { TEST_PASSWORD, createAcademyTeam, createClass, enrollStudent } =
  require('./helpers/contractFixtures');

const describeWithDatabase = process.env.TEST_DATABASE_URL ? describe : describe.skip;
const api = (method, url, token) => {
  const req = request(app)[method](`/api/v2${url}`);
  return token ? req.set('Authorization', `Bearer ${token}`) : req;
};
const upload = (url, token, bytes) =>
  api('post', url, token).set('Content-Type', 'application/octet-stream').send(bytes);

const PDF = Buffer.from('%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n');
const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(32, 1)]);
const DOCX = Buffer.concat([Buffer.from([0x50, 0x4b, 0x03, 0x04]), Buffer.from('....[Content_Types].xml....word/document.xml....')]);
const EXE = Buffer.concat([Buffer.from('MZ'), Buffer.alloc(64, 0)]);

const addUser = async (academyId, role, label) => {
  const email = `${role.toLowerCase()}-${label}-${crypto.randomBytes(4).toString('hex')}@test.taleemplus`;
  const user = await prisma.user.create({ data: {
    email, passwordHash: await bcrypt.hash(TEST_PASSWORD, 4), fullName: `[TEST] ${label}`,
    role, accountStatus: 'ACTIVE', academyId,
    studentCode: role === 'STUDENT' ? crypto.randomBytes(8).toString('hex') : null
  } });
  const login = await api('post', '/auth/login').send({ email, password: TEST_PASSWORD });
  return { user, token: login.body.data.tokens.accessToken };
};

describeWithDatabase('Files, course materials and assignments', () => {
  jest.setTimeout(120000);
  let A; let B; let cls; let otherCls; let otherTeacher; let outsider; let resource;

  beforeAll(async () => {
    A = await createAcademyTeam('Files');
    B = await createAcademyTeam('FilesOther');
    cls = await createClass(A.tokens.admin, { className: 'Files 9', section: 'F', primaryTeacherId: A.teacher.user.id });
    otherTeacher = await addUser(A.academy.id, 'TEACHER', 'otherteacher');
    otherCls = await createClass(A.tokens.admin, { className: 'Files 10', section: 'G', primaryTeacherId: otherTeacher.user.id });
    outsider = await addUser(A.academy.id, 'STUDENT', 'notenrolled');
    await enrollStudent(A.tokens.admin, cls.id, A.student.user.id);
    await api('post', '/users/link-child', A.tokens.admin)
      .send({ parentId: A.parent.user.id, studentId: A.student.user.id });
  });

  afterAll(async () => {
    for (const t of [A, B]) await prisma.academy.delete({ where: { id: t.academy.id } }).catch(() => {});
    fs.rmSync(process.env.LOCAL_UPLOAD_DIR, { recursive: true, force: true });
  });

  describe('course materials', () => {
    let fileId;

    it('only the class teacher (or admin) can share materials with a class', async () => {
      const denied = await api('post', '/resources', otherTeacher.token)
        .send({ classId: cls.id, title: 'Not my class', withAttachment: true });
      expect(denied.statusCode).toBe(403);
      const ok = await api('post', '/resources', A.tokens.teacher)
        .send({ classId: cls.id, title: 'Chapter 1 notes', withAttachment: true });
      expect(ok.statusCode).toBe(201);
      resource = ok.body.data;
    });

    it('uploads a PDF with a sanitised name and lists it on the resource', async () => {
      const r = await upload(`/files?category=COURSE_MATERIAL&ownerId=${resource.id}&filename=${encodeURIComponent('../../etc/Chapter 1.pdf')}`, A.tokens.teacher, PDF);
      expect(r.statusCode).toBe(201);
      expect(r.body.data.originalName).toBe('Chapter 1.pdf');
      expect(r.body.data.mimeType).toBe('application/pdf');
      fileId = r.body.data.id;
      const list = await api('get', `/resources?classId=${cls.id}`, A.tokens.student);
      expect(list.body.data.find((x) => x.id === resource.id).files.map((f) => f.id)).toEqual([fileId]);
    });

    it('enrolled student and linked parent can download the exact bytes', async () => {
      for (const token of [A.tokens.student, A.tokens.parent, A.tokens.admin]) {
        const r = await api('get', `/files/${fileId}/content`, token).buffer(true).parse((res, cb) => {
          const chunks = []; res.on('data', (c) => chunks.push(c)); res.on('end', () => cb(null, Buffer.concat(chunks)));
        });
        expect(r.statusCode).toBe(200);
        expect(r.headers['content-type']).toBe('application/pdf');
        expect(r.headers['cache-control']).toBe('private, no-store');
        expect(Buffer.compare(r.body, PDF)).toBe(0);
      }
    });

    it('unenrolled students, other academies and anonymous callers cannot read it', async () => {
      expect((await api('get', `/files/${fileId}/content`, outsider.token)).statusCode).toBe(404);
      expect((await api('get', `/files/${fileId}/content`, B.tokens.admin)).statusCode).toBe(404);
      expect((await api('get', `/files/${fileId}/content`)).statusCode).toBe(401);
      const foreignList = await api('get', `/resources?classId=${otherCls.id}`, A.tokens.student);
      expect(foreignList.statusCode).toBe(403);
    });

    it('rejects spoofed, disallowed and oversized files', async () => {
      const url = `/files?category=COURSE_MATERIAL&ownerId=${resource.id}`;
      expect((await upload(`${url}&filename=fake.pdf`, A.tokens.teacher, PNG)).statusCode).toBe(415);
      expect((await upload(`${url}&filename=setup.exe`, A.tokens.teacher, EXE)).statusCode).toBe(415);
      expect((await upload(`${url}&filename=virus.pdf`, A.tokens.teacher, EXE)).statusCode).toBe(415);
      const big = Buffer.concat([PDF, Buffer.alloc(4 * 1024 * 1024 + 10)]);
      expect((await upload(`${url}&filename=big.pdf`, A.tokens.teacher, big)).statusCode).toBe(413);
      expect((await upload(`${url}&filename=x.pdf`, A.tokens.student, PDF)).statusCode).toBe(403);
    });

    it('replacing gives a new file and removes the old one; other teachers cannot delete', async () => {
      const rep = await api('put', `/files/${fileId}/content?filename=Chapter%201%20v2.docx`, A.tokens.teacher)
        .set('Content-Type', 'application/octet-stream').send(DOCX);
      expect(rep.statusCode).toBe(200);
      expect(rep.body.data.originalName).toBe('Chapter 1 v2.docx');
      expect((await api('get', `/files/${fileId}/content`, A.tokens.admin)).statusCode).toBe(404);
      const newId = rep.body.data.id;
      expect((await api('delete', `/files/${newId}`, otherTeacher.token)).statusCode).toBe(404);
      expect((await api('delete', `/resources/${resource.id}`, otherTeacher.token)).statusCode).toBe(403);
      expect((await api('delete', `/resources/${resource.id}`, A.tokens.teacher)).statusCode).toBe(200);
      expect(await prisma.storedFile.count({ where: { ownerId: resource.id } })).toBe(0);
    });
  });

  describe('student and teacher documents', () => {
    it('admin uploads; the student and linked parent can read; teachers cannot', async () => {
      const r = await upload(`/files?category=STUDENT_DOCUMENT&ownerId=${A.student.user.id}&filename=admission.pdf`, A.tokens.admin, PDF);
      expect(r.statusCode).toBe(201);
      const id = r.body.data.id;
      expect((await api('get', `/files/${id}/content`, A.tokens.student)).statusCode).toBe(200);
      expect((await api('get', `/files/${id}/content`, A.tokens.parent)).statusCode).toBe(200);
      expect((await api('get', `/files/${id}/content`, A.tokens.teacher)).statusCode).toBe(404);
      expect((await api('get', `/files/${id}/content`, outsider.token)).statusCode).toBe(404);
      expect((await upload(`/files?category=STUDENT_DOCUMENT&ownerId=${A.student.user.id}&filename=x.pdf`, A.tokens.student, PDF)).statusCode).toBe(403);
    });

    it('teacher CVs are visible to admin and that teacher only', async () => {
      const r = await upload(`/files?category=TEACHER_DOCUMENT&ownerId=${A.teacher.user.id}&filename=cv.docx`, A.tokens.admin, DOCX);
      expect(r.statusCode).toBe(201);
      const id = r.body.data.id;
      expect((await api('get', `/files/${id}/content`, A.tokens.teacher)).statusCode).toBe(200);
      expect((await api('get', `/files/${id}/content`, otherTeacher.token)).statusCode).toBe(404);
      expect((await api('get', `/files?category=TEACHER_DOCUMENT&ownerId=${A.teacher.user.id}`, A.tokens.student)).statusCode).toBe(403);
    });
  });

  describe('assignments', () => {
    let assignment; let submission;
    const inOneWeek = () => new Date(Date.now() + 7 * 86400000).toISOString();

    it('only the class teacher creates assignments; instruction file attaches', async () => {
      const body = { classId: cls.id, title: 'Essay', dueAt: inOneWeek(), maxMarks: 20, allowResubmission: true };
      expect((await api('post', '/assignments', otherTeacher.token).send(body)).statusCode).toBe(403);
      const r = await api('post', '/assignments', A.tokens.teacher).send(body);
      expect(r.statusCode).toBe(201);
      assignment = r.body.data;
      const brief = await upload(`/files?category=ASSIGNMENT_INSTRUCTION&ownerId=${assignment.id}&filename=brief.pdf`, A.tokens.teacher, PDF);
      expect(brief.statusCode).toBe(201);
    });

    it('enrolled student submits and may replace before the deadline', async () => {
      expect((await api('post', `/assignments/${assignment.id}/submission`, outsider.token).send({})).statusCode).toBe(403);
      const s = await api('post', `/assignments/${assignment.id}/submission`, A.tokens.student).send({ note: 'My essay' });
      expect(s.statusCode).toBe(201);
      submission = s.body.data;
      const f = await upload(`/files?category=ASSIGNMENT_SUBMISSION&ownerId=${submission.id}&filename=essay.docx`, A.tokens.student, DOCX);
      expect(f.statusCode).toBe(201);
      const rep = await api('put', `/files/${f.body.data.id}/content?filename=essay-final.pdf`, A.tokens.student)
        .set('Content-Type', 'application/octet-stream').send(PDF);
      expect(rep.statusCode).toBe(200);
      // a classmate's file is invisible to others
      expect((await api('get', `/files/${rep.body.data.id}/content`, outsider.token)).statusCode).toBe(404);
      expect((await api('get', `/files/${rep.body.data.id}/content`, A.tokens.teacher)).statusCode).toBe(200);
    });

    it('lists status for the student and parent, counts for the teacher', async () => {
      const s = await api('get', `/assignments?classId=${cls.id}`, A.tokens.student);
      const mine = s.body.data.find((a) => a.id === assignment.id);
      expect(mine.instructionFileCount).toBe(1);
      expect(mine.mySubmissions[0].fileCount).toBe(1);
      const p = await api('get', '/assignments', A.tokens.parent);
      expect(p.body.data.find((a) => a.id === assignment.id).mySubmissions).toHaveLength(1);
      const t = await api('get', `/assignments/${assignment.id}/submissions`, A.tokens.teacher);
      expect(t.body.data.submissions).toHaveLength(1);
      expect(t.body.data.enrolledCount).toBe(1);
      expect((await api('get', `/assignments/${assignment.id}/submissions`, A.tokens.student)).statusCode).toBe(403);
    });

    it('validates marks against the maximum', async () => {
      const url = `/assignments/${assignment.id}/submissions/${submission.id}/grade`;
      expect((await api('put', url, A.tokens.teacher).send({ marks: 25 })).statusCode).toBe(400);
      expect((await api('put', url, A.tokens.teacher).send({ marks: -1 })).statusCode).toBe(400);
      const ok = await api('put', url, A.tokens.teacher).send({ marks: 18, feedback: 'Well argued' });
      expect(ok.statusCode).toBe(200);
      expect(ok.body.data.marks).toBe(18);
    });

    it('closes submissions after the deadline', async () => {
      await prisma.assignment.update({ where: { id: assignment.id }, data: { dueAt: new Date(Date.now() - 1000) } });
      expect((await api('post', `/assignments/${assignment.id}/submission`, A.tokens.student).send({})).statusCode).toBe(409);
      expect((await upload(`/files?category=ASSIGNMENT_SUBMISSION&ownerId=${submission.id}&filename=late.pdf`, A.tokens.student, PDF)).statusCode).toBe(403);
    });

    it('without resubmission a student gets exactly one upload', async () => {
      const a = (await api('post', '/assignments', A.tokens.teacher)
        .send({ classId: cls.id, title: 'One shot', dueAt: inOneWeek(), allowResubmission: false })).body.data;
      const s = (await api('post', `/assignments/${a.id}/submission`, A.tokens.student).send({})).body.data;
      const first = await upload(`/files?category=ASSIGNMENT_SUBMISSION&ownerId=${s.id}&filename=a.pdf`, A.tokens.student, PDF);
      expect(first.statusCode).toBe(201);
      expect((await upload(`/files?category=ASSIGNMENT_SUBMISSION&ownerId=${s.id}&filename=b.pdf`, A.tokens.student, PDF)).statusCode).toBe(403);
      expect((await api('post', `/assignments/${a.id}/submission`, A.tokens.student).send({})).statusCode).toBe(409);
    });
  });

  it('reports storage as unavailable instead of losing files when not configured', async () => {
    const prev = process.env.STORAGE_DRIVER;
    process.env.STORAGE_DRIVER = 'blob';
    const prevToken = process.env.BLOB_READ_WRITE_TOKEN;
    const prevStore = process.env.BLOB_STORE_ID;
    delete process.env.BLOB_READ_WRITE_TOKEN;
    delete process.env.BLOB_STORE_ID;
    try {
      const r = await upload(`/files?category=STUDENT_DOCUMENT&ownerId=${A.student.user.id}&filename=a.pdf`, A.tokens.admin, PDF);
      expect(r.statusCode).toBe(503);
      expect(r.body.code).toBe('STORAGE_UNAVAILABLE');
    } finally {
      process.env.STORAGE_DRIVER = prev;
      if (prevToken) process.env.BLOB_READ_WRITE_TOKEN = prevToken;
      if (prevStore) process.env.BLOB_STORE_ID = prevStore;
    }
  });
});
