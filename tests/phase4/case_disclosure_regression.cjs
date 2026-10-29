const assert=require('node:assert/strict');
const fs=require('node:fs');
const server=fs.readFileSync('server/backend/cases.lua','utf8');
const client=fs.readFileSync('client/backend/cases.lua','utf8');
for (const name of ['grantCaseDisclosure','revokeCaseDisclosure','getCaseDisclosures']) {
 assert(server.includes("':server:"+name+"'"),'Missing server '+name);
 assert(client.includes("RegisterNUICallback('"+name+"'"),'Missing client '+name);
}
assert.match(server,/recipient_citizenid = \?/);
assert.match(server,/revoked_at IS NULL/);
assert.match(server,/expires_at > NOW\(\)/);
const getStart=server.indexOf("':server:getCase'");
const getEnd=server.indexOf('\nend)',getStart);
assert.match(server.slice(getStart,getEnd),/hasCaseDisclosure\(src, caseId\)/);
const createStart=server.indexOf("':server:grantCaseDisclosure'");
const create=server.slice(createStart,server.indexOf('\nend)',createStart));
assert.match(create,/caseRow\.assigned_department ~= employer/);
assert.match(create,/CanAccessMdtCase|canAccessCaseId/);
assert.match(create,/ps\.getIdentifier\(src\) ~= actor/);
const revokeStart=server.indexOf("':server:revokeCaseDisclosure'");
const revoke=server.slice(revokeStart,server.indexOf('\nend)',revokeStart));
assert.match(revoke,/c\.assigned_department = \?/);
assert.match(revoke,/g\.revoked_at IS NULL/);
for(const path of ['sql/qbcore.sql','sql/qbx.sql','sql/migrations/2026-10-28-case-disclosures.sql']) {
 const schema=fs.readFileSync(path,'utf8');
 assert.match(schema,/CREATE TABLE IF NOT EXISTS \`mdt_case_disclosures\`/);
 assert.match(schema,/idx_disclosures_recipient/);
 assert.match(schema,/recipient_job/);
}
console.log('PASS case-specific grants, revocation and source-scoped access contracts');
