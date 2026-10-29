#!/usr/bin/env bash
set -euo pipefail
db=(mariadb --protocol=tcp --host="${MARIADB_HOST:-127.0.0.1}" --port="${MARIADB_PORT:-3306}" --user="${MARIADB_USER:-psmdt}" "${MARIADB_DATABASE:-psmdt_test}")
"${db[@]}" < sql/migrations/2026-10-29-government-property-assessments.sql
"${db[@]}" <<'SQL'
INSERT INTO mdt_government_property_assessments
(property_id,jurisdiction,tax_year,property_type,assessed_value,government_owned,
 tax_exempt,property_owner_snapshot)
VALUES
(70014,'state',2026,'residential',245000,1,0,'CIV-ASSESS-1'),
(70014,'blaine_county',2026,'residential',230000,0,0,'CIV-ASSESS-1'),
(70014,'los_santos_county',2026,'commercial',350000,0,0,'CIV-ASSESS-1'),
(70014,'los_santos_city',2026,'commercial',375000,0,1,'CIV-ASSESS-1'),
(70014,'state',2027,'residential',252000,0,0,'CIV-ASSESS-1');
INSERT INTO mdt_government_property_assessment_audit
(property_id,jurisdiction,tax_year,actor_citizenid,action,previous_status,new_status,
reason,before_snapshot,after_snapshot)
VALUES (70014,'state',2026,'ASSESSOR-TEST','approved','pending','approved',
    'Reviewed source property','{}','{"assessed_value":245000}');
SQL
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_property_assessments
WHERE property_id=70014;")" = 5
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_property_assessments
WHERE property_id=70014 AND government_owned=1 AND tax_exempt=0;")" = 1
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_property_assessment_audit
WHERE property_id=70014 AND jurisdiction='state' AND tax_year=2026
AND action='approved';")" = 1
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_property_assessments
WHERE property_id=70014 AND jurisdiction='state' AND tax_year=2027;")" = 1
echo 'PASS Stage 6 multiple jurisdictions, tax years and independent exemption'
