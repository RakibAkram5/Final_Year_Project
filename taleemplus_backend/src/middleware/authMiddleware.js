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
      return sendError(
        res,
        403,
        ERROR_CODES.FORBIDDEN,
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
    return sendError(res, 403, ERROR_CODES.UNAUTHENTICATED, 'Token expired or invalid.');
  }
};

module.exports = { authenticateToken };
