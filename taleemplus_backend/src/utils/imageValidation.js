/**
 * Server-side validation for small uploaded images (academy logos).
 *
 * Decodes a base64 payload, verifies the declared MIME type against the
 * file's magic bytes, reads the pixel dimensions from the container header
 * (no image library required) and enforces byte/dimension caps. Anything
 * that does not pass returns null so callers can respond with a 400.
 */
const SUPPORTED = ['image/png', 'image/jpeg', 'image/webp'];

const readPngSize = (bytes) => {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (bytes.length < 24 || !bytes.subarray(0, 8).equals(signature)) return null;
  if (bytes.toString('ascii', 12, 16) !== 'IHDR') return null;
  return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
};

const readJpegSize = (bytes) => {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  let offset = 2;
  while (offset + 9 < bytes.length) {
    if (bytes[offset] !== 0xff) { offset += 1; continue; }
    const marker = bytes[offset + 1];
    // Stand-alone markers without a length field.
    if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      offset += 2;
      continue;
    }
    const length = bytes.readUInt16BE(offset + 2);
    const isSof = (marker >= 0xc0 && marker <= 0xcf) && ![0xc4, 0xc8, 0xcc].includes(marker);
    if (isSof) {
      return { height: bytes.readUInt16BE(offset + 5), width: bytes.readUInt16BE(offset + 7) };
    }
    if (length < 2) return null;
    offset += 2 + length;
  }
  return null;
};

const readWebpSize = (bytes) => {
  if (bytes.length < 30) return null;
  if (bytes.toString('ascii', 0, 4) !== 'RIFF' || bytes.toString('ascii', 8, 12) !== 'WEBP') return null;
  const chunk = bytes.toString('ascii', 12, 16);
  if (chunk === 'VP8 ') {
    return { width: bytes.readUInt16LE(26) & 0x3fff, height: bytes.readUInt16LE(28) & 0x3fff };
  }
  if (chunk === 'VP8L') {
    const b0 = bytes[21]; const b1 = bytes[22]; const b2 = bytes[23]; const b3 = bytes[24];
    return { width: 1 + (((b1 & 0x3f) << 8) | b0), height: 1 + (((b3 & 0x0f) << 10) | (b2 << 2) | ((b1 & 0xc0) >> 6)) };
  }
  if (chunk === 'VP8X') {
    return {
      width: 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16)),
      height: 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16)),
    };
  }
  return null;
};

const readSize = (mimeType, bytes) => {
  if (mimeType === 'image/png') return readPngSize(bytes);
  if (mimeType === 'image/jpeg') return readJpegSize(bytes);
  if (mimeType === 'image/webp') return readWebpSize(bytes);
  return null;
};

/**
 * @returns {{ bytes: Buffer, mimeType: string, width: number, height: number } | { error: string }}
 */
const validateImageUpload = (base64, mimeType, { maxBytes, maxDimension }) => {
  if (!SUPPORTED.includes(mimeType)) return { error: 'Logo must be a PNG, JPEG or WebP image.' };
  if (typeof base64 !== 'string' || !base64) return { error: 'Logo image data is missing.' };
  const encoded = base64.replace(/^data:image\/[a-z]+;base64,/i, '').replace(/\s+/g, '');
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)) return { error: 'Logo image data is not valid base64.' };
  // Reject oversized payloads before decoding to avoid allocating big buffers.
  if (encoded.length > Math.ceil(maxBytes / 3) * 4 + 4) {
    return { error: `Logo must be ${Math.round(maxBytes / 1024)} KB or smaller.` };
  }
  const bytes = Buffer.from(encoded, 'base64');
  if (!bytes.length) return { error: 'Logo image data is empty.' };
  if (bytes.length > maxBytes) return { error: `Logo must be ${Math.round(maxBytes / 1024)} KB or smaller.` };
  const size = readSize(mimeType, bytes);
  if (!size || !size.width || !size.height) {
    return { error: 'Logo file content does not match a valid PNG, JPEG or WebP image.' };
  }
  if (size.width > maxDimension || size.height > maxDimension) {
    return { error: `Logo must be at most ${maxDimension}×${maxDimension} pixels.` };
  }
  return { bytes, mimeType, width: size.width, height: size.height };
};

module.exports = { validateImageUpload, readSize, SUPPORTED_IMAGE_TYPES: SUPPORTED };
