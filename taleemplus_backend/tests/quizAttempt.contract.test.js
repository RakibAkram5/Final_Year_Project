/**
 * Online quiz attempt contract tests.
 *
 * Covers the student attempt lifecycle (start → autosave → submit), server-side
 * MCQ grading, idempotent submission, answer-key secrecy before submission,
 * teacher review/grading of written answers, parent read access through the
 * linked child, and tenant/role isolation. Runs only with TEST_DATABASE_URL.
 */
const request = require('supertest');
const app = require('../src/app');
const prisma = require('../src/config/db');
const { createAcademyTeam, createClass, enrollStudent } = require('./helpers/contractFixtures');
const { _internal } = require('../src/controllers/quizAttemptController');

const describeWithDatabase = process.env.TEST_DATABASE_URL ? describe : describe.skip;
const api = (method, path, token) => {
  const req = request(app)[method](`/api/v2${path}`);
  return token ? req.set('Authorization', `Bearer ${token}`) : req;
};

describe('gradeObjective (pure)', () => {
  const quiz = {
    questions: [
      { id: 'q1', type: 'mcq', correctIndex: 2, marks: 2 },
      { id: 'q2', type: 'mcq', correctIndex: 0, marks: 3 },
      { id: 'q3', type: 'short', correctIndex: null, marks: 5 }
    ]
  };

  it('awards full marks for correct MCQs, zero otherwise, and flags written answers for review', () => {
    const r = _internal.gradeObjective(quiz, [
      { questionId: 'q1', selectedIndex: 2 },
      { questionId: 'q2', selectedIndex: 1 }
    ]);
    expect(r.autoScore).toBe(2);
    expect(r.autoMax).toBe(5);
    expect(r.needsReview).toBe(true);
    expect(r.updates.find((u) => u.questionId === 'q1')).toMatchObject({ isCorrect: true, marksAwarded: 2 });
    expect(r.updates.find((u) => u.questionId === 'q2')).toMatchObject({ isCorrect: false, marksAwarded: 0 });
  });

  it('treats an unanswered MCQ as wrong and an all-MCQ quiz as fully graded', () => {
    const mcqOnly = { questions: quiz.questions.slice(0, 2) };
    const r = _internal.gradeObjective(mcqOnly, []);
    expect(r.autoScore).toBe(0);
    expect(r.needsReview).toBe(false);
    expect(r.updates).toHaveLength(2);
  });

  it('computes the earliest of duration and availability deadlines', () => {
    const startedAt = new Date('2026-11-13T10:00:00Z');
    const d1 = _internal.attemptDeadline({ startedAt }, { durationMinutes: 30, availableUntil: new Date('2026-11-13T10:10:00Z') });
    expect(d1.toISOString()).toBe('2026-11-13T10:10:00.000Z');
    const d2 = _internal.attemptDeadline({ startedAt }, { durationMinutes: 30 });
    expect(d2.toISOString()).toBe('2026-11-13T10:30:00.000Z');
    expect(_internal.attemptDeadline({ startedAt }, {})).toBeNull();
  });
});

describeWithDatabase('online quiz attempts', () => {
  jest.setTimeout(120000);
  let A; let B; let cls; let online; let paper; let strangerStudent;

  beforeAll(async () => {
    A = await createAcademyTeam('QuizA');
    B = await createAcademyTeam('QuizB');
    cls = await createClass(A.tokens.admin, {
      className: 'Online 9', section: 'Q', primaryTeacherId: A.teacher.user.id
    });
    await enrollStudent(A.tokens.admin, cls.id, A.student.user.id);
    await prisma.parentStudent.create({
      data: { parentId: A.parent.user.id, studentId: A.student.user.id }
    });
    // A second A-academy student who is NOT enrolled in the class.
    strangerStudent = await (async () => {
      const r = await api('post', '/users/create', A.tokens.admin).send({
        email: `stranger-${Date.now()}@test.taleemplus`, password: 'ContractTest!7',
        fullName: 'Not Enrolled', role: 'student'
      });
      const login = await api('post', '/auth/login').send({ email: r.body.data.email, password: 'ContractTest!7' });
      return { user: r.body.data, token: login.body.data.tokens.accessToken };
    })();

    const create = await api('post', '/quizzes', A.tokens.teacher).send({
      classId: cls.id, title: 'Online Quiz', subject: 'Science', totalMarks: 10,
      attemptMode: 'ONLINE', durationMinutes: 30,
      questions: [
        { text: 'Water is', type: 'mcq', options: ['Solid', 'Liquid', 'Gas', 'Plasma'], correct_index: 1, marks: 2 },
        { text: 'Sun is a', type: 'mcq', options: ['Planet', 'Star', 'Moon', 'Comet'], correct_index: 1, marks: 3 },
        { text: 'Explain photosynthesis', type: 'short', marks: 5 }
      ]
    });
    expect(create.statusCode).toBe(201);
    online = create.body.data;
    expect(online.attempt_mode).toBe('ONLINE');
    expect(online.duration_minutes).toBe(30);

    const paperRes = await api('post', '/quizzes', A.tokens.teacher).send({
      classId: cls.id, title: 'Paper Quiz', subject: 'Science', totalMarks: 5,
      questions: [{ text: 'Q', type: 'mcq', options: ['a', 'b'], correct_index: 0, marks: 5 }]
    });
    paper = paperRes.body.data;
    expect(paper.attempt_mode).toBe('PAPER');
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('rejects bad attempt settings on create', async () => {
    const bad = await api('post', '/quizzes', A.tokens.teacher).send({
      classId: cls.id, title: 'Bad', subject: 'S', totalMarks: 1, attemptMode: 'LIVE', questions: []
    });
    expect(bad.statusCode).toBe(400);
    const badDur = await api('post', '/quizzes', A.tokens.teacher).send({
      classId: cls.id, title: 'Bad', subject: 'S', totalMarks: 1, attemptMode: 'ONLINE', durationMinutes: 0, questions: []
    });
    expect(badDur.statusCode).toBe(400);
  });

  it('students never receive correct answers in the quiz payload', async () => {
    const asStudent = await api('get', `/quizzes/${online.id}`, A.tokens.student);
    expect(asStudent.statusCode).toBe(200);
    for (const q of asStudent.body.data.questions) {
      expect(q).not.toHaveProperty('correct_index');
      expect(q).not.toHaveProperty('grading_keywords');
    }
  });

  it('a paper quiz cannot be attempted online; non-enrolled students and teachers are refused', async () => {
    expect((await api('post', `/quizzes/${paper.id}/attempt`, A.tokens.student)).statusCode).toBe(400);
    expect((await api('post', `/quizzes/${online.id}/attempt`, strangerStudent.token)).statusCode).toBe(403);
    expect((await api('post', `/quizzes/${online.id}/attempt`, A.tokens.teacher)).statusCode).toBe(403);
    expect((await api('post', `/quizzes/${online.id}/attempt`, B.tokens.student)).statusCode).toBe(404);
  });

  it('start → autosave → submit grades MCQs server-side, flags the written answer, and is idempotent', async () => {
    const start = await api('post', `/quizzes/${online.id}/attempt`, A.tokens.student);
    expect(start.statusCode).toBe(201);
    expect(start.body.data.status).toBe('IN_PROGRESS');
    expect(start.body.data.deadline).toBeTruthy();
    expect(start.body.data.auto_score).toBeNull();

    // Starting again resumes the same attempt.
    const again = await api('post', `/quizzes/${online.id}/attempt`, A.tokens.student);
    expect(again.body.data.id).toBe(start.body.data.id);

    const [q1, q2, q3] = online.questions;
    const save = await api('put', `/quizzes/${online.id}/attempt/answers`, A.tokens.student)
      .send({ answers: [{ questionId: q1.id, selectedIndex: 1 }, { questionId: q3.id, answerText: 'Plants make food from light.' }] });
    expect(save.statusCode).toBe(200);
    expect(save.body.data.answers).toHaveLength(2);
    // No correctness leaks while in progress.
    expect(save.body.data.answers[0]).not.toHaveProperty('is_correct');

    const outOfRange = await api('put', `/quizzes/${online.id}/attempt/answers`, A.tokens.student)
      .send({ answers: [{ questionId: q2.id, selectedIndex: 9 }] });
    expect(outOfRange.statusCode).toBe(400);

    // In-progress read by the student: still no answer key.
    const mid = await api('get', `/quizzes/${online.id}/attempt`, A.tokens.student);
    expect(mid.body.data).not.toHaveProperty('correct_indexes');

    const submit = await api('post', `/quizzes/${online.id}/attempt/submit`, A.tokens.student)
      .send({ answers: [{ questionId: q2.id, selectedIndex: 0 }] }); // wrong on purpose
    expect(submit.statusCode).toBe(200);
    expect(submit.body.data.status).toBe('SUBMITTED');
    expect(submit.body.data.needs_review).toBe(true);
    expect(submit.body.data.auto_score).toBe(2);
    expect(submit.body.data.auto_max_score).toBe(5);
    const a1 = submit.body.data.answers.find((a) => a.question_id === q1.id);
    const a2 = submit.body.data.answers.find((a) => a.question_id === q2.id);
    expect(a1).toMatchObject({ is_correct: true, marks_awarded: 2 });
    expect(a2).toMatchObject({ is_correct: false, marks_awarded: 0 });

    // Retry (dropped connection): same submission, nothing re-graded.
    const retry = await api('post', `/quizzes/${online.id}/attempt/submit`, A.tokens.student).send({});
    expect(retry.statusCode).toBe(200);
    expect(retry.body.data.id).toBe(submit.body.data.id);
    expect(retry.body.data.submitted_at).toBe(submit.body.data.submitted_at);

    // No more edits after submission.
    const late = await api('put', `/quizzes/${online.id}/attempt/answers`, A.tokens.student)
      .send({ answers: [{ questionId: q2.id, selectedIndex: 1 }] });
    expect(late.statusCode).toBe(409);

    // After submission the student can see the key; no TestMark yet.
    const after = await api('get', `/quizzes/${online.id}/attempt`, A.tokens.student);
    expect(after.body.data.correct_indexes[q2.id]).toBe(1);
    const marks = await api('get', `/quizzes/marks/student/${A.student.user.id}`, A.tokens.student);
    expect(marks.body.data.find((m) => m.quiz_id === online.id)).toBeUndefined();
  });

  it('teacher lists submissions, grades the written answer, and the result is published as a TestMark', async () => {
    const q3 = online.questions[2];
    const list = await api('get', `/quizzes/${online.id}/submissions`, A.tokens.teacher);
    expect(list.statusCode).toBe(200);
    expect(list.body.data).toHaveLength(1);
    expect(list.body.data[0].student_name).toBe(A.student.user.fullName);
    const sid = list.body.data[0].id;

    // Other teachers / other academies / students are refused.
    expect((await api('get', `/quizzes/${online.id}/submissions`, B.tokens.teacher)).statusCode).toBe(404);
    expect((await api('get', `/quizzes/${online.id}/submissions`, A.tokens.student)).statusCode).toBe(403);

    const tooMuch = await api('put', `/quizzes/${online.id}/submissions/${sid}/grade`, A.tokens.teacher)
      .send({ marks: [{ questionId: q3.id, marksAwarded: 9 }] });
    expect(tooMuch.statusCode).toBe(400);

    const graded = await api('put', `/quizzes/${online.id}/submissions/${sid}/grade`, A.tokens.teacher)
      .send({ marks: [{ questionId: q3.id, marksAwarded: 4 }], teacherNote: 'Good effort' });
    expect(graded.statusCode).toBe(200);
    expect(graded.body.data.status).toBe('GRADED');
    expect(graded.body.data.final_score).toBe(6);
    expect(graded.body.data.needs_review).toBe(false);

    const marks = await api('get', `/quizzes/marks/student/${A.student.user.id}`, A.tokens.student);
    const mark = marks.body.data.find((m) => m.quiz_id === online.id);
    expect(mark).toMatchObject({ marks_obtained: 6, total_marks: 10, percentage: 60, grade_letter: 'C' });
  });

  it('a linked parent can read the child attempt; an unrelated parent cannot', async () => {
    const ok = await api('get', `/quizzes/${online.id}/attempt?studentId=${A.student.user.id}`, A.tokens.parent);
    expect(ok.statusCode).toBe(200);
    expect(ok.body.data.final_score).toBe(6);
    const other = await api('get', `/quizzes/${online.id}/attempt?studentId=${A.student.user.id}`, B.tokens.parent);
    expect(other.statusCode).toBe(404);
  });

  it('an all-MCQ quiz is graded and published immediately on submit', async () => {
    const create = await api('post', '/quizzes', A.tokens.teacher).send({
      classId: cls.id, title: 'MCQ Only', subject: 'Maths', totalMarks: 4, attemptMode: 'ONLINE',
      questions: [
        { text: '1+1', type: 'mcq', options: ['1', '2', '3'], correct_index: 1, marks: 2 },
        { text: '2+2', type: 'mcq', options: ['3', '4', '5'], correct_index: 1, marks: 2 }
      ]
    });
    const quiz = create.body.data;
    await api('post', `/quizzes/${quiz.id}/attempt`, A.tokens.student);
    const submit = await api('post', `/quizzes/${quiz.id}/attempt/submit`, A.tokens.student).send({
      answers: quiz.questions.map((q) => ({ questionId: q.id, selectedIndex: 1 }))
    });
    expect(submit.statusCode).toBe(200);
    expect(submit.body.data.status).toBe('GRADED');
    expect(submit.body.data.final_score).toBe(4);
    const marks = await api('get', `/quizzes/marks/quiz/${quiz.id}`, A.tokens.teacher);
    expect(marks.body.data[0]).toMatchObject({ marks_obtained: 4, percentage: 100, grade_letter: 'A+' });
  });

  it('refuses to start after the availability deadline', async () => {
    const create = await api('post', '/quizzes', A.tokens.teacher).send({
      classId: cls.id, title: 'Closed', subject: 'Maths', totalMarks: 2, attemptMode: 'ONLINE',
      availableUntil: '2020-01-01T00:00:00.000Z',
      questions: [{ text: 'x', type: 'mcq', options: ['a', 'b'], correct_index: 0, marks: 2 }]
    });
    expect(create.statusCode).toBe(201);
    const start = await api('post', `/quizzes/${create.body.data.id}/attempt`, A.tokens.student);
    expect(start.statusCode).toBe(400);
  });
});
