/**
 * Who may upload, read and delete files of each category.
 *
 * Every check is scoped to the caller's academy first; the owning record is
 * then loaded from the database (never trusted from the client) and the
 * caller's relationship to it is verified:
 *   ADMIN    – everything in their academy
 *   TEACHER  – classes they teach (primary teacher) and their own documents
 *   STUDENT  – classes they are enrolled in, their own documents/submissions
 *   PARENT   – the same as their linked children, read-only
 */
const prisma = require('../config/db');
const { DOCUMENT_TYPES, SUBMISSION_TYPES } = require('../utils/fileTypes');

const CATEGORIES = {
  COURSE_MATERIAL: { types: DOCUMENT_TYPES },
  ASSIGNMENT_INSTRUCTION: { types: DOCUMENT_TYPES },
  ASSIGNMENT_SUBMISSION: { types: SUBMISSION_TYPES },
  EXAM_DOCUMENT: { types: DOCUMENT_TYPES },
  STUDENT_DOCUMENT: { types: DOCUMENT_TYPES },
  TEACHER_DOCUMENT: { types: DOCUMENT_TYPES }
};

const linkedChildIds = async (req) =>
  (await prisma.parentStudent.findMany({
    where: { parentId: req.user.id, student: { academyId: req.academyId } },
    select: { studentId: true }
  })).map((l) => l.studentId);

const isEnrolled = async (classId, studentIds) =>
  studentIds.length > 0 &&
  Boolean(await prisma.studentEnrollment.findFirst({
    where: { classId, studentId: { in: studentIds } },
    select: { id: true }
  }));

/** Read access to class-scoped content (materials, assignment briefs). */
const canReadClass = async (req, cls) => {
  const { role, id } = req.user;
  if (role === 'ADMIN') return true;
  if (role === 'TEACHER') return cls.primaryTeacherId === id;
  if (role === 'STUDENT') return isEnrolled(cls.id, [id]);
  if (role === 'PARENT') return isEnrolled(cls.id, await linkedChildIds(req));
  return false;
};

const canManageClass = (req, cls) =>
  req.user.role === 'ADMIN' ||
  (req.user.role === 'TEACHER' && cls.primaryTeacherId === req.user.id);

const findClass = (classId, academyId) =>
  prisma.class.findFirst({ where: { id: classId, academyId } });

/**
 * Loads the record a file belongs to and returns
 * `{ canRead, canWrite, canDelete }` for the caller, or null if the owner
 * does not exist in the caller's academy.
 */
async function ownerPermissions(req, category, ownerId) {
  const academyId = req.academyId;
  const { role, id: userId } = req.user;

  switch (category) {
    case 'COURSE_MATERIAL': {
      const resource = await prisma.sharedResource.findFirst({
        where: { id: ownerId, academyId },
        include: { class: true }
      });
      if (!resource) return null;
      const manage = canManageClass(req, resource.class) ||
        (role === 'TEACHER' && resource.teacherId === userId);
      return { canRead: manage || await canReadClass(req, resource.class), canWrite: manage, canDelete: manage };
    }
    case 'ASSIGNMENT_INSTRUCTION': {
      const assignment = await prisma.assignment.findFirst({ where: { id: ownerId, academyId } });
      if (!assignment) return null;
      const cls = await findClass(assignment.classId, academyId);
      const manage = canManageClass(req, cls);
      return { canRead: manage || await canReadClass(req, cls), canWrite: manage, canDelete: manage };
    }
    case 'ASSIGNMENT_SUBMISSION': {
      const submission = await prisma.assignmentSubmission.findFirst({
        where: { id: ownerId, assignment: { academyId } },
        include: { assignment: true }
      });
      if (!submission) return null;
      const cls = await findClass(submission.assignment.classId, academyId);
      const staff = canManageClass(req, cls);
      const own = role === 'STUDENT' && submission.studentId === userId;
      const parent = role === 'PARENT' && (await linkedChildIds(req)).includes(submission.studentId);
      const beforeDeadline = submission.assignment.dueAt > new Date();
      const hasFile = await prisma.storedFile.count({
        where: { academyId, category: 'ASSIGNMENT_SUBMISSION', ownerId }
      }) > 0;
      // Before the deadline a student may upload; replacing/removing an
      // uploaded file additionally needs resubmission to be allowed.
      const open = beforeDeadline &&
        (submission.assignment.allowResubmission || !hasFile);
      return {
        canRead: staff || own || parent,
        canWrite: own && open,
        canDelete: own && open
      };
    }
    case 'EXAM_DOCUMENT': {
      const quiz = await prisma.quiz.findFirst({ where: { id: ownerId, academyId } });
      if (!quiz) return null;
      const cls = await findClass(quiz.classId, academyId);
      const manage = canManageClass(req, cls);
      return { canRead: manage, canWrite: manage, canDelete: manage };
    }
    case 'STUDENT_DOCUMENT': {
      const student = await prisma.user.findFirst({
        where: { id: ownerId, academyId, role: 'STUDENT' }, select: { id: true }
      });
      if (!student) return null;
      const admin = role === 'ADMIN';
      const self = role === 'STUDENT' && userId === ownerId;
      const parent = role === 'PARENT' && (await linkedChildIds(req)).includes(ownerId);
      return { canRead: admin || self || parent, canWrite: admin, canDelete: admin };
    }
    case 'TEACHER_DOCUMENT': {
      const teacher = await prisma.user.findFirst({
        where: { id: ownerId, academyId, role: 'TEACHER' }, select: { id: true }
      });
      if (!teacher) return null;
      const admin = role === 'ADMIN';
      return { canRead: admin || userId === ownerId, canWrite: admin, canDelete: admin };
    }
    default:
      return null;
  }
}

module.exports = { CATEGORIES, ownerPermissions, canReadClass, canManageClass, linkedChildIds };
