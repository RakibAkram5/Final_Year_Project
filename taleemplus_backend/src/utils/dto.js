const toIso = (value) => {
  if (value === null || value === undefined) return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
};

const toDateOnly = (value) => {
  const iso = toIso(value);
  return iso ? iso.slice(0, 10) : null;
};

const lowerEnum = (value) =>
  typeof value === 'string' ? value.toLowerCase() : value;

const mapEnums = (row, keys) => {
  const result = { ...row };
  for (const key of keys) {
    if (key in result) result[key] = lowerEnum(result[key]);
  }
  return result;
};

module.exports = { toIso, toDateOnly, lowerEnum, mapEnums };
