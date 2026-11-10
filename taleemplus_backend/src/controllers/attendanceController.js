const prisma = require('../config/db');
const { canReadStudent } = require('../utils/studentAccess');
const { toIso, lowerEnum } = require('../utils/dto');
const { forbidden } = require('../utils/apiError');
const { sendSuccess } = require('../utils/response');
const {
  assertClassInAcademy,
  assertStudentInAcademy
} = require('../utils/tenant');

// Teachers may only mark or read attendance for classes they teach.
const assertTeacherOwnsClass = (req, classEntity) => {
  if (req.user.role === 'TEACHER' && classEntity.primaryTeacherId !== req.user.id) {
    throw forbidden('You can only manage attendance for your own classes.');
  }
};

const formatAttendance = (record, studentName = '') => ({
  id: record.id,
  academy_id: record.academyId,
  class_id: record.classId,
  student_id: record.studentId,
  student_name: studentName,
  log_date: record.logDate,
  status: lowerEnum(record.status),
  marked_by_uid: record.markedById,
  recorded_at: toIso(record.recordedAt)
});

const markAttendance = async (req, res, next) => {
  try {
    const { classId, records, logDate } = req.body;

    // Attendance cannot be recorded for days that have not happened yet.
    // One day of tolerance covers time-zone differences (Pakistan is UTC+5).
    const latestAllowed = new Date(Date.now() + 24 * 60 * 60 * 1000)
      .toISOString()
      .slice(0, 10);
    if (logDate > latestAllowed) {
      return res.status(400).json({
        success: false,
        code: 'VALIDATION_ERROR',
        message: 'Attendance cannot be marked for a future date.'
      });
    }

    const classEntity = await assertClassInAcademy(classId, req.academyId);
    assertTeacherOwnsClass(req, classEntity);

    const studentIds = records.map((record) => record.studentId);
    const students = await prisma.user.findMany({
      where: {
        id: { in: studentIds },
        academyId: req.academyId,
        role: 'STUDENT'
      },
      select: { id: true, fullName: true }
    });
    const namesById = new Map(students.map((s) => [s.id, s.fullName]));
    if (students.length !== studentIds.length) {
      throw forbidden('One or more students do not belong to this academy.');
    }
    const enrollments = await prisma.studentEnrollment.findMany({
      where: { classId, studentId: { in: studentIds } },
      select: { studentId: true }
    });
    if (enrollments.length !== studentIds.length) {
      throw forbidden('One or more students are not enrolled in this class.');
    }

    const savedRecords = await prisma.$transaction(
      records.map((record) => {
        const status = String(record.status || 'present').toUpperCase();
        return prisma.attendanceRecord.upsert({
          where: {
            classId_studentId_logDate: {
              classId,
              studentId: record.studentId,
              logDate
            }
          },
          create: {
            academyId: req.academyId,
            classId,
            studentId: record.studentId,
            logDate,
            status,
            markedById: req.user.id
          },
          update: {
            status,
            markedById: req.user.id,
            recordedAt: new Date()
          }
        });
      })
    );

    return sendSuccess(
      res,
      savedRecords.map((record) =>
        formatAttendance(record, namesById.get(record.studentId) || '')
      ),
      { message: 'Attendance saved successfully.' }
    );
  } catch (err) {
    next(err);
  }
};

const getStudentAttendance = async (req, res, next) => {
  try {
    const { studentId } = req.params;
    await assertStudentInAcademy(studentId, req.academyId);
    if (!(await canReadStudent(req, studentId))) {
      throw forbidden('You cannot access this student attendance.');
    }

    const records = await prisma.attendanceRecord.findMany({
      where: {
        academyId: req.academyId,
        studentId
      },
      include: {
        class: { select: { className: true, section: true, subject: true } },
        student: { select: { fullName: true } }
      },
      orderBy: { logDate: 'desc' }
    });

    return sendSuccess(
      res,
      records.map((record) =>
        formatAttendance(record, record.student?.fullName || '')
      )
    );
  } catch (err) {
    next(err);
  }
};

const getClassAttendance = async (req, res, next) => {
  try {
    const { classId, logDate } = req.query;
    const classEntity = await assertClassInAcademy(classId, req.academyId);
    assertTeacherOwnsClass(req, classEntity);

    const records = await prisma.attendanceRecord.findMany({
      where: {
        academyId: req.academyId,
        classId,
        logDate
      },
      include: {
        student: { select: { id: true, fullName: true } }
      }
    });

    return sendSuccess(
      res,
      records.map((record) =>
        formatAttendance(record, record.student?.fullName || '')
      )
    );
  } catch (err) {
    next(err);
  }
};

const getAcademyAttendance = async (req, res, next) => {
  try {
    const where = { academyId: req.academyId };
    if (req.query.classId) {
      await assertClassInAcademy(req.query.classId, req.academyId);
      where.classId = req.query.classId;
    }
    if (req.query.logDate) where.logDate = req.query.logDate;
    if (req.query.from || req.query.to) {
      where.logDate = {};
      if (req.query.from) where.logDate.gte = req.query.from;
      if (req.query.to) where.logDate.lte = req.query.to;
    }

    if (req.user.role === 'STUDENT') {
      where.studentId = req.user.id;
    } else if (req.user.role === 'PARENT') {
      const links = await prisma.parentStudent.findMany({
        where: { parentId: req.user.id },
        select: { studentId: true }
      });
      where.studentId = { in: links.map((link) => link.studentId) };
    } else if (req.user.role === 'TEACHER') {
      const taught = await prisma.class.findMany({
        where: { academyId: req.academyId, primaryTeacherId: req.user.id },
        select: { id: true }
      });
      if (where.classId && !taught.some((item) => item.id === where.classId)) {
        throw forbidden('You cannot access attendance for this class.');
      }
      if (!where.classId) where.classId = { in: taught.map((item) => item.id) };
    }

    const records = await prisma.attendanceRecord.findMany({
      where,
      include: {
        student: { select: { id: true, fullName: true } },
        class: { select: { className: true, section: true, subject: true } }
      },
      orderBy: [{ logDate: 'desc' }, { recordedAt: 'desc' }],
      take: Math.min(Number(req.query.limit) || 2000, 5000)
    });

    return sendSuccess(
      res,
      records.map((record) => ({
        ...formatAttendance(record, record.student?.fullName || ''),
        class_label:
          `${record.class?.className || ''} - ${record.class?.section || ''}`.trim(),
        subject: record.class?.subject || ''
      }))
    );
  } catch (err) {
    next(err);
  }
};

module.exports = {
  markAttendance,
  getStudentAttendance,
  getClassAttendance,
  getAcademyAttendance
};
