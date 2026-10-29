const assert = require('node:assert/strict');
const fs = require('node:fs');
const read = (p) => fs.readFileSync(p, 'utf8');

const intake = read('server/backend/public_records.lua');
const review = read('server/backend/public_records_review.lua');
const locations = read('server/backend/public_service_locations.lua');
const client = read('client/backend/public_services.lua');
const desk = read('client/backend/public_records_office.lua');
const contentArea = read('web/src/components/ContentArea.svelte');
const mdt = read('web/src/pages/MDT.svelte');
const officePage = read('web/src/pages/RecordsOffice.svelte');
const nuiEvents = read('web/src/constants/nuiEvents.ts');
const schema = read('sql/migrations/2026-10-29-public-records-intake.sql');
const responseSchema = read('sql/migrations/2026-10-29-public-records-response.sql');
const auditSchema = read('sql/migrations/2026-10-29-public-records-review.sql');

function getTableDDL(content, tableName) {
  const start = 'CREATE TABLE IF NOT EXISTS `' + tableName + '` (';
  const at = content.indexOf(start);
  assert.ok(at >= 0, 'Missing table ' + tableName);
  const terminator = ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;';
  const end = content.indexOf(terminator, at);
  assert.ok(end > at, 'Missing table terminator for ' + tableName);
  return content.slice(at, end + terminator.length).replace(/\r\n/g, '\n').trim();
}
const qbcoreSchema = read('sql/qbcore.sql');
const qbxSchema = read('sql/qbx.sql');
for (const base of [qbcoreSchema, qbxSchema]) {
  for (const [table, migration] of [
    ['mdt_public_record_requests', schema],
    ['mdt_public_record_request_audit', auditSchema],
    ['mdt_public_record_responses', responseSchema]
  ]) {
    assert.strictEqual(getTableDDL(base, table), getTableDDL(migration, table),
      'Clean install and additive migration must use identical DDL for ' + table);
  }
}


assert.match(intake, /WHERE applicant_citizenid = \?/);
assert.match(intake, /r\.applicant_citizenid = \?/);
assert.match(intake, /ps\.getIdentifier\(source\) ~= cid/);
assert.match(intake, /PublicServiceDeskAllows\(source, nil, 'public_records_status'\)/);
assert.match(intake, /PublicServiceDeskAllows\(source, agency, 'public_records_request'\)/);
assert.match(locations, /function PublicServiceDeskAllows/);
assert.match(locations, /GetEntityCoords\(ped\)/);
assert.match(review, /RecordsOfficers/);
assert.match(review, /PublicServiceDeskAllows\(src, job, 'records_office'\)/);
assert.match(review, /WHERE agency = \?/);
assert.match(review, /MySQL\.startTransaction/);
assert.match(review, /FOR UPDATE/);
assert.match(review, /affectedRows/);
assert.doesNotMatch(review, /MySQL\.transaction\.await/);
assert.match(review, /publishPublicRecordsResponse/);
assert.match(review, /if action == 'denied'/);
assert.match(intake, /r\.status IN \('approved', 'denied'\)/);
assert.match(client, /item\.status == 'denied'/);
assert.match(review, /canUsePublicRecordsOffice/);
assert.match(review, /getPublicRecordRequestAudit/);
assert.match(review, /INNER JOIN mdt_public_record_requests r/);
assert.match(desk, /getPublicRecordRequestAudit/);
assert.match(officePage, /getPublicRecordRequestAudit/);
assert.match(nuiEvents, /OFFICE_AUDIT: "getPublicRecordRequestAudit"/);
assert.match(desk, /canUsePublicRecordsOffice/);
assert.match(officePage, /canUsePublicRecordsOffice/);
assert.match(nuiEvents, /CHECK_OFFICE_ACCESS: "canUsePublicRecordsOffice"/);

assert.match(client, /getMyPublicRecordsResponse/);
assert.match(client, /records_office =/);
assert.match(desk, /reviewPublicRecordsRequest/);
assert.match(desk, /publishPublicRecordsResponse/);
assert.doesNotMatch(desk, /RegisterCommand\(['"]recordsdesk/);
assert.doesNotMatch(desk, /lib\.registerContext/);
assert.match(desk, /SendNUI\('openRecordsOffice'/);
assert.match(contentArea, /<RecordsOffice onClose=/);
assert.match(contentArea, /recordsOfficeOpen: boolean/);
assert.match(mdt, /openRecordsOffice/);
assert.match(officePage, /publishPublicRecordsResponse/);
assert.match(officePage, /getPublicRecordsOfficeQueue/);
assert.match(nuiEvents, /OPEN_OFFICE: "openRecordsOffice"/);
assert.match(nuiEvents, /Object.values\(NUI_EVENTS.PUBLIC_RECORDS\)/);
assert.match(schema, /mdt_public_record_requests/);
assert.match(responseSchema, /UNIQUE KEY.*request/);
console.log('Stage 5 vector-based MDT public-records source contracts passed');
