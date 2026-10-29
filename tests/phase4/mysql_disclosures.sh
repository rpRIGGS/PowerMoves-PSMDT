#!/usr/bin/env bash
set -euo pipefail
: "${MARIADB_HOST:=127.0.0.1}"
: "${MARIADB_PORT:=3306}"
: "${MARIADB_USER:=psmdt}"
: "${MARIADB_DATABASE:=psmdt_test}"
sql() { mariadb --batch --skip-column-names --host="$MARIADB_HOST" --port="$MARIADB_PORT" --user="$MARIADB_USER" "$MARIADB_DATABASE" -e "$1"; }
for migration in sql/migrations/2026-10-28-ia-referrals.sql sql/migrations/2026-10-28-case-disclosures.sql sql/migrations/2026-10-28-report-disclosures.sql sql/migrations/2026-10-29-evidence-disclosures.sql; do
  mariadb --host="$MARIADB_HOST" --port="$MARIADB_PORT" --user="$MARIADB_USER" "$MARIADB_DATABASE" < "$migration"
done
sql "INSERT INTO mdt_case_disclosures (case_id,recipient_citizenid,recipient_job,purpose,granted_by_citizenid,granted_by_job) VALUES (42,'CID-ATTORNEY','sadoj','Case-specific discovery','CID-OFFICER','lspd')"
sql "INSERT INTO mdt_report_disclosures (report_id,recipient_citizenid,recipient_job,purpose,granted_by_citizenid,granted_by_job) VALUES (17,'CID-ATTORNEY','sadoj','Report-specific discovery','CID-OFFICER','lspd')"
test "$(sql "SELECT COUNT(*) FROM mdt_case_disclosures WHERE case_id=42 AND recipient_citizenid='CID-ATTORNEY' AND recipient_job='sadoj' AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at>NOW())")" = 1
test "$(sql "SELECT COUNT(*) FROM mdt_case_disclosures WHERE case_id=42 AND recipient_citizenid='CID-ATTORNEY' AND recipient_job='bcso' AND revoked_at IS NULL")" = 0
sql "UPDATE mdt_case_disclosures SET revoked_at=NOW(),revoked_by_citizenid='CID-OFFICER' WHERE case_id=42"
test "$(sql "SELECT COUNT(*) FROM mdt_case_disclosures WHERE case_id=42 AND recipient_citizenid='CID-ATTORNEY' AND revoked_at IS NULL")" = 0
sql "UPDATE mdt_report_disclosures SET expires_at=DATE_SUB(NOW(), INTERVAL 1 DAY) WHERE report_id=17"
test "$(sql "SELECT COUNT(*) FROM mdt_report_disclosures WHERE report_id=17 AND recipient_citizenid='CID-ATTORNEY' AND recipient_job='sadoj' AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at>NOW())")" = 0
sql "INSERT INTO mdt_evidence_disclosures (evidence_id,recipient_citizenid,recipient_job,purpose,granted_by_citizenid,granted_by_job) VALUES (3,'CID-ATTORNEY','sadoj','Evidence custody discovery','CID-OFFICER','lspd')"
test "$(sql "SELECT COUNT(*) FROM mdt_evidence_disclosures WHERE evidence_id=3 AND recipient_citizenid='CID-ATTORNEY' AND recipient_job='sadoj' AND revoked_at IS NULL")" = 1
test "$(sql "SELECT COUNT(*) FROM mdt_evidence_disclosures WHERE evidence_id=3 AND recipient_citizenid='CID-ATTORNEY' AND recipient_job='bcso' AND revoked_at IS NULL")" = 0
sql "UPDATE mdt_evidence_disclosures SET revoked_at=NOW(),revoked_by_citizenid='CID-OFFICER' WHERE evidence_id=3"
test "$(sql "SELECT COUNT(*) FROM mdt_evidence_disclosures WHERE evidence_id=3 AND recipient_citizenid='CID-ATTORNEY' AND revoked_at IS NULL")" = 0
sql "INSERT INTO mdt_ia_referrals (complaint_id,referring_agency,referred_by_citizenid,reason) VALUES (9,'bcso','CID-BCSO','Refer for state investigation')"
if sql "INSERT INTO mdt_ia_referrals (complaint_id,referring_agency,referred_by_citizenid,reason) VALUES (9,'bcso','CID-BCSO','Duplicate referral')" >/dev/null 2>&1; then
  echo 'FAIL: duplicate IA referral accepted'; exit 1
fi
test "$(sql "UPDATE mdt_ia_referrals SET status='accepted', received_by_citizenid='CID-SADLE', received_at=NOW() WHERE complaint_id=9 AND status='pending'; SELECT ROW_COUNT()")" = 1
test "$(sql "UPDATE mdt_ia_referrals SET status='accepted' WHERE complaint_id=9 AND status='pending'; SELECT ROW_COUNT()")" = 0
echo "PASS Stage 4 MariaDB migration, recipient scoping, revocation, expiry, evidence isolation and IA acceptance"
