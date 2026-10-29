const assert=require('node:assert/strict');
const fs=require('node:fs');
const server=fs.readFileSync('server/backend/reports.lua','utf8');
const client=fs.readFileSync('client/backend/reports.lua','utf8');
for (const action of ['grantReportDisclosure','revokeReportDisclosure','getDisclosedReports','getReportDisclosures']){
 assert(server.includes("':server:"+action+"'"),"Missing server "+action);
 assert(client.includes("RegisterNUICallback('"+action+"'"),"Missing client "+action);
}
assert.match(server,/hasReportDisclosure\(src,reportId\)/);
assert.match(server,/revoked_at IS NULL/);
assert.match(server,/expires_at > NOW\(\)/);
const grant=server.slice(server.indexOf("':server:grantReportDisclosure'"),server.indexOf("':server:revokeReportDisclosure'"));
assert.match(grant,/owner~=employer/);
assert.match(grant,/o\.type = 'owner'/);
assert.match(grant,/ps\.getIdentifier\(src\)~=actor/);
const revoke=server.slice(server.indexOf("':server:revokeReportDisclosure'"),server.indexOf("':server:getDisclosedReports'"));
assert.match(revoke,/o\.identifier = \?/);
assert.match(revoke,/g\.revoked_at IS NULL/);
for(const path of ['sql/qbcore.sql','sql/qbx.sql','sql/migrations/2026-10-28-report-disclosures.sql']) {
 const sql=fs.readFileSync(path,'utf8');
 assert.match(sql,/CREATE TABLE IF NOT EXISTS \`mdt_report_disclosures\`/);
 assert.match(sql,/idx_report_disclosure_subject/);
}
console.log('PASS named report grants, scoped revocations and schema contracts');
