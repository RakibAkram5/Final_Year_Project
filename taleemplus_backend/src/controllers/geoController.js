/**
 * Address search / reverse lookup via OpenStreetMap Nominatim (free, no key).
 *
 * Proxied through the backend so that:
 *  - requests carry an identifying User-Agent, as Nominatim's usage policy
 *    requires (https://operations.osmfoundation.org/policies/nominatim/);
 *  - the 1 request/second limit is respected across all users of this
 *    instance and identical queries are cached;
 *  - the web app is not blocked by CORS.
 * Only admins can call it (it is used when setting the academy location).
 */
const BASE = process.env.NOMINATIM_URL || 'https://nominatim.openstreetmap.org';
const USER_AGENT = process.env.GEOCODER_USER_AGENT ||
  'TaleemPlus/1.0 (academy management system; academy location lookup)';
const CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const MIN_INTERVAL_MS = 1100;

const cache = new Map();
let lastCall = 0;
let queue = Promise.resolve();

/** Serialises upstream calls so they are at least MIN_INTERVAL_MS apart. */
const throttled = (fn) => {
  const run = queue.then(async () => {
    const wait = lastCall + MIN_INTERVAL_MS - Date.now();
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
    lastCall = Date.now();
    return fn();
  });
  queue = run.catch(() => {});
  return run;
};

const fetchJson = async (url) => {
  const key = url.toString();
  const hit = cache.get(key);
  if (hit && hit.expires > Date.now()) return hit.data;
  const data = await throttled(async () => {
    const res = await fetch(url, {
      headers: { 'User-Agent': USER_AGENT, 'Accept-Language': 'en' },
      signal: AbortSignal.timeout(8000)
    });
    if (!res.ok) {
      const err = new Error(`Geocoding service returned HTTP ${res.status}.`);
      err.upstream = true;
      throw err;
    }
    return res.json();
  });
  if (cache.size > 500) cache.delete(cache.keys().next().value);
  cache.set(key, { data, expires: Date.now() + CACHE_TTL_MS });
  return data;
};

const toPlace = (p) => ({
  label: p.display_name,
  latitude: Number(Number(p.lat).toFixed(6)),
  longitude: Number(Number(p.lon).toFixed(6))
});

const unavailable = (res) => res.status(503).json({
  success: false,
  code: 'GEOCODER_UNAVAILABLE',
  message: 'Address search is temporarily unavailable. You can still place the pin on the map.'
});

const search = async (req, res) => {
  const q = String(req.query.q || '').trim();
  if (q.length < 3 || q.length > 200) {
    return res.status(400).json({ success: false, message: 'Enter 3–200 characters to search.' });
  }
  const url = new URL('/search', BASE);
  url.search = new URLSearchParams({ format: 'jsonv2', q, limit: '5' }).toString();
  try {
    const data = await fetchJson(url);
    return res.json({ success: true, data: (Array.isArray(data) ? data : []).map(toPlace) });
  } catch (e) {
    console.error('[geo] search failed:', e.message);
    return unavailable(res);
  }
};

const reverse = async (req, res) => {
  const lat = Number(req.query.lat);
  const lng = Number(req.query.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    return res.status(400).json({ success: false, message: 'Invalid coordinates.' });
  }
  const url = new URL('/reverse', BASE);
  url.search = new URLSearchParams({ format: 'jsonv2', lat: String(lat), lon: String(lng), zoom: '18' }).toString();
  try {
    const data = await fetchJson(url);
    if (!data || data.error) return res.json({ success: true, data: null });
    return res.json({ success: true, data: toPlace(data) });
  } catch (e) {
    console.error('[geo] reverse failed:', e.message);
    return unavailable(res);
  }
};

module.exports = { search, reverse, _cache: cache };
