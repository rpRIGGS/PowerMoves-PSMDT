-- Stage 5: explicitly authored and revocable public-release copies.
-- No linkage or implicit access to confidential case, IA, medical or evidence tables.
-- Apply on a backed-up DEV database. Idempotent additive migration.
CREATE TABLE IF NOT EXISTS `mdt_public_record_release_copies` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `request_id` BIGINT UNSIGNED NOT NULL,
  `agency` VARCHAR(64) NOT NULL,
  `recipient_citizenid` VARCHAR(64) NOT NULL,
  `title` VARCHAR(160) NOT NULL,
  `public_text` TEXT NOT NULL,
  `issued_by_citizenid` VARCHAR(64) NOT NULL,
  `issued_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at` DATETIME NOT NULL,
  `revoked_at` DATETIME DEFAULT NULL,
  `revoked_by_citizenid` VARCHAR(64) DEFAULT NULL,
  `revocation_reason` VARCHAR(1000) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_public_copy_request` (`request_id`,`agency`,`revoked_at`),
  KEY `idx_public_copy_recipient` (`recipient_citizenid`,`request_id`,`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
