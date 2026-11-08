const {
  normalizeEmail,
  normalizeRole,
  normalizeAccountStatus,
  isBcryptHash,
  toDate,
  maskEmail,
  normalizeRecord,
  buildIdentityPlan,
  toReport
} = require('../scripts/migration/lib/identity');

const BCRYPT_HASH = '$2a$04$GpJvnvHOCZrIn52XconcaO32BOgY/jl7/azyUlhpR3x0TNsBga7BK';

const userDoc = (id, data) => ({ id, data });
const academyDoc = (id, data = {}) => ({ id, data });

const existingAcademy = (overrides = {}) => ({
  id: '11111111-1111-4111-8111-111111111111',
  code: 'ACAD-1',
  name: 'Existing Academy',
  legacyFirebaseUid: null,
  academicStructure: null,
  ...overrides
});

const existingUser = (overrides = {}) => ({
  id: '22222222-2222-4222-8222-222222222222',
  email: 'teacher@example.com',
  academyId: '11111111-1111-4111-8111-111111111111',
  role: 'TEACHER',
  accountStatus: 'ACTIVE',
  fullName: 'Existing Teacher',
  phoneNumber: null,
  subject: null,
  extraInfo: null,
  joiningDate: null,
  studentCode: null,
  legacyFirebaseUid: null,
  ...overrides
});

const planFor = (options = {}) =>
  buildIdentityPlan({
    users: options.users || [],
    academies: options.academies || [],
    existingAcademies: options.existingAcademies || [],
    existingUsers: options.existingUsers || [],
    existingMappings: options.existingMappings,
    options: options.options || {}
  });

describe('identity normalization', () => {
  it('normalizes emails and rejects invalid values', () => {
    expect(normalizeEmail('  Teacher@Example.COM ')).toBe('teacher@example.com');
    expect(normalizeEmail('not-an-email')).toBeNull();
    expect(normalizeEmail(null)).toBeNull();
  });

  it('maps role and status aliases to schema enums', () => {
    expect(normalizeRole('teacher')).toBe('TEACHER');
    expect(normalizeRole('Super Admin')).toBe('ADMIN');
    expect(normalizeRole('guardian')).toBe('PARENT');
    expect(normalizeRole('unknown')).toBeNull();
    expect(normalizeAccountStatus('approved')).toBe('ACTIVE');
    expect(normalizeAccountStatus('suspended')).toBe('REJECTED');
    expect(normalizeAccountStatus(true)).toBe('ACTIVE');
    expect(normalizeAccountStatus('weird')).toBeNull();
  });

  it('detects bcrypt hashes and never accepts placeholders', () => {
    expect(isBcryptHash(BCRYPT_HASH)).toBe(true);
    expect(isBcryptHash('$2a$10$abcdefghijklmnopqrstuu')).toBe(false);
    expect(isBcryptHash('plaintext')).toBe(false);
    expect(isBcryptHash('$2a$10$abcdefghijklmnopqrstuu')).toBe(false);
  });

  it('parses ISO, epoch and Firestore timestamp shapes', () => {
    expect(toDate('2024-03-04T05:06:07.000Z').toISOString()).toBe(
      '2024-03-04T05:06:07.000Z'
    );
    expect(toDate(1700000000000).toISOString()).toBe('2023-11-14T22:13:20.000Z');
    expect(toDate({ _seconds: 1700000000, _nanoseconds: 0 }).toISOString()).toBe(
      '2023-11-14T22:13:20.000Z'
    );
    expect(toDate('not-a-date')).toBeNull();
  });

  it('masks emails in reports', () => {
    expect(maskEmail('teacher@example.com')).toBe('t***@example.com');
  });

  it('accepts both wrapped and flattened export records', () => {
    expect(normalizeRecord({ id: 'u1', data: { email: 'a@b.com' } })).toEqual({
      legacyId: 'u1',
      data: { email: 'a@b.com' }
    });
    expect(normalizeRecord({ id: 'u2', email: 'a@b.com' })).toEqual({
      legacyId: 'u2',
      data: { id: 'u2', email: 'a@b.com' }
    });
    expect(normalizeRecord({ data: {} })).toBeNull();
  });
});

describe('identity planning', () => {
  it('creates an academy from settings and imports bcrypt-backed users', () => {
    const plan = planFor({
      academies: [
        academyDoc('legacy-academy', {
          name: 'Legacy Academy',
          academy_code: 'LEG-1',
          academic_structure: { classes: ['1'] }
        })
      ],
      users: [
        userDoc('legacy-admin', {
          email: 'Admin@Example.com',
          full_name: 'Legacy Admin',
          role: 'admin',
          academy_id: 'legacy-academy',
          password_hash: BCRYPT_HASH,
          account_status: 'active'
        }),
        userDoc('legacy-student', {
          email: 'student@example.com',
          full_name: 'Legacy Student',
          role: 'student',
          academy_id: 'legacy-academy',
          student_code: 'STU-001'
        })
      ]
    });

    expect(plan.summary.academies.create).toBe(1);
    expect(plan.summary.users.create).toBe(1);
    expect(plan.summary.users.quarantine).toBe(1);
    const admin = plan.users.find((user) => user.legacyId === 'legacy-admin');
    expect(admin.action).toBe('create');
    expect(admin.email).toBe('admin@example.com');
    expect(admin.passwordHash).toBe(BCRYPT_HASH);
    expect(admin.accountStatus).toBe('ACTIVE');
    const student = plan.users.find((user) => user.legacyId === 'legacy-student');
    expect(student.action).toBe('quarantine');
    expect(student.reason).toBe('MISSING_OR_INCOMPATIBLE_PASSWORD_HASH');
    expect(plan.academies[0]).toMatchObject({
      action: 'create',
      code: 'LEG-1',
      name: 'Legacy Academy'
    });
    expect(plan.gate.passed).toBe(false);
  });

  it('marks reset-required users as pending instead of inventing a fixed password', () => {
    const plan = planFor({
      academies: [academyDoc('a1', { name: 'Academy One' })],
      users: [
        userDoc('u1', {
          email: 'reset@example.com',
          role: 'parent',
          academy_id: 'a1'
        })
      ],
      options: { onMissingPassword: 'reset' }
    });

    const user = plan.users[0];
    expect(user.action).toBe('create');
    expect(user.passwordReset).toBe(true);
    expect(user.passwordHash).toBeNull();
    expect(user.accountStatus).toBe('PENDING');
    expect(user.notes).toContain('PASSWORD_RESET_REQUIRED');
    expect(plan.summary.users.passwordReset).toBe(1);
  });

  it('reuses an existing user by normalized email and backfills the legacy uid', () => {
    const academy = existingAcademy();
    const user = existingUser({ email: 'Teacher@Example.com' });
    const plan = planFor({
      academies: [academyDoc(academy.code, { code: academy.code })],
      users: [
        userDoc('legacy-teacher', {
          email: 'teacher@example.com',
          role: 'teacher',
          academy_id: academy.code,
          password_hash: BCRYPT_HASH
        })
      ],
      existingAcademies: [academy],
      existingUsers: [user]
    });

    const planned = plan.users[0];
    expect(planned.action).toBe('reuse');
    expect(planned.id).toBe(user.id);
    expect(planned.matchedBy).toBe('email');
    expect(planned.updates.legacyFirebaseUid).toBe('legacy-teacher');
    expect(plan.summary.users.create).toBe(0);
  });

  it('reuses mappings idempotently on a second run', () => {
    const academy = existingAcademy({ legacyFirebaseUid: 'a1' });
    const user = existingUser({ legacyFirebaseUid: 'u1' });
    const plan = planFor({
      users: [
        userDoc('u1', {
          email: user.email,
          role: user.role,
          academy_id: 'a1',
          password_hash: BCRYPT_HASH
        })
      ],
      existingAcademies: [academy],
      existingUsers: [user],
      existingMappings: [
        {
          collection: 'academy_settings',
          legacyId: 'a1',
          targetTable: 'academies',
          targetId: academy.id,
          status: 'MAPPED'
        },
        {
          collection: 'users',
          legacyId: 'u1',
          targetTable: 'users',
          targetId: user.id,
          status: 'MAPPED'
        }
      ]
    });

    expect(plan.academies[0].action).toBe('reuse');
    expect(plan.academies[0].setLegacyUid).toBe(false);
    expect(plan.users[0].action).toBe('reuse');
    expect(plan.users[0].matchedBy).toBe('legacy-map');
    expect(plan.gate.passed).toBe(true);
  });

  it('quarantines a user whose email already belongs to another academy', () => {
    const academy = existingAcademy();
    const otherAcademyId = '33333333-3333-4333-8333-333333333333';
    const plan = planFor({
      academies: [academyDoc('a1', { code: academy.code })],
      users: [
        userDoc('u1', {
          email: 'teacher@example.com',
          role: 'teacher',
          academy_id: 'a1'
        })
      ],
      existingAcademies: [academy],
      existingUsers: [existingUser({ academyId: otherAcademyId })]
    });

    expect(plan.users[0].action).toBe('quarantine');
    expect(plan.users[0].reason).toBe('ACADEMY_MISMATCH');
  });

  it('quarantines duplicate emails inside the export', () => {
    const plan = planFor({
      academies: [academyDoc('a1', {})],
      users: [
        userDoc('u1', {
          email: 'dup@example.com',
          role: 'student',
          academy_id: 'a1',
          password_hash: BCRYPT_HASH
        }),
        userDoc('u2', {
          email: 'DUP@example.com',
          role: 'student',
          academy_id: 'a1',
          password_hash: BCRYPT_HASH
        })
      ]
    });

    expect(plan.users.every((user) => user.action === 'quarantine')).toBe(true);
    expect(plan.users.map((user) => user.reason)).toEqual([
      'DUPLICATE_EMAIL_IN_EXPORT',
      'DUPLICATE_EMAIL_IN_EXPORT'
    ]);
    expect(plan.gate.duplicateEmails).toBe(2);
  });

  it('refuses to infer an academy when shell creation is disabled', () => {
    const plan = planFor({
      users: [
        userDoc('u1', {
          email: 'orphan@example.com',
          role: 'student',
          academy_id: 'missing-academy',
          password_hash: BCRYPT_HASH
        })
      ],
      options: { createMissingAcademies: false }
    });

    expect(plan.academyIssues).toEqual([
      expect.objectContaining({
        legacyId: 'missing-academy',
        reason: 'UNRESOLVED_ACADEMY_REFERENCE',
        blocking: true
      })
    ]);
    expect(plan.users[0].action).toBe('quarantine');
    expect(plan.users[0].reason).toBe('UNRESOLVED_ACADEMY');
    expect(plan.gate.unresolvedAcademies).toBe(1);
  });

  it('flags shell academies created only from a user reference', () => {
    const plan = planFor({
      users: [
        userDoc('u1', {
          email: 'orphan@example.com',
          role: 'student',
          academy_id: 'ref-only',
          password_hash: BCRYPT_HASH
        })
      ]
    });

    expect(plan.academies[0].action).toBe('create');
    expect(plan.academies[0].review).toContain('ACADEMY_CREATED_FROM_REFERENCE');
    expect(plan.gate.passed).toBe(true);
  });

  it('produces a PII-masked report', () => {
    const plan = planFor({
      academies: [academyDoc('a1', { name: 'Academy One' })],
      users: [
        userDoc('u1', {
          email: 'student@example.com',
          role: 'student',
          academy_id: 'a1',
          password_hash: BCRYPT_HASH
        })
      ]
    });
    const report = toReport(plan, { mode: 'dry-run' });
    expect(report.users[0].email).toBe('s***@example.com');
    expect(JSON.stringify(report)).not.toContain('student@example.com');
    expect(report.gate.passed).toBe(true);
  });
});
