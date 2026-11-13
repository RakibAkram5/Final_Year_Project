/**
 * Online quiz attempts.
 *
 * A quiz with attemptMode = 'ONLINE' can be attempted by an enrolled student
 * in the student portal. Flow:
 *
 *   POST /quizzes/:id/attempt            start (or resume) the attempt
 *   PUT  /quizzes/:id/attempt/answers    autosave answers while IN_PROGRESS
 *   POST /quizzes/:id/attempt/submit     finalise: MCQs graded server-side
 *   GET  /quizzes/:id/attempt            own attempt (parent: ?studentId)
 *   GET  /quizzes/:id/submissions        teacher/admin: every submission
 *   PUT  /quizzes/:id/submissions/:sid/grade  teacher awards short/long marks
 *
 * Invariants:
 *  - Correct answers are never sent to a student before their submission.
 *  - Exactly one submission per (quiz, student) (DB unique constraint), so a
 *    retried submit returns the already-graded row instead of grading twice.
 *  - A submission becomes a TestMark only when every question has a score
 *    (all-MCQ quizzes immediately; mixed quizzes after teacher grading).
 */
const prisma = require('../config/db');
const { forbidden, notFound, badRequest, conflict } = require('../utils/apiError');
const { sendSuccess } = require('../utils/response');
const { toIso } = require('../utils/dto');
const { canReadStudent } = require('../utils/studentAccess');

const GRACE_SECONDS = 60; // network/clock slack on timed attempts

const calculateGrade = (percentage) => {
  if (percentage >= 90) return 'A+';
  if (percentage >= 80) return 'A';
  if (percentage >= 70) return 'B';
  if (percentage >= 60) return 'C';
  if (percentage >= 50) return 'D';
  return 'F';
};

const formatAnswer = (answer, { reveal }) => ({
  question_id: answer.questionId,
  selected_index: answer.selectedIndex,
  answer_text: answer.answerText || '',
  ...(reveal
    ? { is_correct: answer.isCorrect, marks_awarded: answer.marksAwarded }
    : {})
});

const formatSubmission = (submission, { reveal, quiz }) => {
  const answers = (submission.answers || []).map((a) => formatAnswer(a, { reveal }));
  const deadline = attemptDeadline(submission, quiz);
  return {
    id: submission.id,
    quiz_id: submission.quizId,
    student_id: submission.studentId,
    student_name: submission.student?.fullName || undefined,
    status: submission.status,
    started_at: toIso(submission.startedAt),
    submitted_at: toIso(submission.submittedAt),
    graded_at: toIso(submission.gradedAt),
    deadline: deadline ? deadline.toISOString() : null,
    auto_score: reveal ? submission.autoScore : null,
    auto_max_score: reveal ? submission.autoMaxScore : null,
    final_score: reveal ? submission.finalScore : null,
    needs_review: submission.needsReview,
    teacher_note: reveal ? submission.teacherNote || '' : '',
    answers
  };
};

/** When this attempt must be submitted by (duration and/or availability). */
const attemptDeadline = (submission, quiz) => {
  const candidates = [];
  if (quiz?.durationMinutes && submission?.startedAt) {
    candidates.push(new Date(submission.startedAt.getTime() + quiz.durationMinutes * 60_000));
  }
  if (quiz?.availableUntil) candidates.push(new Date(quiz.availableUntil));
  if (!candidates.length) return null;
  return new Date(Math.min(...candidates.map((d) => d.getTime())));
};

const loadQuiz = async (req) => {
  const quiz = await prisma.quiz.findFirst({
    where: { id: req.params.id, academyId: req.academyId },
    include: { questions: true }
  });
  if (!quiz) throw notFound('Quiz not found in academy.');
  return quiz;
};

const assertStudentMayAttempt = async (req, quiz) => {
  if (req.user.role !== 'STUDENT') throw forbidden('Only students can attempt a quiz.');
  if (quiz.attemptMode !== 'ONLINE') {
    throw badRequest('This test is conducted on paper and cannot be attempted online.');
  }
  const enrollment = await prisma.studentEnrollment.findUnique({
    where: { classId_studentId: { classId: quiz.classId, studentId: req.user.id } }
  });
  if (!enrollment) throw forbidden('You are not enrolled in this class.');
};

const assertTeacherMayReview = async (req, quiz) => {
  if (req.user.role === 'ADMIN') return;
  if (req.user.role !== 'TEACHER') throw forbidden();
  const cls = await prisma.class.findFirst({
    where: { id: quiz.classId, academyId: req.academyId },
    select: { primaryTeacherId: true }
  });
  if (cls?.primaryTeacherId !== req.user.id && quiz.createdById !== req.user.id) {
    throw forbidden('You can only review submissions for your own classes.');
  }
};

const submissionInclude = { answers: true, student: { select: { fullName: true } } };

// ---------------------------------------------------------------------------
// Student: start / resume
// ---------------------------------------------------------------------------
const startAttempt = async (req, res, next) => {
  try {
    const quiz = await loadQuiz(req);
    await assertStudentMayAttempt(req, quiz);
    const now = new Date();
    if (quiz.availableFrom && now < quiz.availableFrom) {
      throw badRequest('This test is not open yet.');
    }

    let submission = await prisma.quizSubmission.findUnique({
      where: { quizId_studentId: { quizId: quiz.id, studentId: req.user.id } },
      include: submissionInclude
    });
    if (submission && submission.status !== 'IN_PROGRESS') {
      // Already submitted: return it (with results) rather than a new attempt.
      return sendSuccess(res, formatSubmission(submission, { reveal: true, quiz }), {
        message: 'This test has already been submitted.'
      });
    }
    if (!submission) {
      if (quiz.availableUntil && now > quiz.availableUntil) {
        throw badRequest('The deadline for this test has passed.');
      }
      try {
        submission = await prisma.quizSubmission.create({
          data: { academyId: req.academyId, quizId: quiz.id, studentId: req.user.id },
          include: submissionInclude
        });
      } catch (err) {
        // Two parallel starts: the unique constraint wins; load the row.
        if (err.code !== 'P2002') throw err;
        submission = await prisma.quizSubmission.findUnique({
          where: { quizId_studentId: { quizId: quiz.id, studentId: req.user.id } },
          include: submissionInclude
        });
      }
    }
    return sendSuccess(res, formatSubmission(submission, { reveal: false, quiz }), {
      status: 201
    });
  } catch (err) {
    next(err);
  }
};

const normalizeAnswers = (quiz, rawAnswers) => {
  if (!Array.isArray(rawAnswers)) throw badRequest('answers must be an array.');
  const byId = new Map(quiz.questions.map((q) => [q.id, q]));
  const out = [];
  for (const raw of rawAnswers) {
    const questionId = String(raw?.questionId ?? raw?.question_id ?? '');
    const question = byId.get(questionId);
    if (!question) throw badRequest('answers reference a question that is not in this quiz.');
    const rawIndex = raw.selectedIndex ?? raw.selected_index;
    let selectedIndex = null;
    if (rawIndex !== null && rawIndex !== undefined && rawIndex !== '') {
      selectedIndex = Number(rawIndex);
      if (!Number.isInteger(selectedIndex) || selectedIndex < 0 ||
          selectedIndex >= (question.options || []).length) {
        throw badRequest('selectedIndex is out of range for its question.');
      }
    }
    const text = raw.answerText ?? raw.answer_text;
    const answerText = text == null ? null : String(text).slice(0, 5000);
    out.push({ questionId, selectedIndex, answerText });
  }
  return out;
};

const assertOpenForWriting = (submission, quiz) => {
  if (!submission) throw notFound('Start the test before saving answers.');
  if (submission.status !== 'IN_PROGRESS') {
    throw conflict('This test has already been submitted.');
  }
  const deadline = attemptDeadline(submission, quiz);
  if (deadline && Date.now() > deadline.getTime() + GRACE_SECONDS * 1000) {
    throw conflict('The time for this test is over.');
  }
};

// ---------------------------------------------------------------------------
// Student: autosave
// ---------------------------------------------------------------------------
const saveAnswers = async (req, res, next) => {
  try {
    const quiz = await loadQuiz(req);
    await assertStudentMayAttempt(req, quiz);
    const submission = await prisma.quizSubmission.findUnique({
      where: { quizId_studentId: { quizId: quiz.id, studentId: req.user.id } }
    });
    assertOpenForWriting(submission, quiz);
    const answers = normalizeAnswers(quiz, req.body.answers);

    await prisma.$transaction(
      answers.map((a) =>
        prisma.quizAnswer.upsert({
          where: { submissionId_questionId: { submissionId: submission.id, questionId: a.questionId } },
          create: { submissionId: submission.id, ...a },
          update: { selectedIndex: a.selectedIndex, answerText: a.answerText }
        })
      )
    );
    const fresh = await prisma.quizSubmission.findUnique({
      where: { id: submission.id },
      include: submissionInclude
    });
    return sendSuccess(res, formatSubmission(fresh, { reveal: false, quiz }), {
      message: 'Answers saved.'
    });
  } catch (err) {
    next(err);
  }
};

/** Grades MCQs; returns per-answer updates and totals. */
const gradeObjective = (quiz, answers) => {
  const byId = new Map(answers.map((a) => [a.questionId, a]));
  let autoScore = 0;
  let autoMax = 0;
  let needsReview = false;
  const updates = [];
  for (const q of quiz.questions) {
    const a = byId.get(q.id);
    const isMcq = q.type === 'mcq' && q.correctIndex !== null && q.correctIndex !== undefined;
    if (isMcq) {
      autoMax += q.marks;
      const correct = a != null && a.selectedIndex === q.correctIndex;
      if (correct) autoScore += q.marks;
      updates.push({
        questionId: q.id,
        isCorrect: correct,
        marksAwarded: correct ? q.marks : 0,
        existing: !!a
      });
    } else {
      needsReview = true;
    }
  }
  return { autoScore, autoMax, needsReview, updates };
};

const upsertTestMarkFromSubmission = async (tx, quiz, submission, finalScore, feedback) => {
  const student = await tx.user.findUnique({ where: { id: submission.studentId } });
  const total = quiz.totalMarks;
  const obtained = Math.min(Math.max(finalScore, 0), total);
  const percentage = total > 0 ? (obtained / total) * 100 : 0;
  return tx.testMark.upsert({
    where: { quizId_studentId: { quizId: quiz.id, studentId: submission.studentId } },
    create: {
      academyId: quiz.academyId,
      quizId: quiz.id,
      studentId: submission.studentId,
      studentName: student?.fullName || 'Student',
      classId: quiz.classId,
      subject: quiz.subject,
      month: quiz.month || null,
      marksObtained: obtained,
      totalMarks: total,
      percentage,
      gradeLetter: calculateGrade(percentage),
      teacherFeedback: feedback || 'Online test'
    },
    update: {
      marksObtained: obtained,
      totalMarks: total,
      percentage,
      gradeLetter: calculateGrade(percentage),
      ...(feedback ? { teacherFeedback: feedback } : {}),
      updatedAt: new Date()
    }
  });
};

// ---------------------------------------------------------------------------
// Student: submit (idempotent)
// ---------------------------------------------------------------------------
const submitAttempt = async (req, res, next) => {
  try {
    const quiz = await loadQuiz(req);
    await assertStudentMayAttempt(req, quiz);
    const existing = await prisma.quizSubmission.findUnique({
      where: { quizId_studentId: { quizId: quiz.id, studentId: req.user.id } },
      include: submissionInclude
    });
    if (existing && existing.status !== 'IN_PROGRESS') {
      // Retry after a dropped connection: nothing is graded twice.
      return sendSuccess(res, formatSubmission(existing, { reveal: true, quiz }), {
        message: 'Already submitted.'
      });
    }
    assertOpenForWriting(existing, quiz);
    const incoming = req.body.answers === undefined ? [] : normalizeAnswers(quiz, req.body.answers);

    const result = await prisma.$transaction(async (tx) => {
      for (const a of incoming) {
        await tx.quizAnswer.upsert({
          where: { submissionId_questionId: { submissionId: existing.id, questionId: a.questionId } },
          create: { submissionId: existing.id, ...a },
          update: { selectedIndex: a.selectedIndex, answerText: a.answerText }
        });
      }
      const answers = await tx.quizAnswer.findMany({ where: { submissionId: existing.id } });
      const { autoScore, autoMax, needsReview, updates } = gradeObjective(quiz, answers);
      for (const u of updates) {
        await tx.quizAnswer.upsert({
          where: { submissionId_questionId: { submissionId: existing.id, questionId: u.questionId } },
          create: {
            submissionId: existing.id,
            questionId: u.questionId,
            isCorrect: u.isCorrect,
            marksAwarded: u.marksAwarded
          },
          update: { isCorrect: u.isCorrect, marksAwarded: u.marksAwarded }
        });
      }
      const now = new Date();
      const graded = !needsReview;
      const updated = await tx.quizSubmission.update({
        where: { id: existing.id },
        data: {
          status: graded ? 'GRADED' : 'SUBMITTED',
          submittedAt: now,
          gradedAt: graded ? now : null,
          autoScore,
          autoMaxScore: autoMax,
          finalScore: graded ? autoScore : null,
          needsReview
        },
        include: submissionInclude
      });
      if (graded) await upsertTestMarkFromSubmission(tx, quiz, updated, autoScore, null);
      return updated;
    });

    return sendSuccess(res, formatSubmission(result, { reveal: true, quiz }), {
      message: result.needsReview
        ? 'Submitted. Objective questions were graded; written answers await your teacher.'
        : 'Submitted and graded.'
    });
  } catch (err) {
    next(err);
  }
};

// ---------------------------------------------------------------------------
// Read one attempt (student: own; parent: linked child; staff: ?studentId)
// ---------------------------------------------------------------------------
const getAttempt = async (req, res, next) => {
  try {
    const quiz = await loadQuiz(req);
    let studentId = req.user.id;
    if (req.user.role !== 'STUDENT') {
      studentId = String(req.query.studentId || '');
      if (!studentId) throw badRequest('studentId is required.');
      if (req.user.role === 'PARENT') {
        if (!(await canReadStudent(req, studentId))) throw forbidden();
      } else {
        await assertTeacherMayReview(req, quiz);
      }
    }
    const submission = await prisma.quizSubmission.findUnique({
      where: { quizId_studentId: { quizId: quiz.id, studentId } },
      include: submissionInclude
    });
    if (!submission) throw notFound('No attempt found for this test.');
    // Students (and parents) only see correctness once the attempt is closed.
    const reveal = req.user.role === 'ADMIN' || req.user.role === 'TEACHER' ||
      submission.status !== 'IN_PROGRESS';
    const payload = formatSubmission(submission, { reveal, quiz });
    if (reveal) {
      payload.correct_indexes = Object.fromEntries(
        quiz.questions.filter((q) => q.type === 'mcq').map((q) => [q.id, q.correctIndex])
      );
    }
    return sendSuccess(res, payload);
  } catch (err) {
    next(err);
  }
};

// ---------------------------------------------------------------------------
// Teacher / admin: list submissions for a quiz
// ---------------------------------------------------------------------------
const listSubmissions = async (req, res, next) => {
  try {
    const quiz = await loadQuiz(req);
    await assertTeacherMayReview(req, quiz);
    const rows = await prisma.quizSubmission.findMany({
      where: { quizId: quiz.id, academyId: req.academyId },
      include: submissionInclude,
      orderBy: [{ status: 'asc' }, { submittedAt: 'desc' }]
    });
    return sendSuccess(res, rows.map((row) => formatSubmission(row, { reveal: true, quiz })));
  } catch (err) {
    next(err);
  }
};

// ---------------------------------------------------------------------------
// Teacher / admin: award marks for written answers, finalise the TestMark
// ---------------------------------------------------------------------------
const gradeSubmission = async (req, res, next) => {
  try {
    const quiz = await loadQuiz(req);
    await assertTeacherMayReview(req, quiz);
    const submission = await prisma.quizSubmission.findFirst({
      where: { id: req.params.sid, quizId: quiz.id, academyId: req.academyId },
      include: { answers: true }
    });
    if (!submission) throw notFound('Submission not found.');
    if (submission.status === 'IN_PROGRESS') {
      throw conflict('The student has not submitted this test yet.');
    }
    const marks = Array.isArray(req.body.marks) ? req.body.marks : [];
    const byId = new Map(quiz.questions.map((q) => [q.id, q]));
    const awards = [];
    for (const raw of marks) {
      const questionId = String(raw?.questionId ?? raw?.question_id ?? '');
      const q = byId.get(questionId);
      if (!q) throw badRequest('marks reference a question that is not in this quiz.');
      const value = Number(raw.marksAwarded ?? raw.marks_awarded);
      if (!Number.isFinite(value) || value < 0 || value > q.marks) {
        throw badRequest(`Marks for a question must be between 0 and ${q.marks}.`);
      }
      awards.push({ questionId, marksAwarded: value });
    }
    const note = req.body.teacherNote != null ? String(req.body.teacherNote).slice(0, 1000) : undefined;

    const updated = await prisma.$transaction(async (tx) => {
      for (const a of awards) {
        await tx.quizAnswer.upsert({
          where: { submissionId_questionId: { submissionId: submission.id, questionId: a.questionId } },
          create: { submissionId: submission.id, questionId: a.questionId, marksAwarded: a.marksAwarded },
          update: { marksAwarded: a.marksAwarded }
        });
      }
      const answers = await tx.quizAnswer.findMany({ where: { submissionId: submission.id } });
      const scored = new Map(answers.map((a) => [a.questionId, a.marksAwarded]));
      const allScored = quiz.questions.every((q) => Number.isFinite(scored.get(q.id)));
      const finalScore = quiz.questions.reduce((sum, q) => sum + (scored.get(q.id) || 0), 0);
      const row = await tx.quizSubmission.update({
        where: { id: submission.id },
        data: {
          status: allScored ? 'GRADED' : 'SUBMITTED',
          needsReview: !allScored,
          finalScore: allScored ? finalScore : null,
          gradedAt: allScored ? new Date() : null,
          ...(note !== undefined ? { teacherNote: note } : {})
        },
        include: submissionInclude
      });
      if (allScored) await upsertTestMarkFromSubmission(tx, quiz, row, finalScore, note);
      return row;
    });

    return sendSuccess(res, formatSubmission(updated, { reveal: true, quiz }), {
      message: updated.needsReview
        ? 'Marks saved; some questions are still ungraded.'
        : 'Submission graded and result published.'
    });
  } catch (err) {
    next(err);
  }
};

module.exports = {
  startAttempt,
  saveAnswers,
  submitAttempt,
  getAttempt,
  listSubmissions,
  gradeSubmission,
  // exported for unit tests
  _internal: { gradeObjective, attemptDeadline }
};
