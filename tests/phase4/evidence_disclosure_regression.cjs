const assert=require('node:assert/strict');
const fs=require('node:fs');
const server=fs.readFileSync('server/backend/evidence.lua','utf8');
const client=fs.readFileSync('client/backend/cases.lua','utf8');
for(const name of ['grantEvidenceDisclosure','revokeEvidenceDisclosure','getDisclosedEvidence','getDisclosedEvidenceDetail','getEvidenceDisclosures']){
 assert(server.includes("':server:"+name+"'"),"Missing server "+name);
 assert(client.includes("RegisterNUICallback('"+name+"'"),"Missing NUI "+name);
}
assert.match(server,/recipient_citizenid = \? AND g\.recipient_job = \?/);
assert.match(server,/AND g\.revoked_at IS NULL/);
const start=server.indexOf("':server:getDisclosedEvidenceDetail'");
const detail=server.slice(start,server.indexOf('\nend)',start));
assert.match(detail,/disclosedEvidenceScope\(src,id\)/);
assert.match(detail,/FROM mdt_evidence_custody/);
assert.doesNotMatch(detail,/stash_id|openEvidenceStash|DeleteEntity|Transfer/);
const recipient=server.slice(server.indexOf("':server:grantEvidenceDisclosure'"),server.indexOf("':server:revokeEvidenceDisclosure'"));
assert.match(recipient,/canEditEvidenceRecord\(src,id\)/);
assert.match(recipient,/CheckPermission\(src,'evidence_transfer'\)/);
for(const path of ['sql/qbcore.sql','sql/qbx.sql','sql/migrations/2026-10-29-evidence-disclosures.sql']){
 const sql=fs.readFileSync(path,'utf8');
 assert.match(sql,/CREATE TABLE IF NOT EXISTS \`mdt_evidence_disclosures\`/);
 assert.match(sql,/recipient_job/);
}
console.log('PASS read-only evidence grant and chain of custody boundaries');
