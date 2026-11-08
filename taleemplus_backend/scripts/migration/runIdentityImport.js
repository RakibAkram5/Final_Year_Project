const path = require('path');
const crypto = require('crypto');

require('dotenv').config({ path: path.resolve(__dirname, '..', '..', '.env') });

const bcrypt = require('bcryptjs');
const {
  buildIdentityPlan,
  toReport
} = require('./lib/identity');
const {
  readCollection,
  readManifest,
  writeJsonFile
} = require('./lib/exportFiles');

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

const loadExisting = async (prisma) => {
  const [academies, users, mappings] = await Promise.all([
    prisma.academy.findMany({
      select: {
        id: true,
        code: true,
        name: true,
        legacyFirebaseUid: true,
        academicStructure: true
      }
    }),
    prisma.user.findMany({
      select: {
        id: true,
        email: true,
        academyId: true,
        role: true,
        accountStatus: true,
        fullName: true,
        phoneNumber: true,
        subject: true,
        extraInfo: true,
        joiningDate: true,
        studentCode: true,
        legacyFirebaseUid: true
      }
    }),
    prisma.legacyIdMap.findMany()
  ]);
  return { academies, users, mappings };
};

const academyCreateData = (plan) => {
  const settings = plan.settings || {};
  const data = {
    code: plan.code,
    name: plan.name,
    legacyFirebaseUid: plan.legacyId
  };
  for (const [column, keys] of [
    ['address', ['address', 'academy_address', 'academyAddress']],
    ['phone', ['phone', 'academy_phone', 'academyPhone']],
    ['logo', ['logo', 'academy_logo', 'academyLogo']]
  ]) {
    const value = keys.map((key) => settings[key]).find((item) => item);
    if (value) data[column] = String(value);
  }
  const structure =
    settings.academic_structure !== undefined
      ? settings.academic_structure
      : settings.academicStructure;
  if (structure !== undefined && structure !== null) {
    data.academicStructure = structure;
  }
  return data;
};

const academyUpdateData = (plan, existing) => {
  const data = {};
  if (plan.setLegacyUid) data.legacyFirebaseUid = plan.legacyId;
  const settings = plan.settings || {};
  const structure =
    settings.academic_structure !== undefined
      ? settings.academic_structure
      : settings.academicStructure;
  if (
    structure !== undefined &&
    structure !== null &&
    (existing.academicStructure === null || existing.academicStructure === undefined)
  ) {
    data.academicStructure = structure;
  }
  return data;
};

const upsertMapping = (tx, mapping, existing = null) => {
  const where = {
    collection_legacyId: {
      collection: mapping.collection,
      legacyId: mapping.legacyId
    }
  };
  if (mapping.status === 'FAILED' && existing) {
    return tx.legacyIdMap.update({
      where,
      data: { status: 'FAILED', notes: mapping.notes }
    });
  }
  return tx.legacyIdMap.upsert({
    where,
    create: {
      collection: mapping.collection,
      legacyId: mapping.legacyId,
      targetTable: mapping.targetTable,
      targetId: mapping.targetId,
      status: mapping.status,
      notes: mapping.notes || null
    },
    update: {
      targetTable: mapping.targetTable,
      targetId: mapping.targetId,
      status: mapping.status,
      notes: mapping.notes || null
    }
  });
};

const userCreateData = (plan, passwordHash) => ({
  email: plan.email,
  passwordHash,
  fullName: plan.fullName,
  role: plan.role,
  accountStatus: plan.accountStatus,
  academyId: plan.academyId,
  legacyFirebaseUid: plan.legacyId,
  studentCode: plan.studentCode || null,
  phoneNumber: plan.phoneNumber || null,
  subject: plan.subject || null,
  extraInfo: plan.extraInfo || null,
  joiningDate: plan.joiningDate || null
});

const applyPlan = async (prisma, plan, existing) => {
  const mappingByKey = new Map(
    existing.mappings.map((mapping) => [
      `${mapping.collection}:${mapping.legacyId}`,
      mapping
    ])
  );

  const resetPasswords = new Map();
  for (const userPlan of plan.users) {
    if (userPlan.action === 'create' && userPlan.passwordReset) {
      const secret = crypto.randomBytes(32).toString('hex');
      resetPasswords.set(userPlan.legacyId, await bcrypt.hash(secret, 12));
    }
  }

  await prisma.$transaction(
    async (tx) => {
      const academyIdByLegacy = new Map();

      for (const academyPlan of plan.academies) {
        let targetId = academyPlan.id;

        if (academyPlan.action === 'create') {
          const created = await tx.academy.create({
            data: academyCreateData(academyPlan)
          });
          targetId = created.id;
        } else {
          const existingAcademy = existing.academies.find(
            (academy) => academy.id === academyPlan.id
          );
          const updates = academyUpdateData(academyPlan, existingAcademy || {});
          if (Object.keys(updates).length) {
            await tx.academy.update({
              where: { id: academyPlan.id },
              data: updates
            });
          }
        }

        academyIdByLegacy.set(academyPlan.legacyId, targetId);
        await upsertMapping(
          tx,
          {
            collection: 'academy_settings',
            legacyId: academyPlan.legacyId,
            targetTable: 'academies',
            targetId,
            status: 'MAPPED',
            notes: academyPlan.review.length
              ? academyPlan.review.join(',')
              : null
          },
          mappingByKey.get(`academy_settings:${academyPlan.legacyId}`)
        );
      }

      for (const userPlan of plan.users) {
        const key = `users:${userPlan.legacyId}`;

        if (userPlan.action === 'quarantine') {
          await upsertMapping(
            tx,
            {
              collection: 'users',
              legacyId: userPlan.legacyId,
              targetTable: 'quarantine',
              targetId: '',
              status: 'FAILED',
              notes: userPlan.reason
            },
            mappingByKey.get(key)
          );
          continue;
        }

        const academyId =
          userPlan.academyId ||
          academyIdByLegacy.get(userPlan.academyLegacyId);
        let targetId = userPlan.id;

        if (userPlan.action === 'create') {
          const passwordHash = userPlan.passwordReset
            ? resetPasswords.get(userPlan.legacyId)
            : userPlan.passwordHash;
          const data = userCreateData(userPlan, passwordHash);
          data.academyId = academyId;
          if (data.studentCode) {
            const taken = await tx.user.findFirst({
              where: { studentCode: data.studentCode },
              select: { id: true }
            });
            if (taken) data.studentCode = null;
          }
          const created = await tx.user.create({ data });
          targetId = created.id;
        } else if (userPlan.updates && Object.keys(userPlan.updates).length) {
          await tx.user.update({
            where: { id: userPlan.id },
            data: userPlan.updates
          });
        }

        await upsertMapping(
          tx,
          {
            collection: 'users',
            legacyId: userPlan.legacyId,
            targetTable: 'users',
            targetId,
            status: 'MAPPED',
            notes: userPlan.notes.length ? userPlan.notes.join(',') : null
          },
          mappingByKey.get(key)
        );
      }
    },
    { timeout: 180000, maxWait: 10000 }
  );
};

const main = async (argv = process.argv.slice(2)) => {
  const args = parseArgs(argv);
  const exportDirectory = args['export-dir']
    ? path.resolve(args['export-dir'])
    : null;
  if (!exportDirectory) {
    throw new Error(
      '--export-dir is required. Point it at the directory produced by the Firestore export.'
    );
  }

  const onMissingPassword = args['on-missing-password'] || 'quarantine';
  if (!['quarantine', 'reset'].includes(onMissingPassword)) {
    throw new Error('--on-missing-password must be "quarantine" or "reset".');
  }
  const apply = Boolean(args.apply);
  const strict = Boolean(args.strict);
  const allowEmpty = Boolean(args['allow-empty']);
  const createMissingAcademies = !args['no-create-missing-academies'];

  if (apply && process.env.NODE_ENV === 'production' && !args['allow-production']) {
    throw new Error(
      'Refusing to apply identity mappings with NODE_ENV=production. Pass --allow-production only after a verified backup.'
    );
  }

  const users = readCollection(exportDirectory, 'users');
  const academies = readCollection(exportDirectory, 'academy_settings');
  if (!users.length && !academies.length && !allowEmpty) {
    throw new Error(
      'The export contains no users or academy_settings documents. Refusing to report migration success from an empty export. Use --allow-empty only if this is independently verified.'
    );
  }

  const prisma = loadPrisma();
  try {
    const existing = await loadExisting(prisma);
    const plan = buildIdentityPlan({
      users,
      academies,
      existingAcademies: existing.academies,
      existingUsers: existing.users,
      existingMappings: existing.mappings,
      options: { createMissingAcademies, onMissingPassword }
    });

    const manifest = readManifest(exportDirectory);
    const reportFile = path.resolve(
      args.report || path.join(exportDirectory, 'identity-report.json')
    );
    const report = toReport(plan, {
      mode: apply ? 'apply' : 'dry-run',
      exportDirectory,
      manifest: manifest
        ? {
            exportedAt: manifest.exportedAt,
            projectId: manifest.projectId,
            totalDocuments: manifest.totalDocuments
          }
        : null,
      options: { createMissingAcademies, onMissingPassword }
    });
    writeJsonFile(reportFile, report);

    console.log(
      `Identity plan (${apply ? 'APPLY' : 'DRY RUN'}): ` +
        `${plan.summary.academies.create} academies to create, ` +
        `${plan.summary.academies.reuse} to reuse, ` +
        `${plan.summary.users.create} users to create, ` +
        `${plan.summary.users.reuse} to reuse, ` +
        `${plan.summary.users.quarantine} quarantined.`
    );
    if (plan.summary.users.passwordReset) {
      console.log(
        `${plan.summary.users.passwordReset} users need a forced password reset (no compatible hash).`
      );
    }
    console.log(`Report: ${reportFile}`);

    if (!plan.gate.passed) {
      console.log(
        'Gate not passed: unresolved academies=' +
          `${plan.gate.unresolvedAcademies}, quarantined users=` +
          `${plan.gate.quarantinedUsers}. Review the report before applying.`
      );
    }

    if (apply) {
      if (!plan.gate.passed && !args['allow-incomplete']) {
        throw new Error(
          'The gate has unresolved identities. Review the report, fix them, or pass --allow-incomplete to apply the mappable records and leave the rest quarantined.'
        );
      }
      await applyPlan(prisma, plan, existing);
      console.log('Identity mappings applied.');
    } else {
      console.log('Dry run only. Re-run with --apply to write mappings.');
    }

    if (strict && !plan.gate.passed) return 1;
    return 0;
  } finally {
    await prisma.$disconnect();
  }
};

if (require.main === module) {
  main()
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error) => {
      console.error(`Identity import failed: ${error.message}`);
      process.exitCode = 1;
    });
}

module.exports = { main };
