-- Stage 5: an explicitly authored public response, never raw source-table access.
-- Apply only after backing up the development database.
CREATE TABLE IF NOT EXISTS `mdt_public_record_responses` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `request_id` BIGINT UNSIGNED NOT NULL,
  `agency` VARCHAR(64) NOT NULL,
  `recipient_citizenid` VARCHAR(64) NOT NULL,
  `response_text` TEXT NOT NULL,
  `issued_by_citizenid` VARCHAR(64) NOT NULL,
  `issued_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_public_response_request` (`request_id`),
  KEY `idx_public_response_recipient` (`recipient_citizenid`, `request_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
