const prisma = require('../config/db');
const { forbidden, notFound } = require('../utils/apiError');
const { sendSuccess } = require('../utils/response');
const { toIso } = require('../utils/dto');

/**
 * Serialises a class. [visibleStudentIds] limits the roster (ids, names, roll
 * numbers) to the students the caller may see: students and parents only get
 * themselves / their linked children, never the whole class list. The total
 * size is still exposed as enrollment_count.
 */
const formatClass = (entity, visibleStudentIds = null) => {
  const all = entity.enrollments || [];
  const enrollments = visibleStudentIds
    ? all.filter((e) => visibleStudentIds.has(e.studentId))
    : all;
  return formatClassRows(entity, enrollments, all.length);
};

const formatClassRows = (entity, enrollments, enrollmentCount) => ({
  enrollment_count: enrollmentCount,
  id: entity.id,
  academy_id: entity.academyId,
  class_name: entity.className,
  section: entity.section,
  subject: entity.subject,
  program: entity.program || '',
  class_section_id: entity.classSectionId,
  primary_teacher_id: entity.primaryTeacherId,
  primary_teacher_name: entity.primaryTeacher?.fullName || '',
  primary_teacher_email: entity.primaryTeacher?.email || '',
  student_ids: enrollments.map((enrollment) => enrollment.studentId),
  student_names: Object.fromEntries(
    enrollments.map((enrollment) => [
      enrollment.studentId,
      enrollment.student?.fullName || ''
    ])
  ),
  student_roll_numbers: Object.fromEntries(
    enrollments.map((enrollment) => [
      enrollment.studentId,
      enrollment.rollNumber || enrollment.student?.rollNumber || ''
    ])
  ),
  created_at: toIso(entity.createdAt),
  updated_at: toIso(entity.updatedAt)
});

const classInclude = {
  primaryTeacher: { select: { id: true, fullName: true, email: true } },
  enrollments: {
    include: {
      student: { select: { id: true, fullName: true, email: true, rollNumber: true } }
    }
  }
};

const getTenantFilter = async (req) => {
  if (req.user.role === 'TEACHER') {
    return { primaryTeacherId: req.user.id };
  }
  if (req.user.role === 'STUDENT') {
    return { enrollments: { some: { studentId: req.user.id } } };
  }
  if (req.user.role === 'PARENT') {
    const links = await prisma.parentStudent.findMany({
      where: { parentId: req.user.id },
      select: { studentId: true }
    });
    return { enrollments: { some: { studentId: { in: links.map((l) => l.studentId) } } } };
  }
  return {};
};

/** Students whose roster rows the caller may see; null = everyone. */
const visibleStudentIdsFor = async (req) => {
  if (req.user.role === 'STUDENT') return new Set([req.user.id]);
  if (req.user.role === 'PARENT') {
    const links = await prisma.parentStudent.findMany({
      where: { parentId: req.user.id },
      select: { studentId: true }
    });
    return new Set(links.map((l) => l.studentId));
  }
  return null;
};

const getClasses = async (req, res, next) => {
  try {
    const classes = await prisma.class.findMany({
      where: { academyId: req.academyId, ...(await getTenantFilter(req)) },
      include: classInclude,
      orderBy: [{ className: 'asc' }, { section: 'asc' }, { subject: 'asc' }]
    });
    const visible = await visibleStudentIdsFor(req);
    return sendSuccess(res, classes.map((c) => formatClass(c, visible)));
  } catch (err) {
    next(err);
  }
};

const validateTeacher = async (teacherId, academyId) => {
  if (!teacherId) return null;
  const teacher = await prisma.user.findFirst({
    where: { id: teacherId, academyId, role: 'TEACHER', accountStatus: 'ACTIVE' }
  });
  if (!teacher) throw forbidden('The selected teacher does not belong to this academy.');
  return teacher;
};

const ensureSection = async (tx, { academyId, className, section, program }) => {
  const normalizedProgram = program || '';
  return tx.classSection.upsert({
    where: {
      academyId_className_program_section: {
        academyId,
        className,
        program: normalizedProgram,
        section
      }
    },
    create: {
      academyId,
      className,
      program: normalizedProgram,
      section
    },
    update: {}
  });
};

const createClass = async (req, res, next) => {
  try {
    const { className, section, subject, primaryTeacherId, program, studentIds } = req.body;

    if (!className || !section || !subject) {
      return res.status(400).json({ success: false, message: 'Class name, section, and subject are required.' });
    }
    await validateTeacher(primaryTeacherId, req.academyId);

    let students = [];
    if (Array.isArray(studentIds) && studentIds.length) {
      students = await prisma.user.findMany({
        where: {
          id: { in: studentIds.map(String) },
          academyId: req.academyId,
          role: 'STUDENT',
          accountStatus: 'ACTIVE'
        },
        select: { id: true }
      });
      if (students.length !== new Set(studentIds.map(String)).size) {
        throw forbidden('One or more selected students do not belong to this academy.');
      }
    }

    const newClass = await prisma.$transaction(async (tx) => {
      const classSection = await ensureSection(tx, {
        academyId: req.academyId,
        className: String(className).trim(),
        section: String(section).trim(),
        program: program || ''
      });
      const created = await tx.class.create({
        data: {
          academyId: req.academyId,
          className: String(className).trim(),
          section: String(section).trim(),
          subject: String(subject).trim(),
          program: program || null,
          classSectionId: classSection.id,
          primaryTeacherId: primaryTeacherId || null
        }
      });
      if (students.length) {
        await tx.studentEnrollment.createMany({
          data: students.map((student) => ({ classId: created.id, studentId: student.id })),
          skipDuplicates: true
        });
      }
      return tx.class.findUnique({ where: { id: created.id }, include: classInclude });
    });

    return sendSuccess(res, formatClass(newClass), {
      status: 201,
      message: 'Class created successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const updateClass = async (req, res, next) => {
  try {
    const { id } = req.params;
    const existing = await prisma.class.findFirst({
      where: { id, academyId: req.academyId }
    });
    if (!existing) throw notFound('Class not found in academy.');

    const data = {};
    for (const field of ['className', 'section', 'subject']) {
      if (req.body[field] !== undefined) {
        if (!String(req.body[field]).trim()) {
          return res.status(400).json({ success: false, message: `${field} cannot be empty.` });
        }
        data[field] = String(req.body[field]).trim();
      }
    }
    if (req.body.program !== undefined) data.program = req.body.program || null;
    if (req.body.primaryTeacherId !== undefined) {
      await validateTeacher(req.body.primaryTeacherId, req.academyId);
      data.primaryTeacherId = req.body.primaryTeacherId || null;
    }
    if (!Object.keys(data).length) {
      return res.status(400).json({ success: false, message: 'No class fields provided.' });
    }

    if (data.className || data.section || data.program !== undefined) {
      const section = await ensureSection(prisma, {
        academyId: req.academyId,
        className: data.className || existing.className,
        section: data.section || existing.section,
        program: data.program !== undefined ? data.program : existing.program
      });
      data.classSectionId = section.id;
    }

    const updated = await prisma.class.update({
      where: { id },
      data,
      include: classInclude
    });
    return sendSuccess(res, formatClass(updated), {
      message: 'Class details updated successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const deleteClass = async (req, res, next) => {
  try {
    const { id } = req.params;
    const existing = await prisma.class.findFirst({
      where: { id, academyId: req.academyId }
    });
    if (!existing) throw notFound('Class not found in academy.');
    // Uploaded files are keyed by owner id (no FK), so remove them first.
    const { deleteFilesForOwner } = require('./fileController');
    const [resources, assignments] = await Promise.all([
      prisma.sharedResource.findMany({ where: { classId: id }, select: { id: true } }),
      prisma.assignment.findMany({
        where: { classId: id },
        select: { id: true, submissions: { select: { id: true } } }
      })
    ]);
    for (const r of resources) await deleteFilesForOwner(req.academyId, 'COURSE_MATERIAL', r.id);
    for (const a of assignments) {
      await deleteFilesForOwner(req.academyId, 'ASSIGNMENT_INSTRUCTION', a.id);
      for (const s of a.submissions) await deleteFilesForOwner(req.academyId, 'ASSIGNMENT_SUBMISSION', s.id);
    }
    await prisma.class.delete({ where: { id } });
    return sendSuccess(res, { deleted: true }, { message: 'Class deleted successfully.' });
  } catch (err) {
    next(err);
  }
};

const enrollStudent = async (req, res, next) => {
  try {
    const { id: classId } = req.params;
    const { studentId, rollNumber } = req.body;

    const classEntity = await prisma.class.findFirst({
      where: { id: classId, academyId: req.academyId }
    });
    if (!classEntity) throw notFound('Class not found in academy.');

    const student = await prisma.user.findFirst({
      where: { id: studentId, academyId: req.academyId, role: 'STUDENT' }
    });
    if (!student) throw forbidden('The selected student does not belong to this academy.');

    const enrollment = await prisma.$transaction(async (tx) => {
      const saved = await tx.studentEnrollment.upsert({
        where: { classId_studentId: { classId, studentId } },
        create: { classId, studentId, rollNumber: rollNumber || null },
        update: { rollNumber: rollNumber || undefined }
      });
      if (rollNumber && !student.rollNumber) {
        await tx.user.update({ where: { id: studentId }, data: { rollNumber } });
      }
      if (classEntity.classSectionId) {
        const duplicate = await tx.classSectionEnrollment.findFirst({
          where: {
            sectionId: classEntity.classSectionId,
            rollNumber: rollNumber || undefined,
            studentId: { not: studentId }
          }
        });
        if (duplicate && rollNumber) {
          throw forbidden('This roll number is already used in the section.');
        }
        await tx.classSectionEnrollment.upsert({
          where: {
            sectionId_studentId: {
              sectionId: classEntity.classSectionId,
              studentId
            }
          },
          create: {
            sectionId: classEntity.classSectionId,
            studentId,
            rollNumber: rollNumber || null
          },
          update: { rollNumber: rollNumber || undefined }
        });
      }
      return saved;
    });

    return sendSuccess(res, enrollment, {
      message: 'Student enrolled successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const unenrollStudent = async (req, res, next) => {
  try {
    const { id: classId, studentId } = req.params;
    const classEntity = await prisma.class.findFirst({
      where: { id: classId, academyId: req.academyId }
    });
    if (!classEntity) throw notFound('Class not found in academy.');
    const deleted = await prisma.studentEnrollment.deleteMany({
      where: { classId, studentId }
    });
    if (!deleted.count) throw notFound('Enrollment not found.');
    return sendSuccess(res, { removed: true }, {
      message: 'Student removed from the class.'
    });
  } catch (err) {
    next(err);
  }
};

module.exports = {
  getClasses,
  createClass,
  updateClass,
  deleteClass,
  enrollStudent,
  unenrollStudent
};
