const { ERROR_CODES } = require('../utils/apiError');
const { sendError } = require('../utils/response');

const normalizeEmail = (value) =>
  typeof value === 'string' ? value.trim().toLowerCase() : '';

const defaultKeyGenerator = (req) =>
  `${req.ip || req.socket?.remoteAddress || 'unknown'}|${normalizeEmail(
    req.body?.email
  )}`;

const createRateLimiter = ({
  windowMs = 15 * 60 * 1000,
  max = 10,
  keyGenerator = defaultKeyGenerator,
  message = 'Too many attempts. Please try again later.'
} = {}) => {
  const hits = new Map();

  const prune = (now) => {
    for (const [key, entry] of hits) {
      if (entry.resetAt <= now) hits.delete(key);
    }
  };

  return (req, res, next) => {
    if (process.env.RATE_LIMIT_DISABLED === 'true') return next();

    const now = Date.now();
    if (hits.size > 1000) prune(now);

    const key = keyGenerator(req);
    let entry = hits.get(key);
    if (!entry || entry.resetAt <= now) {
      entry = { count: 0, resetAt: now + windowMs };
      hits.set(key, entry);
    }

    entry.count += 1;
    const remaining = Math.max(0, max - entry.count);
    res.setHeader('RateLimit-Limit', String(max));
    res.setHeader('RateLimit-Remaining', String(remaining));
    res.setHeader('RateLimit-Reset', String(Math.ceil(entry.resetAt / 1000)));

    if (entry.count > max) {
      const retryAfter = Math.max(1, Math.ceil((entry.resetAt - now) / 1000));
      res.setHeader('Retry-After', String(retryAfter));
      return sendError(
        res,
        429,
        ERROR_CODES.RATE_LIMITED,
        message,
        { retryAfterSeconds: retryAfter }
      );
    }

    return next();
  };
};

const authRateLimiter = createRateLimiter({ max: 10 });
const refreshRateLimiter = createRateLimiter({ max: 30 });

module.exports = { createRateLimiter, authRateLimiter, refreshRateLimiter };
