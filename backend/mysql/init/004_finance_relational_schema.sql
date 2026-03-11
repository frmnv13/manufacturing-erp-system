CREATE TABLE IF NOT EXISTS finance_students (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  office_id BIGINT UNSIGNED NOT NULL,
  nim VARCHAR(40) NOT NULL,
  name VARCHAR(150) NOT NULL,
  major VARCHAR(120) NOT NULL DEFAULT '',
  class_name VARCHAR(80) NOT NULL DEFAULT '',
  semester SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  special_scheme ENUM(
    'none',
    'scholarship_100',
    'scholarship_75',
    'scholarship_50',
    'scholarship_25',
    'installment'
  ) NOT NULL DEFAULT 'none',
  installment_terms TINYINT UNSIGNED NOT NULL DEFAULT 1,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  metadata JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_finance_students_office
    FOREIGN KEY (office_id) REFERENCES offices(id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  UNIQUE KEY uq_finance_students_office_nim (office_id, nim),
  INDEX idx_finance_students_lookup (office_id, major, semester)
);

CREATE TABLE IF NOT EXISTS finance_payment_types (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  office_id BIGINT UNSIGNED NOT NULL,
  external_id VARCHAR(80) NOT NULL,
  name VARCHAR(120) NOT NULL,
  amount INT UNSIGNED NOT NULL DEFAULT 0,
  target_semester SMALLINT UNSIGNED NULL,
  target_major VARCHAR(120) NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_finance_payment_types_office
    FOREIGN KEY (office_id) REFERENCES offices(id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  UNIQUE KEY uq_finance_payment_types_external (office_id, external_id),
  INDEX idx_finance_payment_types_name (office_id, name)
);

CREATE TABLE IF NOT EXISTS finance_payment_type_prerequisites (
  payment_type_id BIGINT UNSIGNED NOT NULL,
  prerequisite_payment_type_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (payment_type_id, prerequisite_payment_type_id),
  CONSTRAINT fk_finance_prereq_payment_type
    FOREIGN KEY (payment_type_id) REFERENCES finance_payment_types(id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  CONSTRAINT fk_finance_prereq_required_type
    FOREIGN KEY (prerequisite_payment_type_id) REFERENCES finance_payment_types(id)
    ON UPDATE CASCADE
    ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS finance_invoices (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  office_id BIGINT UNSIGNED NOT NULL,
  student_id BIGINT UNSIGNED NOT NULL,
  payment_type_id BIGINT UNSIGNED NOT NULL,
  source_key VARCHAR(191) NOT NULL,
  academic_term VARCHAR(50) NOT NULL DEFAULT 'legacy',
  nominal INT UNSIGNED NOT NULL DEFAULT 0,
  discount_percent DECIMAL(5,2) NOT NULL DEFAULT 0.00,
  amount_due INT UNSIGNED NOT NULL DEFAULT 0,
  status ENUM('unpaid', 'partial', 'paid', 'waived') NOT NULL DEFAULT 'unpaid',
  issued_at DATETIME NULL,
  due_at DATETIME NULL,
  settled_at DATETIME NULL,
  notes VARCHAR(255) NULL,
  created_by_user_id BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_finance_invoices_office
    FOREIGN KEY (office_id) REFERENCES offices(id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  CONSTRAINT fk_finance_invoices_student
    FOREIGN KEY (student_id) REFERENCES finance_students(id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  CONSTRAINT fk_finance_invoices_payment_type
    FOREIGN KEY (payment_type_id) REFERENCES finance_payment_types(id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
  CONSTRAINT fk_finance_invoices_created_by
    FOREIGN KEY (created_by_user_id) REFERENCES users(id)
    ON UPDATE CASCADE
    ON DELETE SET NULL,
  UNIQUE KEY uq_finance_invoices_source (office_id, source_key),
  INDEX idx_finance_invoices_status (office_id, status),
  INDEX idx_finance_invoices_student (office_id, student_id)
);

CREATE TABLE IF NOT EXISTS finance_payments (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  office_id BIGINT UNSIGNED NOT NULL,
  invoice_id BIGINT UNSIGNED NULL,
  student_id BIGINT UNSIGNED NOT NULL,
  payment_type_id BIGINT UNSIGNED NULL,
  source ENUM('manual', 'bank_mutation', 'legacy_state', 'import') NOT NULL DEFAULT 'manual',
  reference_no VARCHAR(120) NULL,
  amount INT UNSIGNED NOT NULL DEFAULT 0,
  payment_date DATETIME NOT NULL,
  status ENUM('pending', 'approved', 'rejected') NOT NULL DEFAULT 'approved',
  notes VARCHAR(255) NULL,
  created_by_user_id BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_finance_payments_office
    FOREIGN KEY (office_id) REFERENCES offices(id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  CONSTRAINT fk_finance_payments_invoice
    FOREIGN KEY (invoice_id) REFERENCES finance_invoices(id)
    ON UPDATE CASCADE
    ON DELETE SET NULL,
  CONSTRAINT fk_finance_payments_student
    FOREIGN KEY (student_id) REFERENCES finance_students(id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  CONSTRAINT fk_finance_payments_payment_type
    FOREIGN KEY (payment_type_id) REFERENCES finance_payment_types(id)
    ON UPDATE CASCADE
    ON DELETE SET NULL,
  CONSTRAINT fk_finance_payments_created_by
    FOREIGN KEY (created_by_user_id) REFERENCES users(id)
    ON UPDATE CASCADE
    ON DELETE SET NULL,
  INDEX idx_finance_payments_lookup (office_id, student_id, payment_date),
  INDEX idx_finance_payments_status (office_id, status)
);

CREATE TABLE IF NOT EXISTS finance_cash_transactions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  office_id BIGINT UNSIGNED NOT NULL,
  source_key CHAR(40) NULL,
  kind ENUM('income', 'expense') NOT NULL,
  category VARCHAR(120) NOT NULL,
  description VARCHAR(255) NOT NULL,
  amount INT UNSIGNED NOT NULL DEFAULT 0,
  transaction_date DATETIME NOT NULL,
  status ENUM('completed', 'pending', 'failed') NOT NULL DEFAULT 'completed',
  source ENUM('manual', 'legacy_state', 'auto_match') NOT NULL DEFAULT 'manual',
  related_payment_id BIGINT UNSIGNED NULL,
  created_by_user_id BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_finance_cash_transactions_office
    FOREIGN KEY (office_id) REFERENCES offices(id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  CONSTRAINT fk_finance_cash_transactions_payment
    FOREIGN KEY (related_payment_id) REFERENCES finance_payments(id)
    ON UPDATE CASCADE
    ON DELETE SET NULL,
  CONSTRAINT fk_finance_cash_transactions_created_by
    FOREIGN KEY (created_by_user_id) REFERENCES users(id)
    ON UPDATE CASCADE
    ON DELETE SET NULL,
  UNIQUE KEY uq_finance_cash_transactions_source (office_id, source_key),
  INDEX idx_finance_cash_transactions_lookup (office_id, transaction_date, kind)
);

CREATE TABLE IF NOT EXISTS finance_bank_mutations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  office_id BIGINT UNSIGNED NOT NULL,
  bank_account VARCHAR(80) NULL,
  mutation_date DATETIME NOT NULL,
  description VARCHAR(255) NOT NULL,
  amount INT NOT NULL DEFAULT 0,
  is_credit TINYINT(1) NOT NULL DEFAULT 1,
  reference_no VARCHAR(120) NULL,
  source_file VARCHAR(190) NULL,
  raw_payload JSON NULL,
  match_status ENUM('unmatched', 'candidate', 'matched', 'approved', 'rejected') NOT NULL DEFAULT 'unmatched',
  matched_student_id BIGINT UNSIGNED NULL,
  matched_invoice_id BIGINT UNSIGNED NULL,
  confidence DECIMAL(5,2) NOT NULL DEFAULT 0.00,
  reviewed_by_user_id BIGINT UNSIGNED NULL,
  reviewed_at DATETIME NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_finance_bank_mutations_office
    FOREIGN KEY (office_id) REFERENCES offices(id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  CONSTRAINT fk_finance_bank_mutations_student
    FOREIGN KEY (matched_student_id) REFERENCES finance_students(id)
    ON UPDATE CASCADE
    ON DELETE SET NULL,
  CONSTRAINT fk_finance_bank_mutations_invoice
    FOREIGN KEY (matched_invoice_id) REFERENCES finance_invoices(id)
    ON UPDATE CASCADE
    ON DELETE SET NULL,
  CONSTRAINT fk_finance_bank_mutations_reviewed_by
    FOREIGN KEY (reviewed_by_user_id) REFERENCES users(id)
    ON UPDATE CASCADE
    ON DELETE SET NULL,
  INDEX idx_finance_bank_mutations_lookup (office_id, match_status, mutation_date)
);

CREATE TABLE IF NOT EXISTS finance_migration_runs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  office_id BIGINT UNSIGNED NOT NULL,
  actor_user_id BIGINT UNSIGNED NULL,
  source VARCHAR(40) NOT NULL,
  status ENUM('started', 'completed', 'failed') NOT NULL,
  summary JSON NULL,
  started_at DATETIME NOT NULL,
  finished_at DATETIME NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_finance_migration_runs_office
    FOREIGN KEY (office_id) REFERENCES offices(id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  CONSTRAINT fk_finance_migration_runs_actor
    FOREIGN KEY (actor_user_id) REFERENCES users(id)
    ON UPDATE CASCADE
    ON DELETE SET NULL,
  INDEX idx_finance_migration_runs_lookup (office_id, source, started_at)
);
