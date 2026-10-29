#!/usr/bin/env bash
set -euo pipefail
db=(mariadb --protocol=tcp --host="${MARIADB_HOST:-127.0.0.1}" --port="${MARIADB_PORT:-3306}" --user="${MARIADB_USER:-psmdt}" "${MARIADB_DATABASE:-psmdt_test}")
"${db[@]}" < sql/migrations/2026-10-29-government-property-assessments.sql
"${db[@]}" <<'SQL'
INSERT INTO mdt_government_property_assessments
(property_id,jurisdiction,tax_year,property_type,submitted_by_citizenid,property_owner_snapshot)
VALUES (876543,'blaine_county',2026,'residential','assessor-test','CIV-HOME');
START TRANSACTION;
UPDATE mdt_government_property_assessments
SET status='approved',version=version+1,assessed_value=250000,
government_owned=1,tax_exempt=0,reviewed_by_citizenid='assessor-test',
decision_reason='Verified appraisal'
WHERE property_id=876543 AND jurisdiction='blaine_county' AND tax_year=2026
AND status='pending' AND version=1;
INSERT INTO mdt_government_property_assessment_audit
(property_id,jurisdiction,tax_year,actor_citizenid,action,previous_status,new_status,reason,
 before_snapshot,after_snapshot)
VALUES (876543,'blaine_county',2026,'assessor-test','approved','pending','approved',
        'Verified appraisal','{"status":"pending","tax_exempt":0}',
        '{"status":"approved","tax_exempt":0,"government_owned":1}');
COMMIT;
SQL
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT CONCAT(status,':',assessed_value,':',government_owned,':',tax_exempt)
FROM mdt_government_property_assessments WHERE property_id=876543 AND jurisdiction='blaine_county' AND tax_year=2026;")" = 'approved:250000:1:0'
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_property_assessment_audit
WHERE property_id=876543 AND jurisdiction='blaine_county' AND tax_year=2026 AND action='approved'
AND before_snapshot IS NOT NULL AND after_snapshot IS NOT NULL;")" = 1
"${db[@]}" <<'SQL'
START TRANSACTION;
UPDATE mdt_government_property_assessments SET status='pending',version=version+1
WHERE property_id=876543 AND jurisdiction='blaine_county' AND tax_year=2026
AND status='approved' AND version=2;
INSERT INTO mdt_government_property_assessment_audit
(property_id,jurisdiction,tax_year,actor_citizenid,action,previous_status,new_status,reason)
VALUES (876543,'blaine_county',2026,'assessor-test','reopen','approved','pending','Changed use');
COMMIT;
SQL
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT CONCAT(status,':',version) FROM mdt_government_property_assessments
WHERE property_id=876543 AND jurisdiction='blaine_county' AND tax_year=2026;")" = 'pending:3'
"${db[@]}" <<'SQL'
START TRANSACTION;
UPDATE mdt_government_property_assessments SET tax_exempt=1,status='approved',
version=version+1 WHERE property_id=876543 AND jurisdiction='blaine_county' AND tax_year=2026
AND status='pending' AND version=3;
ROLLBACK;
SQL
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT CONCAT(status,':',version,':',tax_exempt)
FROM mdt_government_property_assessments WHERE property_id=876543 AND jurisdiction='blaine_county' AND tax_year=2026;")" = 'pending:3:0'
echo 'PASS Stage 6 assessor MariaDB approval, ownership exemption separation, audit and rollback'
