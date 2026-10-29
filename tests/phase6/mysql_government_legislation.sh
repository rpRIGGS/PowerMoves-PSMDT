#!/usr/bin/env bash
set -euo pipefail
db=(mariadb --protocol=tcp --host="${MARIADB_HOST:-127.0.0.1}" --port="${MARIADB_PORT:-3306}" --user="${MARIADB_USER:-psmdt}" "${MARIADB_DATABASE:-psmdt_test}")
"${db[@]}" < sql/migrations/2026-10-29-government-legislation.sql
"${db[@]}" <<'SQL'
INSERT INTO mdt_government_legislation
(agency,jurisdiction,measure_type,title,body,status,version,sponsor_citizenid)
VALUES
('bcgov','blaine_county','county_ordinance','BC Test Measure','Internal draft','draft',1,'sponsor-bc'),
('lscgov','los_santos_county','county_ordinance','LSC Test Measure','Unpublished','draft',1,'sponsor-lsc'),
('lsgov','los_santos_city','municipal_code','LS City Published Code','Public law text','published',4,'sponsor-city');
SQL
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_legislation WHERE status='published'
OR agency='bcgov';")" = 2
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_legislation
WHERE agency='bcgov' AND jurisdiction='los_santos_county';")" = 0

# Real database enforces one official vote per citizen per measure.
"${db[@]}" <<'SQL'
UPDATE mdt_government_legislation SET status='voting',version=2
WHERE agency='bcgov' AND status='draft' AND version=1;
INSERT INTO mdt_government_legislation_votes
(measure_id,agency,voter_citizenid,vote)
SELECT id,agency,'voter-a','yes' FROM mdt_government_legislation
WHERE agency='bcgov' AND status='voting';
SQL
if "${db[@]}" -e "
INSERT INTO mdt_government_legislation_votes
(measure_id,agency,voter_citizenid,vote)
SELECT id,agency,'voter-a','no' FROM mdt_government_legislation
WHERE agency='bcgov' AND status='voting';" >/dev/null 2>&1; then
  echo 'ERROR: duplicate official vote was accepted' >&2
  exit 1
fi
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_legislation_votes WHERE voter_citizenid='voter-a';")" = 1

# A failed or abandoned certification must leave the measure unchanged.
"${db[@]}" <<'SQL'
START TRANSACTION;
UPDATE mdt_government_legislation SET status='adopted',
version=version+1,certified_by_citizenid='chair-test'
WHERE agency='bcgov' AND status='voting' AND version=2;
ROLLBACK;
SQL
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT CONCAT(status,':',version) FROM mdt_government_legislation
WHERE agency='bcgov';")" = 'voting:2'

# Correct certification and publication record an audit, without affecting
# the other county's private draft.
"${db[@]}" <<'SQL'
START TRANSACTION;
UPDATE mdt_government_legislation SET status='adopted',
version=version+1,certified_by_citizenid='chair-test',
certification_reason='Certified meeting result',certified_at=UTC_TIMESTAMP()
WHERE agency='bcgov' AND status='voting' AND version=2;
INSERT INTO mdt_government_legislation_audit
(measure_id,agency,actor_citizenid,action,reason)
SELECT id,agency,'chair-test','certified_adopted','Certified meeting result'
FROM mdt_government_legislation WHERE agency='bcgov' AND status='adopted';
COMMIT;
START TRANSACTION;
UPDATE mdt_government_legislation SET status='published',
version=version+1,published_at=UTC_TIMESTAMP()
WHERE agency='bcgov' AND status='adopted' AND version=3;
INSERT INTO mdt_government_legislation_audit
(measure_id,agency,actor_citizenid,action,reason)
SELECT id,agency,'publisher-test','published','Certified measure published'
FROM mdt_government_legislation WHERE agency='bcgov' AND status='published';
COMMIT;
SQL
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT CONCAT(status,':',version) FROM mdt_government_legislation
WHERE agency='bcgov';")" = 'published:4'
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_legislation_audit
WHERE agency='bcgov';")" = 2
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT CONCAT(status,':',version) FROM mdt_government_legislation
WHERE agency='lscgov';")" = 'draft:1'
echo 'Stage 6 MariaDB legislative votes, uniqueness, certification and publication passed'
