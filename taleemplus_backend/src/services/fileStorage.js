/**
 * Private file storage with two interchangeable drivers.
 *
 *  - "blob":  Vercel Blob, private store (production). Credentials come from
 *             BLOB_READ_WRITE_TOKEN, or OIDC + BLOB_STORE_ID when the store is
 *             connected to the Vercel project.
 *  - "local": a folder on disk (development and automated tests only). Never
 *             used on Vercel, whose filesystem is temporary.
 *
 * Objects are addressed by an opaque storage key generated here; original
 * filenames are kept only as metadata, so user input never reaches a path.
 */
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { Readable } = require('stream');

const LOCAL_ROOT = path.resolve(
  process.env.LOCAL_UPLOAD_DIR || path.join(__dirname, '..', '..', 'uploads')
);

const isOnVercel = () => Boolean(process.env.VERCEL);
const hasBlobCredentials = () =>
  Boolean(process.env.BLOB_READ_WRITE_TOKEN || process.env.BLOB_STORE_ID);

/** Which driver to use, or null when no persistent storage is configured. */
const activeDriver = () => {
  const requested = (process.env.STORAGE_DRIVER || '').toLowerCase();
  if (requested === 'blob') return hasBlobCredentials() ? 'blob' : null;
  if (requested === 'local') return isOnVercel() ? null : 'local';
  if (hasBlobCredentials()) return 'blob';
  if (isOnVercel() || process.env.NODE_ENV === 'production') return null;
  return 'local';
};

const newStorageKey = (academyId, category) =>
  `academies/${academyId}/${category.toLowerCase()}/${crypto.randomUUID()}`;

const localPathFor = (key) => {
  const resolved = path.resolve(LOCAL_ROOT, key);
  if (!resolved.startsWith(LOCAL_ROOT + path.sep)) {
    throw new Error('Invalid storage key.');
  }
  return resolved;
};

const blob = () => require('@vercel/blob');

async function putObject(driver, key, buffer, contentType) {
  if (driver === 'blob') {
    await blob().put(key, buffer, {
      access: 'private',
      contentType,
      addRandomSuffix: false,
      allowOverwrite: false
    });
    return;
  }
  const target = localPathFor(key);
  await fs.promises.mkdir(path.dirname(target), { recursive: true });
  await fs.promises.writeFile(target, buffer, { flag: 'wx' });
}

/** Returns a Node readable stream for the object, or null when missing. */
async function getObjectStream(driver, key) {
  if (driver === 'blob') {
    const result = await blob().get(key, { access: 'private' });
    if (!result || result.statusCode !== 200) return null;
    return Readable.fromWeb(result.stream);
  }
  const target = localPathFor(key);
  if (!fs.existsSync(target)) return null;
  return fs.createReadStream(target);
}

async function deleteObject(driver, key) {
  if (driver === 'blob') {
    await blob().del(key);
    return;
  }
  await fs.promises.rm(localPathFor(key), { force: true });
}

module.exports = {
  activeDriver,
  newStorageKey,
  putObject,
  getObjectStream,
  deleteObject,
  LOCAL_ROOT
};
