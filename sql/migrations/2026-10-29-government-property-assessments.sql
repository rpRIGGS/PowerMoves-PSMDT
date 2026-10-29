-- Stage 6 SAGOV assessor register. PS Housing owns properties and sales.
-- This table does not alter PS Housing listings or enforce taxes by itself.
CREATE TABLE IF NOT EXISTS `mdt_government_property_assessments` (
  `property_id` INT UNSIGNED NOT NULL,
  `jurisdiction` VARCHAR(64) NOT NULL,
  `property_type` VARCHAR(32) NOT NULL,
  `assessed_value` BIGINT UNSIGNED DEFAULT NULL,
  `government_owned` TINYINT(1) NOT NULL DEFAULT 0,
  `tax_exempt` TINYINT(1) NOT NULL DEFAULT 0,
  `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
  `version` INT UNSIGNED NOT NULL DEFAULT 1,
  `submitted_by_citizenid` VARCHAR(64) DEFAULT NULL,
  `reviewed_by_citizenid` VARCHAR(64) DEFAULT NULL,
  `decision_reason` VARCHAR(1000) DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`property_id`),
  KEY `idx_gov_assessments_queue` (`status`,`jurisdiction`,`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_government_property_assessment_audit` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `property_id` INT UNSIGNED NOT NULL,
  `actor_citizenid` VARCHAR(64) NOT NULL,
  `action` VARCHAR(24) NOT NULL,
  `previous_status` VARCHAR(20) DEFAULT NULL,
  `new_status` VARCHAR(20) NOT NULL,
  `reason` VARCHAR(1000) NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_gov_assessment_audit` (`property_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
