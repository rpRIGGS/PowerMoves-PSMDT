const assert=require('node:assert/strict');
const fs=require('node:fs');
const read=p=>fs.readFileSync(p,'utf8');
const schema=read('sql/migrations/2026-10-29-government-property-assessments.sql');
const bases=[read('sql/qbcore.sql'),read('sql/qbx.sql')];
const auth=read('server/auth.lua');
const backend=read('server/backend/government_property_assessments.lua');
const client=read('client/backend/government_property_assessments.lua');
const ui=read('web/src/pages/GovernmentAssessments.svelte');
const home=read('web/src/pages/Government.svelte');
const events=read('web/src/constants/nuiEvents.ts');
const config=read('config.lua');
function ddl(data,table){
 const start='CREATE TABLE IF NOT EXISTS \`'+table+'\` (';
 const at=data.indexOf(start);
 assert.ok(at>=0,'Missing table: '+table);
 const end=') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;';
 const to=data.indexOf(end,at);
 assert.ok(to>at,'Missing terminator for: '+table);
 return data.slice(at,to+end.length).trim();
}
for(const base of bases){
 for(const table of ['mdt_government_property_assessments','mdt_government_property_assessment_audit']){
   assert.strictEqual(ddl(base,table),ddl(schema,table));
 }
}
assert.match(schema,/before_snapshot/);
assert.match(schema,/after_snapshot/);
assert.match(backend,/GovernmentJurisdictionContains\('state',key\)/);
assert.match(backend,/SELECT property_id,owner_citizenid FROM properties WHERE property_id=\?/);
assert.match(backend,/IsPropertyAssessmentApproved/);
assert.match(backend,/government_owned/);
assert.match(backend,/tax_exempt/);
assert.match(backend,/reviewed_by_citizenid/);
assert.match(backend,/sameStaff\(source,access\)/);
assert.match(backend,/FOR UPDATE/);
assert.doesNotMatch(backend,/RegisterNetEvent/);
assert.match(auth,/function GetGovernmentPropertyAssessorAccess\(source\)/);
assert.match(auth,/initial\.agency~='sagov'/);
assert.match(config,/government_property_assess/);
assert.match(config,/government_property_assessment_view/);
for(const action of ['getGovernmentPropertyAssessments','queueGovernmentPropertyAssessment','decideGovernmentPropertyAssessment']){
 for(const file of [backend,client,ui,events]){
  assert.match(file,new RegExp(action));
 }
}
assert.match(home,/<GovernmentAssessments/);
console.log('PASS Stage 6 assessor schema parity, state role, NUI and audit contracts');
