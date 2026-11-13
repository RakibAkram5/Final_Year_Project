const jwt = require('jsonwebtoken');
const prisma = require('../config/db');
const { ERROR_CODES } = require('../utils/apiError');
const { sendError } = require('../utils/response');

const authenticateToken = async (req, res, next) => {
  const authHeader = req.headers.authorization;
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return sendError(res, 401, ERROR_CODES.UNAUTHENTICATED, 'Access token required.');
  }

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    const user = await prisma.user.findUnique({
      where: { id: decoded.userId },
      include: { academy: true }
    });

    if (!user) {
      return sendError(res, 401, ERROR_CODES.UNAUTHENTICATED, 'Invalid session user.');
    }

    if (user.accountStatus !== 'ACTIVE') {
      // Authenticated but not allowed: a refresh cannot fix this, so keep 403
      // (the client signs the user out instead of retrying).
      return sendError(
        res,
        403,
        ERROR_CODES.ACCOUNT_INACTIVE,
        'Account is pending approval or disabled.'
      );
    }

    req.user = {
      id: user.id,
      email: user.email,
      role: user.role,
      academyId: user.academyId,
      fullName: user.fullName,
      assignedSections: user.assignedSections
    };

    req.academyId = user.academyId;
    next();
  } catch (err) {
    // 401 (not 403) so clients know a token refresh is the right recovery.
    if (err && err.name === 'TokenExpiredError') {
      return sendError(res, 401, ERROR_CODES.TOKEN_EXPIRED, 'Access token has expired.');
    }
    return sendError(res, 401, ERROR_CODES.UNAUTHENTICATED, 'Token expired or invalid.');
  }
};

module.exports = { authenticateToken };
