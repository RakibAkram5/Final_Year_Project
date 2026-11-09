/**
 * Optional LLM-backed question generator for the exam-paper feature.
 *
 * This is the "optional AI" half of the hybrid generator: the Flutter app
 * always has a fully offline curriculum/source generator, and additionally
 * calls this service when the deployment has an AI key configured. When no key
 * is set, `isConfigured()` is false and the controller returns a 501 so the
 * client silently falls back to offline generation.
 *
 * Provider-agnostic: it speaks the OpenAI-compatible Chat Completions API, so
 * it works with the Vercel AI Gateway (default) or any compatible endpoint.
 * Everything is env-driven:
 *   AI_API_KEY        - required to enable the feature (no key => disabled)
 *   AI_BASE_URL       - default https://ai-gateway.vercel.sh/v1
 *   AI_MODEL          - default anthropic/claude-sonnet-5-5
 *   AI_TIMEOUT_MS     - default 45000
 */

const apiKey = () => process.env.AI_API_KEY || process.env.AI_GATEWAY_API_KEY || '';
const baseUrl = () =>
  (process.env.AI_BASE_URL || 'https://ai-gateway.vercel.sh/v1').replace(/\/$/, '');
const model = () => process.env.AI_MODEL || 'anthropic/claude-sonnet-5-5';
const timeoutMs = () => Number(process.env.AI_TIMEOUT_MS || 45000);

const isConfigured = () => Boolean(apiKey().trim());

const VALID_TYPES = new Set(['mcq', 'short', 'long']);

// Keeps only well-formed items so a malformed model response can never inject
// broken questions into a paper. Invalid entries are dropped, not guessed.
const sanitizeItems = (raw) => {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    const type = String(item.type || '').toLowerCase();
    const text = String(item.text || '').trim();
    if (!VALID_TYPES.has(type) || !text) continue;

    const clean = {
      type,
      chapter: String(item.chapter || '').trim(),
      text,
      answer: String(item.answer || '').trim(),
      keywords: Array.isArray(item.keywords)
        ? item.keywords.map((k) => String(k)).slice(0, 8)
        : [],
      difficulty: ['Easy', 'Medium', 'Hard'].includes(item.difficulty)
        ? item.difficulty
        : 'Medium'
    };

    if (type === 'mcq') {
      const options = Array.isArray(item.options)
        ? item.options.map((o) => String(o)).filter((o) => o.trim())
        : [];
      if (options.length < 4) continue; // an MCQ must have four options
      clean.options = options.slice(0, 4);
      const idx = Number(item.correctIndex);
      clean.correctIndex = Number.isInteger(idx) && idx >= 0 && idx < 4 ? idx : 0;
    }
    out.push(clean);
  }
  return out;
};

const buildPrompt = (config) => {
  const {
    subject,
    classLabel,
    chapters = [],
    difficulty = 'Medium',
    mcqCount = 10,
    shortCount = 8,
    longCount = 3
  } = config;

  const chapterLine = chapters.length
    ? `Chapters/topics to cover: ${chapters.join(', ')}.`
    : 'Cover the standard syllabus for this class and subject.';

  return [
    {
      role: 'system',
      content:
        'You are an expert Pakistani school examination paper setter. You ' +
        'produce accurate, curriculum-relevant questions and never fabricate ' +
        'facts. You reply with STRICT JSON only, no commentary.'
    },
    {
      role: 'user',
      content:
        `Create examination questions for:\n` +
        `Subject: ${subject}\nClass: ${classLabel}\n${chapterLine}\n` +
        `Difficulty: ${difficulty}.\n\n` +
        `Produce approximately ${mcqCount} MCQs, ${shortCount} short ` +
        `questions and ${longCount} long questions.\n\n` +
        `Return a JSON object of the exact shape:\n` +
        `{"items":[{"type":"mcq|short|long","chapter":"...","text":"...",` +
        `"options":["A","B","C","D"],"correctIndex":0,"answer":"model answer ` +
        `or marking guideline","keywords":["..."],"difficulty":"Easy|Medium|Hard"}]}\n` +
        `Rules: every mcq has exactly 4 options and a correctIndex 0-3; short ` +
        `and long items omit options/correctIndex but include a concise model ` +
        `answer. Use Pakistani educational terminology. Do not repeat questions.`
    }
  ];
};

const parseContent = (content) => {
  if (!content) return [];
  // Models sometimes wrap JSON in prose or code fences; extract the object.
  let text = String(content).trim();
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence) text = fence[1].trim();
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start !== -1 && end !== -1 && end > start) {
    text = text.slice(start, end + 1);
  }
  try {
    const parsed = JSON.parse(text);
    return sanitizeItems(parsed.items || parsed.questions || parsed);
  } catch (_) {
    return [];
  }
};

/**
 * Returns a sanitized list of question items, or throws an Error with a
 * `.status` when the upstream call fails. Never throws for "not configured" —
 * callers should check `isConfigured()` first.
 */
const generateItems = async (config) => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs());
  try {
    const response = await fetch(`${baseUrl()}/chat/completions`, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${apiKey()}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: model(),
        temperature: 0.4,
        messages: buildPrompt(config),
        response_format: { type: 'json_object' }
      })
    });

    if (!response.ok) {
      const error = new Error(`AI provider returned ${response.status}.`);
      error.status = 502;
      throw error;
    }
    const data = await response.json();
    const content = data?.choices?.[0]?.message?.content;
    return parseContent(content);
  } catch (err) {
    if (err.status) throw err;
    const wrapped = new Error(`AI question generation failed: ${err.message}`);
    wrapped.status = 502;
    throw wrapped;
  } finally {
    clearTimeout(timer);
  }
};

module.exports = { isConfigured, generateItems, sanitizeItems, parseContent };
