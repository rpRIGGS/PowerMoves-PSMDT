-- Stage 4: named report discovery grants. Apply only on a backed-up DEV DB.
-- This table does not modify legacy report restrictions or permit edits.
CREATE TABLE IF NOT EXISTS `mdt_report_disclosures` (
 `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
 `report_id` INT UNSIGNED NOT NULL,
 `recipient_citizenid` VARCHAR(64) NOT NULL,
 `purpose` VARCHAR(255) NOT NULL,
 `granted_by_citizenid` VARCHAR(64) NOT NULL,
 `granted_by_job` VARCHAR(64) NOT NULL,
 `granted_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 `expires_at` DATETIME DEFAULT NULL,
 `revoked_at` DATETIME DEFAULT NULL,
 `revoked_by_citizenid` VARCHAR(64) DEFAULT NULL,
 PRIMARY KEY (`id`),
 KEY `idx_report_disclosure_subject` (`recipient_citizenid`,`report_id`,`revoked_at`),
 KEY `idx_report_disclosure_report` (`report_id`,`revoked_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
