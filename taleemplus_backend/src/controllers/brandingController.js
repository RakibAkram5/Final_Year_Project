/**
 * Academy white-label branding.
 *
 * TaleemPlus is the platform; each academy owns its own name, logo and
 * contact identity. Branding is always read and written under the caller's
 * own academy id (req.academyId), so no tenant can read or change another
 * tenant's identity. The logo is stored as validated bytes and served as a
 * base64 data URI, which renders identically on Android, Web and in PDFs.
 */
const prisma = require('../config/db');
const { sendSuccess, sendError } = require('../utils/response');
const { ERROR_CODES } = require('../utils/apiError');
const { validateImageUpload } = require('../utils/imageValidation');

// 300 KB keeps the base64 form (~400 KB) small enough to ride along with the
// session profile and the local cache; clients resize to <= 512 px first.
const MAX_LOGO_BYTES = 300 * 1024;
const MAX_LOGO_DIMENSION = 1024;

const BRANDING_SELECT = {
  id: true, code: true, name: true, address: true, phone: true, email: true,
  logo: true, logoData: true, logoMimeType: true, logoUpdatedAt: true,
};

/** Data URI for the stored logo, the legacy URL, or null. */
const logoUri = (academy) => {
  if (academy?.logoData && academy.logoMimeType) {
    return `data:${academy.logoMimeType};base64,${Buffer.from(academy.logoData).toString('base64')}`;
  }
  return academy?.logo || null;
};

const formatBranding = (academy) => ({
  academyId: academy.id,
  academyCode: academy.code,
  name: academy.name,
  address: academy.address,
  phone: academy.phone,
  email: academy.email,
  logo: logoUri(academy),
  logoMimeType: academy.logoData ? academy.logoMimeType : null,
  logoUpdatedAt: academy.logoUpdatedAt,
  hasCustomLogo: Boolean(academy.logoData),
});

const getBranding = async (req, res, next) => {
  try {
    const academy = await prisma.academy.findUnique({ where: { id: req.academyId }, select: BRANDING_SELECT });
    if (!academy) return sendError(res, 404, ERROR_CODES.NOT_FOUND, 'Academy not found.');
    return sendSuccess(res, formatBranding(academy));
  } catch (err) { next(err); }
};

const TEXT_FIELDS = [
  ['name', 120, true],
  ['address', 240, false],
  ['phone', 40, false],
  ['email', 160, false],
];
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

const updateBranding = async (req, res, next) => {
  try {
    const body = req.body || {};
    const data = {};
    for (const [field, maxLength, required] of TEXT_FIELDS) {
      if (body[field] === undefined) continue;
      const value = body[field];
      if (value !== null && typeof value !== 'string') {
        return sendError(res, 400, ERROR_CODES.VALIDATION_ERROR, `Invalid academy ${field}.`);
      }
      const trimmed = typeof value === 'string' ? value.trim() : '';
      if (trimmed.length > maxLength) {
        return sendError(res, 400, ERROR_CODES.VALIDATION_ERROR, `Academy ${field} must be ${maxLength} characters or fewer.`);
      }
      if (required && !trimmed) {
        return sendError(res, 400, ERROR_CODES.VALIDATION_ERROR, 'Academy name is required.');
      }
      if (field === 'email' && trimmed && !EMAIL_PATTERN.test(trimmed)) {
        return sendError(res, 400, ERROR_CODES.VALIDATION_ERROR, 'Academy email is not a valid address.');
      }
      data[field] = trimmed || null;
    }
    if (body.removeLogo === true) {
      data.logoData = null; data.logoMimeType = null; data.logoUpdatedAt = new Date(); data.logo = null;
    } else if (body.logoBase64 !== undefined && body.logoBase64 !== null) {
      const result = validateImageUpload(body.logoBase64, body.logoMimeType, {
        maxBytes: MAX_LOGO_BYTES, maxDimension: MAX_LOGO_DIMENSION,
      });
      if (result.error) return sendError(res, 400, ERROR_CODES.VALIDATION_ERROR, result.error);
      data.logoData = result.bytes; data.logoMimeType = result.mimeType; data.logoUpdatedAt = new Date();
      data.logo = null; // the stored image supersedes any legacy URL
    }
    if (!Object.keys(data).length) {
      return sendError(res, 400, ERROR_CODES.VALIDATION_ERROR, 'No branding fields were provided.');
    }
    const academy = await prisma.academy.update({ where: { id: req.academyId }, data, select: BRANDING_SELECT });
    return sendSuccess(res, formatBranding(academy), { message: 'Academy branding saved.' });
  } catch (err) { next(err); }
};

/**
 * Public identity for the login screen, keyed by the academy code the user
 * already knows. Only the display name and logo are exposed (no contact
 * details, ids or settings).
 */
const publicBranding = async (req, res, next) => {
  try {
    const code = String(req.query.code || '').trim();
    if (!code || code.length > 50) return sendError(res, 400, ERROR_CODES.VALIDATION_ERROR, 'Academy code is required.');
    const academy = await prisma.academy.findFirst({
      where: { code: { equals: code, mode: 'insensitive' } },
      select: { code: true, name: true, logo: true, logoData: true, logoMimeType: true },
    });
    if (!academy) return sendError(res, 404, ERROR_CODES.NOT_FOUND, 'Academy not found.');
    res.setHeader('Cache-Control', 'private, max-age=300');
    return sendSuccess(res, { academyCode: academy.code, name: academy.name, logo: logoUri(academy) });
  } catch (err) { next(err); }
};

module.exports = { getBranding, updateBranding, publicBranding, logoUri, MAX_LOGO_BYTES, MAX_LOGO_DIMENSION };
