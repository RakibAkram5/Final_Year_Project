const { validateEnv } = require('../src/config/env');

const strong = (c) => c.repeat(40);
const base = {
  DATABASE_URL: 'postgresql://u:p@localhost:5432/db',
  JWT_SECRET: strong('a'),
  REFRESH_TOKEN_SECRET: strong('b')
};

describe('runtime configuration validation', () => {
  it('accepts a complete configuration', () => {
    expect(validateEnv({ ...base, NODE_ENV: 'production', CORS_ORIGINS: 'https://x.test' }))
      .toEqual({ errors: [], warnings: [] });
  });

  it('requires database and token secrets', () => {
    const { errors } = validateEnv({});
    expect(errors).toEqual(expect.arrayContaining([
      'DATABASE_URL is required.',
      'JWT_SECRET is required.',
      'REFRESH_TOKEN_SECRET is required.'
    ]));
  });

  it('rejects weak or example secrets in production but only warns in development', () => {
    const weak = { ...base, JWT_SECRET: 'taleemplus_super_secret_jwt_key_2026' };
    expect(validateEnv({ ...weak, NODE_ENV: 'production' }).errors.join())
      .toMatch(/JWT_SECRET must be a unique random value/);
    const dev = validateEnv({ ...weak, NODE_ENV: 'development' });
    expect(dev.errors).toEqual([]);
    expect(dev.warnings.join()).toMatch(/JWT_SECRET is weak/);
  });

  it('rejects identical access and refresh secrets and non-postgres URLs', () => {
    const { errors } = validateEnv({
      DATABASE_URL: 'mysql://x', JWT_SECRET: strong('c'), REFRESH_TOKEN_SECRET: strong('c')
    });
    expect(errors).toEqual(expect.arrayContaining([
      'DATABASE_URL must be a postgresql:// connection string.',
      'JWT_SECRET and REFRESH_TOKEN_SECRET must be different.'
    ]));
  });

  it('never includes secret values in messages', () => {
    const secret = 'super-secret-value';
    const { errors, warnings } = validateEnv({
      ...base, NODE_ENV: 'production', JWT_SECRET: secret
    });
    expect([...errors, ...warnings].join(' ')).not.toContain(secret);
  });
});
