const prisma = require('../config/db');
const aiQuestionService = require('../services/aiQuestionService');
const { canReadStudent } = require('../utils/studentAccess');
const { forbidden, notFound, badRequest } = require('../utils/apiError');
const { sendSuccess } = require('../utils/response');
const { toIso } = require('../utils/dto');
const {
  assertClassInAcademy,
  assertStudentInAcademy,
  assertEnrolledStudent
} = require('../utils/tenant');

const calculateGrade = (percentage) => {
  if (percentage >= 90) return 'A+';
  if (percentage >= 80) return 'A';
  if (percentage >= 70) return 'B';
  if (percentage >= 60) return 'C';
  if (percentage >= 50) return 'D';
  return 'F';
};

const formatQuestion = (question, includeAnswers) => ({
  id: question.id,
  text: question.text,
  type: question.type,
  options: question.options,
  marks: question.marks,
  ...(includeAnswers
    ? {
        correct_index: question.correctIndex,
        grading_keywords: question.gradingKeywords
      }
    : {})
});

// The paperMeta JSON carries the teacher answer key (short/long model answers
// under `answers`). Students must never receive it, so strip that key unless
// the caller is allowed to see answers.
const sanitizePaperMeta = (paperMeta, includeAnswers) => {
  if (!paperMeta || typeof paperMeta !== 'object') return paperMeta || null;
  if (includeAnswers) return paperMeta;
  const { answers, ...safe } = paperMeta;
  return safe;
};

const formatQuiz = (quiz, includeAnswers) => ({
  id: quiz.id,
  academy_id: quiz.academyId,
  class_id: quiz.classId,
  class_label: quiz.classLabel,
  title: quiz.title,
  subject: quiz.subject,
  month: quiz.month || '',
  session: quiz.session || '',
  chapter: quiz.chapter || '',
  difficulty: quiz.difficulty || 'Medium',
  total_marks: quiz.totalMarks,
  test_date: toIso(quiz.testDate),
  instructions: quiz.instructions || '',
  paper_meta: sanitizePaperMeta(quiz.paperMeta, includeAnswers),
  // Online attempts (PAPER = printed test, ONLINE = attempt in the portal).
  attempt_mode: quiz.attemptMode || 'PAPER',
  available_from: toIso(quiz.availableFrom),
  available_until: toIso(quiz.availableUntil),
  duration_minutes: quiz.durationMinutes ?? null,
  created_by_uid: quiz.createdById,
  created_by_name: quiz.createdBy?.fullName || '',
  created_at: toIso(quiz.createdAt),
  questions: (quiz.questions || []).map((question) =>
    formatQuestion(question, includeAnswers)
  )
});

// Accepts the client paperMeta only when it is a plain object, guarding the
// JSON column against arrays/strings/garbage.
const normalizePaperMeta = (value) =>
  value && typeof value === 'object' && !Array.isArray(value) ? value : null;

const formatMark = (mark) => ({
  id: mark.id,
  academy_id: mark.academyId,
  quiz_id: mark.quizId,
  student_id: mark.studentId,
  student_name: mark.studentName,
  class_id: mark.classId,
  subject: mark.subject,
  month: mark.month || '',
  marks_obtained: mark.marksObtained,
  total_marks: mark.totalMarks,
  percentage: mark.percentage,
  grade_letter: mark.gradeLetter,
  teacher_feedback: mark.teacherFeedback || '',
  updated_at: toIso(mark.updatedAt)
});

const quizInclude = {
  questions: true,
  createdBy: { select: { fullName: true } }
};

const allowedQuizClasses = async (req) => {
  if (req.user.role === 'ADMIN') return null;
  if (req.user.role === 'TEACHER') {
    const classes = await prisma.class.findMany({
      where: { academyId: req.academyId, primaryTeacherId: req.user.id },
      select: { id: true }
    });
    return classes.map((item) => item.id);
  }
  if (req.user.role === 'STUDENT') {
    const enrollments = await prisma.studentEnrollment.findMany({
      where: { studentId: req.user.id },
      select: { classId: true }
    });
    return enrollments.map((item) => item.classId);
  }
  if (req.user.role === 'PARENT') {
    const links = await prisma.parentStudent.findMany({
      where: { parentId: req.user.id },
      select: { studentId: true }
    });
    const enrollments = await prisma.studentEnrollment.findMany({
      where: { studentId: { in: links.map((link) => link.studentId) } },
      select: { classId: true }
    });
    return enrollments.map((item) => item.classId);
  }
  return [];
};

const getQuizzes = async (req, res, next) => {
  try {
    const whereClause = { academyId: req.academyId };
    if (req.query.classId) {
      await assertClassInAcademy(req.query.classId, req.academyId);
      whereClause.classId = req.query.classId;
    }
    if (req.user.role !== 'ADMIN') {
      const classIds = await allowedQuizClasses(req);
      if (req.user.role === 'TEACHER') {
        whereClause.OR = [
          { createdById: req.user.id },
          { classId: { in: classIds } }
        ];
      } else if (!whereClause.classId) {
        whereClause.classId = { in: classIds };
      } else if (!classIds.includes(whereClause.classId)) {
        throw forbidden('You cannot access quizzes for this class.');
      }
    }

    const quizzes = await prisma.quiz.findMany({
      where: whereClause,
      include: quizInclude,
      orderBy: { createdAt: 'desc' },
      take: 500
    });
    const includeAnswers = req.user.role === 'ADMIN' || req.user.role === 'TEACHER';
    return sendSuccess(res, quizzes.map((quiz) => formatQuiz(quiz, includeAnswers)));
  } catch (err) {
    next(err);
  }
};

// Teachers may manage quizzes (and their marks) only for classes they
// teach or quizzes they created; admins may manage any quiz in the academy.
const assertCanManageQuiz = async (req, quiz) => {
  if (req.user.role === 'ADMIN') return;
  if (req.user.role !== 'TEACHER') throw forbidden();
  const allowed = await allowedQuizClasses(req);
  if (!allowed.includes(quiz.classId) && quiz.createdById !== req.user.id) {
    throw forbidden('You can only manage quizzes for your own classes.');
  }
};

const assertCanReadQuiz = async (req, quiz) => {
  if (req.user.role === 'ADMIN') return;
  if (req.user.role === 'TEACHER') return assertCanManageQuiz(req, quiz);
  const allowed = await allowedQuizClasses(req);
  if (!allowed.includes(quiz.classId)) {
    throw forbidden('You cannot access this quiz.');
  }
};

const roundMarks = (value, fallback) => {
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? Math.round(n) : fallback;
};

// Online-attempt settings shared by create and update. Returns the Prisma
// data fragment or throws a 400 on bad input. Unknown/absent keys are left
// untouched so legacy clients keep creating PAPER quizzes.
const attemptSettings = (body) => {
  const data = {};
  if (body.attemptMode !== undefined) {
    const mode = String(body.attemptMode || 'PAPER').toUpperCase();
    if (!['PAPER', 'ONLINE'].includes(mode)) {
      throw badRequest('attemptMode must be PAPER or ONLINE.');
    }
    data.attemptMode = mode;
  }
  for (const key of ['availableFrom', 'availableUntil']) {
    if (body[key] === undefined) continue;
    if (body[key] === null || body[key] === '') { data[key] = null; continue; }
    const d = new Date(body[key]);
    if (Number.isNaN(d.getTime())) throw badRequest(`${key} must be an ISO-8601 date-time.`);
    data[key] = d;
  }
  if (body.durationMinutes !== undefined) {
    if (body.durationMinutes === null || body.durationMinutes === '') {
      data.durationMinutes = null;
    } else {
      const n = Number(body.durationMinutes);
      if (!Number.isInteger(n) || n < 1 || n > 600) {
        throw badRequest('durationMinutes must be a whole number between 1 and 600.');
      }
      data.durationMinutes = n;
    }
  }
  if (data.availableFrom && data.availableUntil && data.availableFrom > data.availableUntil) {
    throw badRequest('availableFrom must be before availableUntil.');
  }
  return data;
};

const createQuiz = async (req, res, next) => {
  try {
    const {
      classId,
      classLabel,
      title,
      subject,
      totalMarks,
      questions,
      instructions,
      month,
      session,
      chapter,
      difficulty,
      testDate,
      paperMeta
    } = req.body;

    if (!classId || !title || !subject || !totalMarks || !Array.isArray(questions)) {
      return res.status(400).json({ success: false, message: 'Missing required quiz fields.' });
    }
    const classEntity = await assertClassInAcademy(classId, req.academyId);
    if (req.user.role === 'TEACHER' && classEntity.primaryTeacherId !== req.user.id) {
      throw forbidden('You can only create quizzes for your classes.');
    }

    const quiz = await prisma.quiz.create({
      data: {
        academyId: req.academyId,
        classId,
        classLabel: classLabel || `${classEntity.className} - ${classEntity.section}`,
        title: String(title).trim(),
        subject: String(subject).trim(),
        month: month || null,
        session: session || null,
        chapter: chapter || null,
        difficulty: difficulty || null,
        totalMarks: parseInt(totalMarks, 10),
        testDate: testDate ? new Date(testDate) : null,
        instructions: instructions || null,
        paperMeta: normalizePaperMeta(paperMeta),
        ...attemptSettings(req.body),
        createdById: req.user.id,
        questions: {
          create: questions.map((question) => ({
            text: String(question.text || '').trim(),
            type: question.type || 'short',
            options: Array.isArray(question.options) ? question.options : [],
            correctIndex: question.correct_index != null ? question.correct_index : null,
            marks: roundMarks(question.marks, 5),
            gradingKeywords: Array.isArray(question.grading_keywords)
              ? question.grading_keywords
              : []
          }))
        }
      },
      include: quizInclude
    });

    return sendSuccess(res, formatQuiz(quiz, true), {
      status: 201,
      message: 'Quiz created successfully.'
    });
  } catch (err) {
    next(err);
  }
};

// Optional AI question generation. Returns 501 (not an error) when no AI key
// is configured, so the Flutter client transparently falls back to its offline
// generator. Only returns raw question *items*; the client assembles the paper
// (sections, marks, answer key) exactly as it does for offline generation.
const aiGenerate = async (req, res, next) => {
  try {
    if (!aiQuestionService.isConfigured()) {
      return res.status(501).json({
        success: false,
        code: 'AI_NOT_CONFIGURED',
        message: 'AI generation is not enabled on this server.'
      });
    }
    const { subject } = req.body || {};
    if (!subject || !String(subject).trim()) {
      return res
        .status(400)
        .json({ success: false, message: 'subject is required.' });
    }
    const items = await aiQuestionService.generateItems({
      subject: String(subject).trim(),
      classLabel: String(req.body.classLabel || '').trim(),
      chapters: Array.isArray(req.body.chapters)
        ? req.body.chapters.map((c) => String(c))
        : [],
      difficulty: req.body.difficulty || 'Medium',
      mcqCount: Number(req.body.mcqCount) || 10,
      shortCount: Number(req.body.shortCount) || 8,
      longCount: Number(req.body.longCount) || 3
    });
    if (!items.length) {
      return res.status(502).json({
        success: false,
        code: 'AI_EMPTY',
        message: 'The AI returned no usable questions. Try again or use the '
          + 'offline generator.'
      });
    }
    return sendSuccess(res, { items });
  } catch (err) {
    if (err.status) {
      return res
        .status(err.status)
        .json({ success: false, code: 'AI_ERROR', message: err.message });
    }
    next(err);
  }
};

const getQuizById = async (req, res, next) => {
  try {
    const quiz = await prisma.quiz.findFirst({
      where: { id: req.params.id, academyId: req.academyId },
      include: quizInclude
    });
    if (!quiz) throw notFound('Quiz not found in academy.');
    await assertCanReadQuiz(req, quiz);
    const includeAnswers = req.user.role === 'ADMIN' || req.user.role === 'TEACHER';
    return sendSuccess(res, formatQuiz(quiz, includeAnswers));
  } catch (err) {
    next(err);
  }
};

const updateQuiz = async (req, res, next) => {
  try {
    const { id } = req.params;
    const existing = await prisma.quiz.findFirst({
      where: { id, academyId: req.academyId }
    });
    if (!existing) throw notFound('Quiz not found in academy.');
    if (req.user.role === 'TEACHER') {
      const allowed = await allowedQuizClasses(req);
      if (!allowed.includes(existing.classId) && existing.createdById !== req.user.id) {
        throw forbidden('You cannot edit this quiz.');
      }
      if (req.body.classId !== undefined && !allowed.includes(req.body.classId)) {
        throw forbidden('You cannot move this quiz to a class you do not teach.');
      }
    }

    const data = {};
    for (const field of ['title', 'subject', 'classLabel', 'month', 'session', 'chapter', 'difficulty', 'instructions']) {
      if (req.body[field] !== undefined) {
        data[field] = req.body[field] === null ? null : String(req.body[field]).trim() || null;
      }
    }
    if (req.body.totalMarks !== undefined) data.totalMarks = parseInt(req.body.totalMarks, 10);
    Object.assign(data, attemptSettings(req.body));
    if (req.body.paperMeta !== undefined) {
      data.paperMeta = normalizePaperMeta(req.body.paperMeta);
    }
    if (req.body.testDate !== undefined) {
      data.testDate = req.body.testDate ? new Date(req.body.testDate) : null;
    }
    if (req.body.classId !== undefined) {
      await assertClassInAcademy(req.body.classId, req.academyId);
      data.classId = req.body.classId;
    }

    const updated = await prisma.$transaction(async (tx) => {
      if (Array.isArray(req.body.questions)) {
        await tx.quizQuestion.deleteMany({ where: { quizId: id } });
        await tx.quizQuestion.createMany({
          data: req.body.questions.map((question) => ({
            quizId: id,
            text: String(question.text || '').trim(),
            type: question.type || 'short',
            options: Array.isArray(question.options) ? question.options : [],
            correctIndex: question.correct_index != null ? question.correct_index : null,
            marks: roundMarks(question.marks, 5),
            gradingKeywords: Array.isArray(question.grading_keywords)
              ? question.grading_keywords
              : []
          }))
        });
      }
      return tx.quiz.update({
        where: { id },
        data,
        include: quizInclude
      });
    });

    return sendSuccess(res, formatQuiz(updated, true), {
      message: 'Quiz updated successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const updateQuizQuestions = async (req, res, next) => {
  try {
    const { id } = req.params;
    const existing = await prisma.quiz.findFirst({
      where: { id, academyId: req.academyId }
    });
    if (!existing) throw notFound('Quiz not found in academy.');
    await assertCanManageQuiz(req, existing);
    if (!Array.isArray(req.body.questions)) {
      return res.status(400).json({ success: false, message: 'questions must be an array.' });
    }
    const updated = await prisma.$transaction(async (tx) => {
      await tx.quizQuestion.deleteMany({ where: { quizId: id } });
      await tx.quizQuestion.createMany({
        data: req.body.questions.map((question) => ({
          quizId: id,
          text: String(question.text || '').trim(),
          type: question.type || 'short',
          options: Array.isArray(question.options) ? question.options : [],
          correctIndex: question.correct_index != null ? question.correct_index : null,
          marks: roundMarks(question.marks, 5),
          gradingKeywords: Array.isArray(question.grading_keywords)
            ? question.grading_keywords
            : []
        }))
      });
      return tx.quiz.findUnique({ where: { id }, include: quizInclude });
    });
    return sendSuccess(res, formatQuiz(updated, true), {
      message: 'Quiz questions updated successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const deleteQuiz = async (req, res, next) => {
  try {
    const { id } = req.params;
    const existing = await prisma.quiz.findFirst({
      where: { id, academyId: req.academyId }
    });
    if (!existing) throw notFound('Quiz not found in academy.');
    await assertCanManageQuiz(req, existing);
    await prisma.quiz.delete({ where: { id } });
    return sendSuccess(res, { deleted: true }, { message: 'Quiz deleted successfully.' });
  } catch (err) {
    next(err);
  }
};

const upsertTestMark = async (req, res, next) => {
  try {
    const { quizId, studentId, marksObtained, teacherFeedback } = req.body;

    if (!quizId || !studentId || marksObtained == null) {
      return res.status(400).json({ success: false, message: 'quizId, studentId, and marksObtained are required.' });
    }

    const quiz = await prisma.quiz.findFirst({
      where: { id: quizId, academyId: req.academyId }
    });
    if (!quiz) throw notFound('Quiz not found in academy.');
    await assertCanManageQuiz(req, quiz);
    await assertEnrolledStudent(quiz.classId, studentId, req.academyId);
    const student = await assertStudentInAcademy(studentId, req.academyId);

    const total = quiz.totalMarks;
    const obtained = Number(marksObtained);
    if (!Number.isFinite(obtained) || obtained < 0 || obtained > total) {
      return res.status(400).json({
        success: false,
        message: `marksObtained must be between 0 and ${total}.`
      });
    }
    const percentage = total > 0 ? (obtained / total) * 100 : 0;
    const gradeLetter = calculateGrade(percentage);

    const testMark = await prisma.testMark.upsert({
      where: { quizId_studentId: { quizId, studentId } },
      create: {
        academyId: req.academyId,
        quizId,
        studentId,
        studentName: student.fullName,
        classId: quiz.classId,
        subject: quiz.subject,
        month: quiz.month || null,
        marksObtained: obtained,
        totalMarks: total,
        percentage,
        gradeLetter,
        teacherFeedback: teacherFeedback || null
      },
      update: {
        marksObtained: obtained,
        totalMarks: total,
        percentage,
        gradeLetter,
        teacherFeedback: teacherFeedback || null,
        updatedAt: new Date()
      }
    });

    return sendSuccess(res, formatMark(testMark), {
      message: 'Test mark saved successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const getStudentMarks = async (req, res, next) => {
  try {
    const { studentId } = req.params;
    await assertStudentInAcademy(studentId, req.academyId);
    if (!(await canReadStudent(req, studentId))) {
      throw forbidden('You cannot access this student marks.');
    }

    const marks = await prisma.testMark.findMany({
      where: { academyId: req.academyId, studentId },
      include: { quiz: true },
      orderBy: { updatedAt: 'desc' }
    });
    return sendSuccess(res, marks.map(formatMark));
  } catch (err) {
    next(err);
  }
};

const getMarksByQuiz = async (req, res, next) => {
  try {
    const quiz = await prisma.quiz.findFirst({
      where: { id: req.params.quizId, academyId: req.academyId }
    });
    if (!quiz) throw notFound('Quiz not found in academy.');
    if (req.user.role === 'TEACHER') {
      const allowed = await allowedQuizClasses(req);
      if (!allowed.includes(quiz.classId) && quiz.createdById !== req.user.id) {
        throw forbidden('You cannot access results for this quiz.');
      }
    }
    const marks = await prisma.testMark.findMany({
      where: { academyId: req.academyId, quizId: quiz.id },
      orderBy: { studentName: 'asc' }
    });
    return sendSuccess(res, marks.map(formatMark));
  } catch (err) {
    next(err);
  }
};

const getMarksByClass = async (req, res, next) => {
  try {
    const classId = req.params.classId;
    await assertClassInAcademy(classId, req.academyId);
    if (req.user.role === 'TEACHER') {
      const allowed = await allowedQuizClasses(req);
      if (!allowed.includes(classId)) throw forbidden('You cannot access marks for this class.');
    }
    const marks = await prisma.testMark.findMany({
      where: { academyId: req.academyId, classId },
      orderBy: [{ month: 'desc' }, { studentName: 'asc' }]
    });
    return sendSuccess(res, marks.map(formatMark));
  } catch (err) {
    next(err);
  }
};

const getAllAcademyMarks = async (req, res, next) => {
  try {
    const where = { academyId: req.academyId };
    if (req.query.month) where.month = String(req.query.month);
    if (req.user.role === 'TEACHER') {
      const allowed = await allowedQuizClasses(req);
      where.classId = { in: allowed };
    }
    const marks = await prisma.testMark.findMany({
      where,
      orderBy: [{ updatedAt: 'desc' }],
      take: 5000
    });
    return sendSuccess(res, marks.map(formatMark));
  } catch (err) {
    next(err);
  }
};

const deleteMark = async (req, res, next) => {
  try {
    const mark = await prisma.testMark.findFirst({
      where: { id: req.params.id, academyId: req.academyId }
    });
    if (!mark) throw notFound('Test mark not found in academy.');
    if (req.user.role === 'TEACHER') {
      const allowed = await allowedQuizClasses(req);
      if (!allowed.includes(mark.classId)) {
        throw forbidden('You cannot delete this mark.');
      }
    }
    await prisma.testMark.delete({ where: { id: mark.id } });
    return sendSuccess(res, { deleted: true }, { message: 'Test mark deleted successfully.' });
  } catch (err) {
    next(err);
  }
};

module.exports = {
  getQuizzes,
  getQuizById,
  aiGenerate,
  createQuiz,
  updateQuiz,
  updateQuizQuestions,
  deleteQuiz,
  upsertTestMark,
  getStudentMarks,
  getMarksByQuiz,
  getMarksByClass,
  getAllAcademyMarks,
  deleteMark
};
