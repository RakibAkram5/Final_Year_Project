/**
 * Runtime configuration validation. Runs once when the app module loads
 * (server.js and the Vercel functions), so a misconfigured deployment fails
 * fast with a clear message instead of serving 500s.
 *
 * Never prints secret values.
 */
const EXAMPLE_SECRETS = new Set([
  'taleemplus_super_secret_jwt_key_2026',
  'taleemplus_refresh_token_secret_2026',
  'change-me',
  'changeme',
  'secret'
]);

const validateEnv = (env = process.env) => {
  const errors = [];
  const warnings = [];
  const isProduction = env.NODE_ENV === 'production';

  for (const name of ['DATABASE_URL', 'JWT_SECRET', 'REFRESH_TOKEN_SECRET']) {
    if (!env[name] || !String(env[name]).trim()) errors.push(`${name} is required.`);
  }

  if (env.DATABASE_URL && !/^postgres(ql)?:\/\//.test(env.DATABASE_URL)) {
    errors.push('DATABASE_URL must be a postgresql:// connection string.');
  }

  if (env.JWT_SECRET && env.JWT_SECRET === env.REFRESH_TOKEN_SECRET) {
    errors.push('JWT_SECRET and REFRESH_TOKEN_SECRET must be different.');
  }

  for (const name of ['JWT_SECRET', 'REFRESH_TOKEN_SECRET']) {
    const value = env[name];
    if (!value) continue;
    const weak = value.length < 32 || EXAMPLE_SECRETS.has(value);
    if (weak && isProduction) {
      errors.push(`${name} must be a unique random value of at least 32 characters in production.`);
    } else if (weak) {
      warnings.push(`${name} is weak; use a random value of at least 32 characters outside development.`);
    }
  }

  if (isProduction && !String(env.CORS_ORIGINS || '').trim()) {
    warnings.push('CORS_ORIGINS is empty: only same-origin browsers and native apps can call the API.');
  }

  return { errors, warnings };
};

const assertValidEnv = (env = process.env, log = console) => {
  const { errors, warnings } = validateEnv(env);
  for (const warning of warnings) log.warn(`[config] ${warning}`);
  if (errors.length) {
    throw new Error(`Invalid configuration:\n - ${errors.join('\n - ')}`);
  }
};

module.exports = { validateEnv, assertValidEnv };
