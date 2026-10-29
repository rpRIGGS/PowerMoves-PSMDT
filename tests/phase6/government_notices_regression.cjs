const assert = require('node:assert/strict');
const fs = require('node:fs');
const read = path => fs.readFileSync(path, 'utf8');
const cfg = read('config.lua');
const auth = read('server/auth.lua');
const policy = read('server/backend/government_jurisdiction_policy.lua');
const backend = read('server/backend/government_notices.lua');
const client = read('client/backend/government_notices.lua');
const serviceCounters = read('client/backend/public_services.lua');
const events = read('web/src/constants/nuiEvents.ts');
const home = read('web/src/pages/Government.svelte');
const editor = read('web/src/pages/GovernmentNotices.svelte');
const migration = read('sql/migrations/2026-10-29-government-public-notices.sql');
const withdrawal = read('sql/migrations/2026-10-29-government-notice-withdrawal.sql');
const cleanSchemas = [read('sql/qbcore.sql'), read('sql/qbx.sql')];

function tableDDL(content, name) {
  const start = 'CREATE TABLE IF NOT EXISTS \`' + name + '\` (';
  const from = content.indexOf(start);
  assert.ok(from >= 0, 'Missing ' + name);
  const endToken = ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;';
  const to = content.indexOf(endToken, from);
  assert.ok(to > from, 'Missing table terminator for ' + name);
  return content.slice(from, to + endToken.length).trim();
}
for(const base of cleanSchemas) {
  assert.ok(base.includes(withdrawal.trim()), 'Fresh install missing withdrawal columns');
  for(const table of ['mdt_government_notices','mdt_government_notice_audit']) {
    assert.strictEqual(tableDDL(base,table),tableDDL(migration,table));
  }
}
for (const key of ['sagov','bcgov','lscgov','lsgov']) {
  assert.match(cfg, new RegExp('\\b' + key + "\\s*=\\s*['\"]"));
}
for (const perm of ['government_notice_manage','government_notice_publish','government_notice_oversight']) {
  assert.match(cfg, new RegExp(perm));
}
assert.match(auth, /function GetGovernmentNoticeAccess\(source\)/);
assert.match(auth, /current\.citizenid ~= identity\.citizenid|current\.citizenid ~= initial\.citizenid|initial\.citizenid ~= current\.citizenid/);
assert.match(auth, /contains\(permissions, config\.PublishPermission\)/);
assert.match(policy, /function CanViewGovernmentJurisdictionRecord/);
assert.match(policy, /actorJob ~= 'sagov' or hasStateOversight ~= true/);
assert.match(backend, /MySQL\.startTransaction/);
assert.match(backend, /rawget\(MySQL, 'startTransaction'\)/);
assert.match(backend, /FOR UPDATE/);
assert.match(backend, /version = version \+ 1/);
assert.match(backend, /sameAccess\(source, access\)/);
assert.match(backend, /row\.status == 'published'/);
assert.match(backend, /CanViewGovernmentJurisdictionRecord/);
assert.match(backend, /getPublicGovernmentNotices/);
assert.match(backend, /status = 'withdrawn'/);
assert.match(backend, /withdrawn_by_citizenid/);
assert.match(backend, /PublicServiceDeskAllows\(source, nil, 'government_notices'\)/);
assert.match(backend, /WHERE status = 'published'/);
assert.match(serviceCounters, /government_notices =/);

assert.doesNotMatch(backend, /RegisterCommand/);
for(const action of ['getGovernmentNotices','createGovernmentNotice','editGovernmentNotice','publishGovernmentNotice','withdrawGovernmentNotice']) {
  assert.match(backend,new RegExp("server:" + action));
  assert.match(client,new RegExp(action));
  assert.match(events,new RegExp(action));
  assert.match(editor,new RegExp(action));
}
assert.match(events, /Object\.values\(NUI_EVENTS\.GOVERNMENT_NOTICES\)/);
assert.match(home, /<GovernmentNotices/);
assert.match(home, /activeSection === "notices"/);
console.log('PASS Stage 6 notice contract, auth, NUI, SQL parity');
