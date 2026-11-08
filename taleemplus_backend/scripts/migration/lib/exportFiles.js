const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const COLLECTION_FILE_EXTENSIONS = ['.jsonl', '.json'];

const resolveCollectionFile = (directory, collection) => {
  for (const extension of COLLECTION_FILE_EXTENSIONS) {
    const candidate = path.join(directory, `${collection}${extension}`);
    if (fs.existsSync(candidate)) return candidate;
  }
  return null;
};

const readRecordsFromFile = (file) => {
  if (!file) return [];
  const content = fs.readFileSync(file, 'utf8');
  if (file.toLowerCase().endsWith('.jsonl')) {
    return content
      .split(/\r?\n/)
      .map((line, index) => ({ line, index }))
      .filter(({ line }) => line.trim().length > 0)
      .map(({ line, index }) => {
        try {
          return JSON.parse(line);
        } catch (error) {
          throw new Error(
            `Invalid JSONL in ${path.basename(file)} at line ${index + 1}: ${error.message}`
          );
        }
      });
  }
  const parsed = JSON.parse(content);
  if (!Array.isArray(parsed)) {
    throw new Error(`${path.basename(file)} must contain a JSON array of documents.`);
  }
  return parsed;
};

const readCollection = (directory, collection) =>
  readRecordsFromFile(resolveCollectionFile(directory, collection));

const iterateJsonl = (file, onRecord) => {
  const content = fs.readFileSync(file, 'utf8');
  const lines = content.split(/\r?\n/);
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index].trim();
    if (!line) continue;
    let parsed;
    try {
      parsed = JSON.parse(line);
    } catch (error) {
      throw new Error(
        `Invalid JSONL in ${path.basename(file)} at line ${index + 1}: ${error.message}`
      );
    }
    onRecord(parsed, index + 1);
  }
};

const readManifest = (directory) => {
  const file = path.join(directory, 'manifest.json');
  if (!fs.existsSync(file)) return null;
  return JSON.parse(fs.readFileSync(file, 'utf8'));
};

const sha256File = (file) => {
  const hash = crypto.createHash('sha256');
  const content = fs.readFileSync(file);
  hash.update(content);
  return hash.digest('hex');
};

const writeJsonFile = (file, value) => {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
};

module.exports = {
  resolveCollectionFile,
  readRecordsFromFile,
  readCollection,
  iterateJsonl,
  readManifest,
  sha256File,
  writeJsonFile
};
