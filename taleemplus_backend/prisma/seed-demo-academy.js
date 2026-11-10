/**
 * TaleemPlus — DEMO academy seeder (Bright Future Science Academy).
 *
 * SAFE BY DESIGN:
 *  - Refuses to run unless SEED_DEMO=true is set.
 *  - Touches ONLY the single demo academy (code BFSA-DEMO) and its children.
 *  - Fully idempotent: stable ids + upserts / createMany(skipDuplicates), so
 *    re-running makes no duplicates.
 *  - Uses the existing Prisma schema, the existing bcryptjs hashing, and the
 *    existing unique keys. No invented columns (extra attributes go into the
 *    existing `extraInfo` JSON string field).
 *
 * All identities, phones, emails and addresses are FICTIONAL demo data.
 *
 * Usage (point DATABASE_URL at a SAFE target — e.g. a Neon BRANCH, never prod):
 *   DATABASE_URL="<branch-url>" SEED_DEMO=true node prisma/seed-demo-academy.js
 */
require('dotenv').config();
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const prisma = require('../src/config/db');

// ---------------------------------------------------------------- guards ----
if (process.env.SEED_DEMO !== 'true') {
  console.error('Refusing to seed: set SEED_DEMO=true to confirm this is a safe demo target.');
  process.exit(1);
}
const maskedHost = (process.env.DATABASE_URL || '').replace(/\/\/[^@]*@/, '//****@');
console.log(`[demo-seed] target: ${maskedHost || '(DATABASE_URL not set)'}`);

const ACADEMY_CODE = 'BFSA-DEMO';
const DEMO_PASSWORD = process.env.SEED_DEMO_PASSWORD || 'Demo@BFSA2026';
const SESSION = '2026-2027';
const TODAY = new Date('2026-11-09T00:00:00Z');

// deterministic id so re-runs upsert instead of duplicating
const uid = (key) => {
  const h = crypto.createHash('sha256').update(`bfsa:${key}`).digest('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-8${h.slice(17, 20)}-${h.slice(20, 32)}`;
};
// seeded PRNG for repeatable "random" variation
let _s = 1337;
const rnd = () => { _s = (_s * 1103515245 + 12345) & 0x7fffffff; return _s / 0x7fffffff; };
const pick = (arr) => arr[Math.floor(rnd() * arr.length)];
const pad = (n, w = 4) => String(n).padStart(w, '0');
const iso = (d) => d.toISOString().slice(0, 10);

const log = { created: 0, skipped: 0, failed: 0 };

// ---------------------------------------------------------- demo name pools -
const MALE = ['Ahmed', 'Ali', 'Hassan', 'Hussain', 'Bilal', 'Usman', 'Hamza', 'Zain', 'Umar', 'Saad',
  'Faizan', 'Ibrahim', 'Abdullah', 'Talha', 'Daniyal', 'Shahzaib', 'Arslan', 'Fahad', 'Noman', 'Waleed',
  'Huzaifa', 'Rehan', 'Taha', 'Moiz', 'Shayan'];
const FEMALE = ['Ayesha', 'Fatima', 'Zainab', 'Maryam', 'Hira', 'Sana', 'Amna', 'Iqra', 'Noor', 'Mahnoor',
  'Areeba', 'Laiba', 'Eman', 'Kiran', 'Rabia', 'Sidra', 'Mishal', 'Aiman', 'Komal', 'Nimra',
  'Zoya', 'Hifza', 'Alishba', 'Warda', 'Fajar'];
const LAST = ['Khan', 'Malik', 'Butt', 'Sheikh', 'Chaudhry', 'Qureshi', 'Raza', 'Iqbal', 'Hussain', 'Ahmed',
  'Aslam', 'Javed', 'Bhatti', 'Gondal', 'Awan', 'Dar', 'Mughal', 'Siddiqui', 'Farooq', 'Nawaz'];
const AREAS = ['Johar Town', 'Model Town', 'Wapda Town', 'Faisal Town', 'Township', 'Garden Town',
  'Iqbal Town', 'Valencia', 'Gulberg', 'DHA Phase 5'];
const OCCUPATIONS = ['Businessman', 'Government Officer', 'Doctor', 'Engineer', 'Shopkeeper',
  'Bank Officer', 'Teacher', 'Accountant', 'Farmer', 'Army Officer'];
const QUALS = ['M.Phil Physics', 'MSc Mathematics', 'M.Phil Chemistry', 'MSc Biology', 'MCS',
  'MA English', 'MA Urdu', 'MA Islamic Studies', 'MSc Statistics', 'BS Pakistan Studies'];

const phone = (seq) => `+92-3${pick(['0', '1', '2', '3'])}${pad(seq % 100, 2)}-${pad(1000000 + (seq * 7919) % 8999999, 7)}`;
const slug = (s) => s.toLowerCase().replace(/[^a-z]+/g, '.');
const email = (name, tag, seq) => `${slug(name)}.${tag}${seq}@demo.bfsa.edu.pk`;

// ------------------------------------------------------------- class config -
const GRADES = [
  { key: '9', label: '9th Class', monthly: 3500, dob: 2011 },
  { key: '10', label: '10th Class', monthly: 3800, dob: 2010 },
  { key: '1Y', label: '1st Year', monthly: 4500, dob: 2009 },
  { key: '2Y', label: '2nd Year', monthly: 4800, dob: 2008 },
];
const SUBJECTS = ['Mathematics', 'Physics', 'Chemistry', 'Biology', 'Computer Science', 'English',
  'Urdu', 'Pakistan Studies', 'Islamic Studies', 'Statistics'];
const GRADE_SUBJECTS = {
  '9': ['Mathematics', 'Physics', 'Chemistry', 'English', 'Urdu', 'Islamic Studies'],
  '10': ['Mathematics', 'Physics', 'Chemistry', 'English', 'Urdu', 'Pakistan Studies'],
  '1Y': ['Physics', 'Chemistry', 'Biology', 'English', 'Computer Science', 'Statistics'],
  '2Y': ['Physics', 'Chemistry', 'Biology', 'English', 'Urdu', 'Statistics'],
};
// quizzes/marks generated for these subjects per grade (feeds the ML model)
const EXAM_SUBJECTS = { '9': ['Mathematics', 'Physics'], '10': ['Mathematics', 'Chemistry'],
  '1Y': ['Physics', 'Biology'], '2Y': ['Chemistry', 'Biology'] };

async function main() {
  const passwordHash = await bcrypt.hash(DEMO_PASSWORD, 12);

  // 1) Academy -------------------------------------------------------------
  const academy = await prisma.academy.upsert({
    where: { code: ACADEMY_CODE },
    update: {},
    create: {
      id: uid('academy'), code: ACADEMY_CODE,
      name: 'Bright Future Science Academy (DEMO)',
      address: 'Block H, Johar Town, Lahore, Punjab, Pakistan',
      phone: '+92-42-35290001',
      locationLabel: 'Johar Town, Lahore',
      bankName: 'Demo Bank Ltd', bankAccountNumber: 'PK00DEMO0000000000000001',
      paymentInstructions: 'DEMO data — do not use for real payments.',
      academicStructure: {
        demo: true, session: SESSION, medium: ['English', 'Urdu'], workingDays: 'Mon-Sat',
        timings: '08:00-13:30', programs: ['Matric', 'Intermediate'],
        classes: GRADES.map((g) => ({ name: g.label, sections: ['A'] })),
      },
    },
  });
  console.log(`[demo-seed] academy: ${academy.name}`);
  const academyId = academy.id;

  // 2) Admin ---------------------------------------------------------------
  await prisma.user.upsert({
    where: { email: 'admin@demo.bfsa.edu.pk' },
    update: { accountStatus: 'ACTIVE', academyId },
    create: {
      id: uid('admin'), email: 'admin@demo.bfsa.edu.pk', passwordHash,
      fullName: 'Principal Dr. Imran Shahid', role: 'ADMIN', accountStatus: 'ACTIVE',
      phoneNumber: '+92-300-1112233', academyId, joiningDate: new Date('2026-04-01'),
      extraInfo: JSON.stringify({ demo: true, designation: 'Principal / Administrator', gender: 'Male' }),
    },
  });

  // 3) Teachers (12) -------------------------------------------------------
  const teacherSubjects = [...SUBJECTS, 'Mathematics', 'Biology']; // 12 teachers
  const teachers = [];
  for (let i = 0; i < 12; i += 1) {
    const subject = teacherSubjects[i];
    const first = i % 3 === 0 ? pick(FEMALE) : pick(MALE);
    const gender = FEMALE.includes(first) ? 'Female' : 'Male';
    const name = `${gender === 'Female' ? 'Ms.' : 'Sir'} ${first} ${pick(LAST)}`;
    const t = await prisma.user.upsert({
      where: { email: email(`${first}.t`, 'tch', i + 1) },
      update: { academyId, subject },
      create: {
        id: uid(`teacher:${i}`), email: email(`${first}.t`, 'tch', i + 1), passwordHash,
        fullName: name, role: 'TEACHER', accountStatus: 'ACTIVE', subject,
        phoneNumber: phone(100 + i), academyId, joiningDate: new Date(2026, 3, 1 + i),
        extraInfo: JSON.stringify({ demo: true, employeeId: `BFSA-T-${pad(i + 1, 3)}`,
          gender, qualification: QUALS[i % QUALS.length], specialization: subject,
          experienceYears: 3 + (i % 10) }),
      },
    });
    teachers.push({ ...t, subject });
  }
  const teacherBySubject = (sub) => (teachers.find((t) => t.subject === sub) || teachers[0]);
  console.log(`[demo-seed] teachers: ${teachers.length}`);

  // 4) Sections + subject Classes -----------------------------------------
  const sectionByGrade = {};
  const classByGradeSubject = {};
  for (const g of GRADES) {
    const section = await prisma.classSection.upsert({
      where: { academyId_className_program_section: { academyId, className: g.label, program: '', section: 'A' } },
      update: {},
      create: { id: uid(`sec:${g.key}`), academyId, className: g.label, program: '', section: 'A' },
    });
    sectionByGrade[g.key] = section;
    for (const subject of GRADE_SUBJECTS[g.key]) {
      const cls = await prisma.class.upsert({
        where: { academyId_className_section_subject: { academyId, className: g.label, section: 'A', subject } },
        update: { primaryTeacherId: teacherBySubject(subject).id, classSectionId: section.id },
        create: {
          id: uid(`cls:${g.key}:${subject}`), academyId, className: g.label, section: 'A',
          subject, program: 'General', classSectionId: section.id,
          primaryTeacherId: teacherBySubject(subject).id,
        },
      });
      classByGradeSubject[`${g.key}:${subject}`] = cls;
    }
  }

  // 5) Students (100) + Parents (siblings share a guardian) ----------------
  const students = [];
  const parents = {};         // familyKey -> parent user
  let seq = 0;
  for (const g of GRADES) {
    for (let n = 0; n < 25; n += 1) {
      seq += 1;
      const gender = rnd() < 0.5 ? 'Male' : 'Female';
      const first = gender === 'Male' ? pick(MALE) : pick(FEMALE);
      const familyLast = pick(LAST);
      // ~15% chance this student shares an existing family (sibling)
      const familyKey = (seq > 1 && rnd() < 0.15) ? pick(Object.keys(parents)) : `fam:${seq}`;
      const area = pick(AREAS);
      const address = `House ${10 + (seq % 400)}, Street ${1 + (seq % 30)}, ${area}, Lahore`;
      const studentCode = `BFSA-26-${pad(seq)}`;
      const student = await prisma.user.upsert({
        where: { studentCode },
        update: { academyId, accountStatus: 'ACTIVE' },
        create: {
          id: uid(`stu:${seq}`), email: email(`${first}.${familyLast}`, 'std', seq), passwordHash,
          fullName: `${first} ${familyLast}`, role: 'STUDENT', accountStatus: 'ACTIVE',
          studentCode, rollNumber: `${g.key}-${pad(n + 1, 2)}`, phoneNumber: phone(1000 + seq),
          academyId, joiningDate: new Date('2026-04-10'),
          extraInfo: JSON.stringify({ demo: true, gender, grade: g.label, section: 'A',
            dob: `${g.dob}-${pad(1 + (seq % 12), 2)}-${pad(1 + (seq % 27), 2)}`,
            admissionDate: '2026-04-10', session: SESSION, address }),
        },
      });
      students.push({ ...student, gradeKey: g.key, gradeLabel: g.label, rollNumber: `${g.key}-${pad(n + 1, 2)}` });

      // guardian (father) — one login account per family; mother stored in extraInfo
      if (!parents[familyKey]) {
        const fatherFirst = pick(MALE);
        const fatherName = `${fatherFirst} ${familyLast}`;
        const motherName = `${pick(FEMALE)} ${familyLast}`;
        parents[familyKey] = await prisma.user.upsert({
          where: { email: email(`${fatherFirst}.${familyLast}`, 'par', Object.keys(parents).length + 1) },
          update: { academyId },
          create: {
            id: uid(`parent:${familyKey}`),
            email: email(`${fatherFirst}.${familyLast}`, 'par', Object.keys(parents).length + 1),
            passwordHash, fullName: fatherName, role: 'PARENT', accountStatus: 'ACTIVE',
            phoneNumber: phone(5000 + Object.keys(parents).length), academyId,
            extraInfo: JSON.stringify({ demo: true, relationship: 'Father', motherName,
              occupation: pick(OCCUPATIONS), emergencyContact: phone(6000 + Object.keys(parents).length),
              address }),
          },
        });
      }
      await prisma.parentStudent.upsert({
        where: { parentId_studentId: { parentId: parents[familyKey].id, studentId: student.id } },
        update: {},
        create: { id: uid(`ps:${familyKey}:${seq}`), parentId: parents[familyKey].id, studentId: student.id },
      });
    }
  }
  console.log(`[demo-seed] students: ${students.length}, parents: ${Object.keys(parents).length}`);

  // 6) Enrollments (section + per-subject) ---------------------------------
  const secEnroll = [], subEnroll = [];
  for (const s of students) {
    secEnroll.push({ id: uid(`se:${s.id}`), sectionId: sectionByGrade[s.gradeKey].id,
      studentId: s.id, rollNumber: s.rollNumber });
    for (const subject of GRADE_SUBJECTS[s.gradeKey]) {
      const cls = classByGradeSubject[`${s.gradeKey}:${subject}`];
      subEnroll.push({ id: uid(`en:${s.id}:${subject}`), classId: cls.id, studentId: s.id, rollNumber: s.rollNumber });
    }
  }
  await prisma.classSectionEnrollment.createMany({ data: secEnroll, skipDuplicates: true });
  await prisma.studentEnrollment.createMany({ data: subEnroll, skipDuplicates: true });

  // 7) Timetable (Mon-Sat, 6 periods, conflict-free Latin-square) ----------
  const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const periods = [['08:00', '08:45'], ['08:45', '09:30'], ['09:30', '10:15'],
    ['10:45', '11:30'], ['11:30', '12:15'], ['12:15', '13:00']]; // break 10:15-10:45
  const slots = [];
  GRADES.forEach((g, sIdx) => {
    const subs = GRADE_SUBJECTS[g.key];
    DAYS.forEach((day, dIdx) => {
      periods.forEach(([st, et], pIdx) => {
        const subject = subs[(pIdx + sIdx + dIdx) % subs.length]; // offset => no teacher clash
        const [sh, sm] = st.split(':').map(Number); const [eh, em] = et.split(':').map(Number);
        slots.push({ id: uid(`tt:${g.key}:${day}:${pIdx}`), academyId, classId: classByGradeSubject[`${g.key}:${subject}`].id,
          section: `${g.label}-A`, dayOfWeek: day, dayOfWeekInt: dIdx + 1, startTime: st, endTime: et,
          startMinutes: sh * 60 + sm, endMinutes: eh * 60 + em, subject,
          teacherId: teacherBySubject(subject).id, room: `R-${g.key}` });
      });
    });
  });
  await prisma.timetableSlot.createMany({ data: slots, skipDuplicates: true });

  // 8) Fee challans (6 past months; mixed paid/late/overdue/pending) -------
  const marker = teachers[0].id;
  const months = ['2026-05', '2026-06', '2026-07', '2026-08', '2026-09', '2026-10'];
  const challans = [];
  let feeLate = 0, feeOnTime = 0;
  for (const s of students) {
    const g = GRADES.find((x) => x.key === s.gradeKey);
    months.forEach((bp, mi) => {
      const [yy, mm] = bp.split('-').map(Number);
      const issueDate = new Date(Date.UTC(yy, mm - 1, 1));
      const dueDate = new Date(Date.UTC(yy, mm - 1, 10));
      const admissionFee = mi === 0 ? 5000 : 0;
      const total = g.monthly + admissionFee;
      // outcome distribution (deterministic-ish per student/month)
      const r = rnd();
      let status = 'PAID', paidAt = null;
      const recent = mi >= months.length - 1; // last month may still be pending
      if (recent && r < 0.25) { status = 'PENDING'; paidAt = null; }          // not labelable yet
      else if (r < 0.55) { status = 'PAID'; paidAt = new Date(Date.UTC(yy, mm - 1, 3 + Math.floor(rnd() * 6))); feeOnTime += 1; } // on time (<=10)
      else if (r < 0.78) { status = 'PAID'; paidAt = new Date(Date.UTC(yy, mm - 1, 12 + Math.floor(rnd() * 12))); feeLate += 1; }  // late
      else { status = 'OVERDUE'; paidAt = null; feeLate += 1; }               // overdue (>30d past => labelable late)
      challans.push({ id: uid(`fee:${s.id}:${bp}`), academyId, challanNumber: `CH-DEMO-${uid(`fee:${s.id}:${bp}`).slice(0, 12).toUpperCase()}`,
        studentId: s.id, studentName: s.fullName, classLabel: s.gradeLabel, rollNumber: s.rollNumber,
        issueDate, dueDate, billingPeriod: bp, monthlyFee: g.monthly, admissionFee,
        examFee: 0, transportFee: 0, fine: status !== 'PAID' ? 200 : 0,
        totalAmount: total + (status !== 'PAID' ? 200 : 0), status, paidAt });
    });
  }
  await prisma.feeChallan.createMany({ data: challans, skipDuplicates: true });
  console.log(`[demo-seed] fee challans: ${challans.length} (approx on-time ${feeOnTime}, late/overdue ${feeLate})`);

  // 9) Attendance (last 30 calendar days, Mon-Sat) -------------------------
  const attClassByGrade = {};
  for (const g of GRADES) attClassByGrade[g.key] = classByGradeSubject[`${g.key}:${GRADE_SUBJECTS[g.key][0]}`];
  const attendance = [];
  for (let d = 30; d >= 1; d -= 1) {
    const day = new Date(TODAY.getTime() - d * 86400000);
    if (day.getUTCDay() === 0) continue; // skip Sunday
    const logDate = iso(day);
    for (const s of students) {
      const r = rnd();
      const status = r < 0.86 ? 'PRESENT' : r < 0.93 ? 'ABSENT' : r < 0.98 ? 'LATE' : 'LEAVE';
      attendance.push({ id: uid(`att:${s.id}:${logDate}`), academyId, classId: attClassByGrade[s.gradeKey].id,
        studentId: s.id, logDate, status, markedById: marker });
    }
  }
  // batch to keep each createMany reasonable
  for (let i = 0; i < attendance.length; i += 1000) {
    await prisma.attendanceRecord.createMany({ data: attendance.slice(i, i + 1000), skipDuplicates: true });
  }
  console.log(`[demo-seed] attendance rows: ${attendance.length}`);

  // 10) Quizzes + TestMarks (3 dated quizzes/subject => ML performance data)
  const quizDates = ['2026-08-15', '2026-09-20', '2026-10-18'];
  // Quizzes + marks (idempotent): 3 dated quizzes per exam-subject per grade,
  // so each student accrues prior history (needed by the ML performance model).
  for (const g of GRADES) {
    for (const subject of EXAM_SUBJECTS[g.key]) {
      const cls = classByGradeSubject[`${g.key}:${subject}`];
      const creator = teacherBySubject(subject).id;
      const gradeStudents = students.filter((s) => s.gradeKey === g.key);
      for (let qi = 0; qi < quizDates.length; qi += 1) {
        const quizId = uid(`quiz:${g.key}:${subject}:${qi}`);
        await prisma.quiz.upsert({
          where: { id: quizId },
          update: {},
          create: { id: quizId, academyId, classId: cls.id, classLabel: g.label,
            title: `${subject} Monthly Test ${qi + 1}`, subject, totalMarks: 100,
            testDate: new Date(`${quizDates[qi]}T09:00:00Z`), month: quizDates[qi].slice(0, 7),
            session: SESSION, createdById: creator },
        });
        const marks = gradeStudents.map((s) => {
          const base = 45 + (parseInt(s.rollNumber.split('-')[1], 10) % 40);
          const pct = Math.max(20, Math.min(100, Math.round(base + qi * 3 + (rnd() * 16 - 8))));
          return { id: uid(`mk:${quizId}:${s.id}`), academyId, quizId, studentId: s.id,
            studentName: s.fullName, classId: cls.id, subject, marksObtained: pct, totalMarks: 100,
            percentage: pct, gradeLetter: pct >= 80 ? 'A' : pct >= 70 ? 'B' : pct >= 60 ? 'C' : pct >= 50 ? 'D' : 'F' };
        });
        await prisma.testMark.createMany({ data: marks, skipDuplicates: true });
      }
    }
  }
  console.log(`[demo-seed] quizzes: created for ${GRADES.length} grades; test marks seeded`);

  // ------------------------------------------------------------- summary ----
  const counts = await verifyCounts(academyId);
  console.log('[demo-seed] DONE. Counts:', counts);
  console.log(`[demo-seed] password for ALL demo accounts: ${DEMO_PASSWORD} (see DEMO_LOGIN_CREDENTIALS.md)`);
}

async function verifyCounts(academyId) {
  const [students, teachers, parents, challans, attendance, marks, quizzes, sections] = await Promise.all([
    prisma.user.count({ where: { academyId, role: 'STUDENT' } }),
    prisma.user.count({ where: { academyId, role: 'TEACHER' } }),
    prisma.user.count({ where: { academyId, role: 'PARENT' } }),
    prisma.feeChallan.count({ where: { academyId } }),
    prisma.attendanceRecord.count({ where: { academyId } }),
    prisma.testMark.count({ where: { academyId } }),
    prisma.quiz.count({ where: { academyId } }),
    prisma.classSection.count({ where: { academyId } }),
  ]);
  return { students, teachers, parents, challans, attendance, marks, quizzes, sections };
}

main()
  .catch((e) => { console.error('[demo-seed] FAILED:', e.message); process.exitCode = 1; })
  .finally(async () => { await prisma.$disconnect(); });
