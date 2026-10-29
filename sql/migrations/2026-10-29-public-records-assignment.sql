-- Stage 5: track the designated records officer who first begins review.
-- MariaDB additive, idempotent migration; does not modify existing requests.
ALTER TABLE `mdt_public_record_requests`
  ADD COLUMN IF NOT EXISTS `assigned_to_citizenid` VARCHAR(64) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `assigned_at` DATETIME DEFAULT NULL;
