-- Stage 2 read-only ownership audit. Does not modify or relabel data.
-- Run against a backed-up development database.
SELECT job_type, COALESCE(agency_job, '(unassigned legacy)') AS employer,
       COUNT(*) AS assignments,
       SUM(status IN ('active','suspended')) AS open_assignments
FROM mdt_fto_assignments
GROUP BY job_type, agency_job ORDER BY job_type, employer;

-- The originating employer of old NULL records must be reconciled from
-- historical records, not current trainee/trainer employment.
SELECT id, fto_number, job_type, trainee_citizenid, trainer_citizenid,
       start_date, end_date, created_at
FROM mdt_fto_assignments
WHERE agency_job IS NULL ORDER BY created_at, id;
