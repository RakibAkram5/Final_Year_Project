const { ERROR_CODES } = require('../utils/apiError');
const { sendError } = require('../utils/response');

const PRISMA_ERRORS = {
  P2002: [409, ERROR_CODES.CONFLICT, 'A record with these values already exists.'],
  P2003: [409, ERROR_CODES.CONFLICT, 'A related record does not exist.'],
  P2025: [404, ERROR_CODES.NOT_FOUND, 'The requested record was not found.']
};

const errorHandler = (err, req, res, next) => {
  if (res.headersSent) return next(err);

  if (err && err.name === 'ApiError') {
    return sendError(
      res,
      err.statusCode || 500,
      err.code || ERROR_CODES.INTERNAL_ERROR,
      err.message,
      err.details
    );
  }

  // Client errors raised by body parsers (oversized or malformed bodies) and
  // by controllers that set an explicit 4xx status.
  const clientStatus = err && (err.status || err.statusCode);
  if (clientStatus >= 400 && clientStatus < 500) {
    const message = err.type === 'entity.too.large'
      ? 'The request body is too large.'
      : err.type === 'entity.parse.failed'
        ? 'The request body is not valid JSON.'
        : err.expose === false ? 'Bad request.' : err.message;
    const code = clientStatus === 413
      ? 'PAYLOAD_TOO_LARGE'
      : ERROR_CODES.VALIDATION_ERROR || 'BAD_REQUEST';
    return sendError(res, clientStatus, code, message);
  }

  if (err && err.code && PRISMA_ERRORS[err.code]) {
    const [status, code, message] = PRISMA_ERRORS[err.code];
    return sendError(res, status, code, message);
  }

  // Log a sanitized summary only: Prisma/driver errors embed the failing
  // query's arguments (emails, password hashes), which must not be logged.
  const lastLine = String((err && err.message) || '')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .pop();
  console.error('[Error Handler]', {
    method: req.method,
    path: req.path,
    name: err && err.name,
    code: err && err.code,
    message: lastLine ? lastLine.slice(0, 300) : undefined
  });
  const statusCode = res.statusCode && res.statusCode !== 200 ? res.statusCode : 500;
  const message =
    process.env.NODE_ENV === 'production'
      ? 'Internal Server Error'
      : err.message || 'Internal Server Error';

  return sendError(res, statusCode, ERROR_CODES.INTERNAL_ERROR, message);
};

module.exports = { errorHandler };
