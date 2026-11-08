const path = require('path');

require('dotenv').config({ path: path.resolve(__dirname, '..', '..', '.env') });

const identity = require('./lib/identity');
const {
  resolveCollectionFile,
  iterateJsonl,
  readRecordsFromFile,
  readManifest,
  sha256File,
  writeJsonFile
} = require('./lib/exportFiles');

const { normalizeEmail, maskEmail, isUuid, mappingKey, normalizeRecord } = identity;

const pick = (source, keys) => {
  if (!source || typeof source !== 'object') return undefined;
  for (const key of keys) {
    const value = source[key];
    if (value !== undefined && value !== null && value !== '') return value;
  }
  return undefined;
};

const parseArgs = (argv) => {
  const args = { _: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) {
      args._.push(token);
      continue;
    }
    const key = token.slice(2);
    const next = argv[index + 1];
    if (next === undefined || next.startsWith('--')) {
      args[key] = true;
    } else {
      args[key] = next;
      index += 1;
    }
  }
  return args;
};

const loadPrisma = () => {
  const { PrismaClient } = require('../../generated/client');
  return new PrismaClient();
};

const loadIdentityRecords = (directory) => {
  const file = resolveCollectionFile(directory, 'users');
  if (!file) {
    throw new Error('users.jsonl or users.json was not found in the export directory.');
  }
  const users = [];
  const addRecord = (record) => {
    const normalized = normalizeRecord(record);
    if (normalized) users.push(normalized);
  };
  if (file.toLowerCase().endsWith('.jsonl')) {
    iterateJsonl(file, addRecord);
  } else {
    for (const record of readRecordsFromFile(file)) addRecord(record);
  }
  return users;
};

const verify = async ({ exportDirectory, reportFile, allowEmpty }) => {
  const manifest = readManifest(exportDirectory);
  const users = loadIdentityRecords(exportDirectory);
  const failures = [];
  const academyReferences = new Set();
  const emailToLegacyIds = new Map();
  const userLegacyIds = [];

  for (const record of users) {
    userLegacyIds.push(record.legacyId);
    const email = normalizeEmail(pick(record.data, ['email', 'emailAddress']));
    if (email) {
      if (!emailToLegacyIds.has(email)) emailToLegacyIds.set(email, []);
      emailToLegacyIds.get(email).push(record.legacyId);
    } else {
      failures.push({
        type: 'INVALID_EMAIL',
        legacyId: record.legacyId,
        email: null
      });
    }
    const academyId = pick(record.data, [
      'academy_id',
      'academyId',
      'academy',
      'academyID'
    ]);
    if (academyId !== undefined && academyId !== null) {
      academyReferences.add(String(academyId));
    } else {
      failures.push({
        type: 'MISSING_ACADEMY_REFERENCE',
        legacyId: record.legacyId,
        email: email ? maskEmail(email) : null
      });
    }
  }

  for (const [email, legacyIds] of emailToLegacyIds) {
    if (legacyIds.length > 1) {
      failures.push({
        type: 'DUPLICATE_EMAIL_IN_EXPORT',
        email: maskEmail(email),
        legacyIds
      });
    }
  }

  const manifestCollections =
    manifest && Array.isArray(manifest.collections) ? manifest.collections : [];
  if (manifest) {
    for (const collection of manifestCollections) {
      const file = path.join(exportDirectory, collection.file);
      const actual = sha256File(file);
      if (actual !== collection.sha256) {
        failures.push({
          type: 'EXPORT_CHECKSUM_MISMATCH',
          collection: collection.name
        });
      }
    }
  }

  if (manifest && manifest.totalDocuments === 0 && !allowEmpty) {
    failures.push({
      type: 'EMPTY_EXPORT',
      message: 'Manifest reports zero documents.'
    });
  }
  if (!users.length && !allowEmpty) {
    failures.push({ type: 'EMPTY_USER_EXPORT' });
  }

  const prisma = loadPrisma();
  try {
    const [mappings, dbUsers, dbAcademies] = await Promise.all([
      prisma.legacyIdMap.findMany(),
      prisma.user.findMany({
        select: { id: true, legacyFirebaseUid: true, email: true, academyId: true }
      }),
      prisma.academy.findMany({
        select: { id: true, legacyFirebaseUid: true, code: true }
      })
    ]);

    const mappingIndex = new Map(
      mappings.map((mapping) => [
        mappingKey(mapping.collection, mapping.legacyId),
        mapping
      ])
    );
    const userById = new Map(dbUsers.map((user) => [user.id, user]));
    const academyById = new Map(
      dbAcademies.map((academy) => [academy.id, academy])
    );
    const mappedAcademyIds = new Set(
      mappings
        .filter(
          (mapping) =>
            mapping.collection === 'academy_settings' &&
            mapping.status === 'MAPPED' &&
            mapping.targetTable === 'academies'
        )
        .map((mapping) => mapping.targetId)
    );

    for (const legacyId of userLegacyIds) {
      const mapping = mappingIndex.get(mappingKey('users', legacyId));
      if (!mapping || mapping.status !== 'MAPPED' || mapping.targetTable !== 'users') {
        failures.push({
          type: 'USER_NOT_MAPPED',
          legacyId,
          status: mapping ? mapping.status : 'MISSING',
          notes: mapping ? mapping.notes : null
        });
        continue;
      }
      if (!isUuid(mapping.targetId)) {
        failures.push({
          type: 'USER_TARGET_NOT_UUID',
          legacyId,
          targetId: mapping.targetId
        });
        continue;
      }
      const user = userById.get(mapping.targetId);
      if (!user) {
        failures.push({
          type: 'USER_TARGET_MISSING',
          legacyId,
          targetId: mapping.targetId
        });
        continue;
      }
      if (!user.legacyFirebaseUid) {
        failures.push({
          type: 'USER_LEGACY_UID_NOT_SET',
          legacyId,
          targetId: mapping.targetId,
          email: maskEmail(user.email)
        });
      } else if (user.legacyFirebaseUid !== legacyId) {
        failures.push({
          type: 'USER_LEGACY_UID_MISMATCH',
          legacyId,
          targetId: mapping.targetId,
          email: maskEmail(user.email)
        });
      }
      const academy = academyById.get(user.academyId);
      if (
        !academy ||
        (!academy.legacyFirebaseUid && !mappedAcademyIds.has(user.academyId))
      ) {
        failures.push({
          type: 'USER_ACADEMY_NOT_MAPPED',
          legacyId,
          targetId: mapping.targetId
        });
      }
    }

    for (const legacyId of academyReferences) {
      const mapping = mappingIndex.get(mappingKey('academy_settings', legacyId));
      if (
        !mapping ||
        mapping.status !== 'MAPPED' ||
        mapping.targetTable !== 'academies'
      ) {
        failures.push({
          type: 'ACADEMY_NOT_MAPPED',
          legacyId,
          status: mapping ? mapping.status : 'MISSING',
          notes: mapping ? mapping.notes : null
        });
        continue;
      }
      if (!isUuid(mapping.targetId)) {
        failures.push({
          type: 'ACADEMY_TARGET_NOT_UUID',
          legacyId,
          targetId: mapping.targetId
        });
        continue;
      }
      if (!academyById.has(mapping.targetId)) {
        failures.push({
          type: 'ACADEMY_TARGET_MISSING',
          legacyId,
          targetId: mapping.targetId
        });
      }
    }

    for (const mapping of mappings) {
      if (mapping.collection !== 'users') continue;
      if (mapping.status === 'MAPPED' && !isUuid(mapping.targetId)) {
        failures.push({
          type: 'MAPPING_TARGET_NOT_UUID',
          legacyId: mapping.legacyId,
          targetId: mapping.targetId
        });
      }
    }

    const report = {
      generatedAt: new Date().toISOString(),
      exportDirectory,
      manifest: manifest
        ? {
            exportedAt: manifest.exportedAt,
            projectId: manifest.projectId,
            totalDocuments: manifest.totalDocuments,
            collections: manifestCollections.length
          }
        : null,
      counts: {
        sourceUsers: users.length,
        sourceAcademyReferences: academyReferences.size,
        databaseUsersWithLegacyUid: dbUsers.filter((user) => user.legacyFirebaseUid)
          .length,
        mappings: mappings.length
      },
      failures,
      gate: {
        passed: failures.length === 0,
        failureCount: failures.length
      }
    };

    writeJsonFile(reportFile, report);
    return { report, reportFile };
  } finally {
    await prisma.$disconnect();
  }
};

const main = async (argv = process.argv.slice(2)) => {
  const args = parseArgs(argv);
  if (!args['export-dir']) {
    throw new Error('--export-dir is required.');
  }
  const exportDirectory = path.resolve(args['export-dir']);
  const reportFile = path.resolve(
    args.report || path.join(exportDirectory, 'identity-verification.json')
  );
  const { report } = await verify({
    exportDirectory,
    reportFile,
    allowEmpty: Boolean(args['allow-empty'])
  });

  console.log(
    `Identity verification: ${report.counts.sourceUsers} source users, ` +
      `${report.counts.sourceAcademyReferences} academy references, ` +
      `${report.gate.failureCount} failures.`
  );
  console.log(`Report: ${reportFile}`);

  if (!report.gate.passed) {
    console.log('Gate NOT passed. Resolve the failures before importing data.');
    return 1;
  }
  console.log('Gate passed.');
  return 0;
};

if (require.main === module) {
  main()
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error) => {
      console.error(`Identity verification failed: ${error.message}`);
      process.exitCode = 1;
    });
}

module.exports = { main, verify };
