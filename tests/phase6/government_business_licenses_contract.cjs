const assert = require('node:assert/strict');
const fs = require('node:fs');
const read = (path) => fs.readFileSync(path, 'utf8');
const schema = read('sql/migrations/2026-10-29-government-business-licensing.sql');
const baseSchemas = [read('sql/qbcore.sql'),read('sql/qbx.sql')];
const auth = read('server/auth.lua');
const backend = read('server/backend/government_business_licenses.lua');
const client = read('client/backend/government_business_licenses.lua');
const service = read('client/backend/public_services.lua');
const page = read('web/src/pages/GovernmentLicensing.svelte');
const home = read('web/src/pages/Government.svelte');
const events = read('web/src/constants/nuiEvents.ts');
const config = read('config.lua');
function ddl(text, table) {
  const start = 'CREATE TABLE IF NOT EXISTS \`' + table + '\` (';
  const from = text.indexOf(start);
  assert.ok(from >= 0, 'Missing '+table);
  const endText=') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;';
  const to=text.indexOf(endText,from);
  assert.ok(to>from);
  return text.slice(from,to+endText.length).trim();
}
for (const base of baseSchemas) {
 for (const table of ['mdt_government_business_licenses','mdt_government_business_license_audit']) {
   assert.strictEqual(ddl(base,table),ddl(schema,table));
 }
}
for (const field of ['uq_gov_business_owner_name','owner_citizenid','license_number','jurisdiction']) {
 assert.match(schema,new RegExp(field));
}
assert.match(auth,/function GetGovernmentBusinessLicenseAccess\(source\)/);
assert.match(auth,/contains\(permissions, policy\.IssuePermission\)/);
assert.match(config,/government_business_license_issue/);
assert.match(config,/government_business_license_review/);
assert.match(config,/government_business_license_oversight/);
assert.match(backend,/PublicServiceDeskAllows\(source,agency,'business_license_apply'\)/);
assert.match(backend,/PublicServiceDeskAllows\(source,nil,'business_license_status'\)/);
assert.match(backend,/owner_citizenid = \?/);
assert.match(backend,/WHERE agency = \?/);
assert.match(backend,/GetGovernmentBusinessLicenseAccess/);
assert.match(backend,/sameStaff\(source,access\)/);
assert.match(backend,/FOR UPDATE/);
assert.match(backend,/rawget\(MySQL,'startTransaction'\)/);
assert.match(backend,/license_number=CONCAT\('SA-BIZ-'/);
for (const action of ['getGovernmentBusinessLicenseAuthorities','getGovernmentBusinessLicenses','decideGovernmentBusinessLicense']) {
 assert.match(backend,new RegExp(action));
 assert.match(client,new RegExp(action));
 assert.match(events,new RegExp(action));
 assert.match(page,new RegExp(action));
}
assert.match(service,/business_license_apply =/);
assert.match(service,/business_license_status =/);
assert.match(home,/<GovernmentLicensing/);
assert.doesNotMatch(backend,/RegisterCommand/);
console.log('PASS Stage 6 canonical business licensing, NUI, schema parity and counter contracts');
