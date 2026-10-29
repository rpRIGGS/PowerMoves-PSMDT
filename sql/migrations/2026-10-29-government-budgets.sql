-- Stage 6 annual operating budget proposals. Jurisdiction-owned and audited.
-- No automatic balance changes, tax imposition or spending authorizations.
CREATE TABLE IF NOT EXISTS `mdt_government_budgets` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `agency` VARCHAR(64) NOT NULL,
  `jurisdiction` VARCHAR(64) NOT NULL,
  `department` VARCHAR(100) NOT NULL,
  `fiscal_year` SMALLINT UNSIGNED NOT NULL,
  `revenue_estimate` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `expense_limit` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `notes` TEXT NOT NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'draft',
  `version` INT UNSIGNED NOT NULL DEFAULT 1,
  `created_by_citizenid` VARCHAR(64) NOT NULL,
  `approved_by_citizenid` VARCHAR(64) DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `approved_at` DATETIME DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_gov_budget_year_department` (`agency`,`fiscal_year`,`department`),
  KEY `idx_gov_budget_scope` (`agency`,`status`,`fiscal_year`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mdt_government_budget_audit` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `budget_id` BIGINT UNSIGNED NOT NULL,
  `agency` VARCHAR(64) NOT NULL,
  `actor_citizenid` VARCHAR(64) NOT NULL,
  `action` VARCHAR(24) NOT NULL,
  `reason` VARCHAR(1000) NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_gov_budget_audit` (`budget_id`,`agency`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
