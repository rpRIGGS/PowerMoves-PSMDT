const assert = require('node:assert/strict');
const fs = require('node:fs');
const server = fs.readFileSync('server/backend/ia.lua','utf8');
const client = fs.readFileSync('client/backend/ia.lua','utf8');
const sql = fs.readFileSync('sql/migrations/2026-10-28-ia-referrals.sql','utf8');
for (const endpoint of ['referIAComplaintToSADLE','getSADLEIAReferrals','acceptSADLEIAReferral']) {
  assert(server.includes("':server:"+endpoint+"'"), 'Server missing '+endpoint);
  assert(client.includes("RegisterNUICallback('"+endpoint+"'"),'Client missing '+endpoint);
}
const begin = server.indexOf("':server:referIAComplaintToSADLE'");
const end = server.indexOf('\nend)',begin);
const referral = server.slice(begin,end);
assert.match(referral,/canManageIA\(src\)/);
assert.match(referral,/record\.agency ~= job/);
assert.match(referral,/record\.job_type ~= 'police'/);
assert.match(referral,/ps\.getIdentifier\(src\) ~= cid/);
assert.match(referral,/INSERT INTO mdt_ia_referrals/);
const queueStart = server.indexOf("':server:getSADLEIAReferrals'");
const queue = server.slice(queueStart, server.indexOf('\nend)',queueStart));
assert.match(queue,/ps\.getJobName\(src\) ~= 'sadle'/);
assert.match(queue,/canViewIA\(src\)/);
assert.match(queue,/ps\.getIdentifier\(src\) ~= cid/);
assert.match(sql,/UNIQUE KEY `idx_ia_referral_complaint`/);
assert.match(sql,/CREATE TABLE IF NOT EXISTS `mdt_ia_referrals`/);
const acceptStart = server.indexOf("':server:acceptSADLEIAReferral'");
const accept = server.slice(acceptStart,server.indexOf('\nend)',acceptStart));
assert.match(accept,/ps\.getJobName\(src\) ~= 'sadle'/);
assert.match(accept,/canManageIA\(src\)/);
assert.match(accept,/r\.status = 'pending'/);
assert.match(accept,/c\.job_type = 'police'/);
for (const schemaPath of ['sql/qbcore.sql', 'sql/qbx.sql']) {
  const schema = fs.readFileSync(schemaPath,'utf8');
  assert.match(schema,/CREATE TABLE IF NOT EXISTS \`mdt_ia_referrals\`/);
  assert.match(schema,/idx_ia_referral_complaint/);
}
console.log('PASS Stage 4 referral bridge, employer isolation and SADLE triage rules');
