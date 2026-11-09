/**
 * Detects a file's real type from its bytes and checks it against the
 * filename extension. The MIME type a client claims is never trusted.
 */
const path = require('path');

const TYPES = {
  pdf: { mime: 'application/pdf', label: 'PDF' },
  png: { mime: 'image/png', label: 'PNG image' },
  jpg: { mime: 'image/jpeg', label: 'JPEG image' },
  docx: {
    mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    label: 'Word document'
  },
  xlsx: {
    mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    label: 'Excel workbook'
  },
  pptx: {
    mime: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    label: 'PowerPoint presentation'
  },
  doc: { mime: 'application/msword', label: 'Word 97-2003 document' },
  xls: { mime: 'application/vnd.ms-excel', label: 'Excel 97-2003 workbook' },
  ppt: { mime: 'application/vnd.ms-powerpoint', label: 'PowerPoint 97-2003' },
  txt: { mime: 'text/plain; charset=utf-8', label: 'Text file' }
};

const EXTENSIONS = {
  pdf: 'pdf', png: 'png', jpg: 'jpg', jpeg: 'jpg', docx: 'docx', xlsx: 'xlsx',
  pptx: 'pptx', doc: 'doc', xls: 'xls', ppt: 'ppt', txt: 'txt'
};

const startsWith = (buf, bytes) =>
  buf.length >= bytes.length && bytes.every((b, i) => buf[i] === b);

/** Office Open XML files are ZIPs; the part names tell them apart. */
const detectOoxml = (buf) => {
  // ZIP part names are stored in plain text; part order is not guaranteed,
  // so scan the whole (size-limited) file.
  const all = buf.toString('latin1');
  if (!all.includes('[Content_Types].xml')) return null;
  if (all.includes('word/')) return 'docx';
  if (all.includes('xl/')) return 'xlsx';
  if (all.includes('ppt/')) return 'pptx';
  return null;
};

const isProbablyText = (buf) => {
  if (buf.includes(0)) return false;
  try {
    new TextDecoder('utf-8', { fatal: true }).decode(buf);
    return true;
  } catch {
    return false;
  }
};

/** Returns the detected type key (see TYPES) or null. */
const detectType = (buf, extension) => {
  if (!buf || !buf.length) return null;
  if (startsWith(buf, [0x25, 0x50, 0x44, 0x46, 0x2d])) return 'pdf';
  if (startsWith(buf, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'png';
  if (startsWith(buf, [0xff, 0xd8, 0xff])) return 'jpg';
  if (startsWith(buf, [0x50, 0x4b, 0x03, 0x04])) return detectOoxml(buf);
  if (startsWith(buf, [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])) {
    // Legacy OLE container: trust the extension only among OLE formats.
    return ['doc', 'xls', 'ppt'].includes(extension) ? extension : null;
  }
  if (extension === 'txt' && isProbablyText(buf)) return 'txt';
  return null;
};

/** Safe display filename: no path parts or control characters. */
const sanitizeFilename = (name) => {
  const base = path.basename(String(name || '').replace(/\\/g, '/'));
  const clean = base
    .replace(/[\u0000-\u001f\u007f<>:"|?*]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 150);
  return clean || 'file';
};

/**
 * Validates [buffer] as one of [allowed] type keys. Returns
 * `{ type, mime, filename }` or throws an Error with a user-facing message.
 */
const validateUpload = (buffer, filename, allowed) => {
  const safeName = sanitizeFilename(filename);
  const ext = EXTENSIONS[path.extname(safeName).slice(1).toLowerCase()];
  if (!ext || !allowed.includes(ext)) {
    throw new Error(
      `File type not allowed. Allowed: ${allowed.map((t) => TYPES[t].label).join(', ')}.`
    );
  }
  const detected = detectType(buffer, ext);
  if (!detected || detected !== ext) {
    throw new Error('The file content does not match its extension or is corrupted.');
  }
  return { type: detected, mime: TYPES[detected].mime, filename: safeName };
};

const DOCUMENT_TYPES = ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'png', 'jpg', 'txt'];
const SUBMISSION_TYPES = ['pdf', 'doc', 'docx', 'png', 'jpg'];

module.exports = {
  TYPES,
  DOCUMENT_TYPES,
  SUBMISSION_TYPES,
  detectType,
  sanitizeFilename,
  validateUpload
};
