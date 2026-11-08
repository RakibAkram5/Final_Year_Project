const ERROR_CODES = Object.freeze({
  VALIDATION_ERROR: 'VALIDATION_ERROR',
  UNAUTHENTICATED: 'UNAUTHENTICATED',
  FORBIDDEN: 'FORBIDDEN',
  NOT_FOUND: 'NOT_FOUND',
  CONFLICT: 'CONFLICT',
  RATE_LIMITED: 'RATE_LIMITED',
  INTERNAL_ERROR: 'INTERNAL_ERROR'
});

class ApiError extends Error {
  constructor(statusCode, code, message, details) {
    super(message);
    this.name = 'ApiError';
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
    this.expose = true;
  }
}

const badRequest = (message, details) =>
  new ApiError(400, ERROR_CODES.VALIDATION_ERROR, message, details);
const unauthorized = (message = 'Authentication required.') =>
  new ApiError(401, ERROR_CODES.UNAUTHENTICATED, message);
const forbidden = (message = 'You do not have permission to perform this action.') =>
  new ApiError(403, ERROR_CODES.FORBIDDEN, message);
const notFound = (message = 'The requested resource was not found.') =>
  new ApiError(404, ERROR_CODES.NOT_FOUND, message);
const conflict = (message, details) =>
  new ApiError(409, ERROR_CODES.CONFLICT, message, details);
const tooManyRequests = (message = 'Too many requests. Please try again later.') =>
  new ApiError(429, ERROR_CODES.RATE_LIMITED, message);

module.exports = {
  ERROR_CODES,
  ApiError,
  badRequest,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  tooManyRequests
};
