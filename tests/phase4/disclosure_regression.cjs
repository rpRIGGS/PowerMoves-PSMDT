const assert = require('node:assert/strict');
const fs = require('node:fs');
const cases = fs.readFileSync('server/backend/cases.lua','utf8');
const reports = fs.readFileSync('server/backend/reports.lua','utf8');
const start = cases.indexOf("':server:getCase'");
const end = cases.indexOf("':server:linkReportToCase'");
const read = cases.slice(start,end);
assert.ok(start >= 0 && end > start);
for(const needle of ["not hasCaseDisclosure(src, caseId)","externalRecipient and {} or (attachments or {})","externalRecipient and {} or (notes or {})","externalRecipient and {} or (reports or {})","case_disclosure_accessed"]) assert.ok(read.includes(needle),'Missing restricted case check: '+needle);
for(const [src,type] of [[cases,'case'],[reports,'report']]) {
  for(const needle of ['recipient_citizenid = ?','recipient_job = ?','revoked_at IS NULL','expires_at IS NULL OR expires_at > NOW()']) assert.ok(src.includes(needle),type+': '+needle);
  for(const action of ['granted','revoked']) assert.ok(src.includes(type+'_disclosure_'+action),type+': '+action);
}
assert.ok(reports.includes('owner ~= ps.getJobName(src)'), 'Report write requires originating employer');
for(const path of ['sql/qbcore.sql','sql/qbx.sql']) {
 const sql=fs.readFileSync(path,'utf8');
 for(const tbl of ['mdt_case_disclosures','mdt_report_disclosures']) assert.ok(sql.includes('CREATE TABLE IF NOT EXISTS `'+tbl+'`'),path+': '+tbl);
}
assert.ok(cases.includes("current.agency !== scope.agency") || cases.includes("current.agency ~= scope.agency"), 'Case list requires employer recheck');
const reportList = reports.slice(reports.indexOf("':server:getReports'"), reports.indexOf("':server:getReport'"));
assert.ok(reportList.includes('ps.getIdentifier(src) ~= identifier'), 'Report lists must recheck character after SQL');
assert.ok(reportList.includes('getEffectiveJobType(src) ~= jobType'), 'Report lists must recheck service role after SQL');
assert.ok(read.includes('ps.getIdentifier(src) ~= actorCid'), 'Case detail must reject character switch');
const caseList = cases.slice(cases.indexOf("':server:getCases'"), cases.indexOf("':server:getCase'"));
assert.ok(caseList.includes('ps.getIdentifier(src) ~= actorCid'), 'Case list must reject character switch');
console.log('PASS case and report grant, revocation and redacted case detail invariants');
