#!/usr/bin/env node
/**
 * SYNTHETIC data for demonstrating the ML pipeline end to end.
 *
 * Creates one clearly labelled academy, "[SYNTHETIC] ML Demo Academy"
 * (code SYNTH-ML-DEMO), with 60 synthetic students and 12 months of fee
 * challans, attendance and test marks. Each student has a hidden
 * "diligence" value that drives attendance, payment punctuality and marks,
 * so the models have a real (but artificial) signal to learn.
 *
 * Metrics obtained on this data describe the pipeline on synthetic data
 * only. They are NOT evidence of performance on any real academy.
 *
 * Safety: refuses to run unless DATABASE_URL points at localhost, and only
 * ever touches the SYNTH-ML-DEMO academy (re-running replaces it).
 *
 *   DATABASE_URL=postgresql://postgres@localhost:5434/taleemplus_test \
 *   SYNTH_PASSWORD='...' node scripts/seed-ml-synthetic.js
 */
require('dotenv').config();
const bcrypt = require('bcryptjs');

const url = process.env.DATABASE_URL || '';
if (!/@(localhost|127\.0\.0\.1)[:/]/.test(url)) {
  console.error('Refusing: synthetic ML data may only be written to a local database.');
  process.exit(1);
}
const password = process.env.SYNTH_PASSWORD;
if (!password || password.length < 8) {
  console.error('Set SYNTH_PASSWORD (min 8 chars) for the synthetic admin/teacher accounts.');
  process.exit(1);
}
const prisma = require('../src/config/db');

// Deterministic PRNG (mulberry32) so runs are reproducible.
let seed = 20261109;
const rand = () => {
  seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const normal = () => Math.sqrt(-2 * Math.log(rand() || 1e-9)) * Math.cos(2 * Math.PI * rand());
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
const day = (y, m, d, h = 0) => new Date(Date.UTC(y, m, d, h));
const ymd = (d) => d.toISOString().slice(0, 10);
const grade = (p) => (p >= 90 ? 'A+' : p >= 80 ? 'A' : p >= 70 ? 'B' : p >= 60 ? 'C' : p >= 50 ? 'D' : 'F');

const CODE = 'SYNTH-ML-DEMO';
const STUDENTS = 60;
const MONTHS = 12;

(async () => {
  const existing = await prisma.academy.findUnique({ where: { code: CODE } });
  if (existing) await prisma.academy.delete({ where: { id: existing.id } });

  const academy = await prisma.academy.create({
    data: { code: CODE, name: '[SYNTHETIC] ML Demo Academy', address: 'Synthetic data – not a real academy' }
  });
  const hash = await bcrypt.hash(password, 10);
  const mk = (role, email, fullName) => prisma.user.create({
    data: { email, fullName, role, passwordHash: hash, accountStatus: 'ACTIVE', academyId: academy.id }
  });
  await mk('ADMIN', 'synthetic-admin@ml-demo.test', '[SYNTHETIC] Admin');
  const teacher = await mk('TEACHER', 'synthetic-teacher@ml-demo.test', '[SYNTHETIC] Teacher');
  const cls = await prisma.class.create({
    data: { academyId: academy.id, className: 'Synthetic 9', section: 'A', subject: 'General', primaryTeacherId: teacher.id }
  });

  const students = [];
  for (let i = 0; i < STUDENTS; i++) {
    const diligence = rand();
    const s = await prisma.user.create({ data: {
      email: `synthetic-student-${i}@ml-demo.test`, fullName: `[SYNTHETIC] Student ${i + 1}`,
      role: 'STUDENT', passwordHash: hash, accountStatus: 'ACTIVE', academyId: academy.id,
      studentCode: `synth-${i}-${academy.id.slice(0, 8)}`
    } });
    students.push({ ...s, diligence });
  }
  await prisma.studentEnrollment.createMany({
    data: students.map((s, i) => ({ classId: cls.id, studentId: s.id, rollNumber: String(i + 1) }))
  });

  const start = { y: 2025, m: 10 }; // November 2025 (0-based month)
  const challans = []; const attendance = []; const quizzes = []; const marks = [];
  for (let k = 0; k < MONTHS; k++) {
    const y = start.y + Math.floor((start.m + k) / 12);
    const m = (start.m + k) % 12;
    const issue = day(y, m, 1, 6);
    const due = day(y, m, 10, 6);
    for (const s of students) {
      // Fee: lower diligence -> more likely late, and later.
      const pLate = 1 / (1 + Math.exp(-(1.5 - 4 * s.diligence + 0.6 * normal())));
      const late = rand() < pLate;
      const paidAt = late
        ? new Date(due.getTime() + (2 + Math.floor(rand() * 20)) * 86400000)
        : new Date(due.getTime() - Math.floor(rand() * 8) * 86400000);
      challans.push({
        academyId: academy.id, challanNumber: `SYN-${k}-${s.id.slice(0, 8)}`, studentId: s.id,
        studentName: s.fullName, classLabel: 'Synthetic 9 - A', issueDate: issue, dueDate: due,
        monthlyFee: 3000, totalAmount: 3000, status: 'PAID', paidAt,
        billingPeriod: `${y}-${String(m + 1).padStart(2, '0')}`
      });
      // Attendance: ~12 school days a month.
      for (let d = 2; d <= 28; d += 2 + (d % 3 === 0 ? 1 : 0)) {
        const pPresent = clamp(0.5 + 0.45 * s.diligence + 0.1 * normal(), 0.05, 0.99);
        const r = rand();
        const status = r < pPresent ? (rand() < 0.1 ? 'LATE' : 'PRESENT') : (rand() < 0.2 ? 'LEAVE' : 'ABSENT');
        attendance.push({
          academyId: academy.id, classId: cls.id, studentId: s.id, logDate: ymd(day(y, m, d)),
          status, markedById: teacher.id, recordedAt: day(y, m, d, 15)
        });
      }
    }
    // Two tests a month in two subjects.
    for (const [subject, dd] of [['Mathematics', 12], ['Science', 24]]) {
      const q = await prisma.quiz.create({ data: {
        academyId: academy.id, classId: cls.id, classLabel: 'Synthetic 9 - A',
        title: `[SYNTHETIC] ${subject} test ${k + 1}`, subject, totalMarks: 100,
        testDate: day(y, m, dd), createdById: teacher.id,
        month: new Date(day(y, m, 1)).toLocaleString('en', { month: 'long', timeZone: 'UTC' })
      } });
      quizzes.push(q);
      for (const s of students) {
        const pct = Math.round(clamp(35 + 55 * s.diligence + 7 * normal(), 0, 100) * 10) / 10;
        marks.push({
          academyId: academy.id, quizId: q.id, studentId: s.id, studentName: s.fullName,
          classId: cls.id, subject, month: q.month, marksObtained: pct, totalMarks: 100,
          percentage: pct, gradeLetter: grade(pct)
        });
      }
    }
  }
  await prisma.feeChallan.createMany({ data: challans });
  for (let i = 0; i < attendance.length; i += 2000) {
    await prisma.attendanceRecord.createMany({ data: attendance.slice(i, i + 2000) });
  }
  await prisma.testMark.createMany({ data: marks });
  console.log(`[SYNTHETIC] academy ${CODE}: ${students.length} students, ${challans.length} challans, ` +
    `${attendance.length} attendance rows, ${quizzes.length} tests, ${marks.length} marks.`);
  console.log('Admin login: synthetic-admin@ml-demo.test (password from SYNTH_PASSWORD)');
  await prisma.$disconnect();
})().catch(async (e) => { console.error(e); await prisma.$disconnect(); process.exit(1); });
