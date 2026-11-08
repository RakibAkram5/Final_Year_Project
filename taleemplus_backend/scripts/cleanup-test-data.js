#!/usr/bin/env node
/**
 * Lists (default) or deletes (--confirm) ONLY the academies created by the
 * automated tests: name starts with "Contract " or "Smoke Test Academy " AND
 * every user in the academy has an @test.taleemplus email. Deleting an
 * academy cascades to its users, classes, attendance, fees, etc.
 *
 *   node scripts/cleanup-test-data.js            # dry run
 *   node scripts/cleanup-test-data.js --confirm  # delete (take a backup first)
 */
require('dotenv').config();
const prisma = require('../src/config/db');

(async () => {
  const confirm = process.argv.includes('--confirm');
  const candidates = await prisma.academy.findMany({
    where: {
      OR: [
        { name: { startsWith: 'Contract ' } },
        { name: { startsWith: 'Smoke Test Academy ' } }
      ]
    },
    select: { id: true, name: true, users: { select: { email: true } } }
  });
  // Safety: skip any academy containing a non-test account.
  const safe = candidates.filter((a) =>
    a.users.every((u) => u.email.endsWith('@test.taleemplus')));
  const skipped = candidates.length - safe.length;

  console.log(`${safe.length} test academies (${safe.reduce((n, a) => n + a.users.length, 0)} test users) match.`);
  if (skipped) console.log(`${skipped} matching academies skipped: they contain non-test accounts.`);

  if (!confirm) {
    console.log('Dry run only. Re-run with --confirm to delete them.');
  } else {
    const result = await prisma.academy.deleteMany({ where: { id: { in: safe.map((a) => a.id) } } });
    console.log(`Deleted ${result.count} test academies.`);
  }
  await prisma.$disconnect();
})().catch(async (err) => {
  console.error('Cleanup failed:', err.message);
  await prisma.$disconnect();
  process.exit(1);
});
