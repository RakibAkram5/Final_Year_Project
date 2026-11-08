#!/usr/bin/env node
const path = require('path');

const { main } = require(path.join(
  __dirname,
  '..',
  'taleemplus_backend',
  'scripts',
  'migration',
  'verifyIdentity'
));

const args = process.argv.slice(2);
if (!args.includes('--export-dir')) {
  args.push('--export-dir', path.join(__dirname, '..', 'data_export'));
}

main(args)
  .then((code) => {
    process.exitCode = code;
  })
  .catch((error) => {
    console.error(`Identity verification failed: ${error.message}`);
    process.exitCode = 1;
  });
