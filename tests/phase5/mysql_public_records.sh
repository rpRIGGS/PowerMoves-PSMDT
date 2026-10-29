#!/usr/bin/env bash
set -euo pipefail
db=(mariadb --protocol=tcp --host="${MARIADB_HOST:-127.0.0.1}" --port="${MARIADB_PORT:-3306}" --user="${MARIADB_USER:-psmdt}" "${MARIADB_DATABASE:-psmdt_test}")
"${db[@]}" < sql/migrations/2026-10-29-public-records-intake.sql
"${db[@]}" < sql/migrations/2026-10-29-public-records-review.sql
"${db[@]}" < sql/migrations/2026-10-29-public-records-response.sql
"${db[@]}" <<'SQL'
INSERT INTO mdt_public_record_requests
(request_number, applicant_citizenid, agency, subject, description)
VALUES ('PR-TEST-001','cid-test-a','lspd','Policy request','Public policy inquiry'),
       ('PR-TEST-002','cid-test-b','bcso','Manual request','Public manual inquiry');
UPDATE mdt_public_record_requests SET status = 'under_review'
WHERE request_number = 'PR-TEST-001' AND agency = 'lspd' AND status = 'submitted';
INSERT INTO mdt_public_record_request_audit
(request_id,agency,actor_citizenid,action,reason)
SELECT id,agency,'officer-test','under_review','Reviewed'
FROM mdt_public_record_requests WHERE request_number = 'PR-TEST-001';
UPDATE mdt_public_record_requests SET status = 'approved'
WHERE request_number = 'PR-TEST-001' AND agency = 'lspd' AND status = 'under_review';
INSERT INTO mdt_public_record_responses
(request_id,agency,recipient_citizenid,response_text,issued_by_citizenid)
SELECT id,agency,applicant_citizenid,'Publicly releasable example text','officer-test'
FROM mdt_public_record_requests WHERE request_number = 'PR-TEST-001';
INSERT INTO mdt_public_record_request_audit
(request_id,agency,actor_citizenid,action,reason)
SELECT id,agency,'officer-test','approved','Public response issued'
FROM mdt_public_record_requests WHERE request_number = 'PR-TEST-001';
SQL
read -r own foreign otherAgency auditCount < <("${db[@]}" --batch --skip-column-names -e "
SELECT
 (SELECT COUNT(*) FROM mdt_public_record_responses WHERE recipient_citizenid = 'cid-test-a'),
 (SELECT COUNT(*) FROM mdt_public_record_responses WHERE recipient_citizenid = 'cid-test-b'),
 (SELECT COUNT(*) FROM mdt_public_record_requests WHERE agency='lspd' AND request_number='PR-TEST-002'),
 (SELECT COUNT(*) FROM mdt_public_record_request_audit WHERE action IN ('under_review','approved'));")
test "$own" = 1
test "$foreign" = 0
test "$otherAgency" = 0
test "$auditCount" = 2
# A second response for the same request must fail at the database boundary,
# even when two authorized staff attempts race.
if "${db[@]}" -e "
INSERT INTO mdt_public_record_responses
(request_id,agency,recipient_citizenid,response_text,issued_by_citizenid)
SELECT request_id, agency, recipient_citizenid, 'Duplicate text', 'officer-other'
FROM mdt_public_record_responses
WHERE recipient_citizenid='cid-test-a';" >/dev/null 2>&1; then
  echo 'ERROR: Duplicate public-record release unexpectedly succeeded' >&2
  exit 1
fi
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_public_record_responses
WHERE recipient_citizenid='cid-test-a';")" = 1

# Ensure an interrupted transaction does not change request state.
"${db[@]}" <<'SQL'
START TRANSACTION;
UPDATE mdt_public_record_requests SET status='approved'
WHERE request_number='PR-TEST-002' AND status='submitted';
ROLLBACK;
SQL
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT status FROM mdt_public_record_requests
WHERE request_number='PR-TEST-002';")" = 'submitted'
echo 'Stage 5 MariaDB schema, recipient, duplicate and rollback smoke tests passed'
