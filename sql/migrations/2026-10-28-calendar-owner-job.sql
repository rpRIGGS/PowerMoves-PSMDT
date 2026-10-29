-- Stage 2 opt-in schema migration. Run once on a backed-up DEV database
-- before enabling Config.Court.DepartmentCalendarOwnership.
-- Existing events stay NULL: their originating employers cannot be safely inferred.
ALTER TABLE `mdt_court_hearings`
  ADD COLUMN `owner_job` VARCHAR(64) NULL DEFAULT NULL
    COMMENT 'Originating employer; NULL = legacy/unreconciled'
    AFTER `job_type`,
  ADD INDEX `idx_mdt_hearings_owner_schedule` (`owner_job`, `scheduled_at`);

-- Review historical NULL records manually with the server owner before assigning.
-- Do not auto-update based on current player job, creator name, or legacy 'ems'/'police' domain.
-- Confirm migration: SELECT COUNT(*) AS legacy_unassigned
-- FROM mdt_court_hearings WHERE owner_job IS NULL;
