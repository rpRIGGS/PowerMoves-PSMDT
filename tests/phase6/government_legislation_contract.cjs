const assert = require('node:assert/strict');
const fs = require('node:fs');
const read = name => fs.readFileSync(name, 'utf8');
const server = read('server/backend/government_legislation.lua');
const client = read('client/backend/government_legislation.lua');
const home = read('web/src/pages/Government.svelte');
const screen = read('web/src/pages/GovernmentLegislation.svelte');
const events = read('web/src/constants/nuiEvents.ts');
const sql = read('sql/migrations/2026-10-29-government-legislation.sql');
for(const path of ['sql/qbcore.sql','sql/qbx.sql']) {
  const base=read(path);
  for(const table of ['mdt_government_legislation','mdt_government_legislation_votes','mdt_government_legislation_audit']) {
    const start='CREATE TABLE IF NOT EXISTS \x60'+table+'\x60 (';
    const ending=') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;';
    const extract=s=>{
      const i=s.indexOf(start);
      assert.ok(i>=0,'missing '+table);
      const j=s.indexOf(ending,i);
      assert.ok(j>i,'unclosed '+table);
      return s.slice(i,j+ending.length).trim();
    };
    assert.strictEqual(extract(base),extract(sql),'clean schema differs from migration');
  }
}
const actions = [
  'getGovernmentLegislation','createGovernmentMeasure','editGovernmentMeasure',
  'openGovernmentMeasureVote','castGovernmentOfficialVote','getGovernmentOfficialVotes',
  'certifyGovernmentMeasure','publishGovernmentMeasure'
];
for(const action of actions) {
  assert.ok(server.includes(':server:'+action),'missing server callback '+action);
  assert.ok(client.includes("'"+action+"'"),'missing client NUI '+action);
  assert.ok(events.includes('"'+action+'"'),'unwhitelisted '+action);
  assert.ok(screen.includes('"'+action+'"'),'missing UI action '+action);
}
assert.match(server,/GetGovernmentLegislationAccess/);
assert.match(server,/same\(source,access\)/);
assert.match(server,/FOR UPDATE/);
assert.match(server,/UNIQUE\(measure_id,voter_citizenid\)/);
assert.match(server,/certified_adopted/);
assert.match(server,/certified_rejected/);
assert.match(server,/GovernmentJurisdictionContains/);
assert.match(server,/CanViewGovernmentJurisdictionRecord/);
assert.match(sql,/UNIQUE KEY \x60uq_gov_measure_voter\x60/);
assert.match(home,/<GovernmentLegislation \{authService\} \/>/);
assert.match(home,/activeSection === "legislation"/);
assert.match(events,/Object.values\(NUI_EVENTS.GOVERNMENT_LEGISLATION\)/);
assert.doesNotMatch(client,/RegisterCommand/);
console.log('PASS Stage 6 legislative contracts');
