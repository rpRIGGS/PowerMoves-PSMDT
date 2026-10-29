-- Stage 4: read-only evidence discovery. No stash or transfer rights granted.
-- Apply to backed-up DEV database only.
CREATE TABLE IF NOT EXISTS `mdt_evidence_disclosures` (
 `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
 `evidence_id` INT UNSIGNED NOT NULL,
 `recipient_citizenid` VARCHAR(64) NOT NULL,
 `recipient_job` VARCHAR(64) NOT NULL,
 `purpose` VARCHAR(255) NOT NULL,
 `granted_by_citizenid` VARCHAR(64) NOT NULL,
 `granted_by_job` VARCHAR(64) NOT NULL,
 `granted_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 `revoked_at` DATETIME DEFAULT NULL,
 `revoked_by_citizenid` VARCHAR(64) DEFAULT NULL,
 PRIMARY KEY (`id`),
 KEY `idx_evidence_disclosure_target` (`recipient_citizenid`,`recipient_job`,`evidence_id`,`revoked_at`),
 KEY `idx_evidence_disclosure_item` (`evidence_id`,`revoked_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
