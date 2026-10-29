const assert = require('node:assert/strict');
const fs = require('node:fs');
for (const schema of ['sql/qbcore.sql', 'sql/qbx.sql']) {
  const sql = fs.readFileSync(schema, 'utf8');
  assert.match(sql, /CREATE TABLE IF NOT EXISTS `mdt_personal_accreditations`/);
  const section = sql.slice(sql.indexOf('CREATE TABLE IF NOT EXISTS `mdt_personal_accreditations`'));
  for (const column of [
    'citizenid', 'credential_code', 'credential_name', 'credential_family',
    'issued_by_job', 'issued_by_citizenid', 'issued_at',
    'expires_at', 'source_reference'
  ]) assert.ok(section.includes('`' + column + '`'), schema + ': missing ' + column);
  assert.match(section, /idx_accreditation_citizen/);
  assert.match(section, /idx_accreditation_issuer/);
}
console.log('PASS accreditation schema columns and indices in QBCore and QBX');
