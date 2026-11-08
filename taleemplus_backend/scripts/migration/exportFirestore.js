const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DEFAULT_COLLECTIONS = [
  'academy_settings',
  'users',
  'announcements',
  'class_reports',
  'class_sections',
  'classes',
  'learning_resources',
  'notifications',
  'student_queries',
  'timetables',
  'ocr_documents'
];

const REPO_ROOT = path.resolve(__dirname, '..', '..', '..');

const parseArgs = (argv) => {
  const args = { _: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) {
      args._.push(token);
      continue;
    }
    const key = token.slice(2);
    const next = argv[index + 1];
    if (next === undefined || next.startsWith('--')) {
      args[key] = true;
    } else {
      args[key] = next;
      index += 1;
    }
  }
  return args;
};

const timestampFolder = () =>
  new Date().toISOString().replace(/[:.]/g, '-');

const loadFirebaseAdmin = () => {
  try {
    return require('firebase-admin');
  } catch (error) {
    throw new Error(
      'firebase-admin is not installed. Run "npm install --no-save firebase-admin" in taleemplus_backend before exporting.'
    );
  }
};

const loadServiceAccount = (credentials) => {
  const source = credentials || process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!source) {
    throw new Error(
      'No Firebase credentials supplied. Use --credentials <service-account.json> or set FIREBASE_SERVICE_ACCOUNT / GOOGLE_APPLICATION_CREDENTIALS.'
    );
  }
  const trimmed = source.trim();
  if (trimmed.startsWith('{')) return JSON.parse(trimmed);
  const file = path.resolve(trimmed);
  if (!fs.existsSync(file)) {
    throw new Error('The supplied Firebase service account file does not exist.');
  }
  return JSON.parse(fs.readFileSync(file, 'utf8'));
};

const serializeValue = (value, admin) => {
  if (value === null || value === undefined) return value;
  const firestore = admin.firestore;
  if (firestore && firestore.Timestamp && value instanceof firestore.Timestamp) {
    return value.toDate().toISOString();
  }
  if (
    value &&
    typeof value === 'object' &&
    typeof value.toDate === 'function' &&
    typeof value.seconds === 'number'
  ) {
    return value.toDate().toISOString();
  }
  if (firestore && firestore.GeoPoint && value instanceof firestore.GeoPoint) {
    return { latitude: value.latitude, longitude: value.longitude };
  }
  if (
    firestore &&
    firestore.DocumentReference &&
    value instanceof firestore.DocumentReference
  ) {
    return value.path;
  }
  if (Buffer.isBuffer(value)) return value.toString('base64');
  if (Array.isArray(value)) return value.map((item) => serializeValue(item, admin));
  if (typeof value === 'object') {
    const output = {};
    for (const [key, item] of Object.entries(value)) {
      output[key] = serializeValue(item, admin);
    }
    return output;
  }
  return value;
};

const exportCollection = async ({ db, admin, collection, outputFile, pageSize }) => {
  const hash = crypto.createHash('sha256');
  const stream = fs.createWriteStream(outputFile, { encoding: 'utf8' });
  let count = 0;
  let bytes = 0;
  let lastDocument = null;

  const writeDocument = (document) =>
    new Promise((resolve, reject) => {
      const line = `${JSON.stringify({
        id: document.id,
        data: serializeValue(document.data(), admin)
      })}\n`;
      hash.update(line);
      bytes += Buffer.byteLength(line);
      count += 1;
      if (stream.write(line)) resolve();
      else stream.once('drain', resolve);
      stream.once('error', reject);
    });

  try {
    while (true) {
      let query = db.collection(collection).orderBy(admin.firestore.FieldPath.documentId());
      if (pageSize) query = query.limit(pageSize);
      if (lastDocument) query = query.startAfter(lastDocument);
      const snapshot = await query.get();
      if (snapshot.empty) break;
      for (const document of snapshot.docs) {
        await writeDocument(document);
      }
      lastDocument = snapshot.docs[snapshot.docs.length - 1];
      if (!pageSize) break;
      if (snapshot.size < pageSize) break;
    }
  } finally {
    await new Promise((resolve, reject) => {
      stream.end((error) => (error ? reject(error) : resolve()));
    });
  }

  return { count, bytes, sha256: hash.digest('hex') };
};

const main = async (argv = process.argv.slice(2)) => {
  const args = parseArgs(argv);
  const admin = loadFirebaseAdmin();
  const serviceAccount = loadServiceAccount(
    args.credentials || process.env.GOOGLE_APPLICATION_CREDENTIALS
  );
  const projectId = args['project-id'] || serviceAccount.project_id;
  const collections = args.collections
    ? String(args.collections)
        .split(',')
        .map((item) => item.trim())
        .filter(Boolean)
    : DEFAULT_COLLECTIONS;
  const outputDirectory = path.resolve(
    args.out || path.join(REPO_ROOT, 'migration_exports', timestampFolder())
  );
  const pageSize = (() => {
    const requested = Number(args['page-size']);
    if (!Number.isInteger(requested) || requested < 1) return 500;
    return Math.min(requested, 1000);
  })();

  if (args['dry-run']) {
    console.log('Export dry run: credentials and collection list validated.');
    console.log(`Collections (${collections.length}): ${collections.join(', ')}`);
    return;
  }

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId
  });

  fs.mkdirSync(outputDirectory, { recursive: true });
  const db = admin.firestore();
  const manifest = {
    exportedAt: new Date().toISOString(),
    projectId,
    collections: [],
    totalDocuments: 0
  };

  for (const collection of collections) {
    const outputFile = path.join(outputDirectory, `${collection}.jsonl`);
    process.stdout.write(`Exporting ${collection}... `);
    const result = await exportCollection({
      db,
      admin,
      collection,
      outputFile,
      pageSize
    });
    manifest.collections.push({
      name: collection,
      file: path.basename(outputFile),
      count: result.count,
      bytes: result.bytes,
      sha256: result.sha256
    });
    manifest.totalDocuments += result.count;
    console.log(`${result.count} documents`);
  }

  fs.writeFileSync(
    path.join(outputDirectory, 'manifest.json'),
    `${JSON.stringify(manifest, null, 2)}\n`,
    'utf8'
  );

  console.log(`Export complete: ${manifest.totalDocuments} documents.`);
  console.log(`Manifest: ${path.join(outputDirectory, 'manifest.json')}`);
  if (manifest.totalDocuments === 0) {
    console.warn(
      'WARNING: the export is empty. Do not use it to claim the source data is empty without an independent check.'
    );
  }
};

if (require.main === module) {
  main().catch((error) => {
    console.error(`Export failed: ${error.message}`);
    process.exitCode = 1;
  });
}

module.exports = { main, DEFAULT_COLLECTIONS };
