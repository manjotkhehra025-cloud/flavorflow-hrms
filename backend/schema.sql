PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT NOT NULL UNIQUE COLLATE NOCASE,
    password_hash TEXT NOT NULL,
    full_name TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS employees (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_code TEXT NOT NULL UNIQUE,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE COLLATE NOCASE,
    department TEXT NOT NULL,
    title TEXT NOT NULL,
    employment_type TEXT NOT NULL DEFAULT 'Official Staff',
    phone TEXT NOT NULL DEFAULT '',
    address TEXT NOT NULL DEFAULT '',
    weekly_off_days TEXT NOT NULL DEFAULT '[]',
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'on_leave')),
    start_date TEXT NOT NULL,
    manager_id INTEGER REFERENCES employees(id) ON DELETE SET NULL,
    user_id INTEGER UNIQUE REFERENCES users(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS roles (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT NOT NULL DEFAULT '',
    is_system INTEGER NOT NULL DEFAULT 0 CHECK (is_system IN (0, 1)),
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS permissions (
    key TEXT PRIMARY KEY,
    module TEXT NOT NULL,
    action TEXT NOT NULL,
    label TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS user_roles (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id TEXT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE IF NOT EXISTS role_permissions (
    role_id TEXT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_key TEXT NOT NULL REFERENCES permissions(key) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_key)
);

CREATE TABLE IF NOT EXISTS sessions (
    token_hash TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL
);

-- A device-scoped secret used only after local biometric verification. Its hash
-- is stored server-side and exchanged for a short-lived API session at sign-in.
CREATE TABLE IF NOT EXISTS biometric_login_tokens (
    token_hash TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_biometric_login_tokens_user_expiry
    ON biometric_login_tokens(user_id, expires_at);

CREATE TABLE IF NOT EXISTS work_locations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    address TEXT NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    radius_m INTEGER NOT NULL CHECK (radius_m > 0),
    timezone TEXT NOT NULL DEFAULT 'UTC',
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS attendance_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    work_location_id INTEGER REFERENCES work_locations(id) ON DELETE SET NULL,
    punch_in_at TEXT NOT NULL,
    punch_in_latitude REAL NOT NULL,
    punch_in_longitude REAL NOT NULL,
    punch_in_accuracy_m REAL,
    punch_in_distance_m REAL NOT NULL DEFAULT 0,
    punch_out_at TEXT,
    punch_out_latitude REAL,
    punch_out_longitude REAL,
    punch_out_accuracy_m REAL,
    punch_out_distance_m REAL,
    punch_source TEXT NOT NULL DEFAULT 'gps' CHECK (punch_source IN ('gps', 'manual')),
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS shift_templates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    break_minutes INTEGER NOT NULL DEFAULT 0 CHECK (break_minutes BETWEEN 0 AND 600),
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_active_shift_template_name
    ON shift_templates(name COLLATE NOCASE) WHERE is_active = 1;

CREATE TABLE IF NOT EXISTS shift_assignments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    shift_id INTEGER NOT NULL REFERENCES shift_templates(id),
    work_date TEXT NOT NULL,
    work_location_id INTEGER REFERENCES work_locations(id) ON DELETE SET NULL,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    assigned_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_active_shift_assignment_employee_date
    ON shift_assignments(employee_id, work_date) WHERE is_active = 1;

CREATE TABLE IF NOT EXISTS leave_types (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    annual_allowance_days INTEGER NOT NULL DEFAULT 0,
    is_paid INTEGER NOT NULL DEFAULT 1 CHECK (is_paid IN (0, 1)),
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
);

-- Category-specific leave rules are seeded by the API for both staff types.
-- Official Staff allowances include monthly-reset Short Leave and weekly-off
-- attendance-earned Compensatory Leave; Yellow Card is 15 monthly-accrued EL only.
CREATE TABLE IF NOT EXISTS employment_leave_type_policies (
    employment_type TEXT NOT NULL CHECK (employment_type IN ('Official Staff', 'Yellow Card')),
    leave_type_id INTEGER NOT NULL REFERENCES leave_types(id) ON DELETE CASCADE,
    annual_allowance_days REAL NOT NULL DEFAULT 0 CHECK (annual_allowance_days BETWEEN 0 AND 3660),
    is_applicable INTEGER NOT NULL DEFAULT 1 CHECK (is_applicable IN (0, 1)),
    accrual_method TEXT NOT NULL DEFAULT 'annual' CHECK (accrual_method IN ('annual', 'monthly')),
    monthly_reset INTEGER NOT NULL DEFAULT 0 CHECK (monthly_reset IN (0, 1)),
    attendance_based INTEGER NOT NULL DEFAULT 0 CHECK (attendance_based IN (0, 1)),
    PRIMARY KEY (employment_type, leave_type_id)
);

CREATE TABLE IF NOT EXISTS leave_policy (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    period_start_month INTEGER NOT NULL DEFAULT 1 CHECK (period_start_month BETWEEN 1 AND 12),
    count_weekends INTEGER NOT NULL DEFAULT 1 CHECK (count_weekends IN (0, 1)),
    prorate_new_hires INTEGER NOT NULL DEFAULT 0 CHECK (prorate_new_hires IN (0, 1)),
    carryover_enabled INTEGER NOT NULL DEFAULT 0 CHECK (carryover_enabled IN (0, 1)),
    carryover_limit_days INTEGER NOT NULL DEFAULT 0 CHECK (carryover_limit_days BETWEEN 0 AND 365),
    updated_at TEXT NOT NULL,
    updated_by INTEGER REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS leave_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    leave_type_id INTEGER NOT NULL REFERENCES leave_types(id),
    start_date TEXT NOT NULL,
    end_date TEXT NOT NULL,
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    requested_at TEXT NOT NULL,
    decided_at TEXT,
    approver_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    decision_note TEXT
);

CREATE TABLE IF NOT EXISTS holidays (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    holiday_date TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_holidays_active_name_date
    ON holidays(name COLLATE NOCASE, holiday_date) WHERE is_active = 1;


CREATE TABLE IF NOT EXISTS leave_balance_adjustments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    leave_type_id INTEGER NOT NULL REFERENCES leave_types(id),
    period_start TEXT NOT NULL,
    days REAL NOT NULL CHECK (days BETWEEN -365 AND 365 AND days != 0),
    reason TEXT NOT NULL,
    adjusted_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    adjusted_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_leave_adjustments_employee_period
    ON leave_balance_adjustments(employee_id, leave_type_id, period_start);

CREATE TABLE IF NOT EXISTS overtime_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    work_date TEXT NOT NULL,
    hours REAL NOT NULL CHECK (hours > 0 AND hours <= 24),
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    requested_at TEXT NOT NULL,
    decided_at TEXT,
    approver_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    decision_note TEXT
);

CREATE TABLE IF NOT EXISTS manual_punch_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    work_date TEXT NOT NULL,
    requested_punch_in TEXT NOT NULL,
    requested_punch_out TEXT,
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    attendance_record_id INTEGER REFERENCES attendance_records(id) ON DELETE SET NULL,
    requested_at TEXT NOT NULL,
    decided_at TEXT,
    approver_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    decision_note TEXT
);

CREATE TABLE IF NOT EXISTS gate_passes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    requested_by INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pass_type TEXT NOT NULL CHECK (pass_type IN ('personal_exit', 'official_duty', 'visitor')),
    purpose TEXT NOT NULL,
    valid_from TEXT NOT NULL,
    valid_until TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    reference_code TEXT UNIQUE,
    requested_at TEXT NOT NULL,
    decided_at TEXT,
    decided_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    decision_note TEXT
);

-- KYC metadata only: the API never accepts or stores a full Aadhaar/PAN number
-- or an uploaded document blob. Only a last-four hint may be retained.
CREATE TABLE IF NOT EXISTS employee_kyc_documents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    document_type TEXT NOT NULL,
    last_four TEXT NOT NULL DEFAULT '' CHECK (last_four = '' OR length(last_four) = 4),
    expiry_date TEXT,
    notes TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'verified', 'rejected')),
    created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL,
    verified_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    verified_at TEXT,
    verification_note TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_employee_kyc_documents_employee_status
    ON employee_kyc_documents(employee_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS kra_templates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    department TEXT NOT NULL,
    role_title TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    weight_percent INTEGER NOT NULL CHECK (weight_percent BETWEEN 1 AND 100),
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kra_goals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    template_id INTEGER REFERENCES kra_templates(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    cycle TEXT NOT NULL,
    target TEXT NOT NULL DEFAULT '',
    weight_percent INTEGER NOT NULL DEFAULT 0 CHECK (weight_percent BETWEEN 0 AND 100),
    progress_percent INTEGER NOT NULL DEFAULT 0 CHECK (progress_percent BETWEEN 0 AND 100),
    self_comment TEXT NOT NULL DEFAULT '',
    manager_score INTEGER CHECK (manager_score BETWEEN 0 AND 100),
    manager_comment TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'not_started' CHECK (status IN ('not_started', 'in_progress', 'completed', 'reviewed')),
    created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_kra_goals_employee_cycle
    ON kra_goals(employee_id, cycle, status);

CREATE TABLE IF NOT EXISTS production_output_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    work_date TEXT NOT NULL,
    output_item TEXT NOT NULL,
    quantity REAL NOT NULL CHECK (quantity > 0 AND quantity <= 1000000000),
    unit TEXT NOT NULL,
    target_quantity REAL CHECK (target_quantity IS NULL OR target_quantity >= 0),
    notes TEXT NOT NULL DEFAULT '',
    logged_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_production_output_employee_date
    ON production_output_logs(employee_id, work_date DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_overtime_employee_status
    ON overtime_requests(employee_id, status, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_manual_punch_employee_status
    ON manual_punch_requests(employee_id, status, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_gate_pass_employee_status
    ON gate_passes(employee_id, status, requested_at DESC);

CREATE TABLE IF NOT EXISTS audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    actor_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT,
    details_json TEXT NOT NULL DEFAULT '{}',
    remote_address TEXT,
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_employees_manager ON employees(manager_id);
CREATE INDEX IF NOT EXISTS idx_attendance_employee_punch_in ON attendance_records(employee_id, punch_in_at DESC);
CREATE INDEX IF NOT EXISTS idx_attendance_punch_out ON attendance_records(punch_out_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_one_open_shift ON attendance_records(employee_id) WHERE punch_out_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_leave_employee_status ON leave_requests(employee_id, status, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_holidays_date_active ON holidays(holiday_date, is_active);
CREATE INDEX IF NOT EXISTS idx_shift_assignments_date ON shift_assignments(work_date, is_active);
CREATE INDEX IF NOT EXISTS idx_shift_assignments_employee_date ON shift_assignments(employee_id, work_date);
CREATE INDEX IF NOT EXISTS idx_audit_created_at ON audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_user_expiry ON sessions(user_id, expires_at);

-- Social Wall: posts and comments are visible to active signed-in employees.
CREATE TABLE IF NOT EXISTS social_posts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    author_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body TEXT NOT NULL CHECK (length(trim(body)) BETWEEN 1 AND 2000),
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS social_post_likes (
    post_id INTEGER NOT NULL REFERENCES social_posts(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL,
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS social_post_comments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    post_id INTEGER NOT NULL REFERENCES social_posts(id) ON DELETE CASCADE,
    author_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body TEXT NOT NULL CHECK (length(trim(body)) BETWEEN 1 AND 1000),
    created_at TEXT NOT NULL
);

-- Tickets marked confidential are limited to their submitter and helpdesk managers.
CREATE TABLE IF NOT EXISTS helpdesk_tickets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    requester_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    employee_id INTEGER REFERENCES employees(id) ON DELETE SET NULL,
    category TEXT NOT NULL CHECK (category IN ('payroll', 'attendance', 'leave', 'shift', 'workplace', 'grievance', 'other')),
    title TEXT NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 160),
    description TEXT NOT NULL CHECK (length(trim(description)) BETWEEN 1 AND 5000),
    is_confidential INTEGER NOT NULL DEFAULT 0 CHECK (is_confidential IN (0, 1)),
    priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high')),
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
    assigned_to INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    closed_at TEXT
);

CREATE TABLE IF NOT EXISTS helpdesk_ticket_comments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ticket_id INTEGER NOT NULL REFERENCES helpdesk_tickets(id) ON DELETE CASCADE,
    author_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body TEXT NOT NULL CHECK (length(trim(body)) BETWEEN 1 AND 2000),
    is_internal INTEGER NOT NULL DEFAULT 0 CHECK (is_internal IN (0, 1)),
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS recognition_awards (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    category TEXT NOT NULL CHECK (category IN ('star_worker', 'perfect_attendance', 'safety', 'shift_output', 'teamwork')),
    period TEXT NOT NULL,
    citation TEXT NOT NULL CHECK (length(trim(citation)) BETWEEN 1 AND 1000),
    awarded_by INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TEXT NOT NULL,
    UNIQUE (employee_id, category, period)
);

CREATE TABLE IF NOT EXISTS shift_swap_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    requester_employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    target_employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    requester_assignment_id INTEGER NOT NULL REFERENCES shift_assignments(id) ON DELETE CASCADE,
    target_assignment_id INTEGER NOT NULL REFERENCES shift_assignments(id) ON DELETE CASCADE,
    reason TEXT NOT NULL CHECK (length(trim(reason)) BETWEEN 1 AND 1000),
    status TEXT NOT NULL DEFAULT 'pending_target' CHECK (status IN ('pending_target', 'pending_manager', 'approved', 'rejected', 'cancelled')),
    target_decided_at TEXT,
    manager_decided_at TEXT,
    decided_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    decision_note TEXT,
    requested_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    CHECK (requester_employee_id <> target_employee_id),
    CHECK (requester_assignment_id <> target_assignment_id)
);

CREATE TABLE IF NOT EXISTS app_notifications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'general',
    entity_type TEXT,
    entity_id INTEGER,
    created_at TEXT NOT NULL,
    read_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_social_posts_active_created ON social_posts(is_active, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_social_comments_post_created ON social_post_comments(post_id, created_at);
CREATE INDEX IF NOT EXISTS idx_helpdesk_requester_created ON helpdesk_tickets(requester_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_helpdesk_status_created ON helpdesk_tickets(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_helpdesk_comments_ticket ON helpdesk_ticket_comments(ticket_id, created_at);
CREATE INDEX IF NOT EXISTS idx_recognition_period ON recognition_awards(period DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_shift_swap_requester_status ON shift_swap_requests(requester_employee_id, status);
CREATE INDEX IF NOT EXISTS idx_shift_swap_target_status ON shift_swap_requests(target_employee_id, status);
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread ON app_notifications(user_id, read_at, created_at DESC);
