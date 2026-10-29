-- Stage 4: explicit case detail discovery grants. Apply on backed-up DEV DB.
-- Grants never authorize editing, evidence stashes, or unrestricted report access.
CREATE TABLE IF NOT EXISTS `mdt_case_disclosures` (
 `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
 `case_id` INT UNSIGNED NOT NULL,
 `recipient_citizenid` VARCHAR(64) NOT NULL,
 `recipient_job` VARCHAR(64) NOT NULL,
 `purpose` VARCHAR(255) NOT NULL,
 `granted_by_citizenid` VARCHAR(64) NOT NULL,
 `granted_by_job` VARCHAR(64) NOT NULL,
 `granted_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 `expires_at` DATETIME DEFAULT NULL,
 `revoked_by_citizenid` VARCHAR(64) DEFAULT NULL,
 `revoked_at` DATETIME DEFAULT NULL,
 PRIMARY KEY (`id`),
 KEY `idx_disclosures_case` (`case_id`,`revoked_at`),
 KEY `idx_disclosures_recipient` (`recipient_citizenid`,`case_id`,`revoked_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
