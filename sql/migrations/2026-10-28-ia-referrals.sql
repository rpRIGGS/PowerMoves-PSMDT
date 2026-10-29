-- Stage 4: controlled IA referral queue. Additive, no legacy IA records modified.
-- Back up your development database before applying.
CREATE TABLE IF NOT EXISTS `mdt_ia_referrals` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `complaint_id` INT UNSIGNED NOT NULL,
  `referring_agency` VARCHAR(40) NOT NULL,
  `referred_by_citizenid` VARCHAR(64) NOT NULL,
  `reason` VARCHAR(1000) NOT NULL,
  `status` VARCHAR(24) NOT NULL DEFAULT 'pending',
  `received_by_citizenid` VARCHAR(64) DEFAULT NULL,
  `received_at` DATETIME DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_ia_referral_complaint` (`complaint_id`),
  KEY `idx_ia_referral_status` (`status`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- This table stores the referral, NOT a blanket release of local IA notes.
-- State investigators still require their separate IA authorization.
