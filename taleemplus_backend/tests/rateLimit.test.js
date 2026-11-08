const { createRateLimiter } = require('../src/middleware/rateLimit');

const makeResponse = () => {
  const res = {
    headers: {},
    statusCode: 200,
    body: undefined,
    setHeader: jest.fn((name, value) => { res.headers[name] = value; }),
    status: jest.fn((code) => { res.statusCode = code; return res; }),
    json: jest.fn((body) => { res.body = body; return res; })
  };
  return res;
};

describe('createRateLimiter', () => {
  const originalDisabled = process.env.RATE_LIMIT_DISABLED;

  beforeEach(() => {
    process.env.RATE_LIMIT_DISABLED = 'false';
  });

  afterEach(() => {
    if (originalDisabled === undefined) {
      delete process.env.RATE_LIMIT_DISABLED;
    } else {
      process.env.RATE_LIMIT_DISABLED = originalDisabled;
    }
  });

  it('allows requests up to the limit and rejects the next one', () => {
    const limiter = createRateLimiter({
      max: 2,
      keyGenerator: () => 'fixed-key'
    });
    const req = { ip: '127.0.0.1', body: {} };

    const first = makeResponse();
    const firstNext = jest.fn();
    limiter(req, first, firstNext);
    const second = makeResponse();
    const secondNext = jest.fn();
    limiter(req, second, secondNext);
    const third = makeResponse();
    const thirdNext = jest.fn();
    limiter(req, third, thirdNext);

    expect(firstNext).toHaveBeenCalledTimes(1);
    expect(secondNext).toHaveBeenCalledTimes(1);
    expect(thirdNext).not.toHaveBeenCalled();
    expect(third.statusCode).toBe(429);
    expect(third.body.code).toBe('RATE_LIMITED');
    expect(third.headers['Retry-After']).toBeDefined();
  });

  it('keys attempts by email so one account cannot lock out another', () => {
    const limiter = createRateLimiter({ max: 1 });
    const build = (email) => ({ ip: '127.0.0.1', body: { email } });

    const first = makeResponse();
    limiter(build('one@test.taleemplus'), first, jest.fn());
    const second = makeResponse();
    limiter(build('one@test.taleemplus'), second, jest.fn());
    const other = makeResponse();
    const otherNext = jest.fn();
    limiter(build('two@test.taleemplus'), other, otherNext);

    expect(second.statusCode).toBe(429);
    expect(otherNext).toHaveBeenCalledTimes(1);
  });

  it('can be disabled for controlled test environments', () => {
    process.env.RATE_LIMIT_DISABLED = 'true';
    const limiter = createRateLimiter({ max: 1 });
    const req = { ip: '127.0.0.1', body: {} };
    const res = makeResponse();
    const next = jest.fn();

    limiter(req, res, next);
    limiter(req, res, next);

    expect(next).toHaveBeenCalledTimes(2);
  });
});
