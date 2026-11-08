const prisma = require('../config/db');
const { notFound } = require('../utils/apiError');
const { sendSuccess } = require('../utils/response');
const { toIso } = require('../utils/dto');

const formatReport = (report) => ({
  id: report.id,
  academy_id: report.academyId,
  class_label: report.classLabel,
  generated_at: toIso(report.generatedAt),
  total_students: report.totalStudents,
  present: report.present,
  absent: report.absent,
  fee_paid: report.feePaid,
  fee_pending: report.feePending,
  fee_paid_amount: Number(report.feePaidAmount),
  fee_pending_amount: Number(report.feePendingAmount),
  created_at: toIso(report.createdAt)
});

const getClassReports = async (req, res, next) => {
  try {
    const reports = await prisma.classReport.findMany({
      where: { academyId: req.academyId },
      orderBy: { generatedAt: 'desc' },
      take: Math.min(Number(req.query.limit) || 200, 500)
    });
    return sendSuccess(res, reports.map(formatReport));
  } catch (err) {
    next(err);
  }
};

const generateClassReport = async (req, res, next) => {
  try {
    const { sectionId } = req.body;
    let classLabel = req.body.classLabel ? String(req.body.classLabel).trim() : '';
    let studentIds = [];

    if (sectionId) {
      const section = await prisma.classSection.findFirst({
        where: { id: sectionId, academyId: req.academyId },
        include: { enrollments: { select: { studentId: true } } }
      });
      if (!section) throw notFound('Class section not found in academy.');
      classLabel = [section.className, section.program, section.section].filter(Boolean).join(' - ');
      studentIds = section.enrollments.map((entry) => entry.studentId);
    } else if (classLabel) {
      const section = await prisma.classSection.findFirst({
        where: {
          academyId: req.academyId,
          OR: [
            { className: { equals: classLabel, mode: 'insensitive' } },
            { section: { equals: classLabel, mode: 'insensitive' } }
          ]
        },
        include: { enrollments: { select: { studentId: true } } }
      });
      if (section) {
        classLabel = [section.className, section.program, section.section].filter(Boolean).join(' - ');
        studentIds = section.enrollments.map((entry) => entry.studentId);
      }
    } else {
      return res.status(400).json({
        success: false,
        message: 'sectionId or classLabel is required.'
      });
    }

    // "Today" is the caller's local calendar day when supplied (the server
    // runs in UTC, which differs from Pakistan time for 5 hours a day).
    let logDate = req.body.logDate;
    if (logDate !== undefined && !/^\d{4}-\d{2}-\d{2}$/.test(String(logDate))) {
      return res.status(400).json({ success: false, message: 'logDate must use YYYY-MM-DD.' });
    }
    if (!logDate) logDate = new Date().toISOString().slice(0, 10);

    let present = 0;
    let feePaid = 0;
    let feePending = 0;
    let feePaidAmount = 0;
    let feePendingAmount = 0;

    if (studentIds.length) {
      const [attendance, challans] = await Promise.all([
        prisma.attendanceRecord.findMany({
          where: {
            academyId: req.academyId,
            logDate,
            studentId: { in: studentIds }
          },
          select: { studentId: true, status: true }
        }),
        prisma.feeChallan.findMany({
          where: {
            academyId: req.academyId,
            studentId: { in: studentIds }
          },
          select: { studentId: true, status: true, totalAmount: true }
        })
      ]);

      const presentIds = new Set(
        attendance
          .filter((record) => ['PRESENT', 'LATE'].includes(record.status))
          .map((record) => record.studentId)
      );
      present = presentIds.size;

      const paidStudents = new Set();
      const pendingStudents = new Set();
      for (const challan of challans) {
        const amount = Number(challan.totalAmount);
        if (challan.status === 'PAID') {
          feePaidAmount += amount;
          paidStudents.add(challan.studentId);
        } else {
          feePendingAmount += amount;
          pendingStudents.add(challan.studentId);
        }
      }
      feePaid = paidStudents.size;
      feePending = pendingStudents.size;
    }

    const report = await prisma.classReport.create({
      data: {
        academyId: req.academyId,
        classLabel,
        totalStudents: studentIds.length,
        present,
        absent: Math.max(studentIds.length - present, 0),
        feePaid,
        feePending,
        feePaidAmount,
        feePendingAmount
      }
    });

    return sendSuccess(res, formatReport(report), {
      status: 201,
      message: `Report generated for ${classLabel}.`
    });
  } catch (err) {
    next(err);
  }
};

const deleteClassReport = async (req, res, next) => {
  try {
    const deleted = await prisma.classReport.deleteMany({
      where: { id: req.params.id, academyId: req.academyId }
    });
    if (!deleted.count) throw notFound('Class report not found in academy.');
    return sendSuccess(res, { deleted: true }, {
      message: 'Class report deleted.'
    });
  } catch (err) {
    next(err);
  }
};

module.exports = {
  getClassReports,
  generateClassReport,
  deleteClassReport
};
