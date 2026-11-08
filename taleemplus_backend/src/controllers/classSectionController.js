const prisma = require('../config/db');
const { forbidden, notFound } = require('../utils/apiError');
const { sendSuccess } = require('../utils/response');
const { toIso } = require('../utils/dto');

const formatSection = (section) => ({
  id: section.id,
  academy_id: section.academyId,
  class_name: section.className,
  program: section.program || '',
  section: section.section,
  student_ids: (section.enrollments || []).map((entry) => entry.studentId),
  student_names: Object.fromEntries(
    (section.enrollments || []).map((entry) => [
      entry.studentId,
      entry.student?.fullName || ''
    ])
  ),
  student_roll_numbers: Object.fromEntries(
    (section.enrollments || []).map((entry) => [
      entry.studentId,
      entry.rollNumber || entry.student?.rollNumber || ''
    ])
  ),
  created_at: toIso(section.createdAt),
  updated_at: toIso(section.updatedAt)
});

const include = {
  enrollments: {
    include: {
      student: { select: { id: true, fullName: true, email: true, rollNumber: true } }
    }
  }
};

const scopedWhere = async (req) => {
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

const getSections = async (req, res, next) => {
  try {
    const sections = await prisma.classSection.findMany({
      where: { academyId: req.academyId, ...(await scopedWhere(req)) },
      include,
      orderBy: [{ className: 'asc' }, { program: 'asc' }, { section: 'asc' }]
    });
    return sendSuccess(res, sections.map(formatSection));
  } catch (err) {
    next(err);
  }
};

const createSection = async (req, res, next) => {
  try {
    const { className, program, section, studentIds } = req.body;
    if (!className || !section) {
      return res.status(400).json({ success: false, message: 'className and section are required.' });
    }
    const created = await prisma.classSection.upsert({
      where: {
        academyId_className_program_section: {
          academyId: req.academyId,
          className: String(className).trim(),
          program: String(program || '').trim(),
          section: String(section).trim()
        }
      },
      create: {
        academyId: req.academyId,
        className: String(className).trim(),
        program: String(program || '').trim(),
        section: String(section).trim()
      },
      update: {}
    });

    if (Array.isArray(studentIds) && studentIds.length) {
      const students = await prisma.user.findMany({
        where: {
          id: { in: studentIds.map(String) },
          academyId: req.academyId,
          role: 'STUDENT'
        },
        select: { id: true }
      });
      if (students.length !== new Set(studentIds.map(String)).size) {
        throw forbidden('One or more selected students do not belong to this academy.');
      }
      const validIds = students.map((student) => student.id);
      await prisma.classSectionEnrollment.createMany({
        data: validIds.map((studentId) => ({
          sectionId: created.id,
          studentId
        })),
        skipDuplicates: true
      });
    }

    const detailed = await prisma.classSection.findUnique({
      where: { id: created.id },
      include
    });
    return sendSuccess(res, formatSection(detailed), {
      status: 201,
      message: 'Class section created successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const updateSection = async (req, res, next) => {
  try {
    const { id } = req.params;
    const existing = await prisma.classSection.findFirst({
      where: { id, academyId: req.academyId }
    });
    if (!existing) throw notFound('Class section not found in academy.');

    const data = {};
    if (req.body.className !== undefined) data.className = String(req.body.className).trim();
    if (req.body.section !== undefined) data.section = String(req.body.section).trim();
    if (req.body.program !== undefined) data.program = String(req.body.program || '').trim();
    if (!Object.keys(data).length) {
      return res.status(400).json({ success: false, message: 'No section fields provided.' });
    }

    const updated = await prisma.$transaction(async (tx) => {
      const saved = await tx.classSection.update({ where: { id }, data });
      await tx.class.updateMany({
        where: { academyId: req.academyId, classSectionId: id },
        data: {
          className: saved.className,
          section: saved.section,
          ...(data.program !== undefined ? { program: saved.program || null } : {})
        }
      });
      return tx.classSection.findUnique({ where: { id }, include });
    });
    return sendSuccess(res, formatSection(updated), {
      message: 'Class section updated successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const deleteSection = async (req, res, next) => {
  try {
    const { id } = req.params;
    const existing = await prisma.classSection.findFirst({
      where: { id, academyId: req.academyId }
    });
    if (!existing) throw notFound('Class section not found in academy.');
    await prisma.$transaction([
      prisma.class.updateMany({
        where: { classSectionId: id },
        data: { classSectionId: null }
      }),
      prisma.classSection.delete({ where: { id } })
    ]);
    return sendSuccess(res, { deleted: true }, {
      message: 'Class section deleted successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const enrollStudent = async (req, res, next) => {
  try {
    const { id: sectionId } = req.params;
    const { studentId, rollNumber } = req.body;
    const section = await prisma.classSection.findFirst({
      where: { id: sectionId, academyId: req.academyId }
    });
    if (!section) throw notFound('Class section not found in academy.');
    const student = await prisma.user.findFirst({
      where: { id: studentId, academyId: req.academyId, role: 'STUDENT' }
    });
    if (!student) throw forbidden('The selected student does not belong to this academy.');

    const enrollment = await prisma.$transaction(async (tx) => {
      if (rollNumber) {
        const duplicate = await tx.classSectionEnrollment.findFirst({
          where: { sectionId, rollNumber, studentId: { not: studentId } }
        });
        if (duplicate) throw forbidden('This roll number is already used in the section.');
      }
      const saved = await tx.classSectionEnrollment.upsert({
        where: { sectionId_studentId: { sectionId, studentId } },
        create: { sectionId, studentId, rollNumber: rollNumber || null },
        update: { rollNumber: rollNumber || undefined }
      });
      if (rollNumber && !student.rollNumber) {
        await tx.user.update({ where: { id: studentId }, data: { rollNumber } });
      }
      const offerings = await tx.class.findMany({
        where: { academyId: req.academyId, classSectionId: sectionId },
        select: { id: true }
      });
      if (offerings.length) {
        await tx.studentEnrollment.createMany({
          data: offerings.map((offering) => ({
            classId: offering.id,
            studentId,
            rollNumber: rollNumber || null
          })),
          skipDuplicates: true
        });
      }
      return saved;
    });

    return sendSuccess(res, enrollment, { message: 'Student enrolled successfully.' });
  } catch (err) {
    next(err);
  }
};

const updateEnrollment = async (req, res, next) => {
  try {
    const { id: sectionId } = req.params;
    const studentIds = Array.isArray(req.body.studentIds)
      ? [...new Set(req.body.studentIds.map(String))]
      : null;
    if (!studentIds) {
      return res.status(400).json({ success: false, message: 'studentIds must be an array.' });
    }
    const section = await prisma.classSection.findFirst({
      where: { id: sectionId, academyId: req.academyId }
    });
    if (!section) throw notFound('Class section not found in academy.');

    const students = await prisma.user.findMany({
      where: {
        id: { in: studentIds },
        academyId: req.academyId,
        role: 'STUDENT'
      },
      select: { id: true }
    });
    if (students.length !== studentIds.length) {
      throw forbidden('One or more selected students do not belong to this academy.');
    }
    const validIds = students.map((student) => student.id);

    const updated = await prisma.$transaction(async (tx) => {
      await tx.classSectionEnrollment.deleteMany({
        where: { sectionId, studentId: { notIn: validIds } }
      });
      if (validIds.length) {
        await tx.classSectionEnrollment.createMany({
          data: validIds.map((studentId) => ({ sectionId, studentId })),
          skipDuplicates: true
        });
      }

      const offerings = await tx.class.findMany({
        where: { academyId: req.academyId, classSectionId: sectionId },
        select: { id: true }
      });
      const offeringIds = offerings.map((offering) => offering.id);
      if (offeringIds.length) {
        await tx.studentEnrollment.deleteMany({
          where: {
            classId: { in: offeringIds },
            studentId: { notIn: validIds }
          }
        });
        if (validIds.length) {
          await tx.studentEnrollment.createMany({
            data: offeringIds.flatMap((classId) =>
              validIds.map((studentId) => ({ classId, studentId }))
            ),
            skipDuplicates: true
          });
        }
      }

      return tx.classSection.findUnique({ where: { id: sectionId }, include });
    });

    return sendSuccess(res, formatSection(updated), {
      message: 'Enrollment updated successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const unenrollStudent = async (req, res, next) => {
  try {
    const { id: sectionId, studentId } = req.params;
    const section = await prisma.classSection.findFirst({
      where: { id: sectionId, academyId: req.academyId }
    });
    if (!section) throw notFound('Class section not found in academy.');
    const offerings = await prisma.class.findMany({
      where: { academyId: req.academyId, classSectionId: sectionId },
      select: { id: true }
    });
    await prisma.$transaction([
      prisma.classSectionEnrollment.deleteMany({ where: { sectionId, studentId } }),
      prisma.studentEnrollment.deleteMany({
        where: { studentId, classId: { in: offerings.map((offering) => offering.id) } }
      })
    ]);
    return sendSuccess(res, { removed: true }, {
      message: 'Student removed from the class section.'
    });
  } catch (err) {
    next(err);
  }
};

module.exports = {
  getSections,
  createSection,
  updateSection,
  deleteSection,
  enrollStudent,
  updateEnrollment,
  unenrollStudent
};
