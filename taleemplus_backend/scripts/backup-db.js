#!/usr/bin/env node
/**
 * Read-only logical backup of every table in the configured database's
 * `public` schema to a timestamped JSON file under taleemplus_backend/backups/
 * (gitignored). Use before applying migrations when pg_dump is unavailable.
 *
 *   node scripts/backup-db.js [outputDir]
 */
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const prisma = require('../src/config/db');

const replacer = (_key, value) => {
  if (typeof value === 'bigint') return value.toString();
  if (value && value.type === 'Buffer' && Array.isArray(value.data)) {
    return { $base64: Buffer.from(value.data).toString('base64') };
  }
  return value;
};

(async () => {
  const outDir = path.resolve(process.argv[2] || path.join(__dirname, '..', 'backups'));
  fs.mkdirSync(outDir, { recursive: true });

  const tables = await prisma.$queryRawUnsafe(
    `SELECT table_name FROM information_schema.tables
     WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
     ORDER BY table_name`
  );

  const dump = { createdAt: new Date().toISOString(), tables: {} };
  for (const { table_name: name } of tables) {
    // Table names come from information_schema, not user input.
    const rows = await prisma.$queryRawUnsafe(`SELECT * FROM "${name}"`);
    dump.tables[name] = rows;
    console.log(`${name.padEnd(34)} ${rows.length} rows`);
  }

  const file = path.join(outDir, `backup-${dump.createdAt.replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(file, JSON.stringify(dump, replacer));
  console.log(`\nBackup written: ${file}`);
  await prisma.$disconnect();
})().catch(async (err) => {
  console.error('Backup failed:', err.message);
  await prisma.$disconnect();
  process.exit(1);
});
