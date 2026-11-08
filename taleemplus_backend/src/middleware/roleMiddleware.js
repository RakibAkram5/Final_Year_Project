const { ERROR_CODES } = require('../utils/apiError');
const { sendError } = require('../utils/response');

const authorizeRoles = (...roles) => {
  return (req, res, next) => {
    if (!req.user || !roles.includes(req.user.role)) {
      return sendError(
        res,
        403,
        ERROR_CODES.FORBIDDEN,
        `Forbidden: User role '${req.user?.role}' does not have permission.`
      );
    }
    next();
  };
};

module.exports = { authorizeRoles };
