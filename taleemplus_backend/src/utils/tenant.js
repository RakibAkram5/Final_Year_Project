const prisma = require('../config/db');
const { forbidden, notFound } = require('./apiError');

const requireAcademy = (req) => {
  if (!req.academyId || typeof req.academyId !== 'string') {
    throw forbidden('An academy context is required for this request.');
  }
  return req.academyId;
};

const assertRole = (req, roles) => {
  const allowed = Array.isArray(roles) ? roles : [roles];
  if (!req.user || !allowed.includes(req.user.role)) {
    throw forbidden();
  }
  return req.user;
};

const assertEntityInAcademy = async (model, id, academyId) => {
  const delegate = prisma[model];
  if (!delegate || typeof delegate.findFirst !== 'function') {
    throw new Error(`Unknown tenant-scoped model: ${model}`);
  }
  const entity = await delegate.findFirst({ where: { id, academyId } });
  if (!entity) {
    throw notFound(`The requested ${model} was not found in this academy.`);
  }
  return entity;
};

const assertClassInAcademy = (classId, academyId) =>
  assertEntityInAcademy('class', classId, academyId);

const assertStudentInAcademy = async (studentId, academyId) => {
  const student = await prisma.user.findFirst({
    where: { id: studentId, academyId, role: 'STUDENT' }
  });
  if (!student) {
    throw notFound('The requested student was not found in this academy.');
  }
  return student;
};

const assertEnrolledStudent = async (classId, studentId, academyId) => {
  const student = await prisma.user.findFirst({
    where: { id: studentId, academyId, role: 'STUDENT' }
  });
  const enrollment = student
    ? await prisma.studentEnrollment.findUnique({
        where: { classId_studentId: { classId, studentId } }
      })
    : null;
  if (!student || !enrollment) {
    throw forbidden('The student is not enrolled in this class.');
  }
  return student;
};

module.exports = {
  requireAcademy,
  assertRole,
  assertEntityInAcademy,
  assertClassInAcademy,
  assertStudentInAcademy,
  assertEnrolledStudent
};
