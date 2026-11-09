const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const prisma = require('../config/db');
const { validatePassword } = require('../utils/passwordPolicy');
const crypto = require('crypto');

const makeStudentCode = () => crypto.randomBytes(8).toString('hex');

const MAX_FAILED_LOGINS = Number(process.env.MAX_FAILED_LOGINS || 5);
const LOCKOUT_MINUTES = Number(process.env.LOCKOUT_MINUTES || 15);

const normalizeEmail = (value) =>
  typeof value === 'string' ? value.trim().toLowerCase() : '';

// New accounts are stored lower-case; legacy rows may be mixed case, so
// lookups are case-insensitive.
const findUserByEmail = (email, args = {}) =>
  prisma.user.findFirst({
    where: { email: { equals: normalizeEmail(email), mode: 'insensitive' } },
    ...args
  });

// Academy codes are typed by hand, so they match case-insensitively.
const findAcademyByCode = (code, select) =>
  prisma.academy.findFirst({
    where: { code: { equals: String(code || '').trim(), mode: 'insensitive' } },
    ...(select ? { select } : {})
  });

const STATUS_MESSAGES = {
  PENDING: 'Your account is pending approval by the academy admin.',
  REJECTED: 'Your registration was rejected. Contact the academy admin.',
  INACTIVE: 'Your account has been deactivated. Contact the academy admin.'
};

const hashSecurityAnswer = (answer) => {
  if (typeof answer !== 'string' || !answer.trim()) return null;
  return bcrypt.hash(answer.trim().toLowerCase(), 10);
};

const formatUser = (user, academy) => ({
  id: user.id,
  email: user.email,
  fullName: user.fullName,
  phoneNumber: user.phoneNumber,
  role: user.role,
  accountStatus: user.accountStatus,
  academyId: user.academyId,
  academyCode: academy?.code,
  academyName: academy?.name,
  academyAddress: academy?.address,
  academyPhone: academy?.phone,
  academyLogo: academy?.logo,
  // Phase 6: saved academy location (null until an admin sets it).
  academyLatitude: academy?.latitude == null ? null : Number(academy.latitude),
  academyLongitude: academy?.longitude == null ? null : Number(academy.longitude),
  academyLocationLabel: academy?.locationLabel ?? null,
  assignedSections: user.assignedSections,
  studentCode: user.studentCode,
  rollNumber: user.rollNumber,
  subject: user.subject,
  extraInfo: user.extraInfo,
  joiningDate: user.joiningDate,
  createdAt: user.createdAt,
  linkedChildren: (user.parentLinks || []).map((link) => ({
    id: link.student.id,
    fullName: link.student.fullName,
    email: link.student.email,
  })),
});

const verifyPassword = async (req, res, next) => {
  try {
    const user = await prisma.user.findFirst({
      where: { id: req.user.id, academyId: req.academyId },
      select: { passwordHash: true },
    });
    const valid = Boolean(user && typeof req.body.password === 'string' &&
      await bcrypt.compare(req.body.password, user.passwordHash));
    return res.json({ success: true, data: { valid } });
  } catch (err) { next(err); }
};

const changePassword = async (req, res, next) => {
  try {
    if (typeof req.body.currentPassword !== 'string' || !req.body.currentPassword) {
      return res.status(400).json({ success: false, message: 'Current password is required.' });
    }
    const current = await prisma.user.findFirst({
      where: { id: req.user.id, academyId: req.academyId },
      select: { passwordHash: true },
    });
    if (!current || !(await bcrypt.compare(req.body.currentPassword, current.passwordHash))) {
      return res.status(403).json({ success: false, message: 'Current password is incorrect.' });
    }
    const passwordError = validatePassword(req.body.newPassword);
    if (passwordError) return res.status(400).json({ success: false, message: passwordError });
    if (req.body.currentPassword === req.body.newPassword) {
      return res.status(400).json({ success: false, message: 'Choose a password different from the current one.' });
    }
    const passwordHash = await bcrypt.hash(req.body.newPassword, 12);
    await prisma.user.update({
      where: { id: req.user.id },
      data: { passwordHash },
    });
    res.json({ success: true, message: 'Password updated successfully.' });
  } catch (err) { next(err); }
};

const updateAcademyProfile = async (req, res, next) => {
  try {
    const fields = [
      ['name', 'name', 120], ['address', 'address', 240],
      ['phone', 'phone', 40], ['logo', 'logo', 1000],
    ];
    const data = {};
    for (const [input, column, maxLength] of fields) {
      if (req.body[input] === undefined) continue;
      const value = req.body[input];
      if (value !== null && (typeof value !== 'string' || value.length > maxLength)) {
        return res.status(400).json({ success: false, message: `Invalid academy ${input}.` });
      }
      data[column] = typeof value === 'string' ? value.trim() || null : null;
    }
    // Location: latitude and longitude are set (or cleared) together.
    const { latitude, longitude, locationLabel } = req.body;
    if (latitude !== undefined || longitude !== undefined) {
      if (latitude === null && longitude === null) {
        data.latitude = null;
        data.longitude = null;
        data.locationLabel = null;
      } else {
        const lat = Number(latitude);
        const lng = Number(longitude);
        if (!Number.isFinite(lat) || !Number.isFinite(lng) ||
            lat < -90 || lat > 90 || lng < -180 || lng > 180) {
          return res.status(400).json({ success: false, message: 'Latitude must be between -90 and 90 and longitude between -180 and 180.' });
        }
        data.latitude = Math.round(lat * 1e6) / 1e6;
        data.longitude = Math.round(lng * 1e6) / 1e6;
      }
    }
    if (locationLabel !== undefined && data.locationLabel === undefined) {
      if (locationLabel !== null && (typeof locationLabel !== 'string' || locationLabel.length > 300)) {
        return res.status(400).json({ success: false, message: 'Invalid location label.' });
      }
      data.locationLabel = typeof locationLabel === 'string' ? locationLabel.trim() || null : null;
    }
    if (!Object.keys(data).length) return res.status(400).json({ success: false, message: 'No academy profile fields provided.' });
    const academy = await prisma.academy.update({ where: { id: req.academyId }, data });
    res.json({ success: true, data: {
      academyName: academy.name, academyAddress: academy.address,
      academyPhone: academy.phone, academyLogo: academy.logo,
      academyLatitude: academy.latitude == null ? null : Number(academy.latitude),
      academyLongitude: academy.longitude == null ? null : Number(academy.longitude),
      academyLocationLabel: academy.locationLabel,
    } });
  } catch (err) { next(err); }
};

const JWT_SECRET = process.env.JWT_SECRET;
const REFRESH_SECRET = process.env.REFRESH_TOKEN_SECRET;

if (!JWT_SECRET || !REFRESH_SECRET) {
  throw new Error('JWT_SECRET and REFRESH_TOKEN_SECRET must be configured.');
}

// Every token carries a random jti. Without it, two tokens for the same user
// minted in the same second are byte-identical: refresh "rotation" would
// re-issue the old token (so it stayed valid), and two same-second logins
// would collide on the unique refresh_tokens.token column (HTTP 500).
const generateTokens = (userId, academyId, role) => {
  const accessToken = jwt.sign({ userId, academyId, role }, JWT_SECRET, {
    expiresIn: process.env.JWT_EXPIRES_IN || '15m',
    jwtid: crypto.randomUUID()
  });
  const refreshToken = jwt.sign({ userId, academyId, role }, REFRESH_SECRET, {
    expiresIn: process.env.REFRESH_TOKEN_EXPIRES_IN || '7d',
    jwtid: crypto.randomUUID()
  });
  return { accessToken, refreshToken };
};

const registerAdmin = async (req, res, next) => {
  try {
    const { email, password, fullName, academyName, academyAddress, academyPhone } = req.body;

    if (!email || !password || !fullName || !academyName) {
      return res.status(400).json({ success: false, message: 'Missing required registration fields.' });
    }
    const passwordError = validatePassword(password);
    if (passwordError) return res.status(400).json({ success: false, message: passwordError });

    const existingUser = await findUserByEmail(email);
    if (existingUser) {
      return res.status(400).json({ success: false, message: 'Email address already registered.' });
    }

    const academyCode = 'TP-' + Math.random().toString(36).substring(2, 7).toUpperCase();
    const passwordHash = await bcrypt.hash(password, 10);

    const result = await prisma.$transaction(async (tx) => {
      const academy = await tx.academy.create({
        data: {
          code: academyCode,
          name: academyName,
          address: academyAddress || null,
          phone: academyPhone || null
        }
      });

      const user = await tx.user.create({
        data: {
          email: normalizeEmail(email),
          passwordHash,
          fullName,
          role: 'ADMIN',
          accountStatus: 'ACTIVE',
          academyId: academy.id
        }
      });

      return { academy, user };
    });

    const tokens = generateTokens(result.user.id, result.academy.id, result.user.role);
    await prisma.refreshToken.create({
      data: {
        userId: result.user.id,
        token: tokens.refreshToken,
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
      }
    });

    res.status(201).json({
      success: true,
      data: {
        user: {
          id: result.user.id,
          email: result.user.email,
          fullName: result.user.fullName,
          role: result.user.role,
          accountStatus: result.user.accountStatus,
          academyId: result.user.academyId,
          academyCode: result.academy.code,
          academyName: result.academy.name,
          academyAddress: result.academy.address,
          academyPhone: result.academy.phone,
          academyLogo: result.academy.logo
        },
        tokens
      }
    });
  } catch (err) {
    next(err);
  }
};

const registerUser = async (req, res, next) => {
  try {
    const {
      email,
      password,
      fullName,
      role,
      academyCode,
      phoneNumber,
      securityQuestion,
      securityAnswer
    } = req.body;

    if (!email || !password || !fullName || !role || !academyCode) {
      return res.status(400).json({ success: false, message: 'Missing required registration fields.' });
    }
    const passwordError = validatePassword(password);
    if (passwordError) return res.status(400).json({ success: false, message: passwordError });
    if ((securityQuestion && !securityAnswer) || (!securityQuestion && securityAnswer)) {
      return res.status(400).json({
        success: false,
        message: 'A security question and answer must be provided together.'
      });
    }

    const academy = await findAcademyByCode(academyCode);
    if (!academy) {
      return res.status(404).json({ success: false, message: 'Invalid academy code. Academy not found.' });
    }

    const existingUser = await findUserByEmail(email);
    if (existingUser) {
      return res.status(400).json({ success: false, message: 'Email address already registered.' });
    }

    const userRole = role.toUpperCase();
    if (userRole === 'ADMIN') {
      return res.status(400).json({
        success: false,
        message: 'Admins must register a new academy instead of joining one.'
      });
    }
    const passwordHash = await bcrypt.hash(password, 10);

    const user = await prisma.user.create({
      data: {
        email: normalizeEmail(email),
        passwordHash,
        fullName,
        phoneNumber: phoneNumber || null,
        role: userRole,
        accountStatus: 'PENDING',
        studentCode: userRole === 'STUDENT' ? makeStudentCode() : null,
        academyId: academy.id,
        securityQuestion: securityQuestion || null,
        securityAnswerHash: securityAnswer
          ? await hashSecurityAnswer(securityAnswer)
          : null
      }
    });

    res.status(201).json({
      success: true,
      message: 'Account registered successfully. Pending Admin approval.',
      data: {
        user: {
          id: user.id,
          email: user.email,
          fullName: user.fullName,
          role: user.role,
          accountStatus: user.accountStatus,
          academyId: user.academyId,
          academyName: academy.name,
          academyAddress: academy.address,
          academyPhone: academy.phone,
          academyLogo: academy.logo,
          studentCode: user.studentCode
        }
      }
    });
  } catch (err) {
    next(err);
  }
};

const login = async (req, res, next) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ success: false, message: 'Email and password required.' });
    }

    const user = await findUserByEmail(email, {
      include: {
        academy: true,
        parentLinks: { include: { student: true } }
      }
    });

    if (!user) {
      return res.status(401).json({ success: false, message: 'Invalid credentials. Check email and password.' });
    }

    if (user.lockedUntil && user.lockedUntil > new Date()) {
      const minutes = Math.ceil((user.lockedUntil.getTime() - Date.now()) / 60000);
      return res.status(423).json({
        success: false,
        code: 'ACCOUNT_LOCKED',
        message: `Too many failed sign-in attempts. Try again in ${minutes} minute(s).`
      });
    }

    const isMatch = await bcrypt.compare(password, user.passwordHash);
    if (!isMatch) {
      const attempts = user.failedLoginAttempts + 1;
      const lock = attempts >= MAX_FAILED_LOGINS;
      await prisma.user.update({
        where: { id: user.id },
        data: {
          failedLoginAttempts: lock ? 0 : attempts,
          lockedUntil: lock ? new Date(Date.now() + LOCKOUT_MINUTES * 60000) : null
        }
      });
      if (lock) {
        return res.status(423).json({
          success: false,
          code: 'ACCOUNT_LOCKED',
          message: `Too many failed sign-in attempts. Try again in ${LOCKOUT_MINUTES} minute(s).`
        });
      }
      return res.status(401).json({ success: false, message: 'Invalid credentials. Check email and password.' });
    }

    if (user.failedLoginAttempts || user.lockedUntil) {
      await prisma.user.update({
        where: { id: user.id },
        data: { failedLoginAttempts: 0, lockedUntil: null }
      });
    }

    if (user.accountStatus !== 'ACTIVE') {
      return res.status(403).json({
        success: false,
        code: `ACCOUNT_${user.accountStatus}`,
        message: STATUS_MESSAGES[user.accountStatus] || 'Your account is not active.'
      });
    }

    const tokens = generateTokens(user.id, user.academyId, user.role);

    await prisma.refreshToken.create({
      data: {
        userId: user.id,
        token: tokens.refreshToken,
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
      }
    });

    res.json({
      success: true,
      data: {
        user: formatUser(user, user.academy),
        tokens
      }
    });
  } catch (err) {
    next(err);
  }
};

const refreshToken = async (req, res, next) => {
  try {
    const { refreshToken: token } = req.body;
    if (!token) {
      return res.status(400).json({ success: false, message: 'Refresh token required.' });
    }

    const savedToken = await prisma.refreshToken.findUnique({
      where: { token },
      include: { user: true }
    });

    if (
      !savedToken ||
      savedToken.revoked ||
      savedToken.expiresAt < new Date() ||
      !savedToken.user ||
      savedToken.user.accountStatus !== 'ACTIVE'
    ) {
      return res.status(403).json({ success: false, message: 'Invalid or expired refresh token.' });
    }

    jwt.verify(token, REFRESH_SECRET);
    // Re-derive claims from the database so role/academy changes apply on
    // the next refresh instead of living on in the old token.
    const { user } = savedToken;
    const newTokens = generateTokens(user.id, user.academyId, user.role);

    await prisma.refreshToken.update({
      where: { id: savedToken.id },
      data: { token: newTokens.refreshToken, expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000) }
    });

    res.json({ success: true, data: newTokens });
  } catch (err) {
    return res.status(403).json({ success: false, message: 'Invalid refresh token.' });
  }
};

const logout = async (req, res, next) => {
  try {
    const { refreshToken: token } = req.body;
    if (token) {
      await prisma.refreshToken.updateMany({
        where: { token },
        data: { revoked: true }
      });
    }
    res.json({ success: true, message: 'Logged out successfully.' });
  } catch (err) {
    next(err);
  }
};

const getMe = async (req, res, next) => {
  try {
    const user = await prisma.user.findFirst({
      where: { id: req.user.id, academyId: req.academyId },
      include: {
        academy: true,
        parentLinks: { include: { student: true } },
        studentLinks: { include: { parent: true } }
      }
    });

    if (!user) {
      return res.status(404).json({ success: false, message: 'User profile not found.' });
    }

    res.json({
      success: true,
      data: {
        ...formatUser(user, user.academy),
        linkedParents: user.studentLinks.map((link) => ({
          id: link.parent.id,
          fullName: link.parent.fullName,
          email: link.parent.email
        }))
      }
    });
  } catch (err) {
    next(err);
  }
};

const getSecurityQuestion = async (req, res, next) => {
  try {
    const email = typeof req.query.email === 'string' ? req.query.email.trim() : '';
    if (!email) {
      return res.status(400).json({ success: false, message: 'Email is required.' });
    }
    const user = await findUserByEmail(email, { select: { securityQuestion: true } });
    if (!user || !user.securityQuestion) {
      return res.status(404).json({
        success: false,
        message: 'No security question is configured for this account.'
      });
    }
    return res.json({ success: true, data: { question: user.securityQuestion } });
  } catch (err) {
    return next(err);
  }
};

const resetPassword = async (req, res, next) => {
  try {
    const { email, securityAnswer, newPassword } = req.body;
    if (!email || !securityAnswer || !newPassword) {
      return res.status(400).json({
        success: false,
        message: 'Email, security answer, and new password are required.'
      });
    }
    const passwordError = validatePassword(newPassword);
    if (passwordError) {
      return res.status(400).json({ success: false, message: passwordError });
    }
    const user = await findUserByEmail(email);
    if (!user || !user.securityAnswerHash) {
      return res.status(404).json({
        success: false,
        message: 'Password recovery is not configured for this account.'
      });
    }
    const valid = await bcrypt.compare(
      String(securityAnswer).trim().toLowerCase(),
      user.securityAnswerHash
    );
    if (!valid) {
      return res.status(403).json({ success: false, message: 'The security answer is incorrect.' });
    }
    const passwordHash = await bcrypt.hash(newPassword, 12);
    await prisma.$transaction([
      prisma.user.update({
        where: { id: user.id },
        data: { passwordHash, failedLoginAttempts: 0, lockedUntil: null }
      }),
      prisma.refreshToken.updateMany({
        where: { userId: user.id, revoked: false },
        data: { revoked: true }
      })
    ]);
    return res.json({
      success: true,
      message: 'Password reset successfully. Sign in with your new password.'
    });
  } catch (err) {
    return next(err);
  }
};

const lookupAcademy = async (req, res, next) => {
  try {
    const code = String(req.query.code || '').trim();
    if (!code || code.length > 50) {
      return res.status(400).json({ success: false, message: 'Academy code is required.' });
    }
    const academy = await findAcademyByCode(code, { id: true, name: true, code: true });
    if (!academy) {
      return res.status(404).json({ success: false, message: 'Invalid academy code. Academy not found.' });
    }
    return res.json({ success: true, data: academy });
  } catch (err) {
    return next(err);
  }
};

const setSecurityQuestion = async (req, res, next) => {
  try {
    const question = typeof req.body.question === 'string' ? req.body.question.trim() : '';
    const answer = typeof req.body.answer === 'string' ? req.body.answer.trim() : '';
    if (!question || !answer || question.length > 200 || answer.length > 200) {
      return res.status(400).json({
        success: false,
        message: 'A security question and answer (max 200 characters each) are required.'
      });
    }
    await prisma.user.update({
      where: { id: req.user.id },
      data: {
        securityQuestion: question,
        securityAnswerHash: await hashSecurityAnswer(answer)
      }
    });
    return res.json({ success: true, message: 'Security question saved.' });
  } catch (err) {
    return next(err);
  }
};

module.exports = {
  lookupAcademy,
  setSecurityQuestion,
  registerAdmin,
  registerUser,
  login,
  refreshToken,
  logout,
  getMe,
  verifyPassword,
  changePassword,
  updateAcademyProfile,
  getSecurityQuestion,
  resetPassword
};
