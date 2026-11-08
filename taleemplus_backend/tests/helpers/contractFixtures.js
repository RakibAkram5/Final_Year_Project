const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const request = require('supertest');
const app = require('../../src/app');
const prisma = require('../../src/config/db');

const TEST_PASSWORD = 'ContractTest!7';

const suffix = () =>
  `${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;

const createAcademy = async (label) => {
  const unique = suffix();
  return prisma.academy.create({
    data: {
      code: `TST-${label}-${unique}`.slice(0, 50),
      name: `Contract ${label} Academy ${unique}`
    }
  });
};

const createUser = async ({ academyId, role, label }) => {
  const email = `${role.toLowerCase()}-${label}-${suffix()}@test.taleemplus`;
  const passwordHash = await bcrypt.hash(TEST_PASSWORD, 4);
  const user = await prisma.user.create({
    data: {
      email,
      passwordHash,
      fullName: `${label} ${role}`,
      role,
      accountStatus: 'ACTIVE',
      academyId,
      studentCode: role === 'STUDENT'
        ? crypto.randomBytes(8).toString('hex')
        : null
    }
  });
  return { user, email };
};

const login = async (email) => {
  const response = await request(app)
    .post('/api/v2/auth/login')
    .send({ email, password: TEST_PASSWORD });
  if (response.statusCode !== 200) {
    throw new Error(
      `Login failed for ${email}: ${response.statusCode} ${response.text}`
    );
  }
  return response.body.data;
};

const createAcademyTeam = async (label) => {
  const academy = await createAcademy(label);
  const admin = await createUser({ academyId: academy.id, role: 'ADMIN', label });
  const teacher = await createUser({ academyId: academy.id, role: 'TEACHER', label });
  const student = await createUser({ academyId: academy.id, role: 'STUDENT', label });
  const parent = await createUser({ academyId: academy.id, role: 'PARENT', label });

  return {
    academy,
    admin,
    teacher,
    student,
    parent,
    tokens: {
      admin: (await login(admin.email)).tokens.accessToken,
      teacher: (await login(teacher.email)).tokens.accessToken,
      student: (await login(student.email)).tokens.accessToken,
      parent: (await login(parent.email)).tokens.accessToken
    }
  };
};

const createClass = async (token, overrides = {}) => {
  const response = await request(app)
    .post('/api/v2/classes')
    .set('Authorization', `Bearer ${token}`)
    .send({
      className: overrides.className || 'Class 7',
      section: overrides.section || 'A',
      subject: overrides.subject || 'Mathematics',
      ...(overrides.primaryTeacherId ? { primaryTeacherId: overrides.primaryTeacherId } : {})
    });
  if (response.statusCode !== 201) {
    throw new Error(`Class creation failed: ${response.statusCode} ${response.text}`);
  }
  return response.body.data;
};

const enrollStudent = async (token, classId, studentId) => {
  const response = await request(app)
    .post(`/api/v2/classes/${classId}/enroll`)
    .set('Authorization', `Bearer ${token}`)
    .send({ studentId, rollNumber: '01' });
  if (response.statusCode !== 200) {
    throw new Error(`Enrollment failed: ${response.statusCode} ${response.text}`);
  }
  return response.body.data;
};

module.exports = {
  TEST_PASSWORD,
  createAcademyTeam,
  createClass,
  enrollStudent
};
