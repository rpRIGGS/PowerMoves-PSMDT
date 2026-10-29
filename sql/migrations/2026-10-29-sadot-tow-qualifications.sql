-- Stage 6 transport prerequisites, without enabling access or issuing permits.
-- Authoritative tow qualification requires an approved SAGOV local business
-- license PLUS independent SADOT operator, driver and vehicle records.
CREATE TABLE IF NOT EXISTS `mdt_sadot_tow_permits` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `business_license_id` BIGINT UNSIGNED NOT NULL,
  `licensing_agency` VARCHAR(64) NOT NULL,
  `jurisdiction` VARCHAR(64) NOT NULL,
  `employer_job` VARCHAR(64) NOT NULL,
  `permit_number` VARCHAR(48) NOT NULL,
  `issued_by_citizenid` VARCHAR(64) NOT NULL,
  `issued_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at` DATETIME NOT NULL,
  `revoked_at` DATETIME DEFAULT NULL,
  `revoked_by_citizenid` VARCHAR(64) DEFAULT NULL,
  `revocation_reason` VARCHAR(1000) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_sadot_tow_number` (`permit_number`),
  KEY `idx_sadot_tow_employer` (`employer_job`, `expires_at`),
  KEY `idx_sadot_tow_business` (`business_license_id`, `revoked_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_sadot_qualified_drivers` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `permit_id` BIGINT UNSIGNED NOT NULL,
  `citizenid` VARCHAR(64) NOT NULL,
  `employer_job` VARCHAR(64) NOT NULL,
  `qualification` VARCHAR(120) NOT NULL,
  `expires_at` DATETIME NOT NULL,
  `revoked_at` DATETIME DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_sadot_permit_driver` (`permit_id`, `citizenid`),
  KEY `idx_sadot_driver_validity` (`citizenid`, `employer_job`, `expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_sadot_permitted_vehicles` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `permit_id` BIGINT UNSIGNED NOT NULL,
  `plate` VARCHAR(24) NOT NULL,
  `vehicle_model` VARCHAR(100) NOT NULL,
  `expires_at` DATETIME NOT NULL,
  `revoked_at` DATETIME DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_sadot_permit_plate` (`permit_id`, `plate`),
  KEY `idx_sadot_vehicle_validity` (`plate`, `expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
