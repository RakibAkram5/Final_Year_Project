const path = require('path');

require('dotenv').config({ path: path.resolve(__dirname, '..', '.env') });

if (process.env.TEST_DATABASE_URL) {
  process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
}

// Keep repeated test runs deterministic; rate-limit behaviour is covered by
// dedicated unit tests that opt back in.
if (process.env.RATE_LIMIT_DISABLED === undefined) {
  process.env.RATE_LIMIT_DISABLED = 'true';
}
