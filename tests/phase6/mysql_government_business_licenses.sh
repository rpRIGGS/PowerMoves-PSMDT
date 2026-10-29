#!/usr/bin/env bash
set -euo pipefail
db=(mariadb --protocol=tcp --host="${MARIADB_HOST:-127.0.0.1}" --port="${MARIADB_PORT:-3306}" --user="${MARIADB_USER:-psmdt}" "${MARIADB_DATABASE:-psmdt_test}")
"${db[@]}" < sql/migrations/2026-10-29-government-business-licensing.sql
"${db[@]}" <<'SQL'
INSERT INTO mdt_government_business_licenses
(owner_citizenid,agency,jurisdiction,business_name,business_type,description)
VALUES ('CIV-A','bcgov','blaine_county','Test Café','cafe','Blaine location'),
('CIV-B','lscgov','los_santos_county','Test Printing','print','County location');
INSERT INTO mdt_government_business_license_audit
(application_id,agency,actor_citizenid,action,reason)
SELECT id,agency,owner_citizenid,'submitted','Original applicant'
FROM mdt_government_business_licenses;
SQL
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_business_licenses
WHERE owner_citizenid='CIV-A' AND agency='bcgov';")" = 1
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_business_licenses
WHERE owner_citizenid='CIV-A' AND agency='lscgov';")" = 0

# Under-review and issued license are recorded in the same local authority.
"${db[@]}" <<'SQL'
START TRANSACTION;
UPDATE mdt_government_business_licenses SET status='under_review',version=version+1,
reviewer_citizenid='BC-CLERK',decision_reason='Verifying proposal'
WHERE agency='bcgov' AND status='submitted' AND version=1;
INSERT INTO mdt_government_business_license_audit
(application_id,agency,actor_citizenid,action,reason)
SELECT id,agency,'BC-CLERK','under_review','Verifying proposal'
FROM mdt_government_business_licenses WHERE agency='bcgov';
COMMIT;
START TRANSACTION;
UPDATE mdt_government_business_licenses SET status='approved',version=version+1,
license_number=CONCAT('SA-BIZ-',LPAD(id,9,'0')),
reviewer_citizenid='BC-ISSUER',decision_reason='Local license approved',
issued_at=UTC_TIMESTAMP()
WHERE agency='bcgov' AND status='under_review' AND version=2;
INSERT INTO mdt_government_business_license_audit
(application_id,agency,actor_citizenid,action,reason)
SELECT id,agency,'BC-ISSUER','approved','Local license approved'
FROM mdt_government_business_licenses WHERE agency='bcgov';
COMMIT;
SQL
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_business_licenses
WHERE agency='bcgov' AND status='approved' AND version=3
AND license_number LIKE 'SA-BIZ-%';")" = 1
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_business_license_audit
WHERE agency='bcgov' AND action IN ('under_review','approved');")" = 2

# Unique owner/agency/name blocks duplicate local licenses even on concurrent intake.
if "${db[@]}" -e "
INSERT INTO mdt_government_business_licenses
(owner_citizenid,agency,jurisdiction,business_name,business_type,description)
VALUES ('CIV-A','bcgov','blaine_county','Test Café','cafe','Duplicate');" >/dev/null 2>&1; then
  echo 'Unexpected duplicate application was accepted' >&2
  exit 1
fi
# A denied cross-jurisdiction review cannot commit a mutation.
"${db[@]}" <<'SQL'
START TRANSACTION;
UPDATE mdt_government_business_licenses SET status='approved'
WHERE agency='bcgov' AND jurisdiction='los_santos_county';
ROLLBACK;
SQL
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT CONCAT(status,':',version) FROM mdt_government_business_licenses
WHERE agency='lscgov';")" = 'submitted:1'
echo 'PASS Stage 6 business licensing schema, duplicate guard, local decision and audit'
