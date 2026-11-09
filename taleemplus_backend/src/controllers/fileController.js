/**
 * File upload / list / download / replace / delete.
 *
 * Upload protocol (fits Vercel's 4.5 MB request limit, no base64 overhead):
 *   POST /api/v2/files?category=COURSE_MATERIAL&ownerId=<uuid>&filename=notes.pdf
 *   Content-Type: application/octet-stream
 *   <raw file bytes, max MAX_UPLOAD_BYTES>
 */
const crypto = require('crypto');
const prisma = require('../config/db');
const storage = require('../services/fileStorage');
const { CATEGORIES, ownerPermissions } = require('../services/fileAccess');
const { validateUpload } = require('../utils/fileTypes');

const MAX_UPLOAD_BYTES = 4 * 1024 * 1024;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const fail = (res, status, message, code) =>
  res.status(status).json({ success: false, ...(code ? { code } : {}), message });

const toDto = (f) => ({
  id: f.id,
  category: f.category,
  ownerId: f.ownerId,
  originalName: f.originalName,
  mimeType: f.mimeType,
  sizeBytes: f.sizeBytes,
  description: f.description,
  uploadedById: f.uploadedById,
  uploadedByName: f.uploadedBy?.fullName,
  createdAt: f.createdAt,
  contentPath: `/files/${f.id}/content`
});

const readUpload = (req) => {
  const body = req.body;
  if (!Buffer.isBuffer(body) || body.length === 0) {
    const err = new Error('Send the file bytes as application/octet-stream.');
    err.status = 400;
    throw err;
  }
  return body;
};

async function storeFile(req, res, { category, ownerId, filename, description }) {
  const driver = storage.activeDriver();
  if (!driver) {
    return fail(res, 503, 'File storage is not configured on this server.', 'STORAGE_UNAVAILABLE');
  }
  const bytes = readUpload(req);
  if (bytes.length > MAX_UPLOAD_BYTES) {
    return fail(res, 413, 'Files must be 4 MB or smaller.', 'FILE_TOO_LARGE');
  }
  let checked;
  try {
    checked = validateUpload(bytes, filename, CATEGORIES[category].types);
  } catch (e) {
    return fail(res, 415, e.message, 'UNSUPPORTED_FILE');
  }
  const key = storage.newStorageKey(req.academyId, category);
  await storage.putObject(driver, key, bytes, checked.mime);
  try {
    return await prisma.storedFile.create({
      data: {
        academyId: req.academyId,
        category,
        ownerId,
        originalName: checked.filename,
        storageKey: key,
        storageDriver: driver,
        mimeType: checked.mime,
        sizeBytes: bytes.length,
        sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
        description: description ? String(description).slice(0, 500) : null,
        uploadedById: req.user.id
      },
      include: { uploadedBy: { select: { fullName: true } } }
    });
  } catch (e) {
    await storage.deleteObject(driver, key).catch(() => {});
    throw e;
  }
}

const parseTarget = (req, res) => {
  const category = String(req.query.category || '').toUpperCase();
  const ownerId = String(req.query.ownerId || '');
  if (!CATEGORIES[category]) {
    fail(res, 400, `category must be one of ${Object.keys(CATEGORIES).join(', ')}.`);
    return null;
  }
  if (!UUID.test(ownerId)) {
    fail(res, 400, 'ownerId must be a valid id.');
    return null;
  }
  return { category, ownerId };
};

const uploadFile = async (req, res, next) => {
  try {
    const target = parseTarget(req, res);
    if (!target) return;
    const perms = await ownerPermissions(req, target.category, target.ownerId);
    if (!perms) return fail(res, 404, 'The record this file belongs to was not found.');
    if (!perms.canWrite) return fail(res, 403, 'You cannot upload files here.');
    const file = await storeFile(req, res, {
      ...target,
      filename: req.query.filename,
      description: req.query.description
    });
    if (!file || res.headersSent) return;
    return res.status(201).json({ success: true, data: toDto(file) });
  } catch (err) {
    next(err);
  }
};

const listFiles = async (req, res, next) => {
  try {
    const target = parseTarget(req, res);
    if (!target) return;
    const perms = await ownerPermissions(req, target.category, target.ownerId);
    if (!perms) return fail(res, 404, 'Record not found.');
    if (!perms.canRead) return fail(res, 403, 'You cannot view these files.');
    const files = await prisma.storedFile.findMany({
      where: { academyId: req.academyId, ...target },
      include: { uploadedBy: { select: { fullName: true } } },
      orderBy: { createdAt: 'desc' }
    });
    return res.json({ success: true, data: files.map(toDto) });
  } catch (err) {
    next(err);
  }
};

const loadAuthorized = async (req, res, action) => {
  if (!UUID.test(req.params.id)) {
    fail(res, 404, 'File not found.');
    return null;
  }
  const file = await prisma.storedFile.findFirst({
    where: { id: req.params.id, academyId: req.academyId },
    include: { uploadedBy: { select: { fullName: true } } }
  });
  const perms = file && await ownerPermissions(req, file.category, file.ownerId);
  // Unauthorised callers get the same 404 as for missing files, so ids from
  // other academies or families cannot be probed.
  if (!file || !perms || !perms.canRead) {
    fail(res, 404, 'File not found.');
    return null;
  }
  if (action === 'write' && !perms.canWrite) {
    fail(res, 403, 'You cannot change this file.');
    return null;
  }
  if (action === 'delete' && !perms.canDelete) {
    fail(res, 403, 'You cannot delete this file.');
    return null;
  }
  return file;
};

const contentDisposition = (type, name) => {
  const ascii = name.replace(/[^\x20-\x7e]/g, '_').replace(/["\\]/g, '_');
  return `${type}; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(name)}`;
};

const downloadFile = async (req, res, next) => {
  try {
    const file = await loadAuthorized(req, res, 'read');
    if (!file) return;
    const stream = await storage.getObjectStream(file.storageDriver, file.storageKey);
    if (!stream) return fail(res, 410, 'The stored file is no longer available.', 'FILE_MISSING');
    const inline = req.query.disposition === 'inline' &&
      (file.mimeType === 'application/pdf' || file.mimeType.startsWith('image/'));
    res.setHeader('Content-Type', file.mimeType);
    res.setHeader('Content-Length', String(file.sizeBytes));
    res.setHeader('Content-Disposition', contentDisposition(inline ? 'inline' : 'attachment', file.originalName));
    res.setHeader('Cache-Control', 'private, no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    stream.on('error', next);
    stream.pipe(res);
  } catch (err) {
    next(err);
  }
};

const replaceFile = async (req, res, next) => {
  try {
    const old = await loadAuthorized(req, res, 'write');
    if (!old) return;
    const created = await storeFile(req, res, {
      category: old.category,
      ownerId: old.ownerId,
      filename: req.query.filename || old.originalName,
      description: req.query.description ?? old.description
    });
    if (!created || res.headersSent) return;
    await prisma.storedFile.delete({ where: { id: old.id } });
    await storage.deleteObject(old.storageDriver, old.storageKey).catch((e) =>
      console.error('[files] could not remove replaced object', e.message));
    return res.json({ success: true, data: toDto(created), message: 'File replaced.' });
  } catch (err) {
    next(err);
  }
};

const deleteFile = async (req, res, next) => {
  try {
    const file = await loadAuthorized(req, res, 'delete');
    if (!file) return;
    await prisma.storedFile.delete({ where: { id: file.id } });
    await storage.deleteObject(file.storageDriver, file.storageKey).catch((e) =>
      console.error('[files] could not remove object', e.message));
    return res.json({ success: true, data: { deleted: true }, message: 'File deleted.' });
  } catch (err) {
    next(err);
  }
};

/** Removes every file attached to an owner record (used before deleting it). */
const deleteFilesForOwner = async (academyId, category, ownerId) => {
  const files = await prisma.storedFile.findMany({ where: { academyId, category, ownerId } });
  await prisma.storedFile.deleteMany({ where: { id: { in: files.map((f) => f.id) } } });
  await Promise.all(files.map((f) =>
    storage.deleteObject(f.storageDriver, f.storageKey).catch(() => {})));
};

module.exports = {
  MAX_UPLOAD_BYTES,
  uploadFile,
  listFiles,
  downloadFile,
  replaceFile,
  deleteFile,
  deleteFilesForOwner,
  storeFile,
  toDto
};
