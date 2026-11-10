const BASE_URL = process.env.ML_SERVICE_URL;
const TOKEN = process.env.ML_INTERNAL_TOKEN;

// Render's free web service sleeps after ~15 min idle and cold-starts in
// ~30-60 s, so the default timeout is generous and transient gateway errors
// (502/503/504) and timeouts are retried a small number of times.
// NOTE: keep ML_TIMEOUT_MS within the Vercel function's maxDuration, otherwise
// the platform will cancel the request before this timeout fires.
const RETRYABLE = new Set([502, 503, 504]);
const timeoutMs = () => Number(process.env.ML_TIMEOUT_MS || 60000);
const maxRetries = () => Math.max(0, Number(process.env.ML_MAX_RETRIES || 1));
const backoffMs = () => Number(process.env.ML_RETRY_BACKOFF_MS || 2000);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function fetchWithTimeout(url, options) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs());
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function request(path, { method = 'GET', academyId, body } = {}) {
  if (!BASE_URL || !TOKEN) {
    const error = new Error('ML service is not configured.');
    error.status = 503;
    throw error;
  }
  const url = new URL(path, BASE_URL);
  if (method === 'GET') url.searchParams.set('academy_id', academyId);
  const options = {
    method,
    headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify({ ...body, academy_id: academyId }) : undefined,
  };

  const attempts = maxRetries() + 1;
  for (let i = 1; i <= attempts; i += 1) {
    let response;
    try {
      response = await fetchWithTimeout(url, options);
    } catch (err) {
      // Abort (timeout) or network failure: retry if any attempts remain.
      if (i < attempts) { await sleep(backoffMs()); continue; }
      break;
    }
    const data = await response.json().catch(() => ({}));
    if (response.ok) return data;
    // A cold-starting instance often answers with a transient gateway error.
    if (RETRYABLE.has(response.status) && i < attempts) { await sleep(backoffMs()); continue; }
    const error = new Error(data.detail?.message || data.detail || 'ML service request failed.');
    error.status = response.status;
    throw error;   // meaningful status, no stack trace leaked to the client
  }
  const error = new Error('ML service did not respond in time (it may be waking up). Please retry shortly.');
  error.status = 504;
  throw error;
}

module.exports = { request };
