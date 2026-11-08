#!/usr/bin/env node
const path = require('path');

const { main } = require(path.join(
  __dirname,
  '..',
  'taleemplus_backend',
  'scripts',
  'migration',
  'exportFirestore'
));

main(process.argv.slice(2)).catch((error) => {
  console.error(`Export failed: ${error.message}`);
  process.exitCode = 1;
});
