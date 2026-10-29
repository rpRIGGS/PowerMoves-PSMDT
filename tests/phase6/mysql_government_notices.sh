#!/usr/bin/env bash
set -euo pipefail
db=(mariadb --protocol=tcp --host="${MARIADB_HOST:-127.0.0.1}" --port="${MARIADB_PORT:-3306}" --user="${MARIADB_USER:-psmdt}" "${MARIADB_DATABASE:-psmdt_test}")
"${db[@]}" < sql/migrations/2026-10-29-government-public-notices.sql
"${db[@]}" <<'SQL'
INSERT INTO mdt_government_notices
(agency,jurisdiction,title,body,status,created_by_citizenid)
VALUES ('bcgov','blaine_county','Blaine meeting','Draft only','draft','county-clerk'),
       ('lscgov','los_santos_county','LS County budget meeting','Not public','draft','lsc-clerk'),
       ('lsgov','los_santos_city','City public notice','Published statement','published','city-clerk');
SQL
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_notices
WHERE status='published' OR (agency='bcgov' AND status='draft');")" = 2
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_notices
WHERE agency='bcgov' AND jurisdiction='los_santos_county';")" = 0
"${db[@]}" <<'SQL'
START TRANSACTION;
UPDATE mdt_government_notices SET status='published',version=version+1,
published_by_citizenid='county-publisher',published_at=UTC_TIMESTAMP()
WHERE agency='bcgov' AND status='draft' AND version=1;
INSERT INTO mdt_government_notice_audit
(notice_id,agency,actor_citizenid,action,reason)
SELECT id,agency,'county-publisher','published','Public notice published'
FROM mdt_government_notices WHERE agency='bcgov' AND status='published';
COMMIT;
SQL
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT version FROM mdt_government_notices WHERE agency='bcgov';")" = 2
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_notice_audit
WHERE agency='bcgov' AND action='published';")" = 1
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_notices
WHERE agency='bcgov' AND status='draft' AND version=1;")" = 0

# An abandoned edit must not become a public notice.
"${db[@]}" <<'SQL'
START TRANSACTION;
UPDATE mdt_government_notices SET status='published',version=version+1
WHERE agency='lscgov' AND status='draft' AND version=1;
ROLLBACK;
SQL
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT CONCAT(status,':',version) FROM mdt_government_notices
WHERE agency='lscgov';")" = 'draft:1'
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_government_notice_audit WHERE agency='lscgov';")" = 0
echo 'Stage 6 MariaDB public notices: jurisdiction, optimistic version and rollback passed'
