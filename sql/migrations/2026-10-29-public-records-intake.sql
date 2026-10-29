-- Stage 5: civilian public-records intake. Apply on backed-up DEV MariaDB only.
-- Requests are not grants to confidential case, evidence, IA, or medical data.
CREATE TABLE IF NOT EXISTS `mdt_public_record_requests` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `request_number` VARCHAR(36) DEFAULT NULL,
  `applicant_citizenid` VARCHAR(64) NOT NULL,
  `agency` VARCHAR(64) NOT NULL,
  `subject` VARCHAR(160) NOT NULL,
  `description` TEXT NOT NULL,
  `status` VARCHAR(24) NOT NULL DEFAULT 'submitted',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_public_record_request_number` (`request_number`),
  KEY `idx_public_request_applicant` (`applicant_citizenid`, `created_at`),
  KEY `idx_public_request_agency` (`agency`, `status`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
