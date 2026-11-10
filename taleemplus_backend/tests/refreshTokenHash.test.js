const crypto = require('crypto');

// authController throws at require-time unless the signing secrets exist. In CI
// the workflow provides them; locally setupEnv loads .env. Fall back to
// test-only values so this pure-function test never depends on a DB or a real
// secret.
process.env.JWT_SECRET =
  process.env.JWT_SECRET || 'test-only-jwt-secret-value-0123456789';
process.env.REFRESH_TOKEN_SECRET =
  process.env.REFRESH_TOKEN_SECRET || 'test-only-refresh-secret-value-0123456789';

const { hashToken } = require('../src/controllers/authController');

describe('refresh-token at-rest hashing (hashToken)', () => {
  const sampleToken =
    'eyJhbGciOiJIUzI1NiJ9.eyJ1c2VySWQiOiJ1LTEifQ.signature-part-abc123';

  it('returns a 64-character lowercase hex SHA-256 digest', () => {
    const out = hashToken(sampleToken);
    expect(out).toMatch(/^[0-9a-f]{64}$/);
  });

  it('matches a standard SHA-256 of the token (the stored form)', () => {
    const expected = crypto
      .createHash('sha256')
      .update(sampleToken)
      .digest('hex');
    expect(hashToken(sampleToken)).toBe(expected);
  });

  it('is deterministic for the same token', () => {
    expect(hashToken(sampleToken)).toBe(hashToken(sampleToken));
  });

  it('produces different digests for different tokens', () => {
    expect(hashToken(sampleToken)).not.toBe(hashToken(sampleToken + 'x'));
  });

  it('never stores the raw token (digest differs from input)', () => {
    expect(hashToken(sampleToken)).not.toBe(sampleToken);
  });
});
