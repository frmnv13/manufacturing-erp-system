<?php

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, PUT, POST, DELETE, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

const DEFAULT_SESSION_TTL_SECONDS = 28800;
const DEFAULT_OFFICE_CODE = 'default';
const DEFAULT_OFFICE_NAME = 'Kantor Utama';
const DEFAULT_ADMIN_USERNAME = 'admin';
const DEFAULT_ADMIN_FULL_NAME = 'System Owner';
const DEFAULT_ADMIN_ROLE = 'owner';
const DEFAULT_ADMIN_PASSWORD_HASH = '$2y$10$r5fn9aAABHSpNbZjoAoXc.ybrac3fHpa2.PvpiblRrD1BsJbAWFRC';

function json_response(int $status, array $body): void
{
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_UNICODE);
    exit;
}

function db(): PDO
{
    static $pdo = null;
    if ($pdo instanceof PDO) {
        return $pdo;
    }

    $host = getenv('DB_HOST') ?: '127.0.0.1';
    $port = getenv('DB_PORT') ?: '3306';
    $name = getenv('DB_NAME') ?: 'keuangan_kampus';
    $user = getenv('DB_USER') ?: 'root';
    $pass = getenv('DB_PASSWORD') ?: '';

    $dsn = sprintf('mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4', $host, $port, $name);

    $pdo = new PDO($dsn, $user, $pass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    run_schema_migrations($pdo);

    return $pdo;
}

function run_schema_migrations(PDO $pdo): void
{
    static $isDone = false;
    if ($isDone) {
        return;
    }

    $pdo->exec(
        <<<'SQL'
CREATE TABLE IF NOT EXISTS offices (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(50) NOT NULL UNIQUE,
  name VARCHAR(120) NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
)
SQL
    );

    $stmt = $pdo->prepare(
        'INSERT INTO offices (code, name)
         VALUES (:code, :name)
         ON DUPLICATE KEY UPDATE name = VALUES(name)'
    );
    $stmt->execute([
        ':code' => DEFAULT_OFFICE_CODE,
        ':name' => DEFAULT_OFFICE_NAME,
    ]);

    $pdo->exec(
        <<<'SQL'
CREATE TABLE IF NOT EXISTS users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  office_id BIGINT UNSIGNED NOT NULL,
  username VARCHAR(64) NOT NULL UNIQUE,
  full_name VARCHAR(120) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role ENUM('owner', 'admin', 'operator', 'viewer') NOT NULL DEFAULT 'operator',
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_users_office
    FOREIGN KEY (office_id) REFERENCES offices(id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
)
SQL
    );

    $stmt = $pdo->prepare('SELECT id FROM offices WHERE code = :code LIMIT 1');
    $stmt->execute([':code' => DEFAULT_OFFICE_CODE]);
    $officeId = $stmt->fetchColumn();
    if ($officeId === false) {
        throw new RuntimeException('Failed to resolve default office.');
    }

    $stmt = $pdo->prepare('SELECT id FROM users WHERE username = :username LIMIT 1');
    $stmt->execute([':username' => DEFAULT_ADMIN_USERNAME]);
    $adminExists = $stmt->fetchColumn();

    if ($adminExists === false) {
        $stmt = $pdo->prepare(
            'INSERT INTO users (office_id, username, full_name, password_hash, role, is_active)
             VALUES (:office_id, :username, :full_name, :password_hash, :role, 1)'
        );
        $stmt->execute([
            ':office_id' => (int) $officeId,
            ':username' => DEFAULT_ADMIN_USERNAME,
            ':full_name' => DEFAULT_ADMIN_FULL_NAME,
            ':password_hash' => DEFAULT_ADMIN_PASSWORD_HASH,
            ':role' => DEFAULT_ADMIN_ROLE,
        ]);
    }

    $pdo->exec(
        <<<'SQL'
CREATE TABLE IF NOT EXISTS auth_sessions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  token_hash CHAR(64) NOT NULL UNIQUE,
  expires_at DATETIME NOT NULL,
  revoked_at DATETIME NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_auth_sessions_user
    FOREIGN KEY (user_id) REFERENCES users(id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  INDEX idx_auth_sessions_user_id (user_id),
  INDEX idx_auth_sessions_expires_at (expires_at)
)
SQL
    );

    $pdo->exec(
        <<<'SQL'
CREATE TABLE IF NOT EXISTS audit_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  office_id BIGINT UNSIGNED NOT NULL,
  actor_user_id BIGINT UNSIGNED NULL,
  action VARCHAR(100) NOT NULL,
  entity_type VARCHAR(100) NOT NULL,
  entity_id VARCHAR(64) NULL,
  payload JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_audit_logs_office
    FOREIGN KEY (office_id) REFERENCES offices(id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  CONSTRAINT fk_audit_logs_actor
    FOREIGN KEY (actor_user_id) REFERENCES users(id)
    ON UPDATE CASCADE
    ON DELETE SET NULL,
  INDEX idx_audit_logs_lookup (office_id, entity_type, created_at),
  INDEX idx_audit_logs_action (office_id, action)
)
SQL
    );

    $pdo->exec(
        <<<'SQL'
CREATE TABLE IF NOT EXISTS app_state (
  id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
  payload JSON NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
)
SQL
    );

    $pdo->exec(
        <<<'SQL'
INSERT INTO app_state (id, payload)
VALUES (1, JSON_OBJECT())
ON DUPLICATE KEY UPDATE payload = payload
SQL
    );

    $pdo->exec(
        <<<'SQL'
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
)
SQL
    );

    $pdo->exec(
        <<<'SQL'
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
)
SQL
    );

    $pdo->exec(
        <<<'SQL'
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
)
SQL
    );

    $pdo->exec(
        <<<'SQL'
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
)
SQL
    );

    $pdo->exec(
        <<<'SQL'
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
)
SQL
    );

    $pdo->exec(
        <<<'SQL'
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
)
SQL
    );

    $pdo->exec(
        <<<'SQL'
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
)
SQL
    );

    $pdo->exec(
        <<<'SQL'
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
)
SQL
    );

    $isDone = true;
}

function parse_json_body(): array
{
    $raw = file_get_contents('php://input');
    if ($raw === false || trim($raw) === '') {
        return [];
    }

    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        json_response(422, ['message' => 'Payload JSON tidak valid.']);
    }

    return $decoded;
}

function get_bearer_token(): string
{
    $authorization = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if ($authorization === '' && function_exists('getallheaders')) {
        $headers = getallheaders();
        if (is_array($headers) && isset($headers['Authorization'])) {
            $authorization = (string) $headers['Authorization'];
        }
    }

    if (!preg_match('/Bearer\s+(.+)/i', $authorization, $matches)) {
        return '';
    }

    return trim($matches[1]);
}

function legacy_api_token(): string
{
    return trim((string) (getenv('API_TOKEN') ?: ''));
}

function session_ttl_seconds(): int
{
    $raw = (int) (getenv('SESSION_TTL_SECONDS') ?: DEFAULT_SESSION_TTL_SECONDS);
    return $raw > 0 ? $raw : DEFAULT_SESSION_TTL_SECONDS;
}

function find_active_session_by_token(string $token): ?array
{
    $tokenHash = hash('sha256', $token);
    $stmt = db()->prepare(
        <<<'SQL'
SELECT
  s.id AS session_id,
  s.user_id,
  s.expires_at,
  u.username,
  u.full_name,
  u.role,
  o.id AS office_id,
  o.code AS office_code,
  o.name AS office_name
FROM auth_sessions s
INNER JOIN users u ON u.id = s.user_id
INNER JOIN offices o ON o.id = u.office_id
WHERE s.token_hash = :token_hash
  AND s.revoked_at IS NULL
  AND s.expires_at > UTC_TIMESTAMP()
  AND u.is_active = 1
  AND o.is_active = 1
LIMIT 1
SQL
    );
    $stmt->execute([':token_hash' => $tokenHash]);
    $row = $stmt->fetch();

    return $row !== false ? $row : null;
}

function authenticate_token(string $token): ?array
{
    if ($token === '') {
        return null;
    }

    $legacyToken = legacy_api_token();
    if ($legacyToken !== '' && hash_equals($legacyToken, $token)) {
        return ['type' => 'legacy'];
    }

    $session = find_active_session_by_token($token);
    if ($session === null) {
        return null;
    }

    return [
        'type' => 'session',
        'session' => $session,
    ];
}

function require_auth(): array
{
    $token = get_bearer_token();
    $legacyToken = legacy_api_token();

    if ($token === '') {
        if ($legacyToken === '') {
            return ['type' => 'anonymous'];
        }
        json_response(401, ['message' => 'Missing bearer token']);
    }

    $auth = authenticate_token($token);
    if ($auth === null) {
        json_response(401, ['message' => 'Invalid bearer token']);
    }

    return $auth;
}

function require_user_session(): array
{
    $token = get_bearer_token();
    if ($token === '') {
        json_response(401, ['message' => 'Missing bearer token']);
    }

    $auth = authenticate_token($token);
    if ($auth === null) {
        json_response(401, ['message' => 'Invalid bearer token']);
    }

    if (($auth['type'] ?? '') !== 'session' || !isset($auth['session']) || !is_array($auth['session'])) {
        json_response(403, ['message' => 'Session token required']);
    }

    return $auth['session'];
}

function issue_session_token(int $userId): array
{
    $token = bin2hex(random_bytes(32));
    $tokenHash = hash('sha256', $token);
    $expiresAt = gmdate('Y-m-d H:i:s', time() + session_ttl_seconds());

    $stmt = db()->prepare(
        'INSERT INTO auth_sessions (user_id, token_hash, expires_at) VALUES (:user_id, :token_hash, :expires_at)'
    );
    $stmt->execute([
        ':user_id' => $userId,
        ':token_hash' => $tokenHash,
        ':expires_at' => $expiresAt,
    ]);

    return [
        'token' => $token,
        'expiresAt' => $expiresAt,
    ];
}

function build_user_payload(array $sessionOrUser): array
{
    return [
        'id' => (int) $sessionOrUser['user_id'],
        'username' => (string) $sessionOrUser['username'],
        'fullName' => (string) $sessionOrUser['full_name'],
        'role' => (string) $sessionOrUser['role'],
        'office' => [
            'id' => (int) $sessionOrUser['office_id'],
            'code' => (string) $sessionOrUser['office_code'],
            'name' => (string) $sessionOrUser['office_name'],
        ],
    ];
}

function normalize_role(string $raw): string
{
    $role = strtolower(trim($raw));
    return in_array($role, ['owner', 'admin', 'operator', 'viewer'], true)
        ? $role
        : '';
}

function require_role(array $allowedRoles, array $session): void
{
    $role = strtolower((string) ($session['role'] ?? ''));
    if (!in_array($role, $allowedRoles, true)) {
        json_response(403, ['message' => 'Akses ditolak untuk role ini.']);
    }
}

function write_audit_log(
    int $officeId,
    ?int $actorUserId,
    string $action,
    string $entityType,
    ?string $entityId = null,
    ?array $payload = null
): void {
    $stmt = db()->prepare(
        'INSERT INTO audit_logs (office_id, actor_user_id, action, entity_type, entity_id, payload)
         VALUES (:office_id, :actor_user_id, :action, :entity_type, :entity_id, :payload)'
    );
    $stmt->execute([
        ':office_id' => $officeId,
        ':actor_user_id' => $actorUserId,
        ':action' => $action,
        ':entity_type' => $entityType,
        ':entity_id' => $entityId,
        ':payload' => $payload === null ? null : json_encode($payload, JSON_UNESCAPED_UNICODE),
    ]);
}

function to_bool_value(mixed $value, bool $default = false): bool
{
    if (is_bool($value)) {
        return $value;
    }
    if (is_int($value)) {
        return $value !== 0;
    }
    if (is_string($value)) {
        $lower = strtolower(trim($value));
        if (in_array($lower, ['1', 'true', 'yes', 'y'], true)) {
            return true;
        }
        if (in_array($lower, ['0', 'false', 'no', 'n'], true)) {
            return false;
        }
    }
    return $default;
}

function to_non_negative_int(mixed $value): int
{
    if (is_int($value)) {
        return $value < 0 ? 0 : $value;
    }
    if (is_float($value)) {
        $intValue = (int) floor($value);
        return $intValue < 0 ? 0 : $intValue;
    }
    $parsed = (int) preg_replace('/[^0-9-]/', '', (string) $value);
    return $parsed < 0 ? 0 : $parsed;
}

function normalize_semester(mixed $rawSemester, string $className = ''): int
{
    $semester = to_non_negative_int($rawSemester);
    if ($semester > 0) {
        return $semester;
    }

    if (preg_match('/\d+/', $className, $matches) === 1) {
        $parsed = (int) ($matches[0] ?? 0);
        if ($parsed > 0) {
            return $parsed;
        }
    }

    return 1;
}

function normalize_datetime_string(mixed $raw, ?string $fallback = null): string
{
    if (is_string($raw) && trim($raw) !== '') {
        try {
            $dt = new DateTimeImmutable(trim($raw));
            return $dt->format('Y-m-d H:i:s');
        } catch (Throwable) {
            // Fall through to fallback.
        }
    }

    if ($fallback !== null && trim($fallback) !== '') {
        return trim($fallback);
    }

    return gmdate('Y-m-d H:i:s');
}

function normalize_external_id(string $raw, string $fallbackName): string
{
    $externalId = trim($raw);
    if ($externalId !== '') {
        return substr($externalId, 0, 80);
    }

    $normalizedName = trim($fallbackName);
    if ($normalizedName === '') {
        $normalizedName = 'pembayaran';
    }

    return 'legacy-' . substr(sha1($normalizedName), 0, 24);
}

function payment_type_applies_to_student(array $student, array $paymentType): bool
{
    $studentMajor = trim((string) ($student['major'] ?? ''));
    $studentSemester = (int) ($student['semester'] ?? 1);

    $targetMajor = trim((string) ($paymentType['targetMajor'] ?? ''));
    if ($targetMajor !== '' && strcasecmp($targetMajor, $studentMajor) !== 0) {
        return false;
    }

    $targetSemester = (int) ($paymentType['targetSemester'] ?? 0);
    if ($targetSemester > 0 && $targetSemester !== $studentSemester) {
        return false;
    }

    return true;
}

function load_app_state_payload(): array
{
    $stmt = db()->prepare('SELECT payload, updated_at FROM app_state WHERE id = 1');
    $stmt->execute();
    $row = $stmt->fetch();
    if ($row === false) {
        return [
            'data' => [],
            'updatedAt' => null,
        ];
    }

    $decoded = json_decode((string) $row['payload'], true);
    if (!is_array($decoded)) {
        $decoded = [];
    }

    return [
        'data' => $decoded,
        'updatedAt' => $row['updated_at'] ?? null,
    ];
}

function finance_relational_counts(int $officeId): array
{
    $tables = [
        'students' => 'finance_students',
        'paymentTypes' => 'finance_payment_types',
        'invoices' => 'finance_invoices',
        'payments' => 'finance_payments',
        'cashTransactions' => 'finance_cash_transactions',
        'bankMutations' => 'finance_bank_mutations',
    ];

    $counts = [];
    foreach ($tables as $key => $tableName) {
        $stmt = db()->prepare("SELECT COUNT(*) FROM {$tableName} WHERE office_id = :office_id");
        $stmt->execute([':office_id' => $officeId]);
        $counts[$key] = (int) $stmt->fetchColumn();
    }

    return $counts;
}

function migrate_legacy_state_to_relational(array $session): array
{
    $pdo = db();
    $officeId = (int) ($session['office_id'] ?? 0);
    $actorUserId = (int) ($session['user_id'] ?? 0);
    if ($officeId <= 0) {
        throw new RuntimeException('Office tidak valid untuk migrasi.');
    }

    $state = load_app_state_payload();
    $payload = is_array($state['data'] ?? null) ? $state['data'] : [];
    $paymentTypesRaw = is_array($payload['paymentTypes'] ?? null) ? $payload['paymentTypes'] : [];
    $studentsRaw = is_array($payload['students'] ?? null) ? $payload['students'] : [];
    $transactionsRaw = is_array($payload['transactions'] ?? null) ? $payload['transactions'] : [];

    $startedAt = gmdate('Y-m-d H:i:s');
    $runStmt = $pdo->prepare(
        'INSERT INTO finance_migration_runs (office_id, actor_user_id, source, status, started_at)
         VALUES (:office_id, :actor_user_id, :source, :status, :started_at)'
    );
    $runStmt->execute([
        ':office_id' => $officeId,
        ':actor_user_id' => $actorUserId > 0 ? $actorUserId : null,
        ':source' => 'app_state',
        ':status' => 'started',
        ':started_at' => $startedAt,
    ]);
    $runId = (int) $pdo->lastInsertId();

    $summary = [
        'paymentTypes' => ['created' => 0, 'updated' => 0, 'skipped' => 0, 'prerequisites' => 0],
        'students' => ['created' => 0, 'updated' => 0, 'skipped' => 0],
        'invoices' => ['created' => 0, 'updated' => 0],
        'payments' => ['created' => 0],
        'cashTransactions' => ['created' => 0, 'updated' => 0, 'skipped' => 0],
    ];

    try {
        $existingPaymentTypeKeys = [];
        $stmt = $pdo->prepare(
            'SELECT external_id FROM finance_payment_types WHERE office_id = :office_id'
        );
        $stmt->execute([':office_id' => $officeId]);
        foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $externalId) {
            $existingPaymentTypeKeys[(string) $externalId] = true;
        }

        $existingStudentNims = [];
        $stmt = $pdo->prepare(
            'SELECT nim FROM finance_students WHERE office_id = :office_id'
        );
        $stmt->execute([':office_id' => $officeId]);
        foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $nim) {
            $existingStudentNims[(string) $nim] = true;
        }

        $existingInvoiceKeys = [];
        $stmt = $pdo->prepare(
            'SELECT source_key FROM finance_invoices WHERE office_id = :office_id'
        );
        $stmt->execute([':office_id' => $officeId]);
        foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $sourceKey) {
            $existingInvoiceKeys[(string) $sourceKey] = true;
        }

        $existingCashSourceKeys = [];
        $stmt = $pdo->prepare(
            'SELECT source_key FROM finance_cash_transactions WHERE office_id = :office_id AND source_key IS NOT NULL'
        );
        $stmt->execute([':office_id' => $officeId]);
        foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $sourceKey) {
            $existingCashSourceKeys[(string) $sourceKey] = true;
        }

        $pdo->beginTransaction();

        $upsertPaymentTypeStmt = $pdo->prepare(
            <<<'SQL'
INSERT INTO finance_payment_types
  (office_id, external_id, name, amount, target_semester, target_major, is_active)
VALUES
  (:office_id, :external_id, :name, :amount, :target_semester, :target_major, 1)
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  amount = VALUES(amount),
  target_semester = VALUES(target_semester),
  target_major = VALUES(target_major),
  is_active = 1
SQL
        );

        $paymentTypeDefinitions = [];
        $prerequisitesMap = [];
        foreach ($paymentTypesRaw as $paymentTypeRaw) {
            if (!is_array($paymentTypeRaw)) {
                $summary['paymentTypes']['skipped'] += 1;
                continue;
            }

            $name = trim((string) ($paymentTypeRaw['name'] ?? ''));
            $externalId = normalize_external_id((string) ($paymentTypeRaw['id'] ?? ''), $name);
            if ($name === '') {
                $name = $externalId;
            }

            $amount = to_non_negative_int($paymentTypeRaw['amount'] ?? 0);
            $targetSemester = to_non_negative_int($paymentTypeRaw['targetSemester'] ?? null);
            $targetMajor = trim((string) ($paymentTypeRaw['targetMajor'] ?? ''));

            $upsertPaymentTypeStmt->execute([
                ':office_id' => $officeId,
                ':external_id' => $externalId,
                ':name' => substr($name, 0, 120),
                ':amount' => $amount,
                ':target_semester' => $targetSemester > 0 ? $targetSemester : null,
                ':target_major' => $targetMajor !== '' ? substr($targetMajor, 0, 120) : null,
            ]);

            if (isset($existingPaymentTypeKeys[$externalId])) {
                $summary['paymentTypes']['updated'] += 1;
            } else {
                $summary['paymentTypes']['created'] += 1;
                $existingPaymentTypeKeys[$externalId] = true;
            }

            $paymentTypeDefinitions[$externalId] = [
                'externalId' => $externalId,
                'name' => $name,
                'amount' => $amount,
                'targetSemester' => $targetSemester > 0 ? $targetSemester : 0,
                'targetMajor' => $targetMajor,
            ];

            $prerequisiteTypeIds = is_array($paymentTypeRaw['prerequisiteTypeIds'] ?? null)
                ? $paymentTypeRaw['prerequisiteTypeIds']
                : [];
            $normalizedPrerequisites = [];
            foreach ($prerequisiteTypeIds as $prerequisiteTypeId) {
                $normalizedPrerequisites[] = normalize_external_id(
                    (string) $prerequisiteTypeId,
                    (string) $prerequisiteTypeId
                );
            }
            $prerequisitesMap[$externalId] = $normalizedPrerequisites;
        }

        $paymentTypeIdMap = [];
        $stmt = $pdo->prepare(
            'SELECT id, external_id FROM finance_payment_types WHERE office_id = :office_id'
        );
        $stmt->execute([':office_id' => $officeId]);
        foreach ($stmt->fetchAll() as $row) {
            $paymentTypeIdMap[(string) $row['external_id']] = (int) $row['id'];
        }

        $stmt = $pdo->prepare(
            'DELETE p
             FROM finance_payment_type_prerequisites p
             INNER JOIN finance_payment_types t ON t.id = p.payment_type_id
             WHERE t.office_id = :office_id'
        );
        $stmt->execute([':office_id' => $officeId]);

        $insertPrerequisiteStmt = $pdo->prepare(
            'INSERT IGNORE INTO finance_payment_type_prerequisites
              (payment_type_id, prerequisite_payment_type_id)
             VALUES (:payment_type_id, :prerequisite_payment_type_id)'
        );

        foreach ($prerequisitesMap as $externalId => $prerequisiteExternalIds) {
            $paymentTypeId = $paymentTypeIdMap[$externalId] ?? null;
            if ($paymentTypeId === null) {
                continue;
            }
            foreach ($prerequisiteExternalIds as $prerequisiteExternalId) {
                $prerequisiteId = $paymentTypeIdMap[$prerequisiteExternalId] ?? null;
                if ($prerequisiteId === null || $prerequisiteId === $paymentTypeId) {
                    continue;
                }
                $insertPrerequisiteStmt->execute([
                    ':payment_type_id' => $paymentTypeId,
                    ':prerequisite_payment_type_id' => $prerequisiteId,
                ]);
                $summary['paymentTypes']['prerequisites'] += 1;
            }
        }

        $upsertStudentStmt = $pdo->prepare(
            <<<'SQL'
INSERT INTO finance_students
  (office_id, nim, name, major, class_name, semester, special_scheme, installment_terms, is_active)
VALUES
  (:office_id, :nim, :name, :major, :class_name, :semester, 'none', 1, 1)
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  major = VALUES(major),
  class_name = VALUES(class_name),
  semester = VALUES(semester),
  is_active = 1
SQL
        );

        $studentDefinitions = [];
        foreach ($studentsRaw as $studentRaw) {
            if (!is_array($studentRaw)) {
                $summary['students']['skipped'] += 1;
                continue;
            }

            $nim = trim((string) ($studentRaw['nim'] ?? ''));
            if ($nim === '') {
                $summary['students']['skipped'] += 1;
                continue;
            }

            $name = trim((string) ($studentRaw['name'] ?? ''));
            $major = trim((string) ($studentRaw['major'] ?? ''));
            $className = trim((string) ($studentRaw['className'] ?? ''));
            $semester = normalize_semester($studentRaw['semester'] ?? null, $className);
            $paidTypeIdsRaw = is_array($studentRaw['paidTypeIds'] ?? null) ? $studentRaw['paidTypeIds'] : [];
            $paidTypeIds = [];
            foreach ($paidTypeIdsRaw as $paidTypeId) {
                $paidTypeIds[] = normalize_external_id((string) $paidTypeId, (string) $paidTypeId);
            }

            $upsertStudentStmt->execute([
                ':office_id' => $officeId,
                ':nim' => substr($nim, 0, 40),
                ':name' => substr($name !== '' ? $name : $nim, 0, 150),
                ':major' => substr($major, 0, 120),
                ':class_name' => substr($className, 0, 80),
                ':semester' => $semester,
            ]);

            if (isset($existingStudentNims[$nim])) {
                $summary['students']['updated'] += 1;
            } else {
                $summary['students']['created'] += 1;
                $existingStudentNims[$nim] = true;
            }

            $studentDefinitions[$nim] = [
                'nim' => $nim,
                'major' => $major,
                'semester' => $semester,
                'paidTypeIds' => $paidTypeIds,
            ];
        }

        $studentIdMap = [];
        $stmt = $pdo->prepare(
            'SELECT id, nim FROM finance_students WHERE office_id = :office_id'
        );
        $stmt->execute([':office_id' => $officeId]);
        foreach ($stmt->fetchAll() as $row) {
            $studentIdMap[(string) $row['nim']] = (int) $row['id'];
        }

        $upsertInvoiceStmt = $pdo->prepare(
            <<<'SQL'
INSERT INTO finance_invoices
  (office_id, student_id, payment_type_id, source_key, academic_term, nominal, amount_due, status, settled_at, notes, created_by_user_id)
VALUES
  (:office_id, :student_id, :payment_type_id, :source_key, :academic_term, :nominal, :amount_due, :status, :settled_at, :notes, :created_by_user_id)
ON DUPLICATE KEY UPDATE
  nominal = VALUES(nominal),
  amount_due = VALUES(amount_due),
  status = VALUES(status),
  settled_at = VALUES(settled_at),
  notes = VALUES(notes),
  payment_type_id = VALUES(payment_type_id),
  student_id = VALUES(student_id)
SQL
        );

        $findInvoiceIdStmt = $pdo->prepare(
            'SELECT id FROM finance_invoices WHERE office_id = :office_id AND source_key = :source_key LIMIT 1'
        );
        $findLegacyPaymentStmt = $pdo->prepare(
            'SELECT id FROM finance_payments WHERE invoice_id = :invoice_id AND source = :source LIMIT 1'
        );
        $insertLegacyPaymentStmt = $pdo->prepare(
            <<<'SQL'
INSERT INTO finance_payments
  (office_id, invoice_id, student_id, payment_type_id, source, amount, payment_date, status, notes, created_by_user_id)
VALUES
  (:office_id, :invoice_id, :student_id, :payment_type_id, :source, :amount, :payment_date, :status, :notes, :created_by_user_id)
SQL
        );

        foreach ($studentDefinitions as $nim => $studentDefinition) {
            $studentId = $studentIdMap[$nim] ?? null;
            if ($studentId === null) {
                continue;
            }

            foreach ($paymentTypeDefinitions as $paymentTypeDefinition) {
                if (!payment_type_applies_to_student($studentDefinition, $paymentTypeDefinition)) {
                    continue;
                }

                $externalId = (string) $paymentTypeDefinition['externalId'];
                $paymentTypeId = $paymentTypeIdMap[$externalId] ?? null;
                if ($paymentTypeId === null) {
                    continue;
                }

                $sourceKey = substr($nim . '::' . $externalId, 0, 191);
                $isPaid = in_array($externalId, $studentDefinition['paidTypeIds'], true);
                $status = $isPaid ? 'paid' : 'unpaid';
                $settledAt = $isPaid ? gmdate('Y-m-d H:i:s') : null;
                $nominal = (int) ($paymentTypeDefinition['amount'] ?? 0);

                $upsertInvoiceStmt->execute([
                    ':office_id' => $officeId,
                    ':student_id' => $studentId,
                    ':payment_type_id' => $paymentTypeId,
                    ':source_key' => $sourceKey,
                    ':academic_term' => 'legacy',
                    ':nominal' => $nominal,
                    ':amount_due' => $nominal,
                    ':status' => $status,
                    ':settled_at' => $settledAt,
                    ':notes' => 'Migrasi dari app_state',
                    ':created_by_user_id' => $actorUserId > 0 ? $actorUserId : null,
                ]);

                if (isset($existingInvoiceKeys[$sourceKey])) {
                    $summary['invoices']['updated'] += 1;
                } else {
                    $summary['invoices']['created'] += 1;
                    $existingInvoiceKeys[$sourceKey] = true;
                }

                if (!$isPaid) {
                    continue;
                }

                $findInvoiceIdStmt->execute([
                    ':office_id' => $officeId,
                    ':source_key' => $sourceKey,
                ]);
                $invoiceId = (int) ($findInvoiceIdStmt->fetchColumn() ?: 0);
                if ($invoiceId <= 0) {
                    continue;
                }

                $findLegacyPaymentStmt->execute([
                    ':invoice_id' => $invoiceId,
                    ':source' => 'legacy_state',
                ]);
                $existingPaymentId = (int) ($findLegacyPaymentStmt->fetchColumn() ?: 0);
                if ($existingPaymentId > 0) {
                    continue;
                }

                $insertLegacyPaymentStmt->execute([
                    ':office_id' => $officeId,
                    ':invoice_id' => $invoiceId,
                    ':student_id' => $studentId,
                    ':payment_type_id' => $paymentTypeId,
                    ':source' => 'legacy_state',
                    ':amount' => $nominal,
                    ':payment_date' => gmdate('Y-m-d H:i:s'),
                    ':status' => 'approved',
                    ':notes' => 'Pembayaran hasil migrasi dari app_state',
                    ':created_by_user_id' => $actorUserId > 0 ? $actorUserId : null,
                ]);
                $summary['payments']['created'] += 1;
            }
        }

        $upsertCashTransactionStmt = $pdo->prepare(
            <<<'SQL'
INSERT INTO finance_cash_transactions
  (office_id, source_key, kind, category, description, amount, transaction_date, status, source, created_by_user_id)
VALUES
  (:office_id, :source_key, :kind, :category, :description, :amount, :transaction_date, :status, :source, :created_by_user_id)
ON DUPLICATE KEY UPDATE
  kind = VALUES(kind),
  category = VALUES(category),
  description = VALUES(description),
  amount = VALUES(amount),
  transaction_date = VALUES(transaction_date),
  status = VALUES(status),
  source = VALUES(source)
SQL
        );

        foreach ($transactionsRaw as $transactionRaw) {
            if (!is_array($transactionRaw)) {
                $summary['cashTransactions']['skipped'] += 1;
                continue;
            }

            $category = trim((string) ($transactionRaw['category'] ?? ''));
            $description = trim((string) ($transactionRaw['description'] ?? ''));
            $amount = to_non_negative_int($transactionRaw['amount'] ?? 0);
            if ($amount <= 0) {
                $summary['cashTransactions']['skipped'] += 1;
                continue;
            }

            $isIncome = ($transactionRaw['isIncome'] ?? false) === true;
            $kind = $isIncome ? 'income' : 'expense';
            $statusRaw = strtolower(trim((string) ($transactionRaw['status'] ?? 'completed')));
            $status = in_array($statusRaw, ['completed', 'pending', 'failed'], true)
                ? $statusRaw
                : 'completed';
            $transactionDate = normalize_datetime_string($transactionRaw['date'] ?? null);

            $sourceKey = sha1(json_encode([
                $kind,
                $category,
                $description,
                $amount,
                $transactionDate,
                $status,
            ], JSON_UNESCAPED_UNICODE));

            $upsertCashTransactionStmt->execute([
                ':office_id' => $officeId,
                ':source_key' => $sourceKey,
                ':kind' => $kind,
                ':category' => substr($category !== '' ? $category : 'Lainnya', 0, 120),
                ':description' => substr($description !== '' ? $description : '-', 0, 255),
                ':amount' => $amount,
                ':transaction_date' => $transactionDate,
                ':status' => $status,
                ':source' => 'legacy_state',
                ':created_by_user_id' => $actorUserId > 0 ? $actorUserId : null,
            ]);

            if (isset($existingCashSourceKeys[$sourceKey])) {
                $summary['cashTransactions']['updated'] += 1;
            } else {
                $summary['cashTransactions']['created'] += 1;
                $existingCashSourceKeys[$sourceKey] = true;
            }
        }

        $pdo->commit();

        $finishedAt = gmdate('Y-m-d H:i:s');
        $updateRunStmt = $pdo->prepare(
            'UPDATE finance_migration_runs
             SET status = :status, summary = :summary, finished_at = :finished_at
             WHERE id = :id'
        );
        $updateRunStmt->execute([
            ':status' => 'completed',
            ':summary' => json_encode($summary, JSON_UNESCAPED_UNICODE),
            ':finished_at' => $finishedAt,
            ':id' => $runId,
        ]);

        return [
            'runId' => $runId,
            'startedAt' => $startedAt,
            'finishedAt' => $finishedAt,
            'legacyStateUpdatedAt' => $state['updatedAt'],
            'summary' => $summary,
        ];
    } catch (Throwable $exception) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }

        $updateRunStmt = $pdo->prepare(
            'UPDATE finance_migration_runs
             SET status = :status, summary = :summary, finished_at = :finished_at
             WHERE id = :id'
        );
        $updateRunStmt->execute([
            ':status' => 'failed',
            ':summary' => json_encode([
                'error' => $exception->getMessage(),
            ], JSON_UNESCAPED_UNICODE),
            ':finished_at' => gmdate('Y-m-d H:i:s'),
            ':id' => $runId,
        ]);

        throw $exception;
    }
}

function extract_nim_from_description(string $description): ?string
{
    if (preg_match('/\b\d{5,15}\b/', $description, $matches) !== 1) {
        return null;
    }
    $nim = trim((string) ($matches[0] ?? ''));
    return $nim !== '' ? $nim : null;
}

function find_open_invoices_for_student(int $officeId, int $studentId): array
{
    $stmt = db()->prepare(
        <<<'SQL'
SELECT
          i.id,
          i.amount_due,
          i.status,
          i.payment_type_id,
          pt.name AS payment_type_name
         FROM finance_invoices i
         INNER JOIN finance_payment_types pt ON pt.id = i.payment_type_id
         WHERE i.office_id = :office_id
           AND i.student_id = :student_id
           AND i.status IN ('unpaid', 'partial')
         ORDER BY i.amount_due ASC, i.id ASC
SQL
    );
    $stmt->execute([
        ':office_id' => $officeId,
        ':student_id' => $studentId,
    ]);
    return $stmt->fetchAll();
}

function detect_bank_mutation_match(
    int $officeId,
    string $description,
    int $amount,
    bool $isCredit
): array {
    $result = [
        'status' => 'unmatched',
        'confidence' => 0.0,
        'matchedStudentId' => null,
        'matchedInvoiceId' => null,
        'parsedNim' => null,
        'reason' => 'Tidak ada kandidat yang cocok.',
    ];

    if (!$isCredit) {
        $result['reason'] = 'Mutasi debit tidak diproses untuk auto-match pembayaran.';
        return $result;
    }
    if ($amount <= 0) {
        $result['reason'] = 'Nominal mutasi tidak valid.';
        return $result;
    }

    $parsedNim = extract_nim_from_description($description);
    if ($parsedNim !== null) {
        $result['parsedNim'] = $parsedNim;
        $studentStmt = db()->prepare(
            'SELECT id FROM finance_students WHERE office_id = :office_id AND nim = :nim LIMIT 1'
        );
        $studentStmt->execute([
            ':office_id' => $officeId,
            ':nim' => $parsedNim,
        ]);
        $studentId = (int) ($studentStmt->fetchColumn() ?: 0);
        if ($studentId > 0) {
            $result['matchedStudentId'] = $studentId;
            $openInvoices = find_open_invoices_for_student($officeId, $studentId);
            $exactInvoices = [];
            foreach ($openInvoices as $invoice) {
                if ((int) ($invoice['amount_due'] ?? 0) === $amount) {
                    $exactInvoices[] = $invoice;
                }
            }

            if (count($exactInvoices) === 1) {
                $result['status'] = 'matched';
                $result['confidence'] = 98.0;
                $result['matchedInvoiceId'] = (int) $exactInvoices[0]['id'];
                $result['reason'] = 'NIM dan nominal sesuai tepat dengan 1 tagihan aktif.';
                return $result;
            }

            if (count($exactInvoices) > 1) {
                $result['status'] = 'candidate';
                $result['confidence'] = 74.0;
                $result['reason'] = 'NIM cocok, tapi nominal cocok ke lebih dari satu tagihan.';
                return $result;
            }

            if (count($openInvoices) === 1) {
                $result['status'] = 'candidate';
                $result['confidence'] = 66.0;
                $result['matchedInvoiceId'] = (int) $openInvoices[0]['id'];
                $result['reason'] = 'NIM cocok, nominal berbeda tipis; perlu cek manual.';
                return $result;
            }

            $result['status'] = 'candidate';
            $result['confidence'] = 58.0;
            $result['reason'] = 'NIM cocok, tapi tidak ada nominal tagihan yang sama.';
            return $result;
        }

        $result['status'] = 'candidate';
        $result['confidence'] = 40.0;
        $result['reason'] = 'Format NIM terbaca, tapi mahasiswa belum ada di master data.';
        return $result;
    }

    $amountStmt = db()->prepare(
        <<<'SQL'
SELECT i.id, i.student_id
         FROM finance_invoices i
         WHERE i.office_id = :office_id
           AND i.status IN ('unpaid', 'partial')
           AND i.amount_due = :amount_due
         ORDER BY i.id ASC
         LIMIT 2
SQL
    );
    $amountStmt->execute([
        ':office_id' => $officeId,
        ':amount_due' => $amount,
    ]);
    $rows = $amountStmt->fetchAll();
    if (count($rows) === 1) {
        $row = $rows[0];
        $result['status'] = 'candidate';
        $result['confidence'] = 52.0;
        $result['matchedStudentId'] = (int) ($row['student_id'] ?? 0);
        $result['matchedInvoiceId'] = (int) ($row['id'] ?? 0);
        $result['reason'] = 'Nominal cocok ke 1 tagihan, tapi NIM tidak ditemukan di berita transfer.';
    } else {
        $result['reason'] = 'NIM tidak terdeteksi dan nominal tidak unik.';
    }

    return $result;
}

function import_bank_mutations(array $session, array $rows, string $sourceFile = ''): array
{
    $officeId = (int) ($session['office_id'] ?? 0);
    $actorUserId = (int) ($session['user_id'] ?? 0);
    if ($officeId <= 0) {
        throw new RuntimeException('Office tidak valid.');
    }

    $insertStmt = db()->prepare(
        <<<'SQL'
INSERT INTO finance_bank_mutations
  (
    office_id,
    bank_account,
    mutation_date,
    description,
    amount,
    is_credit,
    reference_no,
    source_file,
    raw_payload,
    match_status,
    matched_student_id,
    matched_invoice_id,
    confidence
  )
VALUES
  (
    :office_id,
    :bank_account,
    :mutation_date,
    :description,
    :amount,
    :is_credit,
    :reference_no,
    :source_file,
    :raw_payload,
    :match_status,
    :matched_student_id,
    :matched_invoice_id,
    :confidence
  )
SQL
    );

    $duplicateStmt = db()->prepare(
        <<<'SQL'
SELECT id FROM finance_bank_mutations
         WHERE office_id = :office_id
           AND mutation_date = :mutation_date
           AND description = :description
           AND amount = :amount
           AND is_credit = :is_credit
           AND COALESCE(reference_no, '') = COALESCE(:reference_no, '')
         LIMIT 1
SQL
    );

    $summary = [
        'imported' => 0,
        'skipped' => 0,
        'duplicates' => 0,
        'matched' => 0,
        'candidate' => 0,
        'unmatched' => 0,
    ];

    foreach ($rows as $row) {
        if (!is_array($row)) {
            $summary['skipped'] += 1;
            continue;
        }

        $description = trim((string) ($row['description'] ?? ''));
        $amount = to_non_negative_int($row['amount'] ?? 0);
        $mutationDate = normalize_datetime_string($row['mutationDate'] ?? null);
        $isCredit = to_bool_value($row['isCredit'] ?? true, true);
        $referenceNo = trim((string) ($row['referenceNo'] ?? ''));
        $bankAccount = trim((string) ($row['bankAccount'] ?? ''));

        if ($description === '' || $amount <= 0) {
            $summary['skipped'] += 1;
            continue;
        }

        $duplicateStmt->execute([
            ':office_id' => $officeId,
            ':mutation_date' => $mutationDate,
            ':description' => $description,
            ':amount' => $amount,
            ':is_credit' => $isCredit ? 1 : 0,
            ':reference_no' => $referenceNo !== '' ? $referenceNo : null,
        ]);
        $duplicateId = (int) ($duplicateStmt->fetchColumn() ?: 0);
        if ($duplicateId > 0) {
            $summary['duplicates'] += 1;
            continue;
        }

        $match = detect_bank_mutation_match($officeId, $description, $amount, $isCredit);

        $rawPayload = [
            'input' => $row,
            'matchReason' => $match['reason'],
            'parsedNim' => $match['parsedNim'],
        ];

        $insertStmt->execute([
            ':office_id' => $officeId,
            ':bank_account' => $bankAccount !== '' ? substr($bankAccount, 0, 80) : null,
            ':mutation_date' => $mutationDate,
            ':description' => substr($description, 0, 255),
            ':amount' => $amount,
            ':is_credit' => $isCredit ? 1 : 0,
            ':reference_no' => $referenceNo !== '' ? substr($referenceNo, 0, 120) : null,
            ':source_file' => $sourceFile !== '' ? substr($sourceFile, 0, 190) : null,
            ':raw_payload' => json_encode($rawPayload, JSON_UNESCAPED_UNICODE),
            ':match_status' => (string) $match['status'],
            ':matched_student_id' => $match['matchedStudentId'],
            ':matched_invoice_id' => $match['matchedInvoiceId'],
            ':confidence' => (float) ($match['confidence'] ?? 0),
        ]);

        $summary['imported'] += 1;
        $status = (string) ($match['status'] ?? 'unmatched');
        if (!isset($summary[$status])) {
            $status = 'unmatched';
        }
        $summary[$status] += 1;
    }

    write_audit_log(
        $officeId,
        $actorUserId > 0 ? $actorUserId : null,
        'bank_mutation.import',
        'bank_mutation',
        null,
        $summary
    );

    return $summary;
}

function recalculate_invoice_status(int $invoiceId): void
{
    $invoiceStmt = db()->prepare(
        'SELECT amount_due FROM finance_invoices WHERE id = :id LIMIT 1'
    );
    $invoiceStmt->execute([':id' => $invoiceId]);
    $invoice = $invoiceStmt->fetch();
    if ($invoice === false) {
        return;
    }

    $amountDue = to_non_negative_int($invoice['amount_due'] ?? 0);
    $sumStmt = db()->prepare(
        <<<'SQL'
SELECT COALESCE(SUM(amount), 0) FROM finance_payments
         WHERE invoice_id = :invoice_id AND status = 'approved'
SQL
    );
    $sumStmt->execute([':invoice_id' => $invoiceId]);
    $paidTotal = to_non_negative_int($sumStmt->fetchColumn());

    $status = 'unpaid';
    $settledAt = null;
    if ($paidTotal >= $amountDue && $amountDue > 0) {
        $status = 'paid';
        $settledAt = gmdate('Y-m-d H:i:s');
    } elseif ($paidTotal > 0) {
        $status = 'partial';
    }

    $updateStmt = db()->prepare(
        'UPDATE finance_invoices
         SET status = :status, settled_at = :settled_at
         WHERE id = :id'
    );
    $updateStmt->execute([
        ':status' => $status,
        ':settled_at' => $settledAt,
        ':id' => $invoiceId,
    ]);
}

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
$path = rtrim((string) $path, '/');
if ($path === '') {
    $path = '/';
}
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

try {
    if ($path === '/health' && $method === 'GET') {
        json_response(200, ['status' => 'ok']);
    }

    if ($path === '/' && $method === 'GET') {
        json_response(200, ['name' => 'Keuangan Kampus API', 'status' => 'ok']);
    }

    if ($path === '/api/auth/login' && $method === 'POST') {
        $payload = parse_json_body();
        $username = trim((string) ($payload['username'] ?? ''));
        $password = (string) ($payload['password'] ?? '');
        $officeCode = trim((string) ($payload['officeCode'] ?? ''));

        if ($username === '' || $password === '') {
            json_response(422, ['message' => 'Username dan password wajib diisi.']);
        }

        $sql = <<<'SQL'
SELECT
  u.id AS user_id,
  u.username,
  u.full_name,
  u.password_hash,
  u.role,
  o.id AS office_id,
  o.code AS office_code,
  o.name AS office_name
FROM users u
INNER JOIN offices o ON o.id = u.office_id
WHERE u.username = :username
  AND u.is_active = 1
  AND o.is_active = 1
SQL;
        if ($officeCode !== '') {
            $sql .= ' AND o.code = :office_code';
        }
        $sql .= ' LIMIT 1';

        $stmt = db()->prepare($sql);
        $params = [':username' => $username];
        if ($officeCode !== '') {
            $params[':office_code'] = $officeCode;
        }
        $stmt->execute($params);
        $row = $stmt->fetch();

        if ($row === false || !password_verify($password, (string) $row['password_hash'])) {
            json_response(401, ['message' => 'Username atau password salah.']);
        }

        $session = issue_session_token((int) $row['user_id']);
        write_audit_log(
            (int) $row['office_id'],
            (int) $row['user_id'],
            'auth.login',
            'auth_session'
        );
        json_response(200, [
            'token' => $session['token'],
            'tokenType' => 'Bearer',
            'expiresAt' => $session['expiresAt'],
            'user' => build_user_payload($row),
        ]);
    }

    if ($path === '/api/auth/me' && $method === 'GET') {
        $session = require_user_session();
        json_response(200, ['user' => build_user_payload($session)]);
    }

    if ($path === '/api/auth/logout' && $method === 'POST') {
        $session = require_user_session();
        $stmt = db()->prepare(
            'UPDATE auth_sessions SET revoked_at = UTC_TIMESTAMP() WHERE id = :id AND revoked_at IS NULL'
        );
        $stmt->execute([':id' => (int) $session['session_id']]);
        write_audit_log(
            (int) $session['office_id'],
            (int) $session['user_id'],
            'auth.logout',
            'auth_session',
            (string) $session['session_id']
        );
        json_response(200, ['message' => 'Logout berhasil.']);
    }

    if ($path === '/api/auth/change-password' && $method === 'POST') {
        $session = require_user_session();
        $payload = parse_json_body();
        $currentPassword = (string) ($payload['currentPassword'] ?? '');
        $newPassword = (string) ($payload['newPassword'] ?? '');

        if ($currentPassword === '' || strlen($newPassword) < 8) {
            json_response(422, ['message' => 'Password lama wajib diisi dan password baru minimal 8 karakter.']);
        }

        $stmt = db()->prepare('SELECT password_hash FROM users WHERE id = :id LIMIT 1');
        $stmt->execute([':id' => (int) $session['user_id']]);
        $currentHash = (string) ($stmt->fetchColumn() ?: '');
        if ($currentHash === '' || !password_verify($currentPassword, $currentHash)) {
            json_response(401, ['message' => 'Password lama tidak sesuai.']);
        }

        $stmt = db()->prepare('UPDATE users SET password_hash = :hash WHERE id = :id');
        $stmt->execute([
            ':hash' => password_hash($newPassword, PASSWORD_BCRYPT),
            ':id' => (int) $session['user_id'],
        ]);

        write_audit_log(
            (int) $session['office_id'],
            (int) $session['user_id'],
            'auth.change_password',
            'user',
            (string) $session['user_id']
        );
        json_response(200, ['message' => 'Password berhasil diubah.']);
    }

    if ($path === '/api/users' && $method === 'GET') {
        $session = require_user_session();
        require_role(['owner', 'admin'], $session);

        $stmt = db()->prepare(
            'SELECT
              u.id AS user_id,
              u.username,
              u.full_name,
              u.role,
              u.is_active,
              u.created_at,
              u.updated_at,
              o.id AS office_id,
              o.code AS office_code,
              o.name AS office_name
             FROM users u
             INNER JOIN offices o ON o.id = u.office_id
             WHERE u.office_id = :office_id
             ORDER BY u.username ASC'
        );
        $stmt->execute([':office_id' => (int) $session['office_id']]);
        $rows = $stmt->fetchAll();
        $items = [];
        foreach ($rows as $row) {
            $item = build_user_payload($row);
            $item['isActive'] = to_bool_value($row['is_active'], true);
            $item['createdAt'] = $row['created_at'];
            $item['updatedAt'] = $row['updated_at'];
            $items[] = $item;
        }
        json_response(200, ['items' => $items]);
    }

    if ($path === '/api/users' && $method === 'POST') {
        $session = require_user_session();
        require_role(['owner', 'admin'], $session);
        $payload = parse_json_body();

        $username = trim((string) ($payload['username'] ?? ''));
        $fullName = trim((string) ($payload['fullName'] ?? ''));
        $password = (string) ($payload['password'] ?? '');
        $role = normalize_role((string) ($payload['role'] ?? 'operator'));
        $isActive = to_bool_value($payload['isActive'] ?? true, true);

        if ($username === '' || $fullName === '' || strlen($password) < 8 || $role === '') {
            json_response(422, ['message' => 'Input user tidak valid.']);
        }

        if (($session['role'] ?? '') !== 'owner' && $role === 'owner') {
            json_response(403, ['message' => 'Hanya owner yang bisa membuat user owner.']);
        }

        $stmt = db()->prepare(
            'INSERT INTO users (office_id, username, full_name, password_hash, role, is_active)
             VALUES (:office_id, :username, :full_name, :password_hash, :role, :is_active)'
        );

        try {
            $stmt->execute([
                ':office_id' => (int) $session['office_id'],
                ':username' => $username,
                ':full_name' => $fullName,
                ':password_hash' => password_hash($password, PASSWORD_BCRYPT),
                ':role' => $role,
                ':is_active' => $isActive ? 1 : 0,
            ]);
        } catch (PDOException $exception) {
            json_response(409, ['message' => 'Username sudah digunakan.']);
        }

        $newId = (int) db()->lastInsertId();
        write_audit_log(
            (int) $session['office_id'],
            (int) $session['user_id'],
            'user.create',
            'user',
            (string) $newId,
            ['role' => $role, 'username' => $username]
        );
        json_response(201, ['id' => $newId, 'message' => 'User berhasil dibuat.']);
    }

    if (preg_match('#^/api/users/(\d+)$#', $path, $matches) === 1 && $method === 'PUT') {
        $session = require_user_session();
        require_role(['owner', 'admin'], $session);

        $targetUserId = (int) $matches[1];
        $payload = parse_json_body();

        $stmt = db()->prepare(
            'SELECT id, role FROM users WHERE id = :id AND office_id = :office_id LIMIT 1'
        );
        $stmt->execute([
            ':id' => $targetUserId,
            ':office_id' => (int) $session['office_id'],
        ]);
        $target = $stmt->fetch();
        if ($target === false) {
            json_response(404, ['message' => 'User tidak ditemukan.']);
        }

        $nextRole = normalize_role((string) ($payload['role'] ?? $target['role']));
        $nextFullName = trim((string) ($payload['fullName'] ?? ''));
        $hasFullName = array_key_exists('fullName', $payload);
        $hasRole = array_key_exists('role', $payload);
        $hasIsActive = array_key_exists('isActive', $payload);
        $nextIsActive = $hasIsActive ? to_bool_value($payload['isActive'], true) : true;

        if ($hasRole && $nextRole === '') {
            json_response(422, ['message' => 'Role tidak valid.']);
        }
        if (($session['role'] ?? '') !== 'owner' && (($target['role'] ?? '') === 'owner' || $nextRole === 'owner')) {
            json_response(403, ['message' => 'Hanya owner yang bisa mengatur role owner.']);
        }
        if ($hasIsActive && !$nextIsActive && $targetUserId === (int) $session['user_id']) {
            json_response(422, ['message' => 'Tidak bisa menonaktifkan akun sendiri.']);
        }

        $changes = [];
        $params = [':id' => $targetUserId];
        if ($hasFullName) {
            if ($nextFullName === '') {
                json_response(422, ['message' => 'Nama lengkap tidak boleh kosong.']);
            }
            $changes[] = 'full_name = :full_name';
            $params[':full_name'] = $nextFullName;
        }
        if ($hasRole) {
            $changes[] = 'role = :role';
            $params[':role'] = $nextRole;
        }
        if ($hasIsActive) {
            $changes[] = 'is_active = :is_active';
            $params[':is_active'] = $nextIsActive ? 1 : 0;
        }
        if ($changes === []) {
            json_response(422, ['message' => 'Tidak ada perubahan untuk disimpan.']);
        }

        $sql = 'UPDATE users SET ' . implode(', ', $changes) . ' WHERE id = :id';
        $stmt = db()->prepare($sql);
        $stmt->execute($params);

        write_audit_log(
            (int) $session['office_id'],
            (int) $session['user_id'],
            'user.update',
            'user',
            (string) $targetUserId
        );
        json_response(200, ['message' => 'User berhasil diperbarui.']);
    }

    if ($path === '/api/audit-logs' && $method === 'GET') {
        $session = require_user_session();
        require_role(['owner', 'admin'], $session);

        $limit = (int) ($_GET['limit'] ?? 100);
        if ($limit < 1) {
            $limit = 1;
        }
        if ($limit > 500) {
            $limit = 500;
        }

        $stmt = db()->prepare(
            'SELECT
              a.id,
              a.action,
              a.entity_type,
              a.entity_id,
              a.actor_user_id,
              a.payload,
              a.created_at,
              u.username AS actor_username
             FROM audit_logs a
             LEFT JOIN users u ON u.id = a.actor_user_id
             WHERE a.office_id = :office_id
             ORDER BY a.id DESC
             LIMIT :limit_value'
        );
        $stmt->bindValue(':office_id', (int) $session['office_id'], PDO::PARAM_INT);
        $stmt->bindValue(':limit_value', $limit, PDO::PARAM_INT);
        $stmt->execute();
        $items = [];
        foreach ($stmt->fetchAll() as $row) {
            $items[] = [
                'id' => (int) $row['id'],
                'action' => (string) $row['action'],
                'entityType' => (string) $row['entity_type'],
                'entityId' => $row['entity_id'],
                'actorUserId' => $row['actor_user_id'] === null ? null : (int) $row['actor_user_id'],
                'actorUsername' => (string) ($row['actor_username'] ?? ''),
                'payload' => is_string($row['payload']) && trim($row['payload']) !== ''
                    ? json_decode($row['payload'], true)
                    : null,
                'createdAt' => $row['created_at'],
            ];
        }
        json_response(200, ['items' => $items]);
    }

    if ($path === '/api/relational/status' && $method === 'GET') {
        $session = require_user_session();
        require_role(['owner', 'admin'], $session);

        $officeId = (int) $session['office_id'];
        $counts = finance_relational_counts($officeId);
        $legacyState = load_app_state_payload();

        $stmt = db()->prepare(
            'SELECT id, source, status, summary, started_at, finished_at
             FROM finance_migration_runs
             WHERE office_id = :office_id
             ORDER BY id DESC
             LIMIT 1'
        );
        $stmt->execute([':office_id' => $officeId]);
        $lastRun = $stmt->fetch();

        $lastRunPayload = null;
        if ($lastRun !== false) {
            $summary = null;
            if (is_string($lastRun['summary']) && trim($lastRun['summary']) !== '') {
                $decodedSummary = json_decode($lastRun['summary'], true);
                if (is_array($decodedSummary)) {
                    $summary = $decodedSummary;
                }
            }

            $lastRunPayload = [
                'id' => (int) $lastRun['id'],
                'source' => (string) ($lastRun['source'] ?? ''),
                'status' => (string) ($lastRun['status'] ?? ''),
                'summary' => $summary,
                'startedAt' => $lastRun['started_at'],
                'finishedAt' => $lastRun['finished_at'],
            ];
        }

        json_response(200, [
            'data' => [
                'counts' => $counts,
                'legacyStateUpdatedAt' => $legacyState['updatedAt'],
                'lastMigrationRun' => $lastRunPayload,
            ],
        ]);
    }

    if ($path === '/api/relational/bootstrap' && $method === 'POST') {
        $session = require_user_session();
        require_role(['owner', 'admin'], $session);

        $result = migrate_legacy_state_to_relational($session);

        write_audit_log(
            (int) $session['office_id'],
            (int) $session['user_id'],
            'relational.bootstrap',
            'migration',
            isset($result['runId']) ? (string) $result['runId'] : null,
            isset($result['summary']) && is_array($result['summary']) ? $result['summary'] : null
        );

        json_response(200, [
            'message' => 'Migrasi app_state ke tabel relasional selesai.',
            'data' => $result,
        ]);
    }

    if ($path === '/api/bank-mutations' && $method === 'GET') {
        $session = require_user_session();
        require_role(['owner', 'admin', 'operator', 'viewer'], $session);

        $officeId = (int) $session['office_id'];
        $status = trim((string) ($_GET['status'] ?? ''));
        $limit = (int) ($_GET['limit'] ?? 200);
        if ($limit < 1) {
            $limit = 1;
        }
        if ($limit > 500) {
            $limit = 500;
        }

        $allowedStatuses = ['unmatched', 'candidate', 'matched', 'approved', 'rejected'];
        $filters = ['m.office_id = :office_id'];
        $params = [':office_id' => $officeId];
        if ($status !== '' && in_array($status, $allowedStatuses, true)) {
            $filters[] = 'm.match_status = :status';
            $params[':status'] = $status;
        }

        $sql = 'SELECT
                  m.id,
                  m.mutation_date,
                  m.description,
                  m.amount,
                  m.is_credit,
                  m.reference_no,
                  m.source_file,
                  m.match_status,
                  m.confidence,
                  m.matched_student_id,
                  m.matched_invoice_id,
                  m.reviewed_at,
                  m.raw_payload,
                  s.nim AS student_nim,
                  s.name AS student_name,
                  i.amount_due AS invoice_amount_due,
                  i.status AS invoice_status,
                  pt.name AS invoice_payment_type_name
                FROM finance_bank_mutations m
                LEFT JOIN finance_students s ON s.id = m.matched_student_id
                LEFT JOIN finance_invoices i ON i.id = m.matched_invoice_id
                LEFT JOIN finance_payment_types pt ON pt.id = i.payment_type_id
                WHERE ' . implode(' AND ', $filters) . '
                ORDER BY m.id DESC
                LIMIT :limit_value';
        $stmt = db()->prepare($sql);
        foreach ($params as $key => $value) {
            $stmt->bindValue($key, $value);
        }
        $stmt->bindValue(':limit_value', $limit, PDO::PARAM_INT);
        $stmt->execute();

        $items = [];
        foreach ($stmt->fetchAll() as $row) {
            $rawPayload = null;
            if (is_string($row['raw_payload']) && trim($row['raw_payload']) !== '') {
                $decodedPayload = json_decode($row['raw_payload'], true);
                if (is_array($decodedPayload)) {
                    $rawPayload = $decodedPayload;
                }
            }

            $items[] = [
                'id' => (int) $row['id'],
                'mutationDate' => $row['mutation_date'],
                'description' => (string) ($row['description'] ?? ''),
                'amount' => (int) ($row['amount'] ?? 0),
                'isCredit' => ((int) ($row['is_credit'] ?? 0)) === 1,
                'referenceNo' => $row['reference_no'],
                'sourceFile' => $row['source_file'],
                'matchStatus' => (string) ($row['match_status'] ?? 'unmatched'),
                'confidence' => (float) ($row['confidence'] ?? 0),
                'reviewedAt' => $row['reviewed_at'],
                'matchedStudent' => $row['matched_student_id'] === null
                    ? null
                    : [
                        'id' => (int) $row['matched_student_id'],
                        'nim' => (string) ($row['student_nim'] ?? ''),
                        'name' => (string) ($row['student_name'] ?? ''),
                    ],
                'matchedInvoice' => $row['matched_invoice_id'] === null
                    ? null
                    : [
                        'id' => (int) $row['matched_invoice_id'],
                        'amountDue' => (int) ($row['invoice_amount_due'] ?? 0),
                        'status' => (string) ($row['invoice_status'] ?? ''),
                        'paymentTypeName' => (string) ($row['invoice_payment_type_name'] ?? ''),
                    ],
                'rawPayload' => $rawPayload,
            ];
        }

        $countStmt = db()->prepare(
            'SELECT match_status, COUNT(*) AS total
             FROM finance_bank_mutations
             WHERE office_id = :office_id
             GROUP BY match_status'
        );
        $countStmt->execute([':office_id' => $officeId]);
        $counts = [
            'unmatched' => 0,
            'candidate' => 0,
            'matched' => 0,
            'approved' => 0,
            'rejected' => 0,
        ];
        foreach ($countStmt->fetchAll() as $row) {
            $key = (string) ($row['match_status'] ?? '');
            if (isset($counts[$key])) {
                $counts[$key] = (int) ($row['total'] ?? 0);
            }
        }

        json_response(200, [
            'items' => $items,
            'counts' => $counts,
        ]);
    }

    if ($path === '/api/bank-mutations/import' && $method === 'POST') {
        $session = require_user_session();
        require_role(['owner', 'admin', 'operator'], $session);

        $payload = parse_json_body();
        $rows = is_array($payload['rows'] ?? null) ? $payload['rows'] : [];
        $sourceFile = trim((string) ($payload['sourceFile'] ?? ''));

        if ($rows === []) {
            json_response(422, ['message' => 'Data mutasi kosong.']);
        }

        $summary = import_bank_mutations($session, $rows, $sourceFile);
        json_response(200, [
            'message' => 'Import mutasi selesai.',
            'summary' => $summary,
        ]);
    }

    if (preg_match('#^/api/bank-mutations/(\d+)/approve$#', $path, $matches) === 1 && $method === 'POST') {
        $session = require_user_session();
        require_role(['owner', 'admin', 'operator'], $session);
        $officeId = (int) $session['office_id'];
        $actorUserId = (int) $session['user_id'];
        $mutationId = (int) $matches[1];
        $payload = parse_json_body();
        $overrideInvoiceId = to_non_negative_int($payload['invoiceId'] ?? 0);

        $mutationStmt = db()->prepare(
            'SELECT id, mutation_date, description, amount, is_credit, match_status, matched_student_id, matched_invoice_id, reference_no
             FROM finance_bank_mutations
             WHERE id = :id AND office_id = :office_id
             LIMIT 1'
        );
        $mutationStmt->execute([
            ':id' => $mutationId,
            ':office_id' => $officeId,
        ]);
        $mutation = $mutationStmt->fetch();
        if ($mutation === false) {
            json_response(404, ['message' => 'Data mutasi tidak ditemukan.']);
        }
        if ((int) ($mutation['is_credit'] ?? 0) !== 1) {
            json_response(422, ['message' => 'Mutasi debit tidak bisa di-approve sebagai pembayaran.']);
        }

        $invoiceId = $overrideInvoiceId > 0
            ? $overrideInvoiceId
            : (int) ($mutation['matched_invoice_id'] ?? 0);
        if ($invoiceId <= 0) {
            json_response(422, ['message' => 'Mutasi ini belum memiliki tagihan target.']);
        }

        $invoiceStmt = db()->prepare(
            'SELECT id, student_id, payment_type_id
             FROM finance_invoices
             WHERE id = :id AND office_id = :office_id
             LIMIT 1'
        );
        $invoiceStmt->execute([
            ':id' => $invoiceId,
            ':office_id' => $officeId,
        ]);
        $invoice = $invoiceStmt->fetch();
        if ($invoice === false) {
            json_response(404, ['message' => 'Tagihan target tidak ditemukan.']);
        }

        $referenceNo = 'MUTATION-' . $mutationId;
        $existingPaymentStmt = db()->prepare(
            <<<'SQL'
SELECT id FROM finance_payments
             WHERE office_id = :office_id
               AND source = 'bank_mutation'
               AND reference_no = :reference_no
             LIMIT 1
SQL
        );
        $existingPaymentStmt->execute([
            ':office_id' => $officeId,
            ':reference_no' => $referenceNo,
        ]);
        $existingPaymentId = (int) ($existingPaymentStmt->fetchColumn() ?: 0);
        if ($existingPaymentId <= 0) {
            $insertPaymentStmt = db()->prepare(
                'INSERT INTO finance_payments
                  (office_id, invoice_id, student_id, payment_type_id, source, reference_no, amount, payment_date, status, notes, created_by_user_id)
                 VALUES
                  (:office_id, :invoice_id, :student_id, :payment_type_id, :source, :reference_no, :amount, :payment_date, :status, :notes, :created_by_user_id)'
            );
            $insertPaymentStmt->execute([
                ':office_id' => $officeId,
                ':invoice_id' => (int) $invoice['id'],
                ':student_id' => (int) $invoice['student_id'],
                ':payment_type_id' => (int) $invoice['payment_type_id'],
                ':source' => 'bank_mutation',
                ':reference_no' => $referenceNo,
                ':amount' => to_non_negative_int($mutation['amount'] ?? 0),
                ':payment_date' => normalize_datetime_string($mutation['mutation_date'] ?? null),
                ':status' => 'approved',
                ':notes' => 'Approved dari mutasi bank #' . $mutationId,
                ':created_by_user_id' => $actorUserId > 0 ? $actorUserId : null,
            ]);
            $paymentId = (int) db()->lastInsertId();

            $insertCashStmt = db()->prepare(
                <<<'SQL'
INSERT INTO finance_cash_transactions
  (office_id, source_key, kind, category, description, amount, transaction_date, status, source, related_payment_id, created_by_user_id)
VALUES
  (:office_id, :source_key, :kind, :category, :description, :amount, :transaction_date, :status, :source, :related_payment_id, :created_by_user_id)
ON DUPLICATE KEY UPDATE
  amount = VALUES(amount),
  transaction_date = VALUES(transaction_date),
  status = VALUES(status),
  related_payment_id = VALUES(related_payment_id)
SQL
            );
            $insertCashStmt->execute([
                ':office_id' => $officeId,
                ':source_key' => sha1('bank-mutation-approve:' . $mutationId),
                ':kind' => 'income',
                ':category' => 'Mutasi Bank',
                ':description' => substr((string) ($mutation['description'] ?? ''), 0, 255),
                ':amount' => to_non_negative_int($mutation['amount'] ?? 0),
                ':transaction_date' => normalize_datetime_string($mutation['mutation_date'] ?? null),
                ':status' => 'completed',
                ':source' => 'auto_match',
                ':related_payment_id' => $paymentId,
                ':created_by_user_id' => $actorUserId > 0 ? $actorUserId : null,
            ]);
        } else {
            $paymentId = $existingPaymentId;
        }

        recalculate_invoice_status((int) $invoice['id']);

        $updateMutationStmt = db()->prepare(
            'UPDATE finance_bank_mutations
             SET match_status = :match_status,
                 matched_student_id = :matched_student_id,
                 matched_invoice_id = :matched_invoice_id,
                 reviewed_by_user_id = :reviewed_by_user_id,
                 reviewed_at = :reviewed_at
             WHERE id = :id AND office_id = :office_id'
        );
        $updateMutationStmt->execute([
            ':match_status' => 'approved',
            ':matched_student_id' => (int) $invoice['student_id'],
            ':matched_invoice_id' => (int) $invoice['id'],
            ':reviewed_by_user_id' => $actorUserId > 0 ? $actorUserId : null,
            ':reviewed_at' => gmdate('Y-m-d H:i:s'),
            ':id' => $mutationId,
            ':office_id' => $officeId,
        ]);

        write_audit_log(
            $officeId,
            $actorUserId > 0 ? $actorUserId : null,
            'bank_mutation.approve',
            'bank_mutation',
            (string) $mutationId,
            [
                'invoiceId' => (int) $invoice['id'],
                'paymentId' => $paymentId,
            ]
        );

        json_response(200, [
            'message' => 'Mutasi berhasil di-approve sebagai pembayaran.',
            'data' => [
                'mutationId' => $mutationId,
                'invoiceId' => (int) $invoice['id'],
                'paymentId' => $paymentId,
            ],
        ]);
    }

    if (preg_match('#^/api/bank-mutations/(\d+)/reject$#', $path, $matches) === 1 && $method === 'POST') {
        $session = require_user_session();
        require_role(['owner', 'admin', 'operator'], $session);
        $officeId = (int) $session['office_id'];
        $actorUserId = (int) $session['user_id'];
        $mutationId = (int) $matches[1];

        $stmt = db()->prepare(
            'UPDATE finance_bank_mutations
             SET match_status = :status,
                 reviewed_by_user_id = :reviewed_by_user_id,
                 reviewed_at = :reviewed_at
             WHERE id = :id AND office_id = :office_id'
        );
        $stmt->execute([
            ':status' => 'rejected',
            ':reviewed_by_user_id' => $actorUserId > 0 ? $actorUserId : null,
            ':reviewed_at' => gmdate('Y-m-d H:i:s'),
            ':id' => $mutationId,
            ':office_id' => $officeId,
        ]);

        if ($stmt->rowCount() < 1) {
            json_response(404, ['message' => 'Data mutasi tidak ditemukan.']);
        }

        write_audit_log(
            $officeId,
            $actorUserId > 0 ? $actorUserId : null,
            'bank_mutation.reject',
            'bank_mutation',
            (string) $mutationId
        );

        json_response(200, [
            'message' => 'Mutasi ditandai rejected.',
        ]);
    }

    if ($path === '/api/reports/summary' && $method === 'GET') {
        $session = require_user_session();
        require_role(['owner', 'admin', 'operator', 'viewer'], $session);

        $stmt = db()->prepare('SELECT payload FROM app_state WHERE id = 1');
        $stmt->execute();
        $row = $stmt->fetch();
        $payload = [];
        if ($row !== false) {
            $decoded = json_decode((string) $row['payload'], true);
            if (is_array($decoded)) {
                $payload = $decoded;
            }
        }

        $students = is_array($payload['students'] ?? null) ? $payload['students'] : [];
        $paymentTypes = is_array($payload['paymentTypes'] ?? null) ? $payload['paymentTypes'] : [];
        $transactions = is_array($payload['transactions'] ?? null) ? $payload['transactions'] : [];

        $activeStudentCount = count($students);
        $unpaidBillCount = 0;
        foreach ($students as $student) {
            if (!is_array($student)) {
                continue;
            }
            $paidTypeIds = is_array($student['paidTypeIds'] ?? null) ? $student['paidTypeIds'] : [];
            $paidLookup = [];
            foreach ($paidTypeIds as $paid) {
                $paidLookup[(string) $paid] = true;
            }

            $major = trim((string) ($student['major'] ?? ''));
            $semester = (int) ($student['semester'] ?? 0);
            if ($semester <= 0) {
                $className = (string) ($student['className'] ?? '');
                if (preg_match('/\\d+/', $className, $m) === 1) {
                    $semester = (int) $m[0];
                }
            }

            foreach ($paymentTypes as $paymentType) {
                if (!is_array($paymentType)) {
                    continue;
                }
                $id = (string) ($paymentType['id'] ?? '');
                if ($id === '') {
                    continue;
                }
                $targetMajor = trim((string) ($paymentType['targetMajor'] ?? ''));
                $targetSemester = (int) ($paymentType['targetSemester'] ?? 0);
                if ($targetMajor !== '' && $targetMajor !== $major) {
                    continue;
                }
                if ($targetSemester > 0 && $targetSemester !== $semester) {
                    continue;
                }
                if (!isset($paidLookup[$id])) {
                    $unpaidBillCount++;
                }
            }
        }

        $totalIncome = 0;
        $totalExpense = 0;
        $pendingTransactionCount = 0;
        $failedTransactionCount = 0;
        foreach ($transactions as $transaction) {
            if (!is_array($transaction)) {
                continue;
            }
            $amount = (int) ($transaction['amount'] ?? 0);
            $isIncome = ($transaction['isIncome'] ?? false) === true;
            if ($isIncome) {
                $totalIncome += $amount;
            } else {
                $totalExpense += $amount;
            }
            $status = (string) ($transaction['status'] ?? 'completed');
            if ($status === 'pending') {
                $pendingTransactionCount++;
            } elseif ($status === 'failed') {
                $failedTransactionCount++;
            }
        }

        json_response(200, [
            'data' => [
                'activeStudentCount' => $activeStudentCount,
                'unpaidBillCount' => $unpaidBillCount,
                'totalIncome' => $totalIncome,
                'totalExpense' => $totalExpense,
                'pendingTransactionCount' => $pendingTransactionCount,
                'failedTransactionCount' => $failedTransactionCount,
            ],
        ]);
    }

    if ($path === '/api/state') {
        $stateAuth = require_auth();

        if ($method === 'GET') {
            $stmt = db()->prepare('SELECT payload, updated_at FROM app_state WHERE id = 1');
            $stmt->execute();
            $row = $stmt->fetch();
            if (!$row) {
                json_response(404, ['message' => 'State not found']);
            }

            $payload = json_decode((string) $row['payload'], true);
            if (!is_array($payload)) {
                $payload = [];
            }

            json_response(200, [
                'data' => $payload,
                'updatedAt' => $row['updated_at'],
            ]);
        }

        if ($method === 'PUT') {
            $decoded = parse_json_body();
            if (!isset($decoded['data']) || !is_array($decoded['data'])) {
                json_response(422, ['message' => 'Invalid payload. Expected {"data": {...}}']);
            }

            $state = $decoded['data'];
            $jsonState = json_encode($state, JSON_UNESCAPED_UNICODE);
            if ($jsonState === false) {
                json_response(422, ['message' => 'Unable to encode state']);
            }

            $sql = <<<'SQL'
INSERT INTO app_state (id, payload)
VALUES (1, CAST(:payload AS JSON))
ON DUPLICATE KEY UPDATE payload = VALUES(payload), updated_at = CURRENT_TIMESTAMP
SQL;

            $stmt = db()->prepare($sql);
            $stmt->bindValue(':payload', $jsonState, PDO::PARAM_STR);
            $stmt->execute();

            if (($stateAuth['type'] ?? '') === 'session') {
                $session = $stateAuth['session'];
                if (is_array($session)) {
                    write_audit_log(
                        (int) $session['office_id'],
                        (int) $session['user_id'],
                        'state.update',
                        'app_state',
                        '1'
                    );
                }
            }

            json_response(200, ['message' => 'State saved']);
        }

        json_response(405, ['message' => 'Method not allowed']);
    }

    json_response(404, ['message' => 'Not found']);
} catch (Throwable $exception) {
    json_response(500, [
        'message' => 'Internal server error',
    ]);
}
