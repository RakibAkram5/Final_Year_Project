const { validateImageUpload, readSize } = require('../src/utils/imageValidation');
const { png, jpegHeader } = require('./helpers/images');

const limits = { maxBytes: 300 * 1024, maxDimension: 1024 };

describe('logo image validation', () => {
  it('accepts a real PNG and reports its dimensions', () => {
    const result = validateImageUpload(png(16, 9).toString('base64'), 'image/png', limits);
    expect(result.error).toBeUndefined();
    expect(result).toMatchObject({ mimeType: 'image/png', width: 16, height: 9 });
  });

  it('accepts a data URI prefix and JPEG headers', () => {
    const uri = `data:image/jpeg;base64,${jpegHeader(640, 480).toString('base64')}`;
    expect(validateImageUpload(uri, 'image/jpeg', limits)).toMatchObject({ width: 640, height: 480 });
  });

  it('rejects content that does not match the declared type', () => {
    expect(validateImageUpload(png().toString('base64'), 'image/jpeg', limits).error).toMatch(/does not match/);
    expect(validateImageUpload(Buffer.from('<svg/>').toString('base64'), 'image/png', limits).error).toMatch(/does not match/);
    expect(validateImageUpload(png().toString('base64'), 'image/svg+xml', limits).error).toMatch(/PNG, JPEG or WebP/);
  });

  it('enforces byte and dimension caps', () => {
    expect(validateImageUpload(png(2000, 2).toString('base64'), 'image/png', limits).error).toMatch(/1024/);
    const big = validateImageUpload(png(64, 64).toString('base64'), 'image/png', { maxBytes: 100, maxDimension: 1024 });
    expect(big.error).toMatch(/KB or smaller/);
    expect(validateImageUpload('***', 'image/png', limits).error).toMatch(/base64/);
  });

  it('parses WebP headers', () => {
    const header = Buffer.alloc(30);
    header.write('RIFF', 0, 'ascii'); header.write('WEBP', 8, 'ascii'); header.write('VP8 ', 12, 'ascii');
    header.writeUInt16LE(300, 26); header.writeUInt16LE(200, 28);
    expect(readSize('image/webp', header)).toEqual({ width: 300, height: 200 });
  });
});
