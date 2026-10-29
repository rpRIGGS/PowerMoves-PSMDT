-- Stage 6: jurisdiction-owned business registrations and vending permits.
-- Application decisions are NOT property-tax assessments or SADOT tow permits.
CREATE TABLE IF NOT EXISTS `mdt_government_license_applications` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `applicant_citizenid` VARCHAR(64) NOT NULL,
  `agency` VARCHAR(64) NOT NULL,
  `jurisdiction` VARCHAR(64) NOT NULL,
  `license_type` VARCHAR(24) NOT NULL,
  `business_name` VARCHAR(160) NOT NULL,
  `description` TEXT NOT NULL,
  `status` VARCHAR(24) NOT NULL DEFAULT 'submitted',
  `assigned_to_citizenid` VARCHAR(64) DEFAULT NULL,
  `decided_by_citizenid` VARCHAR(64) DEFAULT NULL,
  `decision_reason` VARCHAR(1000) DEFAULT NULL,
  `decided_at` DATETIME DEFAULT NULL,
  `expires_at` DATETIME DEFAULT NULL,
  `revoked_by_citizenid` VARCHAR(64) DEFAULT NULL,
  `revoked_at` DATETIME DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_gov_license_applicant` (`applicant_citizenid`, `created_at`),
  KEY `idx_gov_license_agency` (`agency`, `status`, `created_at`),
  KEY `idx_gov_license_business` (`jurisdiction`, `license_type`, `business_name`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_government_license_audit` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `application_id` BIGINT UNSIGNED NOT NULL,
  `agency` VARCHAR(64) NOT NULL,
  `actor_citizenid` VARCHAR(64) NOT NULL,
  `action` VARCHAR(24) NOT NULL,
  `reason` VARCHAR(1000) NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_gov_license_audit` (`application_id`, `agency`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
