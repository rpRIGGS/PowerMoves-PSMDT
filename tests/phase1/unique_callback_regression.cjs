// Ensure backend Lua files do not overwrite each other's callback handlers.
// The ps_lib dispatcher is keyed by the registered callback name.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..', 'server/backend');
const seen = new Map();
let count = 0;
for (const name of fs.readdirSync(root).filter(f => f.endsWith('.lua'))) {
  const source = fs.readFileSync(path.join(root, name), 'utf8');
  const pattern = /ps\.registerCallback\(\s*(?:resourceName\s*\.\.\s*)?['"](?:ps-mdt:server:|:server:)([A-Za-z0-9_]+)['"]/g;
  let match;
  while ((match = pattern.exec(source))) {
    count++;
    const callback = match[1];
    if (seen.has(callback)) throw new Error(`Duplicate MDT callback ${callback}: ${seen.get(callback)} and ${name}`);
    seen.set(callback, name);
  }
}
assert.ok(count > 100, `Expected substantial callback coverage, got ${count}`);
console.log(`Validated ${count} backend callback registrations with unique names.`);
