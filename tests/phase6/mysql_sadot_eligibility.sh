#!/usr/bin/env bash
set -euo pipefail
db=(mariadb --protocol=tcp --host="${MARIADB_HOST:-127.0.0.1}" --port="${MARIADB_PORT:-3306}" --user="${MARIADB_USER:-psmdt}" "${MARIADB_DATABASE:-psmdt_test}")
"${db[@]}" < sql/migrations/2026-10-29-government-business-licensing.sql
"${db[@]}" < sql/migrations/2026-10-29-sadot-tow-qualifications.sql
"${db[@]}" <<'SQL'
INSERT INTO mdt_government_business_licenses
(owner_citizenid,agency,jurisdiction,business_name,business_type,description,status,license_number)
VALUES ('TOW-BIZ-OWNER','bcgov','blaine_county','SADOT TEST RECOVERY',
'tow services','Smoke-test business registration','approved','BIZ-TOW-TEST-001');
INSERT INTO mdt_sadot_tow_permits
(business_license_id,licensing_agency,jurisdiction,employer_job,permit_number,
issued_by_citizenid,expires_at)
SELECT id,agency,jurisdiction,'towshop1','TOW-TEST-001','sadot-issuer',
DATE_ADD(UTC_TIMESTAMP(),INTERVAL 30 DAY)
FROM mdt_government_business_licenses WHERE license_number='BIZ-TOW-TEST-001';
INSERT INTO mdt_sadot_qualified_drivers
(permit_id,citizenid,employer_job,qualification,expires_at)
SELECT id,'DRIVER-511-TEST','towshop1','Class T recovery',
DATE_ADD(UTC_TIMESTAMP(),INTERVAL 30 DAY)
FROM mdt_sadot_tow_permits WHERE permit_number='TOW-TEST-001';
INSERT INTO mdt_sadot_permitted_vehicles
(permit_id,plate,vehicle_model,expires_at)
SELECT id,'PLATE511','Tow Recovery Unit',
DATE_ADD(UTC_TIMESTAMP(),INTERVAL 30 DAY)
FROM mdt_sadot_tow_permits WHERE permit_number='TOW-TEST-001';
SQL
eligible="SELECT COUNT(*) FROM mdt_sadot_tow_permits p
JOIN mdt_government_business_licenses b ON b.id=p.business_license_id
AND b.agency=p.licensing_agency AND b.jurisdiction=p.jurisdiction
AND b.status='approved' AND b.revoked_at IS NULL
JOIN mdt_sadot_qualified_drivers d ON d.permit_id=p.id
AND d.citizenid='DRIVER-511-TEST' AND d.employer_job=p.employer_job
AND d.revoked_at IS NULL AND d.expires_at>UTC_TIMESTAMP()
JOIN mdt_sadot_permitted_vehicles v ON v.permit_id=p.id
AND v.plate='PLATE511' AND v.revoked_at IS NULL
AND v.expires_at>UTC_TIMESTAMP()
WHERE p.employer_job='towshop1' AND p.revoked_at IS NULL
AND p.expires_at>UTC_TIMESTAMP()"
test "$("${db[@]}" --batch --skip-column-names -e "$eligible")" = 1
"${db[@]}" -e "UPDATE mdt_sadot_qualified_drivers
 SET revoked_at=UTC_TIMESTAMP() WHERE citizenid='DRIVER-511-TEST';"
test "$("${db[@]}" --batch --skip-column-names -e "$eligible")" = 0
"${db[@]}" -e "UPDATE mdt_sadot_qualified_drivers
 SET revoked_at=NULL WHERE citizenid='DRIVER-511-TEST';"
"${db[@]}" -e "UPDATE mdt_sadot_permitted_vehicles
 SET expires_at=DATE_SUB(UTC_TIMESTAMP(),INTERVAL 1 DAY) WHERE plate='PLATE511';"
test "$("${db[@]}" --batch --skip-column-names -e "$eligible")" = 0
"${db[@]}" -e "UPDATE mdt_sadot_permitted_vehicles
 SET expires_at=DATE_ADD(UTC_TIMESTAMP(),INTERVAL 30 DAY) WHERE plate='PLATE511';"
"${db[@]}" -e "UPDATE mdt_government_business_licenses SET status='suspended'
 WHERE license_number='BIZ-TOW-TEST-001';"
test "$("${db[@]}" --batch --skip-column-names -e "$eligible")" = 0
echo 'PASS Stage 6 SADOT approved business, tow, driver, vehicle and revocation SQL'
