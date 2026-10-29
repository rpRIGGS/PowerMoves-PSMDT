-- Stage 6: government notices, NOT enacted statutes or election results.
-- Agency-authored drafts remain unpublished until a separately authorized
-- publishing officer approves them. Additive migration; back up DEV first.
CREATE TABLE IF NOT EXISTS `mdt_government_notices` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `agency` VARCHAR(64) NOT NULL,
  `jurisdiction` VARCHAR(64) NOT NULL,
  `title` VARCHAR(160) NOT NULL,
  `body` TEXT NOT NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'draft',
  `version` INT UNSIGNED NOT NULL DEFAULT 1,
  `created_by_citizenid` VARCHAR(64) NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `published_by_citizenid` VARCHAR(64) DEFAULT NULL,
  `published_at` DATETIME DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_gov_notices_agency` (`agency`, `status`, `updated_at`),
  KEY `idx_gov_notices_public` (`status`, `updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_government_notice_audit` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `notice_id` BIGINT UNSIGNED NOT NULL,
  `agency` VARCHAR(64) NOT NULL,
  `actor_citizenid` VARCHAR(64) NOT NULL,
  `action` VARCHAR(24) NOT NULL,
  `reason` VARCHAR(500) NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_gov_notice_audit` (`notice_id`, `agency`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
