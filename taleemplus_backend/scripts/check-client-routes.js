#!/usr/bin/env node
/**
 * Contract check: every `_api.get/post/put/patch/delete('<path>')` call in the
 * Flutter client (lib/) must match a route registered in the Express app.
 * Exits 1 when a client call has no backend route.
 *
 *   node scripts/check-client-routes.js
 */
// The app is only loaded to enumerate routes (no requests, no DB access),
// so placeholder configuration is enough when none is set.
process.env.JWT_SECRET = process.env.JWT_SECRET || 'route-check-access-placeholder';
process.env.REFRESH_TOKEN_SECRET =
  process.env.REFRESH_TOKEN_SECRET || 'route-check-refresh-placeholder';
process.env.DATABASE_URL =
  process.env.DATABASE_URL || 'postgresql://route-check@localhost/none';
const fs = require('fs');
const path = require('path');
const app = require('../src/app');

// Express 4 stores a mount path only as a compiled regexp; recover it.
const mountPath = (layer) => {
  const src = layer.regexp.source;
  if (src === '^\\/?$' || src === '^\\/?(?=\\/|$)') return '';
  return src
    .replace(/^\^/, '')
    .replace(/\\\/\?\(\?=\\\/\|\$\)$/, '')
    .replace(/\\\//g, '/');
};

const routes = [];
const walk = (stack, prefix) => {
  for (const layer of stack) {
    if (layer.route) {
      for (const method of Object.keys(layer.route.methods)) {
        routes.push({ method: method.toUpperCase(), path: prefix + layer.route.path });
      }
    } else if (layer.name === 'router' && layer.handle.stack) {
      walk(layer.handle.stack, prefix + mountPath(layer));
    }
  }
};
walk(app._router.stack, '');
const v2 = routes.filter((r) => r.path.startsWith('/api/v2'));
const toRegex = (p) =>
  new RegExp('^' + p.replace(/\/$/, '').replace(/:[^/]+/g, '[^/]+') + '/?$');

const files = [];
const collect = (dir) => {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) collect(full);
    else if (entry.name.endsWith('.dart')) files.push(full);
  }
};
collect(path.resolve(__dirname, '..', '..', 'lib'));

const callRe = /_api\s*\.\s*(get|post|put|patch|delete)\w*\s*\(\s*(['"])(.*?)\2/gs;
let failures = 0;
let total = 0;
for (const file of files) {
  const text = fs.readFileSync(file, 'utf8');
  for (const m of text.matchAll(callRe)) {
    total += 1;
    const method = m[1].toUpperCase();
    const clientPath =
      '/api/v2' + m[3].split('?')[0].replace(/\$\{[^}]+\}|\$\w+/g, 'X');
    const matches = v2.filter((r) => r.method === method && toRegex(r.path).test(clientPath));
    // A literal client segment (e.g. "marks") that only matches a `:param`
    // route segment is almost always a wrong path: Express would treat
    // "/quizzes/marks" as "/quizzes/:id" with id="marks".
    const literalIntoParam = (route) => {
      const r = route.path.replace(/\/$/, '').split('/');
      const c = clientPath.replace(/\/$/, '').split('/');
      return r.some((seg, i) => seg.startsWith(':') && c[i] !== 'X');
    };
    const ok = matches.some((route) => !literalIntoParam(route));
    if (!ok) {
      failures += 1;
      const line = text.slice(0, m.index).split('\n').length;
      console.log(
        `MISSING  ${method.padEnd(6)} ${clientPath}   (${path.relative(process.cwd(), file)}:${line})`
      );
    }
  }
}
if (process.argv.includes('--list')) {
  for (const r of v2) console.log(`ROUTE    ${r.method.padEnd(6)} ${r.path}`);
}
console.log(`\n${total} client calls checked, ${failures} without a backend route.`);
process.exit(failures ? 1 : 0);
