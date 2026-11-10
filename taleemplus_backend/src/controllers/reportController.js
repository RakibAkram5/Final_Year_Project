/**
 * Excel (.xlsx) exports built from the live database.
 *
 *   GET /reports/attendance.xlsx?classId&from&to   ADMIN, class teacher
 *   GET /reports/results.xlsx?classId[&quizId]     ADMIN, class teacher
 *   GET /reports/fees.xlsx?[period=YYYY-MM][&status] ADMIN
 *
 * Totals, percentages and grades are taken from the stored marks (computed
 * by the marks API on entry) so exports always match what the app shows.
 */
const ExcelJS = require('exceljs');
const prisma = require('../config/db');
const { canManageClass } = require('../services/fileAccess');

const fail = (res, status, message) => res.status(status).json({ success: false, message });
/** Real calendar dates only (rejects 2026-13-01, 2026-02-30). */
const DATE = {
  test: (s) => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
    const d = new Date(`${s}T00:00:00Z`);
    return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
  }
};
const XLSX = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

const sendWorkbook = async (res, workbook, filename) => {
  const buffer = await workbook.xlsx.writeBuffer();
  res.setHeader('Content-Type', XLSX);
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  res.setHeader('Cache-Control', 'private, no-store');
  res.setHeader('Content-Length', String(buffer.length));
  res.end(Buffer.from(buffer));
};

const styleHeader = (sheet) => {
  const row = sheet.getRow(1);
  row.font = { bold: true, color: { argb: 'FF042020' } };
  row.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF17E9DF' } };
  sheet.views = [{ state: 'frozen', ySplit: 1 }];
};

const safeName = (s) => String(s).replace(/[^\w.-]+/g, '_').slice(0, 60);

const loadClass = async (req, res) => {
  const classId = String(req.query.classId || '');
  const cls = classId && await prisma.class.findFirst({
    where: { id: classId, academyId: req.academyId }
  });
  if (!cls) {
    fail(res, 404, 'Class not found.');
    return null;
  }
  if (!canManageClass(req, cls)) {
    fail(res, 403, 'Only the class teacher or an admin can export this class.');
    return null;
  }
  return cls;
};

const classLabel = (c) => `${c.className} - ${c.section} (${c.subject})`;

const attendanceXlsx = async (req, res, next) => {
  try {
    const cls = await loadClass(req, res);
    if (!cls) return;
    const today = new Date().toISOString().slice(0, 10);
    const from = String(req.query.from || today.slice(0, 8) + '01');
    const to = String(req.query.to || today);
    if (!DATE.test(from) || !DATE.test(to) || from > to) {
      return fail(res, 400, 'from and to must be YYYY-MM-DD dates with from <= to.');
    }
    const [enrollments, records] = await Promise.all([
      prisma.studentEnrollment.findMany({
        where: { classId: cls.id },
        include: { student: { select: { id: true, fullName: true, rollNumber: true } } }
      }),
      prisma.attendanceRecord.findMany({
        where: { classId: cls.id, logDate: { gte: from, lte: to } },
        orderBy: [{ logDate: 'asc' }]
      })
    ]);
    const students = enrollments
      .map((e) => ({ ...e.student, roll: e.rollNumber || e.student.rollNumber || '' }))
      .sort((a, b) => a.roll.localeCompare(b.roll, undefined, { numeric: true }) ||
        a.fullName.localeCompare(b.fullName));
    const dates = [...new Set(records.map((r) => r.logDate))].sort();
    const byKey = new Map(records.map((r) => [`${r.studentId}|${r.logDate}`, r.status]));

    const wb = new ExcelJS.Workbook();
    wb.creator = 'TaleemPlus';
    const summary = wb.addWorksheet('Summary');
    summary.columns = [
      { header: 'Roll', key: 'roll', width: 10 },
      { header: 'Student', key: 'name', width: 32 },
      { header: 'Present', key: 'p', width: 10 },
      { header: 'Late', key: 'l', width: 8 },
      { header: 'Leave', key: 'lv', width: 8 },
      { header: 'Absent', key: 'a', width: 9 },
      { header: 'Days marked', key: 't', width: 13 },
      { header: 'Attendance %', key: 'pct', width: 14 }
    ];
    for (const s of students) {
      const own = dates.map((d) => byKey.get(`${s.id}|${d}`)).filter(Boolean);
      const count = (st) => own.filter((x) => x === st).length;
      const present = count('PRESENT') + count('LATE');
      summary.addRow({
        roll: s.roll, name: s.fullName, p: count('PRESENT'), l: count('LATE'),
        lv: count('LEAVE'), a: count('ABSENT'), t: own.length,
        pct: own.length ? Math.round((present / own.length) * 1000) / 10 : null
      });
    }
    styleHeader(summary);

    const daily = wb.addWorksheet('Daily');
    daily.columns = [
      { header: 'Roll', key: 'roll', width: 10 },
      { header: 'Student', key: 'name', width: 32 },
      ...dates.map((d) => ({ header: d, key: d, width: 12 }))
    ];
    for (const s of students) {
      const row = { roll: s.roll, name: s.fullName };
      for (const d of dates) row[d] = byKey.get(`${s.id}|${d}`) || '';
      daily.addRow(row);
    }
    styleHeader(daily);

    const info = wb.addWorksheet('About');
    info.addRows([
      ['Class', classLabel(cls)],
      ['Period', `${from} to ${to}`],
      ['Generated', new Date().toISOString()],
      ['Attendance %', '(Present + Late) / days marked for the student']
    ]);
    await sendWorkbook(res, wb, `attendance_${safeName(cls.className)}_${from}_${to}.xlsx`);
  } catch (err) {
    next(err);
  }
};

const resultsXlsx = async (req, res, next) => {
  try {
    const cls = await loadClass(req, res);
    if (!cls) return;
    const quizId = req.query.quizId ? String(req.query.quizId) : null;
    const quizzes = await prisma.quiz.findMany({
      where: { classId: cls.id, academyId: req.academyId, ...(quizId ? { id: quizId } : {}) },
      orderBy: { createdAt: 'asc' }
    });
    if (quizId && !quizzes.length) return fail(res, 404, 'Test not found in this class.');
    const marks = await prisma.testMark.findMany({
      where: { quizId: { in: quizzes.map((q) => q.id) } },
      include: { student: { select: { fullName: true, rollNumber: true } } }
    });

    const wb = new ExcelJS.Workbook();
    wb.creator = 'TaleemPlus';
    const sheet = wb.addWorksheet('Results');
    sheet.columns = [
      { header: 'Test', key: 'test', width: 30 },
      { header: 'Date', key: 'date', width: 12 },
      { header: 'Roll', key: 'roll', width: 10 },
      { header: 'Student', key: 'name', width: 32 },
      { header: 'Obtained', key: 'obt', width: 11 },
      { header: 'Total', key: 'tot', width: 9 },
      { header: 'Percentage', key: 'pct', width: 12 },
      { header: 'Grade', key: 'grade', width: 8 },
      { header: 'Feedback', key: 'fb', width: 40 }
    ];
    const quizById = new Map(quizzes.map((q) => [q.id, q]));
    marks
      .sort((a, b) => (quizById.get(a.quizId).createdAt - quizById.get(b.quizId).createdAt) ||
        a.studentName.localeCompare(b.studentName))
      .forEach((m) => {
        const q = quizById.get(m.quizId);
        sheet.addRow({
          test: q.title,
          date: q.testDate ? q.testDate.toISOString().slice(0, 10) : '',
          roll: m.student?.rollNumber || '',
          name: m.student?.fullName || m.studentName,
          obt: m.marksObtained,
          tot: m.totalMarks,
          pct: Math.round(m.percentage * 10) / 10,
          grade: m.gradeLetter,
          fb: m.teacherFeedback || ''
        });
      });
    styleHeader(sheet);

    // Per-student overall totals across the exported tests.
    const totals = wb.addWorksheet('Student totals');
    totals.columns = [
      { header: 'Student', key: 'name', width: 32 },
      { header: 'Tests', key: 'n', width: 8 },
      { header: 'Obtained', key: 'obt', width: 11 },
      { header: 'Total', key: 'tot', width: 9 },
      { header: 'Overall %', key: 'pct', width: 11 }
    ];
    const per = new Map();
    for (const m of marks) {
      const t = per.get(m.studentId) || { name: m.student?.fullName || m.studentName, n: 0, obt: 0, tot: 0 };
      t.n += 1; t.obt += m.marksObtained; t.tot += m.totalMarks;
      per.set(m.studentId, t);
    }
    [...per.values()].sort((a, b) => a.name.localeCompare(b.name)).forEach((t) =>
      totals.addRow({ ...t, pct: t.tot ? Math.round((t.obt / t.tot) * 1000) / 10 : null }));
    styleHeader(totals);

    await sendWorkbook(res, wb, `results_${safeName(cls.className)}.xlsx`);
  } catch (err) {
    next(err);
  }
};

const feesXlsx = async (req, res, next) => {
  try {
    if (req.user.role !== 'ADMIN') return fail(res, 403, 'Only admins can export fee records.');
    const period = req.query.period ? String(req.query.period) : null;
    if (period && !/^\d{4}-\d{2}$/.test(period)) return fail(res, 400, 'period must be YYYY-MM.');
    const status = req.query.status ? String(req.query.status).toUpperCase() : null;
    if (status && !['PENDING', 'PAID', 'OVERDUE'].includes(status)) {
      return fail(res, 400, 'status must be PENDING, PAID or OVERDUE.');
    }
    const challans = await prisma.feeChallan.findMany({
      where: {
        academyId: req.academyId,
        ...(period ? { billingPeriod: period } : {}),
        ...(status ? { status } : {})
      },
      orderBy: [{ classLabel: 'asc' }, { studentName: 'asc' }],
      take: 10000
    });
    const wb = new ExcelJS.Workbook();
    wb.creator = 'TaleemPlus';
    const sheet = wb.addWorksheet('Fee records');
    sheet.columns = [
      { header: 'Challan #', key: 'no', width: 22 },
      { header: 'Period', key: 'period', width: 10 },
      { header: 'Class', key: 'cls', width: 24 },
      { header: 'Roll', key: 'roll', width: 9 },
      { header: 'Student', key: 'name', width: 30 },
      { header: 'Due date', key: 'due', width: 12 },
      { header: 'Total (PKR)', key: 'total', width: 13 },
      { header: 'Status', key: 'status', width: 10 },
      { header: 'Paid on', key: 'paid', width: 12 }
    ];
    for (const c of challans) {
      sheet.addRow({
        no: c.challanNumber, period: c.billingPeriod || '', cls: c.classLabel,
        roll: c.rollNumber || '', name: c.studentName,
        due: c.dueDate.toISOString().slice(0, 10), total: Number(c.totalAmount),
        status: c.status, paid: c.paidAt ? c.paidAt.toISOString().slice(0, 10) : ''
      });
    }
    sheet.getColumn('total').numFmt = '#,##0';
    styleHeader(sheet);
    await sendWorkbook(res, wb, `fees_${period || 'all'}${status ? `_${status.toLowerCase()}` : ''}.xlsx`);
  } catch (err) {
    next(err);
  }
};

module.exports = { attendanceXlsx, resultsXlsx, feesXlsx };
