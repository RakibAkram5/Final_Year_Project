require('dotenv').config();
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const prisma = require('../src/config/db');

const isProduction = process.env.NODE_ENV === 'production';
if (isProduction && process.env.ALLOW_SEED !== 'true') {
  console.error('Refusing to seed a production database without ALLOW_SEED=true.');
  process.exit(1);
}

const generatedPassword = `${crypto.randomBytes(12).toString('base64url')}aA1!`;
const password = process.env.SEED_PASSWORD || generatedPassword;

const demoAcademy = {
  code: process.env.SEED_ACADEMY_CODE || 'DEMO-ACADEMY',
  name: process.env.SEED_ACADEMY_NAME || 'TaleemPlus Demo Academy',
  address: 'Demo Campus',
  phone: '+92-000-0000000'
};

const demoUsers = [
  { email: 'admin@demo.taleemplus', fullName: 'Demo Admin', role: 'ADMIN' },
  { email: 'teacher@demo.taleemplus', fullName: 'Demo Teacher', role: 'TEACHER' },
  { email: 'student@demo.taleemplus', fullName: 'Demo Student', role: 'STUDENT' },
  { email: 'parent@demo.taleemplus', fullName: 'Demo Parent', role: 'PARENT' }
];

const ids = {
  section: '00000000-0000-4000-8000-000000000010',
  quiz: '00000000-0000-4000-8000-000000000020',
  resource: '00000000-0000-4000-8000-000000000030',
  query: '00000000-0000-4000-8000-000000000040',
  notification: '00000000-0000-4000-8000-000000000050',
  announcement: '00000000-0000-4000-8000-000000000060',
  timetable: '00000000-0000-4000-8000-000000000070',
  report: '00000000-0000-4000-8000-000000000080',
  ocr: '00000000-0000-4000-8000-000000000090'
};

const toDateOnly = (date) => date.toISOString().slice(0, 10);

async function main() {
  const academy = await prisma.academy.upsert({
    where: { code: demoAcademy.code },
    update: {},
    create: {
      ...demoAcademy,
      academicStructure: {
        programs: ['General'],
        classes: [{ name: 'Grade 5', sections: ['A'] }],
        groups: []
      }
    }
  });

  const passwordHash = await bcrypt.hash(password, 12);
  const users = {};

  for (const demoUser of demoUsers) {
    const existing = await prisma.user.findUnique({
      where: { email: demoUser.email }
    });
    users[demoUser.role] = existing || await prisma.user.create({
      data: {
        ...demoUser,
        passwordHash,
        accountStatus: 'ACTIVE',
        academyId: academy.id,
        studentCode: demoUser.role === 'STUDENT'
          ? crypto.randomBytes(8).toString('hex')
          : null
      }
    });
  }

  await prisma.parentStudent.upsert({
    where: {
      parentId_studentId: {
        parentId: users.PARENT.id,
        studentId: users.STUDENT.id
      }
    },
    update: {},
    create: { parentId: users.PARENT.id, studentId: users.STUDENT.id }
  });

  const section = await prisma.classSection.upsert({
    where: {
      academyId_className_program_section: {
        academyId: academy.id,
        className: 'Grade 5',
        program: 'General',
        section: 'A'
      }
    },
    update: {},
    create: {
      id: ids.section,
      academyId: academy.id,
      className: 'Grade 5',
      program: 'General',
      section: 'A'
    }
  });

  const demoClass = await prisma.class.upsert({
    where: {
      academyId_className_section_subject: {
        academyId: academy.id,
        className: 'Grade 5',
        section: 'A',
        subject: 'Mathematics'
      }
    },
    update: { classSectionId: section.id, program: 'General' },
    create: {
      academyId: academy.id,
      className: 'Grade 5',
      section: 'A',
      subject: 'Mathematics',
      program: 'General',
      classSectionId: section.id,
      primaryTeacherId: users.TEACHER.id
    }
  });

  await prisma.studentEnrollment.upsert({
    where: {
      classId_studentId: { classId: demoClass.id, studentId: users.STUDENT.id }
    },
    update: { rollNumber: '5A-01' },
    create: {
      classId: demoClass.id,
      studentId: users.STUDENT.id,
      rollNumber: '5A-01'
    }
  });

  await prisma.classSectionEnrollment.upsert({
    where: {
      sectionId_studentId: {
        sectionId: section.id,
        studentId: users.STUDENT.id
      }
    },
    update: { rollNumber: '5A-01' },
    create: {
      sectionId: section.id,
      studentId: users.STUDENT.id,
      rollNumber: '5A-01'
    }
  });

  const today = toDateOnly(new Date());

  await prisma.attendanceRecord.upsert({
    where: {
      classId_studentId_logDate: {
        classId: demoClass.id,
        studentId: users.STUDENT.id,
        logDate: today
      }
    },
    update: { status: 'PRESENT', markedById: users.TEACHER.id },
    create: {
      academyId: academy.id,
      classId: demoClass.id,
      studentId: users.STUDENT.id,
      logDate: today,
      status: 'PRESENT',
      markedById: users.TEACHER.id
    }
  });

  await prisma.feeChallan.upsert({
    where: {
      academyId_studentId_billingPeriod: {
        academyId: academy.id,
        studentId: users.STUDENT.id,
        billingPeriod: '2026-11'
      }
    },
    update: {},
    create: {
      academyId: academy.id,
      challanNumber: 'DEMO-CHALLAN-2026-11',
      studentId: users.STUDENT.id,
      studentName: users.STUDENT.fullName,
      fatherName: 'Demo Parent',
      classLabel: 'Grade 5 - A',
      rollNumber: '5A-01',
      dueDate: new Date('2026-11-15T00:00:00.000Z'),
      monthlyFee: 5000,
      totalAmount: 5000,
      billingPeriod: '2026-11'
    }
  });

  const quiz = await prisma.quiz.upsert({
    where: { id: ids.quiz },
    update: {},
    create: {
      id: ids.quiz,
      academyId: academy.id,
      classId: demoClass.id,
      classLabel: 'Grade 5 - A',
      title: 'Demo Fractions Quiz',
      subject: 'Mathematics',
      month: 'November',
      session: '2026-2027',
      totalMarks: 10,
      createdById: users.TEACHER.id,
      questions: {
        create: [
          {
            text: 'What is 1/2 + 1/4?',
            type: 'short',
            correctIndex: 0,
            options: ['3/4', '2/6', '1/6'],
            marks: 10
          }
        ]
      }
    }
  });

  await prisma.testMark.upsert({
    where: {
      quizId_studentId: { quizId: quiz.id, studentId: users.STUDENT.id }
    },
    update: {},
    create: {
      academyId: academy.id,
      quizId: quiz.id,
      studentId: users.STUDENT.id,
      studentName: users.STUDENT.fullName,
      classId: demoClass.id,
      subject: 'Mathematics',
      month: 'November',
      marksObtained: 8,
      totalMarks: 10,
      percentage: 80,
      gradeLetter: 'A'
    }
  });

  await prisma.sharedResource.upsert({
    where: { id: ids.resource },
    update: {},
    create: {
      id: ids.resource,
      academyId: academy.id,
      classId: demoClass.id,
      teacherId: users.TEACHER.id,
      title: 'Fractions notes',
      description: 'Worked examples for the demo quiz.',
      contentText: 'A fraction represents a part of a whole.',
      mimeType: 'text/plain'
    }
  });

  await prisma.studentQuery.upsert({
    where: { id: ids.query },
    update: {},
    create: {
      id: ids.query,
      academyId: academy.id,
      classId: demoClass.id,
      studentId: users.STUDENT.id,
      teacherId: users.TEACHER.id,
      question: 'Why do we need a common denominator?'
    }
  });

  await prisma.notification.upsert({
    where: { id: ids.notification },
    update: {},
    create: {
      id: ids.notification,
      academyId: academy.id,
      recipientId: users.STUDENT.id,
      title: 'Welcome',
      message: 'Your demo academy is ready.',
      type: 'general'
    }
  });

  await prisma.announcement.upsert({
    where: { id: ids.announcement },
    update: {},
    create: {
      id: ids.announcement,
      academyId: academy.id,
      title: 'Demo announcement',
      message: 'Classes start at 8:00 AM.',
      targetRoles: ['all'],
      createdById: users.ADMIN.id
    }
  });

  await prisma.timetableSlot.upsert({
    where: { id: ids.timetable },
    update: {},
    create: {
      id: ids.timetable,
      academyId: academy.id,
      classId: demoClass.id,
      section: 'A',
      dayOfWeek: '1',
      startTime: '08:00',
      endTime: '08:45',
      subject: 'Mathematics',
      teacherId: users.TEACHER.id,
      dayOfWeekInt: 1,
      startMinutes: 480,
      endMinutes: 525,
      room: 'Room 1',
      semester: '2026-2027'
    }
  });

  await prisma.classReport.upsert({
    where: { id: ids.report },
    update: {},
    create: {
      id: ids.report,
      academyId: academy.id,
      classLabel: 'Grade 5 - A',
      totalStudents: 1,
      present: 1,
      absent: 0,
      feePaid: 0,
      feePending: 1,
      feePaidAmount: 0,
      feePendingAmount: 5000
    }
  });

  await prisma.ocrDocument.upsert({
    where: { id: ids.ocr },
    update: {},
    create: {
      id: ids.ocr,
      academyId: academy.id,
      createdById: users.TEACHER.id,
      createdByName: users.TEACHER.fullName,
      title: 'Demo OCR note',
      extractedText: 'Sample extracted text for the demo academy.'
    }
  });

  console.log(`Seeded academy: ${academy.name} (${academy.code})`);
  for (const user of Object.values(users)) {
    console.log(`  ${user.role.padEnd(8)} ${user.email}`);
  }
  console.log(`  CLASS    ${demoClass.className} - ${demoClass.section} (${demoClass.subject})`);
  if (!process.env.SEED_PASSWORD) {
    console.log(`\nGenerated seed password: ${password}`);
    console.log('Set SEED_PASSWORD to choose a different password next time.');
  }
}

main()
  .catch((error) => {
    console.error('Seed failed:', error.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
