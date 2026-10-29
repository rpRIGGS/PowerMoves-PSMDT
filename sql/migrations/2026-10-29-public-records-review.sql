-- Stage 5 additive records-office review audit. DEV migration after backup.
CREATE TABLE IF NOT EXISTS `mdt_public_record_request_audit` (
 `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
 `request_id` BIGINT UNSIGNED NOT NULL,
 `agency` VARCHAR(64) NOT NULL,
 `actor_citizenid` VARCHAR(64) NOT NULL,
 `action` VARCHAR(32) NOT NULL,
 `reason` VARCHAR(1000) NOT NULL,
 `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY (`id`),
 KEY `idx_public_request_audit` (`request_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
