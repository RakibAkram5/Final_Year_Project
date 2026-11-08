const crypto = require('crypto');

const ACADEMY_COLLECTION = 'academy_settings';
const USER_COLLECTION = 'users';
const VALID_ROLES = ['ADMIN', 'TEACHER', 'STUDENT', 'PARENT'];
const VALID_STATUSES = ['ACTIVE', 'PENDING', 'REJECTED'];
const BCRYPT_PATTERN = /^\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}$/;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const ROLE_ALIASES = {
  SUPER_ADMIN: 'ADMIN',
  SUPERADMIN: 'ADMIN',
  ADMINISTRATOR: 'ADMIN',
  ADMINS: 'ADMIN',
  STAFF: 'TEACHER',
  TEACHERS: 'TEACHER',
  STUDENTS: 'STUDENT',
  GUARDIAN: 'PARENT',
  GUARDIANS: 'PARENT',
  PARENTS: 'PARENT'
};

const STATUS_ALIASES = {
  ACTIVE: 'ACTIVE',
  APPROVED: 'ACTIVE',
  ENABLED: 'ACTIVE',
  PENDING: 'PENDING',
  WAITING: 'PENDING',
  IN_REVIEW: 'PENDING',
  REJECTED: 'REJECTED',
  DISABLED: 'REJECTED',
  SUSPENDED: 'REJECTED',
  INACTIVE: 'REJECTED',
  BLOCKED: 'REJECTED'
};

const pick = (source, keys) => {
  if (!source || typeof source !== 'object') return undefined;
  for (const key of keys) {
    const value = source[key];
    if (value !== undefined && value !== null && value !== '') return value;
  }
  return undefined;
};

const normalizeEmail = (value) => {
  if (typeof value !== 'string') return null;
  const email = value.trim().toLowerCase();
  return EMAIL_PATTERN.test(email) ? email : null;
};

const normalizeRole = (value) => {
  if (typeof value !== 'string') return null;
  const token = value.trim().toUpperCase().replace(/[\s-]+/g, '_');
  const normalized = ROLE_ALIASES[token] || token;
  return VALID_ROLES.includes(normalized) ? normalized : null;
};

const normalizeAccountStatus = (value) => {
  if (typeof value === 'boolean') return value ? 'ACTIVE' : 'REJECTED';
  if (typeof value !== 'string') return null;
  const token = value.trim().toUpperCase().replace(/[\s-]+/g, '_');
  return STATUS_ALIASES[token] || null;
};

const isBcryptHash = (value) =>
  typeof value === 'string' && BCRYPT_PATTERN.test(value);

const isUuid = (value) => typeof value === 'string' && UUID_PATTERN.test(value);

const toDate = (value) => {
  if (value === null || value === undefined || value === '') return null;
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value;
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    const millis = value > 1e12 ? value : value * 1000;
    const date = new Date(millis);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed) return null;
    if (/^\d+$/.test(trimmed)) return toDate(Number(trimmed));
    const date = new Date(trimmed);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (typeof value === 'object') {
    const seconds = value._seconds !== undefined ? value._seconds : value.seconds;
    const nanos =
      value._nanoseconds !== undefined
        ? value._nanoseconds
        : value.nanoseconds !== undefined
          ? value.nanoseconds
          : 0;
    if (typeof seconds === 'number') {
      return new Date(seconds * 1000 + Math.floor(nanos / 1e6));
    }
    if (value.value && typeof value.value === 'object') {
      return toDate(value.value);
    }
  }
  return null;
};

const maskEmail = (email) => {
  const normalized = normalizeEmail(email);
  if (!normalized) return null;
  const [local, domain] = normalized.split('@');
  const visible = local.slice(0, 1) || '*';
  return `${visible}***@${domain}`;
};

const sha256 = (value) =>
  crypto.createHash('sha256').update(String(value)).digest('hex');

const normalizeRecord = (raw) => {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  if (raw.id === undefined || raw.id === null) return null;
  if (raw.data && typeof raw.data === 'object' && !Array.isArray(raw.data)) {
    return { legacyId: String(raw.id), data: raw.data };
  }
  return { legacyId: String(raw.id), data: { ...raw } };
};

const mappingKey = (collection, legacyId) => `${collection}:${legacyId}`;

const indexMappings = (existingMappings) => {
  const index = new Map();
  if (!existingMappings) return index;
  const entries = Array.isArray(existingMappings)
    ? existingMappings
    : Object.entries(existingMappings).map(([key, value]) => {
        const separator = key.indexOf(':');
        return {
          collection: separator === -1 ? key : key.slice(0, separator),
          legacyId: separator === -1 ? '' : key.slice(separator + 1),
          ...value
        };
      });
  for (const entry of entries) {
    if (!entry || entry.collection === undefined || entry.legacyId === undefined) {
      continue;
    }
    index.set(mappingKey(entry.collection, entry.legacyId), entry);
  }
  return index;
};

const chooseAcademyCode = (preferred, legacyId, usedCodes) => {
  const preferredCode =
    typeof preferred === 'string' ? preferred.trim().toUpperCase() : '';
  if (preferredCode && !usedCodes.has(preferredCode)) {
    usedCodes.add(preferredCode);
    return { code: preferredCode, conflict: false };
  }
  const base = `MIG-${sha256(legacyId).slice(0, 10).toUpperCase()}`;
  let candidate = base;
  let counter = 1;
  while (usedCodes.has(candidate)) {
    candidate = `${base}-${counter}`;
    counter += 1;
  }
  usedCodes.add(candidate);
  return { code: candidate, conflict: Boolean(preferredCode) };
};

const buildIdentityPlan = ({
  users = [],
  academies = [],
  existingAcademies = [],
  existingUsers = [],
  existingMappings,
  options = {}
}) => {
  const createMissingAcademies = options.createMissingAcademies !== false;
  const onMissingPassword = options.onMissingPassword || 'quarantine';

  const userRecords = users.map(normalizeRecord).filter(Boolean);
  const academyRecords = academies.map(normalizeRecord).filter(Boolean);

  const invalidRecords = [];
  const seenUserIds = new Set();
  const seenAcademyIds = new Set();
  const dedupedUserRecords = [];
  const dedupedAcademyRecords = [];

  for (const record of userRecords) {
    if (seenUserIds.has(record.legacyId)) {
      invalidRecords.push({
        collection: USER_COLLECTION,
        legacyId: record.legacyId,
        reason: 'DUPLICATE_LEGACY_ID'
      });
      continue;
    }
    seenUserIds.add(record.legacyId);
    dedupedUserRecords.push(record);
  }
  for (const record of academyRecords) {
    if (seenAcademyIds.has(record.legacyId)) {
      invalidRecords.push({
        collection: ACADEMY_COLLECTION,
        legacyId: record.legacyId,
        reason: 'DUPLICATE_LEGACY_ID'
      });
      continue;
    }
    seenAcademyIds.add(record.legacyId);
    dedupedAcademyRecords.push(record);
  }

  const academyById = new Map(existingAcademies.map((item) => [item.id, item]));
  const academyByLegacy = new Map(
    existingAcademies
      .filter((item) => item.legacyFirebaseUid)
      .map((item) => [item.legacyFirebaseUid, item])
  );
  const academyByCode = new Map(
    existingAcademies.map((item) => [String(item.code).toUpperCase(), item])
  );
  const userById = new Map(existingUsers.map((item) => [item.id, item]));
  const userByEmail = new Map();
  for (const user of existingUsers) {
    const email = normalizeEmail(user.email);
    if (email && !userByEmail.has(email)) userByEmail.set(email, user);
  }

  const mappings = indexMappings(existingMappings);
  const usedCodes = new Set(existingAcademies.map((item) => String(item.code).toUpperCase()));
  const usedStudentCodes = new Set(
    existingUsers.map((item) => item.studentCode).filter(Boolean)
  );

  const plannedAcademies = new Map();
  const academyIssues = [];

  const resolveMappedAcademy = (legacyId) => {
    const mapping = mappings.get(mappingKey(ACADEMY_COLLECTION, legacyId));
    if (!mapping || mapping.status !== 'MAPPED' || mapping.targetTable !== 'academies') {
      return null;
    }
    return academyById.get(mapping.targetId) || null;
  };

  const planAcademy = (legacyId, settings, source) => {
    if (plannedAcademies.has(legacyId)) {
      const existingPlan = plannedAcademies.get(legacyId);
      if (settings && !existingPlan.settings) existingPlan.settings = settings;
      return existingPlan;
    }

    const mapped = resolveMappedAcademy(legacyId);
    if (mapped) {
      const plan = {
        legacyId,
        action: 'reuse',
        id: mapped.id,
        code: mapped.code,
        name: mapped.name,
        matchedBy: 'legacy-map',
        settings: settings || null,
        setLegacyUid: mapped.legacyFirebaseUid !== legacyId,
        review: []
      };
      plannedAcademies.set(legacyId, plan);
      return plan;
    }

    const byLegacyUid = academyByLegacy.get(legacyId);
    if (byLegacyUid) {
      const plan = {
        legacyId,
        action: 'reuse',
        id: byLegacyUid.id,
        code: byLegacyUid.code,
        name: byLegacyUid.name,
        matchedBy: 'legacy-uid',
        settings: settings || null,
        setLegacyUid: false,
        review: []
      };
      plannedAcademies.set(legacyId, plan);
      return plan;
    }

    if (academyById.has(legacyId)) {
      const exact = academyById.get(legacyId);
      const plan = {
        legacyId,
        action: 'reuse',
        id: exact.id,
        code: exact.code,
        name: exact.name,
        matchedBy: 'id',
        settings: settings || null,
        setLegacyUid: exact.legacyFirebaseUid !== legacyId,
        review: []
      };
      plannedAcademies.set(legacyId, plan);
      return plan;
    }

    const preferredCode = settings
      ? pick(settings, ['academy_code', 'academyCode', 'code'])
      : undefined;
    if (preferredCode) {
      const byCode = academyByCode.get(String(preferredCode).trim().toUpperCase());
      if (byCode) {
        if (byCode.legacyFirebaseUid && byCode.legacyFirebaseUid !== legacyId) {
          academyIssues.push({
            legacyId,
            source,
            reason: 'ACADEMY_CODE_CONFLICT',
            blocking: true
          });
          return null;
        }
        const plan = {
          legacyId,
          action: 'reuse',
          id: byCode.id,
          code: byCode.code,
          name: byCode.name,
          matchedBy: 'academy-code',
          settings: settings || null,
          setLegacyUid: byCode.legacyFirebaseUid !== legacyId,
          review: []
        };
        plannedAcademies.set(legacyId, plan);
        return plan;
      }
    }

    if (!createMissingAcademies && source !== 'settings') {
      academyIssues.push({
        legacyId,
        source,
        reason: 'UNRESOLVED_ACADEMY_REFERENCE',
        blocking: true
      });
      return null;
    }

    const { code, conflict } = chooseAcademyCode(preferredCode, legacyId, usedCodes);
    const plan = {
      legacyId,
      action: 'create',
      id: null,
      code,
      name:
        (settings &&
          pick(settings, ['name', 'academy_name', 'academyName', 'title'])) ||
        `Legacy Academy ${legacyId.slice(0, 8)}`,
      matchedBy: source === 'settings' ? 'settings-document' : 'reference',
      settings: settings || null,
      setLegacyUid: true,
      review: []
    };
    if (source !== 'settings') plan.review.push('ACADEMY_CREATED_FROM_REFERENCE');
    if (conflict) plan.review.push('ACADEMY_CODE_CONFLICT_REASSIGNED');
    plannedAcademies.set(legacyId, plan);
    return plan;
  };

  for (const record of dedupedAcademyRecords) {
    planAcademy(record.legacyId, record.data, 'settings');
  }

  for (const record of dedupedUserRecords) {
    const legacyAcademyId = pick(record.data, [
      'academy_id',
      'academyId',
      'academy',
      'academyID'
    ]);
    if (legacyAcademyId !== undefined && legacyAcademyId !== null) {
      planAcademy(String(legacyAcademyId), null, 'reference');
    }
  }

  const userRecordsByEmail = new Map();
  for (const record of dedupedUserRecords) {
    const email = normalizeEmail(pick(record.data, ['email', 'emailAddress']));
    if (!email) continue;
    if (!userRecordsByEmail.has(email)) userRecordsByEmail.set(email, []);
    userRecordsByEmail.get(email).push(record.legacyId);
  }

  const userPlans = [];
  const quarantinePlans = [];

  for (const record of dedupedUserRecords) {
    const data = record.data;
    const email = normalizeEmail(pick(data, ['email', 'emailAddress']));
    if (!email) {
      const plan = {
        legacyId: record.legacyId,
        action: 'quarantine',
        reason: 'INVALID_EMAIL',
        emailMasked: null,
        role: null,
        academyLegacyId: null
      };
      userPlans.push(plan);
      quarantinePlans.push(plan);
      continue;
    }

    const role = normalizeRole(pick(data, ['role', 'user_role', 'userRole']));
    if (!role) {
      const plan = {
        legacyId: record.legacyId,
        action: 'quarantine',
        reason: 'INVALID_ROLE',
        emailMasked: maskEmail(email),
        role: null,
        academyLegacyId: null
      };
      userPlans.push(plan);
      quarantinePlans.push(plan);
      continue;
    }

    const legacyAcademyId = pick(data, [
      'academy_id',
      'academyId',
      'academy',
      'academyID'
    ]);
    const academyPlan =
      legacyAcademyId !== undefined && legacyAcademyId !== null
        ? plannedAcademies.get(String(legacyAcademyId))
        : null;
    if (!academyPlan) {
      const plan = {
        legacyId: record.legacyId,
        action: 'quarantine',
        reason: 'UNRESOLVED_ACADEMY',
        emailMasked: maskEmail(email),
        role,
        academyLegacyId:
          legacyAcademyId !== undefined && legacyAcademyId !== null
            ? String(legacyAcademyId)
            : null,
        academyId: null
      };
      userPlans.push(plan);
      quarantinePlans.push(plan);
      continue;
    }

    const duplicates = userRecordsByEmail.get(email) || [];
    if (duplicates.length > 1) {
      const plan = {
        legacyId: record.legacyId,
        action: 'quarantine',
        reason: 'DUPLICATE_EMAIL_IN_EXPORT',
        emailMasked: maskEmail(email),
        role,
        academyLegacyId: String(legacyAcademyId),
        academyId: academyPlan.id
      };
      userPlans.push(plan);
      quarantinePlans.push(plan);
      continue;
    }

    const mapping = mappings.get(mappingKey(USER_COLLECTION, record.legacyId));
    const mappingTarget =
      mapping && mapping.status === 'MAPPED' && mapping.targetTable === 'users'
        ? userById.get(mapping.targetId)
        : null;

    let existing = mappingTarget || userByEmail.get(email) || null;
    let matchedBy = mappingTarget ? 'legacy-map' : existing ? 'email' : null;

    if (existing && existing.academyId !== academyPlan.id) {
      const plan = {
        legacyId: record.legacyId,
        action: 'quarantine',
        reason: 'ACADEMY_MISMATCH',
        emailMasked: maskEmail(email),
        role,
        academyLegacyId: String(legacyAcademyId),
        academyId: academyPlan.id,
        existingUserId: existing.id
      };
      userPlans.push(plan);
      quarantinePlans.push(plan);
      continue;
    }

    if (existing && existing.role !== role) {
      const plan = {
        legacyId: record.legacyId,
        action: 'quarantine',
        reason: 'ROLE_MISMATCH',
        emailMasked: maskEmail(email),
        role,
        academyLegacyId: String(legacyAcademyId),
        academyId: academyPlan.id,
        existingUserId: existing.id
      };
      userPlans.push(plan);
      quarantinePlans.push(plan);
      continue;
    }

    if (
      existing &&
      existing.legacyFirebaseUid &&
      existing.legacyFirebaseUid !== record.legacyId
    ) {
      const plan = {
        legacyId: record.legacyId,
        action: 'quarantine',
        reason: 'LEGACY_UID_CONFLICT',
        emailMasked: maskEmail(email),
        role,
        academyLegacyId: String(legacyAcademyId),
        academyId: academyPlan.id,
        existingUserId: existing.id
      };
      userPlans.push(plan);
      quarantinePlans.push(plan);
      continue;
    }

    const fullName =
      pick(data, ['full_name', 'fullName', 'name']) ||
      email.split('@')[0] ||
      'Migrated User';
    const phoneNumber = pick(data, ['phone_number', 'phoneNumber', 'phone']) || null;
    const subject = pick(data, ['subject']) || null;
    const extraInfo = pick(data, ['extra_info', 'extraInfo']) || null;
    const joiningDate = toDate(
      pick(data, ['joining_date', 'joiningDate', 'created_at', 'createdAt'])
    );
    const rawStudentCode = pick(data, ['student_code', 'studentCode']) || null;
    const studentCode =
      role === 'STUDENT' && rawStudentCode && !usedStudentCodes.has(rawStudentCode)
        ? String(rawStudentCode)
        : null;

    if (existing) {
      const updates = {};
      if (!existing.legacyFirebaseUid) updates.legacyFirebaseUid = record.legacyId;
      if ((!existing.fullName || existing.fullName === '') && fullName) {
        updates.fullName = fullName;
      }
      if ((!existing.phoneNumber || existing.phoneNumber === '') && phoneNumber) {
        updates.phoneNumber = phoneNumber;
      }
      if ((!existing.subject || existing.subject === '') && subject) {
        updates.subject = subject;
      }
      if ((!existing.extraInfo || existing.extraInfo === '') && extraInfo) {
        updates.extraInfo = extraInfo;
      }
      if (!existing.joiningDate && joiningDate) updates.joiningDate = joiningDate;
      if (
        (!existing.studentCode || existing.studentCode === '') &&
        studentCode &&
        !usedStudentCodes.has(studentCode)
      ) {
        updates.studentCode = studentCode;
        usedStudentCodes.add(studentCode);
      }

      userPlans.push({
        legacyId: record.legacyId,
        action: 'reuse',
        id: existing.id,
        matchedBy,
        email,
        emailMasked: maskEmail(email),
        fullName,
        role,
        accountStatus: existing.accountStatus,
        academyLegacyId: String(legacyAcademyId),
        academyId: academyPlan.id,
        updates,
        notes: []
      });
      continue;
    }

    const rawHash = pick(data, [
      'password_hash',
      'passwordHash',
      'password',
      'password_digest'
    ]);
    if (!isBcryptHash(rawHash) && onMissingPassword !== 'reset') {
      const plan = {
        legacyId: record.legacyId,
        action: 'quarantine',
        reason: 'MISSING_OR_INCOMPATIBLE_PASSWORD_HASH',
        emailMasked: maskEmail(email),
        role,
        academyLegacyId: String(legacyAcademyId),
        academyId: academyPlan.id
      };
      userPlans.push(plan);
      quarantinePlans.push(plan);
      continue;
    }

    const passwordReset = !isBcryptHash(rawHash);
    let accountStatus =
      normalizeAccountStatus(
        pick(data, ['account_status', 'accountStatus', 'status', 'approved'])
      ) || (passwordReset ? 'PENDING' : 'ACTIVE');
    if (passwordReset) accountStatus = 'PENDING';

    if (studentCode) usedStudentCodes.add(studentCode);

    userPlans.push({
      legacyId: record.legacyId,
      action: 'create',
      email,
      emailMasked: maskEmail(email),
      fullName,
      role,
      accountStatus,
      academyLegacyId: String(legacyAcademyId),
      academyId: academyPlan.id,
      passwordHash: isBcryptHash(rawHash) ? rawHash : null,
      passwordReset,
      studentCode,
      phoneNumber,
      subject,
      extraInfo,
      joiningDate,
      notes: passwordReset ? ['PASSWORD_RESET_REQUIRED'] : []
    });
  }

  const plannedMappings = [];
  for (const plan of plannedAcademies.values()) {
    plannedMappings.push({
      collection: ACADEMY_COLLECTION,
      legacyId: plan.legacyId,
      targetTable: 'academies',
      targetId: plan.id,
      status: 'MAPPED',
      action: plan.action,
      notes: plan.review.length ? plan.review.join(',') : null
    });
  }
  for (const plan of userPlans) {
    if (plan.action === 'quarantine') {
      plannedMappings.push({
        collection: USER_COLLECTION,
        legacyId: plan.legacyId,
        targetTable: 'quarantine',
        targetId: '',
        status: 'FAILED',
        action: 'quarantine',
        notes: plan.reason
      });
    } else {
      plannedMappings.push({
        collection: USER_COLLECTION,
        legacyId: plan.legacyId,
        targetTable: 'users',
        targetId: plan.id,
        status: 'MAPPED',
        action: plan.action,
        notes: plan.notes && plan.notes.length ? plan.notes.join(',') : null
      });
    }
  }

  const unresolvedAcademies = new Set(
    academyIssues.filter((issue) => issue.blocking).map((issue) => issue.legacyId)
  );
  const quarantinedUsers = userPlans.filter((plan) => plan.action === 'quarantine');
  const createdAcademies = [...plannedAcademies.values()].filter(
    (plan) => plan.action === 'create'
  );
  const reusedAcademies = [...plannedAcademies.values()].filter(
    (plan) => plan.action === 'reuse'
  );
  const createdUsers = userPlans.filter((plan) => plan.action === 'create');
  const reusedUsers = userPlans.filter((plan) => plan.action === 'reuse');

  return {
    academies: [...plannedAcademies.values()],
    users: userPlans,
    mappings: plannedMappings,
    quarantines: quarantinedUsers,
    academyIssues,
    invalidRecords,
    summary: {
      academies: {
        total: plannedAcademies.size,
        create: createdAcademies.length,
        reuse: reusedAcademies.length,
        unresolved: unresolvedAcademies.size
      },
      users: {
        total: userPlans.length,
        create: createdUsers.length,
        reuse: reusedUsers.length,
        quarantine: quarantinedUsers.length,
        passwordReset: createdUsers.filter((plan) => plan.passwordReset).length
      }
    },
    gate: {
      unresolvedAcademies: unresolvedAcademies.size,
      quarantinedUsers: quarantinedUsers.length,
      duplicateEmails: userPlans.filter(
        (plan) => plan.action === 'quarantine' && plan.reason === 'DUPLICATE_EMAIL_IN_EXPORT'
      ).length,
      passed: unresolvedAcademies.size === 0 && quarantinedUsers.length === 0
    }
  };
};

const toReport = (plan, meta = {}) => ({
  generatedAt: new Date().toISOString(),
  ...meta,
  summary: plan.summary,
  gate: plan.gate,
  academies: plan.academies.map((academy) => ({
    legacyId: academy.legacyId,
    action: academy.action,
    targetId: academy.id,
    code: academy.code,
    matchedBy: academy.matchedBy,
    review: academy.review
  })),
  users: plan.users.map((user) => ({
    legacyId: user.legacyId,
    action: user.action,
    targetId: user.id || null,
    email: user.emailMasked,
    role: user.role,
    academyLegacyId: user.academyLegacyId,
    reason: user.reason || null,
    notes: user.notes || []
  })),
  academyIssues: plan.academyIssues,
  invalidRecords: plan.invalidRecords
});

module.exports = {
  ACADEMY_COLLECTION,
  USER_COLLECTION,
  VALID_ROLES,
  VALID_STATUSES,
  normalizeEmail,
  normalizeRole,
  normalizeAccountStatus,
  isBcryptHash,
  isUuid,
  toDate,
  maskEmail,
  normalizeRecord,
  mappingKey,
  indexMappings,
  buildIdentityPlan,
  toReport
};
