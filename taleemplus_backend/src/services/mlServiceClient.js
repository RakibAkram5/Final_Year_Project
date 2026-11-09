const BASE_URL = process.env.ML_SERVICE_URL;
const TOKEN = process.env.ML_INTERNAL_TOKEN;

async function request(path, { method = 'GET', academyId, body } = {}) {
  if (!BASE_URL || !TOKEN) {
    const error = new Error('ML service is not configured.');
    error.status = 503;
    throw error;
  }
  const url = new URL(path, BASE_URL);
  if (method === 'GET') url.searchParams.set('academy_id', academyId);
  const controller = new AbortController();
  // A sleeping Hugging Face Space can take ~20 s to wake; stay under
  // Vercel's 30 s function limit.
  const timer = setTimeout(() => controller.abort(), Number(process.env.ML_TIMEOUT_MS || 25000));
  try {
    const response = await fetch(url, {
      method,
      headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify({ ...body, academy_id: academyId }) : undefined,
      signal: controller.signal,
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      const error = new Error(data.detail?.message || data.detail || 'ML service request failed.');
      error.status = response.status;
      throw error;
    }
    return data;
  } finally {
    clearTimeout(timer);
  }
}

module.exports = { request };
