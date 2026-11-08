const { isValidDateOnly } = require('../src/utils/validation');

describe('isValidDateOnly', () => {
  it('accepts real calendar dates in YYYY-MM-DD form', () => {
    expect(isValidDateOnly('2026-01-05')).toBe(true);
    expect(isValidDateOnly('2024-02-29')).toBe(true);
  });

  it('rejects malformed or impossible dates', () => {
    expect(isValidDateOnly('2026-1-5')).toBe(false);
    expect(isValidDateOnly('2025-02-29')).toBe(false);
    expect(isValidDateOnly('2026-13-01')).toBe(false);
    expect(isValidDateOnly('2026-04-31')).toBe(false);
    expect(isValidDateOnly('not-a-date')).toBe(false);
  });
});
