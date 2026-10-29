-- Stage 6: published administrative notice withdrawal (never delete history).
-- Idempotent additive migration; back up the development database first.
ALTER TABLE `mdt_government_notices`
  ADD COLUMN IF NOT EXISTS `withdrawn_by_citizenid` VARCHAR(64) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `withdrawn_at` DATETIME DEFAULT NULL;
