-- READ ONLY: Run after installing owner_job migration on a backed-up dev DB.
-- Do not assign historical owners automatically.
SELECT job_type, category, COALESCE(owner_job, '(unassigned legacy)') AS owner,
       COUNT(*) AS event_count, MIN(scheduled_at) AS earliest_event,
       MAX(scheduled_at) AS latest_event
FROM mdt_court_hearings
GROUP BY job_type, category, owner_job
ORDER BY job_type, category, owner;

-- Identify unassigned legacy departmental events for manual employer triage.
SELECT id, title, category, job_type, created_by, created_by_name,
       scheduled_at, created_at
FROM mdt_court_hearings
WHERE category <> 'court' AND owner_job IS NULL
ORDER BY created_at, id;

-- Inspect employer ownership and live invitations without exposing names.
SELECT h.id, h.title, h.category, h.job_type, h.owner_job,
       COUNT(a.id) AS attendee_count,
       SUM(CASE WHEN a.delivered_at IS NULL AND a.notified_at IS NOT NULL THEN 1 ELSE 0 END)
         AS pending_notifications
FROM mdt_court_hearings h
LEFT JOIN mdt_court_attendees a ON a.hearing_id = h.id
GROUP BY h.id, h.title, h.category, h.job_type, h.owner_job
ORDER BY h.id;
