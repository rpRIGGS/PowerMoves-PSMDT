#!/usr/bin/env bash
set -euo pipefail
db=(mariadb --protocol=tcp --host="${MARIADB_HOST:-127.0.0.1}" --port="${MARIADB_PORT:-3306}" --user="${MARIADB_USER:-psmdt}" "${MARIADB_DATABASE:-psmdt_test}")
"${db[@]}" < sql/migrations/2026-10-29-public-records-intake.sql
"${db[@]}" < sql/migrations/2026-10-29-public-records-review.sql
"${db[@]}" < sql/migrations/2026-10-29-public-records-response.sql
"${db[@]}" < sql/migrations/2026-10-29-public-record-release-copies.sql
"${db[@]}" < sql/migrations/2026-10-29-public-records-assignment.sql
# Migration is deliberately idempotent for existing DEV installations.
"${db[@]}" < sql/migrations/2026-10-29-public-records-assignment.sql
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
# First reviewer is stored in the request, not just its audit log.
"${db[@]}" -e "
UPDATE mdt_public_record_requests
SET assigned_to_citizenid='officer-test', assigned_at=UTC_TIMESTAMP()
WHERE request_number='PR-TEST-001' AND agency='lspd' AND status='approved';"
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT assigned_to_citizenid FROM mdt_public_record_requests
WHERE request_number='PR-TEST-001';")" = 'officer-test'

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
# Denial notices must be delivered to the original citizen, not an
# employee audit reader or another applicant.
"${db[@]}" <<'SQL'
UPDATE mdt_public_record_requests SET status='under_review'
WHERE request_number='PR-TEST-002' AND agency='bcso' AND status='submitted';
START TRANSACTION;
INSERT INTO mdt_public_record_responses
(request_id,agency,recipient_citizenid,response_text,issued_by_citizenid)
SELECT id,agency,applicant_citizenid,'Public denial explanation','bcso-records-1'
FROM mdt_public_record_requests WHERE request_number='PR-TEST-002' AND status='under_review';
UPDATE mdt_public_record_requests SET status='denied'
WHERE request_number='PR-TEST-002' AND agency='bcso' AND status='under_review';
INSERT INTO mdt_public_record_request_audit
(request_id,agency,actor_citizenid,action,reason)
SELECT id,agency,'bcso-records-1','denied','Public denial explanation'
FROM mdt_public_record_requests WHERE request_number='PR-TEST-002';
COMMIT;
SQL
read -r denied foreignNotice < <("${db[@]}" --batch --skip-column-names -e "
SELECT
 (SELECT COUNT(*) FROM mdt_public_record_responses p
  JOIN mdt_public_record_requests r ON r.id=p.request_id
  WHERE r.request_number='PR-TEST-002' AND r.status='denied'
    AND p.recipient_citizenid='cid-test-b' AND p.agency='bcso'),
 (SELECT COUNT(*) FROM mdt_public_record_responses p
  JOIN mdt_public_record_requests r ON r.id=p.request_id
  WHERE r.request_number='PR-TEST-002' AND p.recipient_citizenid='cid-test-a');")
test "$denied" = 1
test "$foreignNotice" = 0
# Expiring, manually authored release copies are stored separately from source records.
"${db[@]}" <<'SQL'
INSERT INTO mdt_public_record_release_copies
(request_id,agency,recipient_citizenid,title,public_text,issued_by_citizenid,expires_at)
SELECT id,agency,applicant_citizenid,'Public policy excerpt','Reviewed public-only content',
'office-test',DATE_ADD(UTC_TIMESTAMP(),INTERVAL 30 DAY)
FROM mdt_public_record_requests WHERE request_number='PR-TEST-001';
INSERT INTO mdt_public_record_release_copies
(request_id,agency,recipient_citizenid,title,public_text,issued_by_citizenid,expires_at)
SELECT id,agency,applicant_citizenid,'Expired copy','No longer available',
'office-test',DATE_SUB(UTC_TIMESTAMP(),INTERVAL 1 DAY)
FROM mdt_public_record_requests WHERE request_number='PR-TEST-001';
SQL
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_public_record_release_copies c
JOIN mdt_public_record_requests r ON r.id=c.request_id
WHERE r.request_number='PR-TEST-001' AND r.applicant_citizenid='cid-test-a'
AND c.recipient_citizenid='cid-test-a' AND c.revoked_at IS NULL
AND c.expires_at>UTC_TIMESTAMP();")" = 1
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_public_record_release_copies c
JOIN mdt_public_record_requests r ON r.id=c.request_id
WHERE r.request_number='PR-TEST-001' AND r.applicant_citizenid='cid-test-b'
AND c.recipient_citizenid='cid-test-b' AND c.revoked_at IS NULL
AND c.expires_at>UTC_TIMESTAMP();")" = 0
"${db[@]}" -e "
UPDATE mdt_public_record_release_copies SET revoked_at=UTC_TIMESTAMP(),
revoked_by_citizenid='office-test',revocation_reason='Corrected document'
WHERE title='Public policy excerpt' AND revoked_at IS NULL;"
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_public_record_release_copies
WHERE revoked_at IS NULL AND expires_at>UTC_TIMESTAMP();")" = 0
test "$("${db[@]}" --batch --skip-column-names -e "
SELECT COUNT(*) FROM mdt_public_record_release_copies
WHERE title='Public policy excerpt' AND revoked_by_citizenid='office-test';")" = 1
echo 'Stage 5 MariaDB applicant, expiry, revocation and rollback smoke tests passed'
