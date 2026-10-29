-- Stage 6 SAGOV: one licensing authority for each local business application.
-- This does not create a QBCore business, establish property ownership,
-- calculate taxes, or grant a SADOT tow-operator permit.
CREATE TABLE IF NOT EXISTS `mdt_government_business_licenses` (
 `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
 `owner_citizenid` VARCHAR(64) NOT NULL,
 `agency` VARCHAR(64) NOT NULL,
 `jurisdiction` VARCHAR(64) NOT NULL,
 `business_name` VARCHAR(160) NOT NULL,
 `business_type` VARCHAR(80) NOT NULL,
 `description` TEXT NOT NULL,
 `property_reference` VARCHAR(120) DEFAULT NULL,
 `status` VARCHAR(20) NOT NULL DEFAULT 'submitted',
 `license_number` VARCHAR(40) DEFAULT NULL,
 `version` INT UNSIGNED NOT NULL DEFAULT 1,
 `reviewer_citizenid` VARCHAR(64) DEFAULT NULL,
 `decision_reason` VARCHAR(1000) DEFAULT NULL,
 `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
 `issued_at` DATETIME DEFAULT NULL,
 `revoked_at` DATETIME DEFAULT NULL,
 PRIMARY KEY (`id`),
 UNIQUE KEY `uq_government_business_license_number` (`license_number`),
 UNIQUE KEY `uq_gov_business_owner_name` (`owner_citizenid`,`agency`,`business_name`),
 KEY `idx_gov_business_owner` (`owner_citizenid`,`created_at`),
 KEY `idx_gov_business_authority` (`agency`,`status`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_government_business_license_audit` (
 `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
 `application_id` BIGINT UNSIGNED NOT NULL,
 `agency` VARCHAR(64) NOT NULL,
 `actor_citizenid` VARCHAR(64) NOT NULL,
 `action` VARCHAR(24) NOT NULL,
 `reason` VARCHAR(1000) NOT NULL,
 `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY (`id`),
 KEY `idx_gov_business_license_audit` (`application_id`,`agency`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
