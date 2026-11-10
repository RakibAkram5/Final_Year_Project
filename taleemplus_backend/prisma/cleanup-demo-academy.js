/**
 * TaleemPlus — DEMO academy cleanup.
 *
 * Deletes ONLY the demo academy (code BFSA-DEMO). Every child table has
 * onDelete: Cascade from Academy in the Prisma schema, so removing the academy
 * removes exactly its students, teachers, parents, classes, challans,
 * attendance, quizzes and marks — and nothing else. It never touches any other
 * academy's data.
 *
 * Usage (point DATABASE_URL at the SAME target you seeded):
 *   DATABASE_URL="<branch-url>" CONFIRM_DELETE=true node prisma/cleanup-demo-academy.js
 */
require('dotenv').config();
const prisma = require('../src/config/db');

const ACADEMY_CODE = 'BFSA-DEMO';

if (process.env.CONFIRM_DELETE !== 'true') {
  console.error('Refusing to delete: set CONFIRM_DELETE=true to confirm.');
  process.exit(1);
}

async function main() {
  const academy = await prisma.academy.findUnique({ where: { code: ACADEMY_CODE }, select: { id: true, name: true } });
  if (!academy) {
    console.log(`[cleanup] no academy with code ${ACADEMY_CODE}; nothing to delete.`);
    return;
  }
  const before = {
    students: await prisma.user.count({ where: { academyId: academy.id, role: 'STUDENT' } }),
    users: await prisma.user.count({ where: { academyId: academy.id } }),
    challans: await prisma.feeChallan.count({ where: { academyId: academy.id } }),
    attendance: await prisma.attendanceRecord.count({ where: { academyId: academy.id } }),
  };
  console.log(`[cleanup] deleting academy "${academy.name}" and cascading children:`, before);
  await prisma.academy.delete({ where: { id: academy.id } });
  console.log('[cleanup] done. Only the demo academy was removed.');
}

main()
  .catch((e) => { console.error('[cleanup] FAILED:', e.message); process.exitCode = 1; })
  .finally(async () => { await prisma.$disconnect(); });
