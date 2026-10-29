-- Stage 6 legislative docket, official votes and audit.
-- No automatic quorum, tax levy, election ballot, or court judgment.
CREATE TABLE IF NOT EXISTS `mdt_government_legislation` (
 `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
 `agency` VARCHAR(64) NOT NULL,
 `jurisdiction` VARCHAR(64) NOT NULL,
 `measure_type` VARCHAR(32) NOT NULL,
 `title` VARCHAR(180) NOT NULL,
 `body` TEXT NOT NULL,
 `status` VARCHAR(24) NOT NULL DEFAULT 'draft',
 `version` INT UNSIGNED NOT NULL DEFAULT 1,
 `sponsor_citizenid` VARCHAR(64) NOT NULL,
 `certified_by_citizenid` VARCHAR(64) DEFAULT NULL,
 `certification_reason` VARCHAR(1000) DEFAULT NULL,
 `certified_at` DATETIME DEFAULT NULL,
 `published_at` DATETIME DEFAULT NULL,
 `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
 PRIMARY KEY (`id`),
 KEY `idx_gov_legislation_agency` (`agency`,`status`,`updated_at`),
 KEY `idx_gov_legislation_public` (`status`,`published_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_government_legislation_votes` (
 `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
 `measure_id` BIGINT UNSIGNED NOT NULL,
 `agency` VARCHAR(64) NOT NULL,
 `voter_citizenid` VARCHAR(64) NOT NULL,
 `vote` VARCHAR(12) NOT NULL,
 `cast_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY (`id`),
 UNIQUE KEY `uq_gov_measure_voter` (`measure_id`,`voter_citizenid`),
 KEY `idx_gov_measure_votes` (`agency`,`measure_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_government_legislation_audit` (
 `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
 `measure_id` BIGINT UNSIGNED NOT NULL,
 `agency` VARCHAR(64) NOT NULL,
 `actor_citizenid` VARCHAR(64) NOT NULL,
 `action` VARCHAR(24) NOT NULL,
 `reason` VARCHAR(1000) NOT NULL,
 `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY (`id`),
 KEY `idx_gov_legislation_audit` (`measure_id`,`agency`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
