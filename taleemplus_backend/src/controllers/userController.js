const bcrypt = require('bcryptjs');
const { validatePassword } = require('../utils/passwordPolicy');
const crypto = require('crypto');
const prisma = require('../config/db');
const { notFound } = require('../utils/apiError');
const { sendSuccess } = require('../utils/response');
const { toIso } = require('../utils/dto');
const { assertEntityInAcademy } = require('../utils/tenant');

const USER_ROLES = ['ADMIN', 'TEACHER', 'STUDENT', 'PARENT'];

const safeUser = (user) => ({
  id: user.id,
  fullName: user.fullName,
  email: user.email,
  phoneNumber: user.phoneNumber,
  role: user.role,
  accountStatus: user.accountStatus,
  academyId: user.academyId,
  studentCode: user.studentCode,
  rollNumber: user.rollNumber,
  subject: user.subject,
  extraInfo: user.extraInfo,
  joiningDate: toIso(user.joiningDate),
  assignedSections: user.assignedSections,
  createdAt: toIso(user.createdAt),
  updatedAt: toIso(user.updatedAt)
});

const directoryUser = (user) => ({
  id: user.id,
  fullName: user.fullName,
  email: user.email,
  role: user.role,
  phoneNumber: user.phoneNumber,
  studentCode: user.studentCode,
  rollNumber: user.rollNumber,
  subject: user.subject,
  joiningDate: toIso(user.joiningDate)
});

const getPendingUsers = async (req, res, next) => {
  try {
    const pendingUsers = await prisma.user.findMany({
      where: {
        academyId: req.academyId,
        accountStatus: 'PENDING'
      },
      orderBy: { createdAt: 'desc' }
    });

    return sendSuccess(res, pendingUsers.map(safeUser));
  } catch (err) {
    next(err);
  }
};

const approveUser = async (req, res, next) => {
  try {
    const { id } = req.params;
    const user = await prisma.user.findFirst({
      where: { id, academyId: req.academyId }
    });

    if (!user) throw notFound('User not found in academy.');

    const updated = await prisma.user.update({
      where: { id },
      data: { accountStatus: 'ACTIVE' }
    });

    await prisma.notification.create({
      data: {
        academyId: req.academyId,
        recipientId: id,
        title: 'Account Approved',
        message: 'Your TaleemPlus account has been approved by the Admin.',
        type: 'approval'
      }
    });

    return sendSuccess(res, safeUser(updated), {
      message: 'User approved successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const rejectUser = async (req, res, next) => {
  try {
    const { id } = req.params;
    const user = await prisma.user.findFirst({
      where: { id, academyId: req.academyId }
    });

    if (!user) throw notFound('User not found in academy.');

    const updated = await prisma.user.update({
      where: { id },
      data: { accountStatus: 'REJECTED' }
    });

    await prisma.refreshToken.updateMany({
      where: { userId: id, revoked: false },
      data: { revoked: true }
    });

    return sendSuccess(res, safeUser(updated), {
      message: 'User rejected successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const getUsersByRole = async (req, res, next) => {
  try {
    const { role } = req.query;
    const whereClause = {
      academyId: req.academyId,
      accountStatus: 'ACTIVE'
    };

    if (role) {
      const normalized = String(role).toUpperCase();
      if (!USER_ROLES.includes(normalized)) {
        return res.status(400).json({ success: false, message: 'Invalid role filter.' });
      }
      whereClause.role = normalized;
    }

    // Parents may list staff, but only their own linked children among
    // students, and never other parents.
    if (req.user.role === 'PARENT') {
      if (whereClause.role === 'PARENT') {
        whereClause.id = req.user.id;
      } else if (whereClause.role === 'STUDENT' || !whereClause.role) {
        whereClause.OR = [
          { role: { in: ['ADMIN', 'TEACHER'] } },
          { role: 'STUDENT', studentLinks: { some: { parentId: req.user.id } } }
        ];
      }
    }

    // Admins can additionally include deactivated accounts for management.
    if (req.user.role === 'ADMIN' && req.query.includeInactive === 'true') {
      whereClause.accountStatus = { in: ['ACTIVE', 'INACTIVE'] };
    }

    const users = await prisma.user.findMany({
      where: whereClause,
      orderBy: { fullName: 'asc' }
    });

    const serialize = req.user.role === 'ADMIN' ? safeUser : directoryUser;
    return sendSuccess(res, users.map(serialize));
  } catch (err) {
    next(err);
  }
};

const setAccountActive = (active) => async (req, res, next) => {
  try {
    const { id } = req.params;
    if (id === req.user.id) {
      return res.status(400).json({
        success: false,
        message: 'You cannot change the status of your own account.'
      });
    }
    const target = await assertEntityInAcademy('user', id, req.academyId);
    const expected = active ? 'INACTIVE' : 'ACTIVE';
    if (target.accountStatus !== expected) {
      return res.status(409).json({
        success: false,
        message: active
          ? 'Only deactivated accounts can be reactivated.'
          : 'Only active accounts can be deactivated.'
      });
    }
    const [updated] = await prisma.$transaction([
      prisma.user.update({
        where: { id: target.id },
        data: {
          accountStatus: active ? 'ACTIVE' : 'INACTIVE',
          deactivatedAt: active ? null : new Date()
        }
      }),
      prisma.refreshToken.updateMany({
        where: { userId: target.id, revoked: false },
        data: { revoked: true }
      })
    ]);
    return sendSuccess(res, safeUser(updated), {
      message: active ? 'Account reactivated.' : 'Account deactivated. Historical records are kept.'
    });
  } catch (err) {
    next(err);
  }
};

// Admin-assisted recovery for accounts without a security question.
const adminResetPassword = async (req, res, next) => {
  try {
    const { id } = req.params;
    if (id === req.user.id) {
      return res.status(400).json({
        success: false,
        message: 'Use "Change password" to update your own password.'
      });
    }
    const target = await assertEntityInAcademy('user', id, req.academyId);
    const passwordError = validatePassword(req.body.newPassword);
    if (passwordError) return res.status(400).json({ success: false, message: passwordError });
    const passwordHash = await bcrypt.hash(req.body.newPassword, 12);
    await prisma.$transaction([
      prisma.user.update({
        where: { id: target.id },
        data: { passwordHash, failedLoginAttempts: 0, lockedUntil: null }
      }),
      prisma.refreshToken.updateMany({
        where: { userId: target.id, revoked: false },
        data: { revoked: true }
      })
    ]);
    return sendSuccess(res, { reset: true }, {
      message: 'Password reset. Share the new password with the user privately.'
    });
  } catch (err) {
    next(err);
  }
};

const deactivateUser = setAccountActive(false);
const reactivateUser = setAccountActive(true);

const checkRollNumber = async (req, res, next) => {
  try {
    const rollNumber = String(req.query.rollNumber || '').trim();
    if (!rollNumber) {
      return res.status(400).json({ success: false, message: 'rollNumber is required.' });
    }
    const excludeId = req.query.excludeId ? String(req.query.excludeId) : undefined;
    const duplicate = await prisma.user.findFirst({
      where: {
        academyId: req.academyId,
        rollNumber: { equals: rollNumber, mode: 'insensitive' },
        ...(excludeId ? { id: { not: excludeId } } : {})
      },
      select: { id: true }
    });
    return sendSuccess(res, { available: !duplicate });
  } catch (err) {
    next(err);
  }
};

const linkChildToParent = async (req, res, next) => {
  try {
    let { parentId, studentId } = req.body;
    if (req.user.role === 'PARENT') {
      parentId = req.user.id;
    }
    if (!parentId || !studentId) {
      return res.status(400).json({
        success: false,
        message: 'parentId and studentId are required.'
      });
    }

    const parent = await prisma.user.findFirst({
      where: { id: parentId, academyId: req.academyId, role: 'PARENT' }
    });
    const student = await prisma.user.findFirst({
      where: { id: studentId, academyId: req.academyId, role: 'STUDENT' }
    });

    if (!parent || !student) {
      throw notFound('Parent or student not found in academy.');
    }

    const link = await prisma.parentStudent.upsert({
      where: { parentId_studentId: { parentId, studentId } },
      create: { parentId, studentId },
      update: {}
    });

    return sendSuccess(res, link, {
      message: 'Student linked to parent successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const removeLinkedChild = async (req, res, next) => {
  try {
    const parentId = req.user.role === 'PARENT'
      ? req.user.id
      : (req.body && req.body.parentId) || req.query.parentId;
    const { studentId } = req.params;
    if (!parentId || !studentId) {
      return res.status(400).json({
        success: false,
        message: 'parentId and studentId are required.'
      });
    }
    if (req.user.role !== 'PARENT' && req.user.role !== 'ADMIN') {
      return res.status(403).json({ success: false, message: 'Forbidden.' });
    }
    const link = await prisma.parentStudent.findFirst({
      where: {
        parentId,
        studentId,
        parent: { academyId: req.academyId },
        student: { academyId: req.academyId }
      }
    });
    if (!link) throw notFound('Linked child not found.');
    await prisma.parentStudent.delete({ where: { id: link.id } });
    return sendSuccess(res, { removed: true }, {
      message: 'Linked child removed successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const createUserByAdmin = async (req, res, next) => {
  try {
    const {
      email,
      password,
      fullName,
      role,
      phoneNumber,
      assignedSections,
      rollNumber,
      subject,
      extraInfo,
      joiningDate
    } = req.body;

    if (!email || !password || !fullName || !role) {
      return res.status(400).json({ success: false, message: 'Missing required user fields.' });
    }
    const normalizedRole = String(role).toUpperCase();
    if (!USER_ROLES.includes(normalizedRole)) {
      return res.status(400).json({ success: false, message: 'Invalid user role.' });
    }
    const passwordError = validatePassword(password);
    if (passwordError) return res.status(400).json({ success: false, message: passwordError });

    const normalizedEmail = String(email).trim().toLowerCase();
    const existing = await prisma.user.findFirst({
      where: { email: { equals: normalizedEmail, mode: 'insensitive' } },
      select: { id: true }
    });
    if (existing) {
      return res.status(400).json({ success: false, message: 'User email already exists.' });
    }

    const trimmedRoll = rollNumber ? String(rollNumber).trim() : '';
    if (trimmedRoll) {
      const duplicate = await prisma.user.findFirst({
        where: {
          academyId: req.academyId,
          rollNumber: { equals: trimmedRoll, mode: 'insensitive' }
        },
        select: { id: true }
      });
      if (duplicate) {
        return res.status(409).json({
          success: false,
          message: 'This roll number is already assigned to another student.'
        });
      }
    }
    let parsedJoiningDate = null;
    if (joiningDate) {
      parsedJoiningDate = new Date(joiningDate);
      if (Number.isNaN(parsedJoiningDate.getTime())) {
        return res.status(400).json({ success: false, message: 'Invalid joining date.' });
      }
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const newUser = await prisma.user.create({
      data: {
        email: normalizedEmail,
        passwordHash,
        fullName: String(fullName).trim(),
        phoneNumber: phoneNumber || null,
        role: normalizedRole,
        accountStatus: 'ACTIVE',
        studentCode: normalizedRole === 'STUDENT'
          ? crypto.randomBytes(8).toString('hex') : null,
        rollNumber: trimmedRoll || null,
        subject: subject || null,
        extraInfo: extraInfo || null,
        joiningDate: parsedJoiningDate,
        academyId: req.academyId,
        assignedSections: Array.isArray(assignedSections) ? assignedSections : []
      }
    });

    return sendSuccess(res, safeUser(newUser), {
      status: 201,
      message: 'User created successfully.'
    });
  } catch (err) {
    next(err);
  }
};

const updateUser = async (req, res, next) => {
  try {
    const { id } = req.params;
    const target = await assertEntityInAcademy('user', id, req.academyId);
    const data = {};
    const fields = ['fullName', 'phoneNumber', 'subject', 'extraInfo', 'rollNumber'];
    for (const field of fields) {
      if (req.body[field] === undefined) continue;
      data[field] = req.body[field] === null ? null : String(req.body[field]).trim() || null;
    }
    if (req.body.joiningDate !== undefined) {
      const parsed = req.body.joiningDate ? new Date(req.body.joiningDate) : null;
      if (parsed && Number.isNaN(parsed.getTime())) {
        return res.status(400).json({ success: false, message: 'Invalid joining date.' });
      }
      data.joiningDate = parsed;
    }
    if (req.body.assignedSections !== undefined) {
      if (!Array.isArray(req.body.assignedSections)) {
        return res.status(400).json({ success: false, message: 'assignedSections must be an array.' });
      }
      data.assignedSections = req.body.assignedSections.map(String);
    }
    if (req.body.accountStatus !== undefined) {
      const status = String(req.body.accountStatus).toUpperCase();
      if (!['ACTIVE', 'PENDING', 'REJECTED', 'INACTIVE'].includes(status)) {
        return res.status(400).json({ success: false, message: 'Invalid account status.' });
      }
      data.accountStatus = status;
    }
    if (!Object.keys(data).length) {
      return res.status(400).json({ success: false, message: 'No profile fields provided.' });
    }

    if (data.accountStatus && target.id === req.user.id) {
      return res.status(400).json({
        success: false,
        message: 'You cannot change the status of your own account.'
      });
    }

    if (data.rollNumber) {
      const duplicate = await prisma.user.findFirst({
        where: {
          academyId: req.academyId,
          rollNumber: { equals: data.rollNumber, mode: 'insensitive' },
          id: { not: target.id }
        },
        select: { id: true }
      });
      if (duplicate) {
        return res.status(409).json({
          success: false,
          message: 'This roll number is already assigned to another student.'
        });
      }
    }

    const updated = await prisma.user.update({ where: { id: target.id }, data });
    if (data.accountStatus && data.accountStatus !== 'ACTIVE') {
      await prisma.refreshToken.updateMany({
        where: { userId: target.id, revoked: false },
        data: { revoked: true }
      });
    }
    return sendSuccess(res, safeUser(updated), { message: 'Profile updated successfully.' });
  } catch (err) {
    next(err);
  }
};

const updateOwnProfile = async (req, res, next) => {
  try {
    const data = {};
    for (const field of ['fullName', 'phoneNumber', 'subject', 'extraInfo']) {
      if (req.body[field] === undefined) continue;
      data[field] = req.body[field] === null ? null : String(req.body[field]).trim() || null;
    }
    if (req.body.joiningDate !== undefined) {
      const parsed = req.body.joiningDate ? new Date(req.body.joiningDate) : null;
      if (parsed && Number.isNaN(parsed.getTime())) {
        return res.status(400).json({ success: false, message: 'Invalid joining date.' });
      }
      data.joiningDate = parsed;
    }
    if (!Object.keys(data).length) {
      return res.status(400).json({ success: false, message: 'No profile fields provided.' });
    }
    const updated = await prisma.user.update({
      where: { id: req.user.id },
      data
    });
    return sendSuccess(res, safeUser(updated), { message: 'Profile updated successfully.' });
  } catch (err) {
    next(err);
  }
};

const getProfilesByIds = async (req, res, next) => {
  try {
    const { ids } = req.body;
    if (!Array.isArray(ids) || ids.length === 0) {
      return res.status(400).json({ success: false, message: 'ids must be a non-empty array.' });
    }
    if (ids.length > 200) {
      return res.status(400).json({ success: false, message: 'A maximum of 200 ids is allowed.' });
    }
    const users = await prisma.user.findMany({
      where: {
        academyId: req.academyId,
        id: { in: ids.map(String) },
        ...(req.user.role === 'PARENT'
          ? { studentLinks: { some: { parentId: req.user.id } } }
          : req.user.role === 'STUDENT'
            ? { id: req.user.id }
            : {})
      }
    });
    return sendSuccess(
      res,
      users.map((user) => ({ ...directoryUser(user), accountStatus: user.accountStatus }))
    );
  } catch (err) {
    next(err);
  }
};

const searchUsers = async (req, res, next) => {
  try {
    const query = String(req.query.query || req.query.q || '').trim();
    const roleFilter = String(req.query.role || 'STUDENT').toUpperCase();
    if (!USER_ROLES.includes(roleFilter)) {
      return res.status(400).json({ success: false, message: 'Invalid role filter.' });
    }
    if (query.length < 2) {
      return sendSuccess(res, []);
    }
    const users = await prisma.user.findMany({
      where: {
        academyId: req.academyId,
        role: roleFilter,
        accountStatus: 'ACTIVE',
        OR: [
          { fullName: { contains: query, mode: 'insensitive' } },
          { email: { contains: query, mode: 'insensitive' } },
          { rollNumber: { contains: query, mode: 'insensitive' } },
          { studentCode: { contains: query, mode: 'insensitive' } }
        ]
      },
      take: 30,
      orderBy: { fullName: 'asc' }
    });
    return sendSuccess(res, users.map(directoryUser));
  } catch (err) {
    next(err);
  }
};

const getDirectory = async (req, res, next) => {
  try {
    const role = String(req.query.role || '').toUpperCase();
    const where = {
      academyId: req.academyId,
      accountStatus: 'ACTIVE',
      ...(role && USER_ROLES.includes(role) ? { role } : {})
    };
    // Privacy: a parent may only see staff and their OWN linked children.
    // Without this the directory leaked every student's contact details to
    // any parent account (same scoping as getUsersByRole).
    if (req.user.role === 'PARENT') {
      if (where.role === 'PARENT') {
        where.id = req.user.id;
      } else if (where.role === 'STUDENT') {
        where.studentLinks = { some: { parentId: req.user.id } };
      } else if (!where.role) {
        where.OR = [
          { role: { in: ['ADMIN', 'TEACHER'] } },
          { role: 'STUDENT', studentLinks: { some: { parentId: req.user.id } } },
          { id: req.user.id }
        ];
      }
    }
    const users = await prisma.user.findMany({
      where,
      orderBy: { fullName: 'asc' }
    });
    return sendSuccess(res, users.map(directoryUser));
  } catch (err) {
    next(err);
  }
};

const getProfileById = async (req, res, next) => {
  try {
    const { id } = req.params;
    if (req.user.role === 'STUDENT' && id !== req.user.id) {
      return res.status(403).json({ success: false, message: 'Forbidden.' });
    }
    const user = await prisma.user.findFirst({
      where: { id, academyId: req.academyId }
    });
    if (!user) throw notFound('User not found in academy.');
    if (req.user.role === 'PARENT') {
      const link = await prisma.parentStudent.findFirst({
        where: { parentId: req.user.id, studentId: id }
      });
      if (!link && id !== req.user.id) {
        return res.status(403).json({ success: false, message: 'Forbidden.' });
      }
    }
    return sendSuccess(res, safeUser(user));
  } catch (err) {
    next(err);
  }
};

// ---------------------------------------------------------------------------
// Parent → child link requests (admin-approved).
//
// A parent submits the child's identifying details; the backend tries to match
// exactly one STUDENT in the parent's academy, but the link is created ONLY
// after an academy admin approves. This prevents a parent from reading an
// unrelated student's data by self-linking, while still letting a parent start
// the process. All queries are scoped to req.academyId (no cross-academy).
// ---------------------------------------------------------------------------

const { conflict, badRequest } = require('../utils/apiError');

const LINK_REQUEST_STATUSES = ['PENDING', 'APPROVED', 'REJECTED'];

const publicLinkRequest = (reqRow) => ({
  id: reqRow.id,
  childName: reqRow.childName,
  childEmail: reqRow.childEmail,
  rollNumber: reqRow.rollNumber,
  status: reqRow.status,
  note: reqRow.note,
  createdAt: toIso(reqRow.createdAt),
  decidedAt: toIso(reqRow.decidedAt)
});

// Resolve at most one matching STUDENT in the academy from the submitted
// details. A match needs the name plus at least one of email / roll number.
const findStudentCandidate = async (academyId, { childName, childEmail, rollNumber }) => {
  const or = [];
  if (childEmail) or.push({ email: { equals: childEmail, mode: 'insensitive' } });
  if (rollNumber) or.push({ rollNumber: { equals: rollNumber, mode: 'insensitive' } });
  if (!or.length) return null;
  const candidates = await prisma.user.findMany({
    where: {
      academyId,
      role: 'STUDENT',
      fullName: { equals: childName, mode: 'insensitive' },
      OR: or
    },
    take: 2
  });
  // Exactly one unambiguous match; otherwise leave it for the admin to resolve.
  return candidates.length === 1 ? candidates[0] : null;
};

const createLinkRequest = async (req, res, next) => {
  try {
    const childName = String(req.body.childName || '').trim();
    const childEmail = req.body.childEmail ? String(req.body.childEmail).trim().toLowerCase() : null;
    const rollNumber = req.body.rollNumber ? String(req.body.rollNumber).trim() : null;
    if (!childName) throw badRequest('Child name is required.');
    if (!childEmail && !rollNumber) {
      throw badRequest('Provide the child\'s email or roll number.');
    }

    const parentId = req.user.id;
    const candidate = await findStudentCandidate(req.academyId, { childName, childEmail, rollNumber });

    // Already linked to this (resolved) child → nothing to request.
    if (candidate) {
      const existingLink = await prisma.parentStudent.findUnique({
        where: { parentId_studentId: { parentId, studentId: candidate.id } }
      });
      if (existingLink) throw conflict('This child is already linked to your account.');
    }

    // Prevent a duplicate PENDING request for the same child details.
    const duplicate = await prisma.parentLinkRequest.findFirst({
      where: {
        parentId,
        status: 'PENDING',
        childName: { equals: childName, mode: 'insensitive' },
        childEmail: childEmail || undefined,
        rollNumber: rollNumber || undefined
      }
    });
    if (duplicate) {
      throw conflict('You already have a pending request for this child.');
    }

    const created = await prisma.parentLinkRequest.create({
      data: {
        academyId: req.academyId,
        parentId,
        studentId: candidate ? candidate.id : null,
        childName,
        childEmail,
        rollNumber,
        status: 'PENDING'
      }
    });
    return sendSuccess(res, publicLinkRequest(created), {
      status: 201,
      message: 'Link request submitted. An academy admin will review it.'
    });
  } catch (err) {
    next(err);
  }
};

const getMyLinkRequests = async (req, res, next) => {
  try {
    const rows = await prisma.parentLinkRequest.findMany({
      where: { parentId: req.user.id },
      orderBy: { createdAt: 'desc' }
    });
    return sendSuccess(res, rows.map(publicLinkRequest));
  } catch (err) {
    next(err);
  }
};

const listLinkRequests = async (req, res, next) => {
  try {
    const status = req.query.status ? String(req.query.status).toUpperCase() : 'PENDING';
    if (!LINK_REQUEST_STATUSES.includes(status)) {
      throw badRequest('Invalid status filter.');
    }
    const rows = await prisma.parentLinkRequest.findMany({
      where: { academyId: req.academyId, status },
      orderBy: { createdAt: 'asc' },
      include: {
        parent: { select: { id: true, fullName: true, email: true, phoneNumber: true } },
        student: { select: { id: true, fullName: true, email: true, rollNumber: true, studentCode: true } }
      }
    });
    const data = rows.map((row) => ({
      ...publicLinkRequest(row),
      parent: row.parent,
      // The admin sees the auto-matched student (if any) to verify before approving.
      matchedStudent: row.student || null
    }));
    return sendSuccess(res, data);
  } catch (err) {
    next(err);
  }
};

const approveLinkRequest = async (req, res, next) => {
  try {
    const { id } = req.params;
    const request = await prisma.parentLinkRequest.findFirst({
      where: { id, academyId: req.academyId }
    });
    if (!request) throw notFound('Link request not found.');
    if (request.status !== 'PENDING') {
      throw conflict('This request has already been decided.');
    }

    // Admin may confirm/override which student to link (academy-scoped).
    const studentId = (req.body && req.body.studentId) || request.studentId;
    if (!studentId) {
      throw badRequest('No matching student. Specify the student to link.');
    }
    const student = await prisma.user.findFirst({
      where: { id: studentId, academyId: req.academyId, role: 'STUDENT' }
    });
    if (!student) throw notFound('Student not found in this academy.');

    const [, updated] = await prisma.$transaction([
      prisma.parentStudent.upsert({
        where: { parentId_studentId: { parentId: request.parentId, studentId } },
        create: { parentId: request.parentId, studentId },
        update: {}
      }),
      prisma.parentLinkRequest.update({
        where: { id: request.id },
        data: {
          status: 'APPROVED',
          studentId,
          decidedById: req.user.id,
          decidedAt: new Date()
        }
      })
    ]);
    return sendSuccess(res, publicLinkRequest(updated), {
      message: 'Request approved and child linked to the parent.'
    });
  } catch (err) {
    next(err);
  }
};

const rejectLinkRequest = async (req, res, next) => {
  try {
    const { id } = req.params;
    const note = req.body && req.body.note ? String(req.body.note).trim().slice(0, 500) : null;
    const request = await prisma.parentLinkRequest.findFirst({
      where: { id, academyId: req.academyId }
    });
    if (!request) throw notFound('Link request not found.');
    if (request.status !== 'PENDING') {
      throw conflict('This request has already been decided.');
    }
    const updated = await prisma.parentLinkRequest.update({
      where: { id: request.id },
      data: { status: 'REJECTED', note, decidedById: req.user.id, decidedAt: new Date() }
    });
    return sendSuccess(res, publicLinkRequest(updated), { message: 'Request rejected.' });
  } catch (err) {
    next(err);
  }
};

module.exports = {
  adminResetPassword,
  deactivateUser,
  reactivateUser,
  checkRollNumber,
  getPendingUsers,
  approveUser,
  rejectUser,
  getUsersByRole,
  linkChildToParent,
  removeLinkedChild,
  createUserByAdmin,
  updateUser,
  updateOwnProfile,
  getProfilesByIds,
  searchUsers,
  getDirectory,
  getProfileById,
  createLinkRequest,
  getMyLinkRequests,
  listLinkRequests,
  approveLinkRequest,
  rejectLinkRequest
};
