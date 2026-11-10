/**
 * Assignments: teachers create them for a class (optionally attaching
 * instruction files), students submit before the deadline (files are
 * uploaded to /files with category ASSIGNMENT_SUBMISSION), teachers grade.
 */
const { z } = require('zod');
const prisma = require('../config/db');
const { canManageClass, linkedChildIds } = require('../services/fileAccess');
const { deleteFilesForOwner } = require('./fileController');

const fail = (res, status, message) => res.status(status).json({ success: false, message });

const assignmentBody = z.object({
  classId: z.string().uuid(),
  title: z.string().trim().min(2).max(160),
  instructions: z.string().trim().max(5000).optional().nullable(),
  dueAt: z.string().datetime({ offset: true }),
  maxMarks: z.number().int().min(1).max(1000).optional().nullable(),
  allowResubmission: z.boolean().optional()
});

const gradeBody = z.object({
  marks: z.number().min(0),
  feedback: z.string().trim().max(2000).optional().nullable()
});

const validationError = (res, error) => res.status(400).json({
  success: false,
  code: 'VALIDATION_ERROR',
  message: 'Request validation failed.',
  details: error.issues.map((i) => ({ path: i.path.join('.'), message: i.message }))
});

/** Class ids whose assignments the caller may see. null = all in academy. */
const visibleClassIds = async (req) => {
  const { role, id } = req.user;
  if (role === 'ADMIN') return null;
  if (role === 'TEACHER') {
    return (await prisma.class.findMany({
      where: { academyId: req.academyId, primaryTeacherId: id }, select: { id: true }
    })).map((c) => c.id);
  }
  const studentIds = role === 'STUDENT' ? [id] : await linkedChildIds(req);
  return (await prisma.studentEnrollment.findMany({
    where: { studentId: { in: studentIds }, class: { academyId: req.academyId } },
    select: { classId: true }
  })).map((e) => e.classId);
};

const fileCounts = async (academyId, category, ownerIds) => {
  if (!ownerIds.length) return {};
  const rows = await prisma.storedFile.groupBy({
    by: ['ownerId'],
    where: { academyId, category, ownerId: { in: ownerIds } },
    _count: { _all: true }
  });
  return Object.fromEntries(rows.map((r) => [r.ownerId, r._count._all]));
};

const formatSubmission = (s, files) => ({
  id: s.id,
  studentId: s.studentId,
  studentName: s.student?.fullName,
  note: s.note,
  submittedAt: s.submittedAt,
  updatedAt: s.updatedAt,
  marks: s.marks,
  feedback: s.feedback,
  gradedAt: s.gradedAt,
  fileCount: files[s.id] || 0
});

const listAssignments = async (req, res, next) => {
  try {
    const allowed = await visibleClassIds(req);
    const classFilter = req.query.classId ? String(req.query.classId) : null;
    if (classFilter && allowed && !allowed.includes(classFilter)) return fail(res, 403, 'Forbidden.');
    const where = {
      academyId: req.academyId,
      ...(classFilter ? { classId: classFilter } : allowed ? { classId: { in: allowed } } : {})
    };
    const assignments = await prisma.assignment.findMany({
      where,
      include: {
        class: { select: { className: true, section: true, subject: true } },
        createdBy: { select: { fullName: true } },
        _count: { select: { submissions: true } }
      },
      orderBy: { dueAt: 'desc' },
      take: 200
    });
    const ids = assignments.map((a) => a.id);
    const briefFiles = await fileCounts(req.academyId, 'ASSIGNMENT_INSTRUCTION', ids);

    // Students see their own submission; parents their children's.
    let mine = [];
    if (req.user.role === 'STUDENT' || req.user.role === 'PARENT') {
      const studentIds = req.user.role === 'STUDENT' ? [req.user.id] : await linkedChildIds(req);
      mine = await prisma.assignmentSubmission.findMany({
        where: { assignmentId: { in: ids }, studentId: { in: studentIds } },
        include: { student: { select: { fullName: true } } }
      });
    }
    const subFiles = await fileCounts(req.academyId, 'ASSIGNMENT_SUBMISSION', mine.map((s) => s.id));
    const now = new Date();
    const data = assignments.map((a) => ({
      id: a.id,
      classId: a.classId,
      classLabel: `${a.class.className} - ${a.class.section} (${a.class.subject})`,
      title: a.title,
      instructions: a.instructions,
      dueAt: a.dueAt,
      isOpen: a.dueAt > now,
      maxMarks: a.maxMarks,
      allowResubmission: a.allowResubmission,
      createdByName: a.createdBy.fullName,
      createdAt: a.createdAt,
      instructionFileCount: briefFiles[a.id] || 0,
      ...(req.user.role === 'ADMIN' || req.user.role === 'TEACHER'
        ? { submissionCount: a._count.submissions }
        : {
            mySubmissions: mine
              .filter((s) => s.assignmentId === a.id)
              .map((s) => formatSubmission(s, subFiles))
          })
    }));
    return res.json({ success: true, data });
  } catch (err) {
    next(err);
  }
};

const loadManaged = async (req, res) => {
  const assignment = await prisma.assignment.findFirst({
    where: { id: req.params.id, academyId: req.academyId },
    include: { class: true }
  });
  if (!assignment) {
    fail(res, 404, 'Assignment not found.');
    return null;
  }
  if (!canManageClass(req, assignment.class)) {
    fail(res, 403, 'Only the class teacher or an admin can do this.');
    return null;
  }
  return assignment;
};

const createAssignment = async (req, res, next) => {
  try {
    const parsed = assignmentBody.safeParse(req.body);
    if (!parsed.success) return validationError(res, parsed.error);
    const body = parsed.data;
    const cls = await prisma.class.findFirst({ where: { id: body.classId, academyId: req.academyId } });
    if (!cls) return fail(res, 404, 'Class not found.');
    if (!canManageClass(req, cls)) return fail(res, 403, 'You can only create assignments for your own classes.');
    const assignment = await prisma.assignment.create({
      data: {
        academyId: req.academyId,
        classId: cls.id,
        title: body.title,
        instructions: body.instructions || null,
        dueAt: new Date(body.dueAt),
        maxMarks: body.maxMarks ?? null,
        allowResubmission: body.allowResubmission ?? true,
        createdById: req.user.id
      }
    });
    return res.status(201).json({ success: true, data: assignment });
  } catch (err) {
    next(err);
  }
};

const updateAssignment = async (req, res, next) => {
  try {
    const existing = await loadManaged(req, res);
    if (!existing) return;
    const parsed = assignmentBody.omit({ classId: true }).partial().safeParse(req.body);
    if (!parsed.success) return validationError(res, parsed.error);
    const b = parsed.data;
    const updated = await prisma.assignment.update({
      where: { id: existing.id },
      data: {
        ...(b.title !== undefined ? { title: b.title } : {}),
        ...(b.instructions !== undefined ? { instructions: b.instructions || null } : {}),
        ...(b.dueAt !== undefined ? { dueAt: new Date(b.dueAt) } : {}),
        ...(b.maxMarks !== undefined ? { maxMarks: b.maxMarks } : {}),
        ...(b.allowResubmission !== undefined ? { allowResubmission: b.allowResubmission } : {})
      }
    });
    return res.json({ success: true, data: updated });
  } catch (err) {
    next(err);
  }
};

const deleteAssignment = async (req, res, next) => {
  try {
    const existing = await loadManaged(req, res);
    if (!existing) return;
    const subs = await prisma.assignmentSubmission.findMany({
      where: { assignmentId: existing.id }, select: { id: true }
    });
    for (const s of subs) await deleteFilesForOwner(req.academyId, 'ASSIGNMENT_SUBMISSION', s.id);
    await deleteFilesForOwner(req.academyId, 'ASSIGNMENT_INSTRUCTION', existing.id);
    await prisma.assignment.delete({ where: { id: existing.id } });
    return res.json({ success: true, data: { deleted: true } });
  } catch (err) {
    next(err);
  }
};

const listSubmissions = async (req, res, next) => {
  try {
    const assignment = await loadManaged(req, res);
    if (!assignment) return;
    const [subs, enrolled] = await Promise.all([
      prisma.assignmentSubmission.findMany({
        where: { assignmentId: assignment.id },
        include: { student: { select: { fullName: true } } },
        orderBy: { submittedAt: 'asc' }
      }),
      prisma.studentEnrollment.count({ where: { classId: assignment.classId } })
    ]);
    const files = await fileCounts(req.academyId, 'ASSIGNMENT_SUBMISSION', subs.map((s) => s.id));
    return res.json({
      success: true,
      data: {
        enrolledCount: enrolled,
        submissions: subs.map((s) => ({
          ...formatSubmission(s, files),
          late: s.submittedAt > assignment.dueAt
        }))
      }
    });
  } catch (err) {
    next(err);
  }
};

/** Student creates/updates their own submission record (note). */
const submit = async (req, res, next) => {
  try {
    const assignment = await prisma.assignment.findFirst({
      where: { id: req.params.id, academyId: req.academyId }
    });
    if (!assignment) return fail(res, 404, 'Assignment not found.');
    const enrolled = await prisma.studentEnrollment.findFirst({
      where: { classId: assignment.classId, studentId: req.user.id }, select: { id: true }
    });
    if (!enrolled) return fail(res, 403, 'You are not enrolled in this class.');
    if (assignment.dueAt <= new Date()) return fail(res, 409, 'The deadline for this assignment has passed.');
    const note = typeof req.body?.note === 'string' ? req.body.note.trim().slice(0, 2000) : null;
    const existing = await prisma.assignmentSubmission.findUnique({
      where: { assignmentId_studentId: { assignmentId: assignment.id, studentId: req.user.id } }
    });
    if (existing && !assignment.allowResubmission) {
      const files = await prisma.storedFile.count({
        where: { academyId: req.academyId, category: 'ASSIGNMENT_SUBMISSION', ownerId: existing.id }
      });
      if (files > 0) return fail(res, 409, 'Resubmission is not allowed for this assignment.');
    }
    const submission = existing
      ? await prisma.assignmentSubmission.update({
          where: { id: existing.id },
          data: { note, submittedAt: new Date() }
        })
      : await prisma.assignmentSubmission.create({
          data: { assignmentId: assignment.id, studentId: req.user.id, note }
        });
    return res.status(existing ? 200 : 201).json({ success: true, data: submission });
  } catch (err) {
    next(err);
  }
};

const gradeSubmission = async (req, res, next) => {
  try {
    const assignment = await loadManaged(req, res);
    if (!assignment) return;
    const parsed = gradeBody.safeParse(req.body);
    if (!parsed.success) return validationError(res, parsed.error);
    if (assignment.maxMarks != null && parsed.data.marks > assignment.maxMarks) {
      return fail(res, 400, `Marks cannot exceed the maximum of ${assignment.maxMarks}.`);
    }
    const submission = await prisma.assignmentSubmission.findFirst({
      where: { id: req.params.submissionId, assignmentId: assignment.id }
    });
    if (!submission) return fail(res, 404, 'Submission not found.');
    const graded = await prisma.assignmentSubmission.update({
      where: { id: submission.id },
      data: { marks: parsed.data.marks, feedback: parsed.data.feedback || null, gradedAt: new Date() }
    });
    return res.json({ success: true, data: graded });
  } catch (err) {
    next(err);
  }
};

module.exports = {
  listAssignments,
  createAssignment,
  updateAssignment,
  deleteAssignment,
  listSubmissions,
  submit,
  gradeSubmission
};
