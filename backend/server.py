#!/usr/bin/env python3
"""Small, self-contained REST API for the FlavorFlow HRMS native client.

The service intentionally uses only Python's standard library. It is suitable for
local development and demos; expose it to production only behind TLS, a hardened
reverse proxy, persistent backups, and an operational secrets policy.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import math
import os
import re
import secrets
import sqlite3
import threading
from contextlib import contextmanager
from datetime import date, datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Iterator
from urllib.parse import parse_qs, urlsplit

BASE_PATH = "/api/v1"
ROOT = Path(__file__).resolve().parent
DEFAULT_DB = ROOT / "data" / "hrms.sqlite3"
PBKDF2_ROUNDS = 240_000
SESSION_TOKEN_DAYS = 7
BIOMETRIC_LOGIN_TOKEN_DAYS = 30
EMPLOYMENT_CATEGORIES = ("Official Staff", "Yellow Card")
DEPARTMENT_OPTIONS = (
    "Production", "Agriculture", "Security", "Engineering", "Accounts", "Quality",
    # Retain legacy team names already present in existing HR records.
    "Management", "Quality - Lab", "Production & Quality",
)
YELLOW_CARD_LEAVE_RULE = "Yellow Card staff members strictly receive 15 Earned Leaves (EL) per year, accrued monthly at 1.25 days per elapsed month. Casual Leaves (CL), Sick Leaves (SL), Optional Holidays, and Short Leaves are not applicable."
KYC_DOCUMENT_TYPES = ("Aadhaar", "PAN", "ESIC", "Passport", "Bank Details", "Other")

# This is the server-owned permission catalog. It is stored in `permissions`,
# delivered to the app by GET /roles, and checked again on every protected API.
PERMISSION_CATALOG = (
    ("dashboard.read", "dashboard", "read", "View dashboard"),
    ("employees.read", "employees", "read", "View all employees"),
    ("employees.read.team", "employees", "read team", "View team employees"),
    ("employees.read.self", "employees", "read self", "View own employee profile"),
    ("employees.create", "employees", "create", "Create employees"),
    ("employees.update", "employees", "update", "Update employees"),
    ("employees.delete", "employees", "delete", "Delete employees"),
    ("team.read", "team", "read", "View the team directory and attendance presence"),
    ("idcard.read", "id card", "read", "View employee ID cards"),
    ("idcard.read.team", "id card", "read team", "View reporting-team ID cards"),
    ("idcard.read.self", "id card", "read self", "View own ID card"),
    ("idcard.update", "id card", "update", "Edit employee ID card contact details"),
    ("kra.read", "kra", "read", "View all Official Staff KRAs and goals"),
    ("kra.read.team", "kra", "read team", "View reporting-team KRAs and goals"),
    ("kra.read.self", "kra", "read self", "View own KRAs and goals"),
    ("kra.manage", "kra", "manage", "Manage role templates and assign goals"),
    ("kra.update.team", "kra", "update team", "Review reporting-team KRAs"),
    ("kra.update.self", "kra", "update self", "Update own goal progress"),
    ("output.read", "output", "read", "View all production output logs"),
    ("output.read.team", "output", "read team", "View reporting-team output logs"),
    ("output.read.self", "output", "read self", "View own production output logs"),
    ("output.create.self", "output", "create self", "Add own production output log"),
    ("output.manage", "output", "manage", "Manage all production output logs"),
    ("kyc.read", "kyc", "read", "View employee KYC metadata"),
    ("kyc.read.self", "kyc", "read self", "View own KYC metadata"),
    ("kyc.create.self", "kyc", "create self", "Add own KYC metadata"),
    ("kyc.manage", "kyc", "manage", "Review and verify employee KYC metadata"),
    ("attendance.read", "attendance", "read", "View all attendance"),
    ("attendance.read.team", "attendance", "read team", "View team attendance"),
    ("attendance.read.self", "attendance", "read self", "View own attendance"),
    ("attendance.punch", "attendance", "punch", "Punch in and out"),
    ("attendance.manage", "attendance", "manage", "Manage attendance records"),
    ("attendance.request", "attendance", "request", "Request overtime and attendance corrections"),
    ("attendance.approve", "attendance", "approve", "Review team overtime and attendance corrections"),
    ("locations.read", "locations", "read", "View work locations"),
    ("locations.create", "locations", "create", "Create work locations"),
    ("locations.update", "locations", "update", "Update work locations"),
    ("locations.delete", "locations", "delete", "Delete work locations"),
    ("calendar.read", "calendar", "read", "View the holiday calendar"),
    ("calendar.manage", "calendar", "manage", "Manage company holidays"),
    ("shifts.read", "shifts", "read", "View all shift assignments"),
    ("shifts.read.team", "shifts", "read team", "View team shift assignments"),
    ("shifts.read.self", "shifts", "read self", "View own shift assignments"),
    ("shifts.manage", "shifts", "manage", "Manage shift templates and assignments"),
    ("leave.read", "leave", "read", "View all leave requests"),
    ("leave.read.team", "leave", "read team", "View team leave requests"),
    ("leave.read.self", "leave", "read self", "View own leave requests"),
    ("leave.create", "leave", "create", "Submit leave requests"),
    ("leave.approve", "leave", "approve", "Approve or reject leave requests"),
    ("leave.manage", "leave", "manage", "Manage all leave requests"),
    ("leave.policy.manage", "leave", "manage policy", "Configure leave balance and period rules"),
    ("leave.balance.manage", "leave", "manage balance", "Adjust employee leave balances"),
    ("gatepass.read", "gate pass", "read", "View all gate passes"),
    ("gatepass.read.team", "gate pass", "read team", "View reporting-team gate passes"),
    ("gatepass.read.self", "gate pass", "read self", "View own gate passes"),
    ("gatepass.create", "gate pass", "create", "Request a gate pass"),
    ("gatepass.approve", "gate pass", "approve", "Review reporting-team gate passes"),
    ("gatepass.manage", "gate pass", "manage", "Manage all gate passes"),
    ("users.read", "users", "read", "View user accounts"),
    ("users.create", "users", "create", "Create user accounts"),
    ("users.update", "users", "update", "Update user accounts"),
    ("rbac.read", "rbac", "read", "View roles and permission catalog"),
    ("rbac.update", "rbac", "update", "Create roles and edit permissions"),
    ("audit.read", "audit", "read", "View audit log"),
    ("reports.read", "reports", "read", "View workforce and attendance reports"),
    ("social.read", "social", "read", "View the Social Wall"),
    ("social.create", "social", "create", "Create Social Wall posts and comments"),
    ("social.manage", "social", "manage", "Moderate Social Wall posts"),
    ("helpdesk.create", "helpdesk", "create", "Submit helpdesk tickets and grievances"),
    ("helpdesk.read.self", "helpdesk", "read self", "View own helpdesk tickets"),
    ("helpdesk.manage", "helpdesk", "manage", "Manage helpdesk tickets and confidential grievances"),
    ("recognition.read", "recognition", "read", "View employee recognition awards"),
    ("recognition.manage", "recognition", "manage", "Issue employee recognition awards"),
    ("shifts.swap.request", "shifts", "request swap", "Request a shift swap"),
    ("shifts.swap.approve", "shifts", "approve swaps", "Approve reporting-team shift swaps"),
    ("notifications.read", "notifications", "read", "View in-app notifications"),
    ("notifications.test", "notifications", "test", "Create an in-app notification test"),
)

ROLE_SEEDS: dict[str, tuple[str, str, set[str]]] = {
    "super_admin": (
        "Super Admin",
        "Immutable system role with full access to every permission in the catalog.",
        {permission[0] for permission in PERMISSION_CATALOG},
    ),
    "hr_admin": (
        "HR Admin",
        "People operations access for employee, attendance, location, and leave administration.",
        {
            "dashboard.read", "employees.read", "employees.create", "employees.update",
            "team.read", "idcard.read", "idcard.update", "kra.read", "kra.manage", "kyc.read", "kyc.manage", "output.read", "output.manage", "attendance.read", "attendance.manage",
            "attendance.request", "attendance.approve", "locations.read", "locations.create",
            "locations.update", "calendar.read", "calendar.manage", "shifts.read", "shifts.manage",
            "leave.read", "leave.create",
            "leave.approve", "leave.manage", "leave.policy.manage", "leave.balance.manage",
            "gatepass.read", "gatepass.create", "gatepass.approve", "gatepass.manage",
            "users.read", "audit.read", "reports.read", "social.read", "social.create", "social.manage",
            "helpdesk.create", "helpdesk.read.self", "helpdesk.manage", "recognition.read", "recognition.manage",
            "shifts.swap.approve", "notifications.read", "notifications.test",
        },
    ),
    "people_ops": (
        "People Ops",
        "People Operations access to employee records, HR workflows, confidential grievances, and recognition.",
        {
            "dashboard.read", "employees.read", "employees.create", "employees.update",
            "team.read", "idcard.read", "idcard.update", "kra.read", "kra.manage", "kyc.read", "kyc.manage", "output.read", "output.manage", "attendance.read", "attendance.manage",
            "attendance.request", "attendance.approve", "locations.read", "locations.create",
            "locations.update", "calendar.read", "calendar.manage", "shifts.read", "shifts.manage",
            "leave.read", "leave.create", "leave.approve", "leave.manage", "leave.policy.manage",
            "leave.balance.manage", "gatepass.read", "gatepass.create", "gatepass.approve",
            "gatepass.manage", "users.read", "audit.read", "reports.read", "social.read", "social.create",
            "social.manage", "helpdesk.create", "helpdesk.read.self", "helpdesk.manage",
            "recognition.read", "recognition.manage", "shifts.swap.approve",
            "notifications.read", "notifications.test",
        },
    ),
    "manager": (
        "Manager",
        "Team-level visibility and leave approvals.",
        {
            "dashboard.read", "employees.read.team", "attendance.read.team", "locations.read",
            "team.read", "idcard.read.team", "idcard.read.self", "kra.read.team", "kra.read.self", "kra.update.team", "output.read.team", "output.read.self", "output.create.self", "attendance.request", "attendance.approve",
            "gatepass.read.team", "gatepass.read.self", "gatepass.create", "gatepass.approve",
            "calendar.read", "shifts.read.team", "shifts.read.self", "leave.read.team",
            "leave.read.self", "leave.create", "leave.approve", "social.read", "social.create",
            "helpdesk.create", "helpdesk.read.self", "recognition.read", "shifts.swap.request",
            "shifts.swap.approve", "notifications.read", "notifications.test",
        },
    ),
    "employee": (
        "Employee",
        "Self-service attendance and leave access.",
        {
            "dashboard.read", "employees.read.self", "team.read", "idcard.read.self",
            "kyc.read.self", "kyc.create.self", "kra.read.self", "kra.update.self", "output.read.self", "output.create.self",
            "attendance.read.self", "attendance.punch", "attendance.request", "gatepass.read.self",
            "gatepass.create", "locations.read", "calendar.read", "shifts.read.self",
            "leave.read.self", "leave.create", "social.read", "social.create", "helpdesk.create",
            "helpdesk.read.self", "recognition.read", "shifts.swap.request", "notifications.read", "notifications.test",
        },
    ),
}


class ApiError(Exception):
    def __init__(self, status: int, message: str, details: Any | None = None):
        super().__init__(message)
        self.status = status
        self.message = message
        self.details = details


class HRMSApplication:
    def __init__(self, db_path: str | Path = DEFAULT_DB):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_lock = threading.Lock()
        self._initialize()

    @contextmanager
    def _db(self) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(str(self.db_path), timeout=15)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA busy_timeout = 15000")
        try:
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def _initialize(self) -> None:
        with self._init_lock, self._db() as connection:
            connection.executescript((ROOT / "schema.sql").read_text(encoding="utf-8"))
            self._ensure_column(connection, "employees", "phone", "TEXT NOT NULL DEFAULT ''")
            self._ensure_column(connection, "employees", "address", "TEXT NOT NULL DEFAULT ''")
            self._ensure_column(connection, "employees", "weekly_off_days", "TEXT NOT NULL DEFAULT '[]'")
            self._ensure_column(
                connection,
                "attendance_records",
                "punch_source",
                "TEXT NOT NULL DEFAULT 'gps' CHECK (punch_source IN ('gps', 'manual'))",
            )
            self._ensure_column(
                connection,
                "employment_leave_type_policies",
                "monthly_reset",
                "INTEGER NOT NULL DEFAULT 0 CHECK (monthly_reset IN (0, 1))",
            )
            self._ensure_column(
                connection,
                "employment_leave_type_policies",
                "attendance_based",
                "INTEGER NOT NULL DEFAULT 0 CHECK (attendance_based IN (0, 1))",
            )
            now = _now()
            connection.execute(
                """INSERT OR IGNORE INTO leave_policy
                   (id, period_start_month, count_weekends, prorate_new_hires,
                    carryover_enabled, carryover_limit_days, updated_at)
                   VALUES (1, 1, 1, 0, 0, 0, ?)""",
                (now,),
            )
            for permission in PERMISSION_CATALOG:
                connection.execute(
                    "INSERT OR IGNORE INTO permissions(key, module, action, label) VALUES (?, ?, ?, ?)",
                    permission,
                )
            for role_id, (name, description, grants) in ROLE_SEEDS.items():
                connection.execute(
                    "INSERT OR IGNORE INTO roles(id, name, description, is_system, created_at) VALUES (?, ?, ?, ?, ?)",
                    (role_id, name, description, int(role_id == "super_admin"), now),
                )
                for permission_key in grants:
                    connection.execute(
                        "INSERT OR IGNORE INTO role_permissions(role_id, permission_key) VALUES (?, ?)",
                        (role_id, permission_key),
                    )
            # The Super Admin's effective access is also expanded from the live DB
            # catalog in _effective_permissions(), so new catalog rows are covered.
            connection.execute("DELETE FROM role_permissions WHERE role_id = 'super_admin'")
            connection.executemany(
                "INSERT INTO role_permissions(role_id, permission_key) VALUES ('super_admin', ?)",
                [(row[0],) for row in connection.execute("SELECT key FROM permissions").fetchall()],
            )

            if connection.execute("SELECT COUNT(*) FROM users").fetchone()[0] == 0:
                self._seed_demo_data(connection, now)

            # Normalize the legacy display name while preserving its existing ID
            # and all linked leave requests.
            connection.execute(
                """UPDATE leave_types SET name = 'Sick Leave (SL)'
                   WHERE name = 'Sick leave'
                   AND NOT EXISTS (SELECT 1 FROM leave_types WHERE name = 'Sick Leave (SL)')"""
            )
            # Add screenshot-aligned leave types without rewriting allowance
            # values or existing leave requests.
            connection.executemany(
                "INSERT OR IGNORE INTO leave_types(name, annual_allowance_days, is_paid, is_active) VALUES (?, 0, 1, 1)",
                [
                    ("Earned Leave (EL)",), ("Casual Leave (CL)",),
                    ("Optional Holiday",), ("Short Leave",), ("Compensatory Leave",),
                ],
            )
            leave_types = connection.execute(
                "SELECT id, name FROM leave_types WHERE is_active = 1"
            ).fetchall()
            official_rules = {
                "Earned Leave (EL)": (14, 1, "annual", 0, 0),
                "Sick Leave (SL)": (14, 1, "annual", 0, 0),
                "Casual Leave (CL)": (7, 1, "annual", 0, 0),
                # Stored as 24 days/year; the monthly-reset rule exposes 2 days per month.
                "Short Leave": (24, 1, "monthly", 1, 0),
                # Credits are derived from completed attendance on a scheduled weekly off.
                "Compensatory Leave": (0, 1, "annual", 0, 1),
            }
            for leave_type in leave_types:
                annual_allowance, applicable, accrual_method, monthly_reset, attendance_based = official_rules.get(
                    leave_type["name"], (0, 0, "annual", 0, 0)
                )
                connection.execute(
                    """INSERT OR IGNORE INTO employment_leave_type_policies
                       (employment_type, leave_type_id, annual_allowance_days, is_applicable,
                        accrual_method, monthly_reset, attendance_based)
                       VALUES ('Official Staff', ?, ?, ?, ?, ?, ?)""",
                    (leave_type["id"], annual_allowance, applicable, accrual_method, monthly_reset, attendance_based),
                )

            for leave_type in leave_types:
                is_earned_leave = leave_type["name"] == "Earned Leave (EL)"
                connection.execute(
                    """INSERT OR IGNORE INTO employment_leave_type_policies
                       (employment_type, leave_type_id, annual_allowance_days, is_applicable,
                        accrual_method, monthly_reset, attendance_based)
                       VALUES ('Yellow Card', ?, ?, ?, ?, 0, 0)""",
                    (leave_type["id"], 15 if is_earned_leave else 0, int(is_earned_leave), "monthly" if is_earned_leave else "annual"),
                )

    @staticmethod
    def _ensure_column(connection: sqlite3.Connection, table: str, column: str, declaration: str) -> None:
        existing = {row["name"] for row in connection.execute(f"PRAGMA table_info({table})")}
        if column not in existing:
            connection.execute(f"ALTER TABLE {table} ADD COLUMN {column} {declaration}")

    def _seed_demo_data(self, connection: sqlite3.Connection, now: str) -> None:
        admin_email = os.environ.get("HRMS_ADMIN_EMAIL", "admin@flavorflow.com").strip().lower()
        manager_email = os.environ.get("HRMS_MANAGER_EMAIL", "manager@flavorflow.com").strip().lower()
        employee_email = os.environ.get("HRMS_EMPLOYEE_EMAIL", "employee@flavorflow.com").strip().lower()
        admin_password = os.environ.get("HRMS_ADMIN_PASSWORD", "Admin123!")
        manager_password = os.environ.get("HRMS_MANAGER_PASSWORD", "Manager123!")
        employee_password = os.environ.get("HRMS_EMPLOYEE_PASSWORD", "Employee123!")
        # Fresh-install demo profiles mirror the supplied roster. Existing
        # initialized databases are intentionally not rewritten by this seed path.
        admin_id = self._insert_user(connection, admin_email, admin_password, "Super Admin", "super_admin", now)
        manager_id = self._insert_user(connection, manager_email, manager_password, "Harpreet Singh", "manager", now)
        employee_id = self._insert_user(connection, employee_email, employee_password, "Rajwinder Singh", "employee", now)

        # Keep the existing demo-seed convention; these are not verified hire dates.
        today = date.today().isoformat()
        seed_employees = (
            ("FF-001", "Super", "Admin", "admin@hrmate.com", "Management", "Super Admin", "Official Staff", [], None, admin_id),
            ("FF-002", "Harpreet", "Singh", "harpreet@hrmate.com", "Production", "Senior Executive", "Official Staff", ["Saturday"], None, manager_id),
            ("FF-003", "Rajwinder", "Singh", "rajwinder@hrmate.com", "Quality - Lab", "Lab Assistant", "Yellow Card", [], 2, employee_id),
            ("FF-004", "Manjot", "Singh", "manjotadmin@hrmate.com", "Production", "Super Admin", "Yellow Card", [], None, None),
            ("FF-005", "Ravinder", "Singh", "ravinder@hrmate.com", "Production & Quality", "Senior Manager Production", "Official Staff", [], None, None),
        )
        for code, first, last, email, department, title, employment_type, weekly_off_days, manager, user_id in seed_employees:
            connection.execute(
                """INSERT INTO employees
                   (employee_code, first_name, last_name, email, department, title, employment_type,
                    weekly_off_days, status, start_date, manager_id, user_id, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?)""",
                (code, first, last, email, department, title, employment_type, json.dumps(weekly_off_days),
                 today, manager, user_id, now, now),
            )

        connection.execute(
            """INSERT INTO work_locations(name, address, latitude, longitude, radius_m, timezone,
                   is_active, created_at, updated_at)
               VALUES ('Harbor HQ', '45 Bay Street, San Francisco', 37.7952, -122.3937, 250,
                       'America/Los_Angeles', 1, ?, ?)""",
            (now, now),
        )
        connection.executemany(
            "INSERT OR IGNORE INTO leave_types(name, annual_allowance_days, is_paid, is_active) VALUES (?, ?, ?, 1)",
            [("Annual leave", 0, 1), ("Sick leave", 0, 1), ("Personal leave", 0, 0)],
        )

    @staticmethod
    def _insert_user(
        connection: sqlite3.Connection,
        email: str,
        password: str,
        full_name: str,
        role_id: str,
        now: str,
    ) -> int:
        cursor = connection.execute(
            "INSERT INTO users(email, password_hash, full_name, is_active, created_at) VALUES (?, ?, ?, 1, ?)",
            (email, _hash_password(password), full_name, now),
        )
        user_id = int(cursor.lastrowid)
        connection.execute("INSERT INTO user_roles(user_id, role_id) VALUES (?, ?)", (user_id, role_id))
        return user_id

    def handle(
        self,
        method: str,
        raw_path: str,
        headers: dict[str, str] | None = None,
        body: dict[str, Any] | None = None,
        remote_address: str | None = None,
    ) -> tuple[int, dict[str, Any]]:
        headers = headers or {}
        body = body or {}
        parsed = urlsplit(raw_path)
        route = parsed.path.rstrip("/")
        query = {key: values[-1] for key, values in parse_qs(parsed.query).items()}
        if route == BASE_PATH and method == "GET":
            return 200, {"status": "ok", "service": "flavorflow-hrms-api", "health": f"{BASE_PATH}/health"}
        if route == f"{BASE_PATH}/health" and method == "GET":
            return 200, {"status": "ok", "service": "flavorflow-hrms-api"}
        if not route.startswith(BASE_PATH + "/"):
            return 404, {"error": {"message": "Route not found."}}
        endpoint = route[len(BASE_PATH):]
        try:
            if endpoint == "/auth/login" and method == "POST":
                return 200, self._login(body, remote_address)
            if endpoint == "/auth/biometric-login" and method == "POST":
                return 200, self._biometric_login(body, remote_address)
            if endpoint == "/auth/biometric-revoke" and method == "POST":
                return 200, self._revoke_biometric_login(body)
            user = self._authenticate(headers)
            if endpoint == "/auth/logout" and method == "POST":
                return 200, self._logout(user, headers, remote_address)
            if endpoint == "/auth/biometric-register" and method == "POST":
                return 201, self._register_biometric_login(user, remote_address)
            if endpoint == "/auth/me" and method == "GET":
                return 200, self._session_payload(user["id"])
            return self._route(method, endpoint, query, body, user, remote_address)
        except ApiError as exc:
            error: dict[str, Any] = {"message": exc.message}
            if exc.details is not None:
                error["details"] = exc.details
            return exc.status, {"error": error}
        except sqlite3.IntegrityError as exc:
            message = "The requested change conflicts with existing data."
            if "UNIQUE constraint failed: attendance_records.employee_id" in str(exc):
                message = "You are already punched in."
            elif (
                "holidays.name, holidays.holiday_date" in str(exc)
                or "idx_holidays_active_name_date" in str(exc)
            ):
                message = "A holiday with that name and date already exists."
            elif (
                "shift_assignments.employee_id, shift_assignments.work_date" in str(exc)
                or "idx_active_shift_assignment_employee_date" in str(exc)
            ):
                message = "This employee already has a shift assigned for that date."
            elif "shift_templates.name" in str(exc) or "idx_active_shift_template_name" in str(exc):
                message = "An active shift template with that name already exists."
            elif "UNIQUE constraint failed" in str(exc):
                message = "A record with that email or code already exists."
            return 409, {"error": {"message": message}}
        except (ValueError, TypeError, KeyError) as exc:
            return 400, {"error": {"message": str(exc) or "Invalid request."}}

    def _route(
        self,
        method: str,
        endpoint: str,
        query: dict[str, str],
        body: dict[str, Any],
        user: dict[str, Any],
        remote_address: str | None,
    ) -> tuple[int, dict[str, Any]]:
        if endpoint == "/dashboard" and method == "GET":
            self._require(user, "dashboard.read")
            return 200, self._dashboard(user)

        if endpoint == "/employee-options" and method == "GET":
            self._require_any(user, {
                "employees.read", "employees.read.team", "employees.read.self",
                "employees.create", "employees.update",
            })
            return 200, {
                "employment_types": [
                    {"value": "Official Staff", "label": "Official Staff"},
                    {"value": "Yellow Card", "label": "Yellow Card Staff (15 EL Only)"},
                ],
                "departments": list(DEPARTMENT_OPTIONS),
            }
        if endpoint == "/employees" and method == "GET":
            permissions = self._permissions(user["id"])
            self._require_any(user, {"employees.read", "employees.read.team", "employees.read.self"})
            return 200, self._list_employees(user, permissions, query.get("q", ""))
        if endpoint == "/employees" and method == "POST":
            self._require(user, "employees.create")
            return 201, self._create_employee(body, user, remote_address)
        employee_match = re.fullmatch(r"/employees/(\d+)", endpoint)
        if employee_match:
            employee_id = int(employee_match.group(1))
            if method == "GET":
                return 200, self._get_employee(employee_id, user)
            if method == "PATCH":
                self._require(user, "employees.update")
                return 200, self._update_employee(employee_id, body, user, remote_address)
            if method == "DELETE":
                self._require(user, "employees.delete")
                return 200, self._deactivate_employee(employee_id, user, remote_address)

        if endpoint == "/team" and method == "GET":
            self._require(user, "team.read")
            return 200, self._list_team(query)

        if endpoint == "/id-cards" and method == "GET":
            permissions = self._permissions(user["id"])
            self._require_any(user, {"idcard.read", "idcard.read.team", "idcard.read.self", "idcard.update"})
            return 200, self._list_id_cards(user, permissions, query)
        id_card_match = re.fullmatch(r"/id-cards/(\d+)", endpoint)
        if id_card_match and method == "PATCH":
            self._require(user, "idcard.update")
            return 200, self._update_id_card(int(id_card_match.group(1)), body, user, remote_address)

        if endpoint == "/kra/templates" and method == "GET":
            permissions = self._permissions(user["id"])
            self._require_any(user, {"kra.read", "kra.read.team", "kra.read.self", "kra.manage"})
            return 200, self._list_kra_templates(user, permissions)
        if endpoint == "/kra/templates" and method == "POST":
            self._require(user, "kra.manage")
            return 201, self._create_kra_template(body, user, remote_address)
        kra_template_match = re.fullmatch(r"/kra/templates/(\d+)", endpoint)
        if kra_template_match and method == "PATCH":
            self._require(user, "kra.manage")
            return 200, self._update_kra_template(int(kra_template_match.group(1)), body, user, remote_address)
        if endpoint == "/kra/goals" and method == "GET":
            permissions = self._permissions(user["id"])
            self._require_any(user, {"kra.read", "kra.read.team", "kra.read.self", "kra.manage"})
            return 200, self._list_kra_goals(user, permissions)
        if endpoint == "/kra/goals" and method == "POST":
            self._require(user, "kra.manage")
            return 201, self._create_kra_goal(body, user, remote_address)
        kra_goal_match = re.fullmatch(r"/kra/goals/(\d+)", endpoint)
        if kra_goal_match and method == "PATCH":
            return 200, self._update_kra_goal(int(kra_goal_match.group(1)), body, user, remote_address)

        if endpoint == "/output-logs" and method == "GET":
            permissions = self._permissions(user["id"])
            self._require_any(user, {"output.read", "output.read.team", "output.read.self", "output.create.self", "output.manage"})
            return 200, self._list_output_logs(user, permissions, query)
        if endpoint == "/output-logs" and method == "POST":
            self._require_any(user, {"output.create.self", "output.manage"})
            return 201, self._create_output_log(body, user, remote_address)

        if endpoint == "/kyc-documents" and method == "GET":
            permissions = self._permissions(user["id"])
            self._require_any(user, {"kyc.read", "kyc.read.self", "kyc.manage"})
            return 200, self._list_kyc_documents(user, permissions)
        if endpoint == "/kyc-documents" and method == "POST":
            self._require_any(user, {"kyc.create.self", "kyc.manage"})
            return 201, self._create_kyc_document(body, user, remote_address)
        kyc_verification = re.fullmatch(r"/kyc-documents/(\d+)/verification", endpoint)
        if kyc_verification and method == "PATCH":
            self._require(user, "kyc.manage")
            return 200, self._verify_kyc_document(int(kyc_verification.group(1)), body, user, remote_address)

        if endpoint == "/locations" and method == "GET":
            self._require(user, "locations.read")
            return 200, self._list_locations()
        if endpoint == "/locations" and method == "POST":
            self._require(user, "locations.create")
            return 201, self._create_location(body, user, remote_address)
        location_match = re.fullmatch(r"/locations/(\d+)", endpoint)
        if location_match and method == "PATCH":
            self._require(user, "locations.update")
            return 200, self._update_location(int(location_match.group(1)), body, user, remote_address)
        if location_match and method == "GET":
            self._require(user, "locations.read")
            location = self._location(int(location_match.group(1)))
            if not location:
                raise ApiError(404, "Work location not found.")
            return 200, location
        if location_match and method == "DELETE":
            self._require(user, "locations.delete")
            return 200, self._deactivate_location(int(location_match.group(1)), user, remote_address)

        if endpoint == "/holidays" and method == "GET":
            self._require(user, "calendar.read")
            return 200, self._list_holidays()
        if endpoint == "/holidays" and method == "POST":
            self._require(user, "calendar.manage")
            return 201, self._create_holiday(body, user, remote_address)
        holiday_match = re.fullmatch(r"/holidays/([0-9]+)", endpoint)
        if holiday_match and method == "GET":
            self._require(user, "calendar.read")
            holiday = self._holiday(int(holiday_match.group(1)))
            if not holiday:
                raise ApiError(404, "Holiday not found.")
            return 200, holiday
        if holiday_match and method == "PATCH":
            self._require(user, "calendar.manage")
            return 200, self._update_holiday(int(holiday_match.group(1)), body, user, remote_address)
        if holiday_match and method == "DELETE":
            self._require(user, "calendar.manage")
            return 200, self._deactivate_holiday(int(holiday_match.group(1)), user, remote_address)

        if endpoint == "/shift-templates" and method == "GET":
            self._require_any(user, {"shifts.read", "shifts.read.team", "shifts.read.self", "shifts.manage"})
            return 200, self._list_shift_templates()
        if endpoint == "/shift-templates" and method == "POST":
            self._require(user, "shifts.manage")
            return 201, self._create_shift_template(body, user, remote_address)
        shift_match = re.fullmatch(r"/shift-templates/([0-9]+)", endpoint)
        if shift_match and method == "PATCH":
            self._require(user, "shifts.manage")
            return 200, self._update_shift_template(int(shift_match.group(1)), body, user, remote_address)
        if shift_match and method == "DELETE":
            self._require(user, "shifts.manage")
            return 200, self._deactivate_shift_template(int(shift_match.group(1)), user, remote_address)

        if endpoint == "/shift-assignments" and method == "GET":
            permissions = self._permissions(user["id"])
            self._require_any(user, {"shifts.read", "shifts.read.team", "shifts.read.self", "shifts.manage"})
            return 200, self._list_shift_assignments(user, permissions, query)
        if endpoint == "/shift-assignments" and method == "POST":
            self._require(user, "shifts.manage")
            return 201, self._assign_shift(body, user, remote_address)
        assignment_match = re.fullmatch(r"/shift-assignments/([0-9]+)", endpoint)
        if assignment_match and method == "DELETE":
            self._require(user, "shifts.manage")
            return 200, self._deactivate_shift_assignment(int(assignment_match.group(1)), user, remote_address)

        if endpoint == "/attendance/punch-in" and method == "POST":
            self._require(user, "attendance.punch")
            return 201, self._punch_in(user, body, remote_address)
        if endpoint == "/attendance/punch-out" and method == "POST":
            self._require(user, "attendance.punch")
            return 200, self._punch_out(user, body, remote_address)
        if endpoint == "/attendance" and method == "GET":
            permissions = self._permissions(user["id"])
            self._require_any(user, {
                "attendance.read", "attendance.read.team", "attendance.read.self", "attendance.manage",
                "attendance.punch",
            })
            return 200, self._list_attendance(user, permissions, query)

        if endpoint == "/attendance/overtime-requests" and method == "GET":
            permissions = self._permissions(user["id"])
            self._require_any(user, {
                "attendance.request", "attendance.approve", "attendance.manage", "attendance.read",
                "attendance.read.team", "attendance.read.self", "attendance.punch",
            })
            return 200, self._list_attendance_requests("overtime", user, permissions, query)
        if endpoint == "/attendance/overtime-requests" and method == "POST":
            self._require(user, "attendance.request")
            return 201, self._create_overtime_request(body, user, remote_address)
        overtime_decision = re.fullmatch(r"/attendance/overtime-requests/(\d+)/decision", endpoint)
        if overtime_decision and method == "POST":
            self._require_any(user, {"attendance.approve", "attendance.manage"})
            return 200, self._decide_attendance_request(
                "overtime", int(overtime_decision.group(1)), body, user, remote_address
            )

        if endpoint == "/attendance/manual-punch-requests" and method == "GET":
            permissions = self._permissions(user["id"])
            self._require_any(user, {
                "attendance.request", "attendance.approve", "attendance.manage", "attendance.read",
                "attendance.read.team", "attendance.read.self", "attendance.punch",
            })
            return 200, self._list_attendance_requests("manual", user, permissions, query)
        if endpoint == "/attendance/manual-punch-requests" and method == "POST":
            self._require(user, "attendance.request")
            return 201, self._create_manual_punch_request(body, user, remote_address)
        manual_decision = re.fullmatch(r"/attendance/manual-punch-requests/(\d+)/decision", endpoint)
        if manual_decision and method == "POST":
            self._require_any(user, {"attendance.approve", "attendance.manage"})
            return 200, self._decide_attendance_request(
                "manual", int(manual_decision.group(1)), body, user, remote_address
            )

        if endpoint == "/leave-balance-adjustments" and method == "POST":
            self._require(user, "leave.balance.manage")
            return 201, self._create_leave_balance_adjustment(body, user, remote_address)

        if endpoint == "/gate-passes" and method == "GET":
            permissions = self._permissions(user["id"])
            self._require_any(user, {
                "gatepass.read", "gatepass.read.team", "gatepass.read.self", "gatepass.create",
                "gatepass.approve", "gatepass.manage",
            })
            return 200, self._list_gate_passes(user, permissions, query)
        if endpoint == "/gate-passes" and method == "POST":
            self._require_any(user, {"gatepass.create", "gatepass.manage"})
            return 201, self._create_gate_pass(body, user, remote_address)
        gate_pass_decision = re.fullmatch(r"/gate-passes/(\d+)/decision", endpoint)
        if gate_pass_decision and method == "POST":
            self._require_any(user, {"gatepass.approve", "gatepass.manage"})
            return 200, self._decide_gate_pass(
                int(gate_pass_decision.group(1)), body, user, remote_address
            )

        if endpoint == "/social-posts" and method == "GET":
            self._require(user, "social.read")
            return 200, self._list_social_posts(user)
        if endpoint == "/social-posts" and method == "POST":
            self._require(user, "social.create")
            return 201, self._create_social_post(body, user, remote_address)
        social_like = re.fullmatch(r"/social-posts/(\d+)/like", endpoint)
        if social_like and method == "POST":
            self._require(user, "social.create")
            return 200, self._toggle_social_like(int(social_like.group(1)), user, remote_address)
        social_comment = re.fullmatch(r"/social-posts/(\d+)/comments", endpoint)
        if social_comment and method == "POST":
            self._require(user, "social.create")
            return 201, self._create_social_comment(int(social_comment.group(1)), body, user, remote_address)
        social_post = re.fullmatch(r"/social-posts/(\d+)", endpoint)
        if social_post and method == "DELETE":
            self._require(user, "social.manage")
            return 200, self._deactivate_social_post(int(social_post.group(1)), user, remote_address)

        if endpoint == "/helpdesk-tickets" and method == "GET":
            self._require_any(user, {"helpdesk.read.self", "helpdesk.manage"})
            return 200, self._list_helpdesk_tickets(user, self._permissions(user["id"]), query)
        if endpoint == "/helpdesk-tickets" and method == "POST":
            self._require(user, "helpdesk.create")
            return 201, self._create_helpdesk_ticket(body, user, remote_address)
        ticket_match = re.fullmatch(r"/helpdesk-tickets/(\d+)", endpoint)
        if ticket_match and method == "GET":
            self._require_any(user, {"helpdesk.read.self", "helpdesk.manage"})
            return 200, self._get_helpdesk_ticket(int(ticket_match.group(1)), user)
        if ticket_match and method == "PATCH":
            self._require(user, "helpdesk.manage")
            if not self._can_manage_helpdesk(user):
                raise ApiError(403, "Only People Ops, HR Admin, and Super Admin can manage helpdesk tickets.")
            return 200, self._update_helpdesk_ticket(int(ticket_match.group(1)), body, user, remote_address)
        ticket_comments = re.fullmatch(r"/helpdesk-tickets/(\d+)/comments", endpoint)
        if ticket_comments and method == "POST":
            self._require_any(user, {"helpdesk.create", "helpdesk.manage"})
            return 201, self._create_helpdesk_comment(int(ticket_comments.group(1)), body, user, remote_address)

        if endpoint == "/recognition-awards" and method == "GET":
            self._require(user, "recognition.read")
            return 200, self._list_recognition_awards(query)
        if endpoint == "/recognition-awards" and method == "POST":
            self._require(user, "recognition.manage")
            if not self._can_manage_helpdesk(user):
                raise ApiError(403, "Only Admin, People Ops, and HR Admin can issue recognition awards.")
            return 201, self._create_recognition_award(body, user, remote_address)

        if endpoint == "/shift-swap-options" and method == "GET":
            self._require(user, "shifts.swap.request")
            return 200, self._list_shift_swap_options(query)
        if endpoint == "/shift-swap-requests" and method == "GET":
            self._require_any(user, {"shifts.swap.request", "shifts.swap.approve", "shifts.manage"})
            return 200, self._list_shift_swap_requests(user, self._permissions(user["id"]), query)
        if endpoint == "/shift-swap-requests" and method == "POST":
            self._require(user, "shifts.swap.request")
            return 201, self._create_shift_swap_request(body, user, remote_address)
        swap_decision = re.fullmatch(r"/shift-swap-requests/(\d+)/decision", endpoint)
        if swap_decision and method == "POST":
            self._require_any(user, {"shifts.swap.approve", "shifts.manage"})
            return 200, self._decide_shift_swap(int(swap_decision.group(1)), body, user, remote_address)
        swap_target_decision = re.fullmatch(r"/shift-swap-requests/(\d+)/target-decision", endpoint)
        if swap_target_decision and method == "POST":
            self._require(user, "shifts.swap.request")
            return 200, self._decide_shift_swap_target(int(swap_target_decision.group(1)), body, user, remote_address)
        swap_cancel = re.fullmatch(r"/shift-swap-requests/(\d+)/cancel", endpoint)
        if swap_cancel and method == "POST":
            self._require(user, "shifts.swap.request")
            return 200, self._cancel_shift_swap(int(swap_cancel.group(1)), user, remote_address)

        if endpoint == "/notifications" and method == "GET":
            self._require(user, "notifications.read")
            return 200, self._list_notifications(user)
        if endpoint == "/notifications/test" and method == "POST":
            self._require(user, "notifications.test")
            return 201, self._create_test_notification(user, remote_address)
        notification_match = re.fullmatch(r"/notifications/(\d+)", endpoint)
        if notification_match and method == "PATCH":
            self._require(user, "notifications.read")
            return 200, self._mark_notification_read(int(notification_match.group(1)), user, remote_address)

        if endpoint == "/leave-policy" and method == "GET":
            self._require(user, "leave.policy.manage")
            return 200, self._get_leave_policy()
        if endpoint == "/leave-policy" and method == "PATCH":
            self._require(user, "leave.policy.manage")
            return 200, self._update_leave_policy(body, user, remote_address)

        if endpoint == "/leave-types" and method == "GET":
            self._require_any(user, {
                "leave.read", "leave.read.self", "leave.read.team", "leave.create", "leave.approve", "leave.manage",
            })
            return 200, self._list_leave_types(user)
        if endpoint == "/leave-requests" and method == "GET":
            permissions = self._permissions(user["id"])
            self._require_any(user, {
                "leave.read", "leave.read.self", "leave.read.team", "leave.create", "leave.approve", "leave.manage",
            })
            return 200, self._list_leave_requests(user, permissions, query)
        if endpoint == "/leave-requests" and method == "POST":
            self._require(user, "leave.create")
            return 201, self._create_leave_request(body, user, remote_address)
        leave_match = re.fullmatch(r"/leave-requests/(\d+)", endpoint)
        if leave_match and method == "GET":
            return 200, self._get_leave_request(int(leave_match.group(1)), user)
        if leave_match and method == "PATCH":
            return 200, self._update_leave_request(int(leave_match.group(1)), body, user, remote_address)
        decision_match = re.fullmatch(r"/leave-requests/(\d+)/decision", endpoint)
        if decision_match and method == "POST":
            self._require(user, "leave.approve")
            return 200, self._decide_leave(int(decision_match.group(1)), body, user, remote_address)

        if endpoint == "/users" and method == "GET":
            self._require(user, "users.read")
            return 200, self._list_users()
        if endpoint == "/users" and method == "POST":
            self._require(user, "users.create")
            return 201, self._create_user(body, user, remote_address)
        user_match = re.fullmatch(r"/users/(\d+)", endpoint)
        if user_match and method == "PATCH":
            self._require(user, "users.update")
            return 200, self._update_user(int(user_match.group(1)), body, user, remote_address)

        if endpoint == "/roles" and method == "GET":
            self._require(user, "rbac.read")
            return 200, self._list_roles()
        if endpoint == "/roles" and method == "POST":
            self._require(user, "rbac.update")
            return 201, self._create_role(body, user, remote_address)
        role_permission_match = re.fullmatch(r"/roles/([a-z0-9_-]+)/permissions", endpoint)
        if role_permission_match and method == "PATCH":
            self._require(user, "rbac.update")
            return 200, self._update_role_permissions(role_permission_match.group(1), body, user, remote_address)

        if endpoint == "/audit-logs" and method == "GET":
            self._require(user, "audit.read")
            return 200, self._list_audit_logs(query)
        raise ApiError(404, "Route not found.")

    def _login(self, body: dict[str, Any], remote_address: str | None) -> dict[str, Any]:
        email = str(body.get("email", "")).strip().lower()
        password = str(body.get("password", ""))
        if not email or not password:
            raise ApiError(400, "Email and password are required.")

        enable_biometrics = body.get("enable_biometrics") is True
        previous_biometric_token = str(body.get("replace_biometric_token", "")).strip()
        with self._db() as connection:
            row = connection.execute(
                "SELECT * FROM users WHERE email = ? COLLATE NOCASE", (email,)
            ).fetchone()
            if not row or not row["is_active"] or not _verify_password(password, row["password_hash"]):
                raise ApiError(401, "Email or password is incorrect.")

            user_id = int(row["id"])
            now = datetime.now(timezone.utc)
            if previous_biometric_token:
                connection.execute(
                    "DELETE FROM biometric_login_tokens WHERE token_hash = ?",
                    (hashlib.sha256(previous_biometric_token.encode("utf-8")).hexdigest(),),
                )
            token = self._issue_session_token(connection, user_id, now)
            biometric_token = (
                self._issue_biometric_login_token(connection, user_id, now)
                if enable_biometrics
                else None
            )

        self._audit(
            user_id,
            "auth.login",
            "session",
            None,
            {"email": email, "biometric_login_enabled": enable_biometrics},
            remote_address,
        )
        result = {"token": token, "user": self._session_payload(user_id)}
        if biometric_token is not None:
            result["biometric_token"] = biometric_token
        return result

    def _biometric_login(
        self, body: dict[str, Any], remote_address: str | None
    ) -> dict[str, Any]:
        biometric_token = str(body.get("biometric_token", "")).strip()
        previous_session_token = str(body.get("previous_session_token", "")).strip()
        if not biometric_token:
            raise ApiError(400, "A biometric device token is required.")

        token_hash = hashlib.sha256(biometric_token.encode("utf-8")).hexdigest()
        now = datetime.now(timezone.utc)
        now_text = now.isoformat(timespec="seconds").replace("+00:00", "Z")
        inactive = False
        with self._db() as connection:
            row = connection.execute(
                """SELECT t.user_id, u.is_active FROM biometric_login_tokens t
                   JOIN users u ON u.id = t.user_id
                   WHERE t.token_hash = ? AND t.expires_at > ?""",
                (token_hash, now_text),
            ).fetchone()
            if row is None:
                raise ApiError(401, "Biometric sign-in expired. Sign in with your password again.")

            user_id = int(row["user_id"])
            if not row["is_active"]:
                connection.execute(
                    "DELETE FROM biometric_login_tokens WHERE token_hash = ?", (token_hash,)
                )
                inactive = True
            else:
                # Revoke the previous API session, then rotate the device
                # credential atomically with a fresh authenticated session.
                if previous_session_token:
                    connection.execute(
                        "DELETE FROM sessions WHERE token_hash = ? AND user_id = ?",
                        (
                            hashlib.sha256(previous_session_token.encode("utf-8")).hexdigest(),
                            user_id,
                        ),
                    )
                connection.execute(
                    "DELETE FROM biometric_login_tokens WHERE token_hash = ?", (token_hash,)
                )
                session_token = self._issue_session_token(connection, user_id, now)
                next_biometric_token = self._issue_biometric_login_token(
                    connection, user_id, now
                )

        if inactive:
            raise ApiError(401, "This account is inactive. Contact your HR team.")

        self._audit(user_id, "auth.biometric_login", "session", None, {}, remote_address)
        return {
            "token": session_token,
            "biometric_token": next_biometric_token,
            "user": self._session_payload(user_id),
        }

    def _register_biometric_login(
        self, user: dict[str, Any], remote_address: str | None
    ) -> dict[str, Any]:
        now = datetime.now(timezone.utc)
        with self._db() as connection:
            biometric_token = self._issue_biometric_login_token(
                connection, int(user["id"]), now
            )
        self._audit(
            user["id"], "auth.biometric_login_registered", "session", None, {}, remote_address
        )
        return {"biometric_token": biometric_token}

    def _revoke_biometric_login(self, body: dict[str, Any]) -> dict[str, Any]:
        biometric_token = str(body.get("biometric_token", "")).strip()
        if biometric_token:
            token_hash = hashlib.sha256(biometric_token.encode("utf-8")).hexdigest()
            with self._db() as connection:
                connection.execute(
                    "DELETE FROM biometric_login_tokens WHERE token_hash = ?", (token_hash,)
                )
        # Idempotent response avoids revealing whether a device token existed.
        return {"message": "Biometric sign-in disabled."}

    @staticmethod
    def _issue_session_token(
        connection: sqlite3.Connection, user_id: int, now: datetime
    ) -> str:
        token = secrets.token_urlsafe(36)
        expires = (now + timedelta(days=SESSION_TOKEN_DAYS)).isoformat(
            timespec="seconds"
        ).replace("+00:00", "Z")
        created = now.isoformat(timespec="seconds").replace("+00:00", "Z")
        connection.execute(
            "INSERT INTO sessions(token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)",
            (hashlib.sha256(token.encode("utf-8")).hexdigest(), user_id, expires, created),
        )
        return token

    @staticmethod
    def _issue_biometric_login_token(
        connection: sqlite3.Connection, user_id: int, now: datetime
    ) -> str:
        token = secrets.token_urlsafe(48)
        expires = (now + timedelta(days=BIOMETRIC_LOGIN_TOKEN_DAYS)).isoformat(
            timespec="seconds"
        ).replace("+00:00", "Z")
        created = now.isoformat(timespec="seconds").replace("+00:00", "Z")
        connection.execute(
            """INSERT INTO biometric_login_tokens(token_hash, user_id, expires_at, created_at)
               VALUES (?, ?, ?, ?)""",
            (hashlib.sha256(token.encode("utf-8")).hexdigest(), user_id, expires, created),
        )
        return token

    def _logout(
        self,
        user: dict[str, Any],
        headers: dict[str, str],
        remote_address: str | None,
    ) -> dict[str, Any]:
        token = _header(headers, "authorization").removeprefix("Bearer ").strip()
        if token:
            with self._db() as connection:
                connection.execute(
                    "DELETE FROM sessions WHERE token_hash = ?",
                    (hashlib.sha256(token.encode("utf-8")).hexdigest(),),
                )
        self._audit(user["id"], "auth.logout", "session", None, {}, remote_address)
        return {"message": "Signed out."}

    def _authenticate(self, headers: dict[str, str]) -> dict[str, Any]:
        authorization = _header(headers, "authorization")
        if not authorization.startswith("Bearer "):
            raise ApiError(401, "A bearer session token is required.")
        token = authorization[7:].strip()
        if not token:
            raise ApiError(401, "A bearer session token is required.")
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        with self._db() as connection:
            row = connection.execute(
                """SELECT u.id, u.email,
                          COALESCE(NULLIF(TRIM(e.first_name || ' ' || e.last_name), ''), u.full_name) AS full_name,
                          u.is_active
                   FROM sessions s JOIN users u ON u.id = s.user_id
                   LEFT JOIN employees e ON e.user_id = u.id
                   WHERE s.token_hash = ? AND s.expires_at > ?""",
                (token_hash, _now()),
            ).fetchone()
        if not row or not row["is_active"]:
            raise ApiError(401, "Session expired or user is inactive. Please sign in again.")
        return dict(row)

    def _session_payload(self, user_id: int) -> dict[str, Any]:
        with self._db() as connection:
            row = connection.execute(
                """SELECT u.id, u.email,
                          COALESCE(NULLIF(TRIM(e.first_name || ' ' || e.last_name), ''), u.full_name) AS full_name,
                          u.is_active
                   FROM users u LEFT JOIN employees e ON e.user_id = u.id
                   WHERE u.id = ?""", (user_id,)
            ).fetchone()
            if not row:
                raise ApiError(401, "User account no longer exists.")
            roles = connection.execute(
                "SELECT r.id, r.name FROM user_roles ur JOIN roles r ON r.id = ur.role_id WHERE ur.user_id = ? ORDER BY r.name",
                (user_id,),
            ).fetchall()
            employee = connection.execute("SELECT id FROM employees WHERE user_id = ?", (user_id,)).fetchone()
        permissions = sorted(self._permissions(user_id))
        return {
            "id": row["id"],
            "email": row["email"],
            "full_name": row["full_name"],
            "is_active": bool(row["is_active"]),
            "employee_id": employee["id"] if employee else None,
            "roles": [role["id"] for role in roles],
            "role_names": [role["name"] for role in roles],
            "permissions": permissions,
        }

    def _permissions(self, user_id: int) -> set[str]:
        with self._db() as connection:
            role_ids = {
                row[0] for row in connection.execute("SELECT role_id FROM user_roles WHERE user_id = ?", (user_id,))
            }
            if "super_admin" in role_ids:
                return {row[0] for row in connection.execute("SELECT key FROM permissions")}
            rows = connection.execute(
                """SELECT DISTINCT rp.permission_key FROM user_roles ur
                   JOIN role_permissions rp ON rp.role_id = ur.role_id WHERE ur.user_id = ?""",
                (user_id,),
            ).fetchall()
        return {row[0] for row in rows}

    def _require(self, user: dict[str, Any], permission: str) -> None:
        if permission not in self._permissions(user["id"]):
            raise ApiError(403, f"Missing permission: {permission}.")

    def _require_any(self, user: dict[str, Any], permissions: set[str]) -> None:
        if not self._permissions(user["id"]).intersection(permissions):
            raise ApiError(403, "Your role does not allow this action.")

    def _employee_for_user(self, user_id: int) -> sqlite3.Row | None:
        with self._db() as connection:
            return connection.execute("SELECT * FROM employees WHERE user_id = ?", (user_id,)).fetchone()

    def _can_access_employee(self, employee: sqlite3.Row, user: dict[str, Any], permissions: set[str], scope: str) -> bool:
        if f"{scope}.read" in permissions:
            return True
        own = employee["user_id"] == user["id"]
        manager = self._employee_id(user["id"])
        team = manager is not None and employee["manager_id"] == manager
        return (own and f"{scope}.read.self" in permissions) or (team and f"{scope}.read.team" in permissions)

    def _employee_id(self, user_id: int) -> int | None:
        # Resolve the employee profile from the active application database;
        # client-supplied employee IDs are never trusted for self/team scope.
        with self._db() as connection:
            row = connection.execute("SELECT id FROM employees WHERE user_id = ?", (user_id,)).fetchone()
        return row[0] if row else None

    def _list_employees(self, user: dict[str, Any], permissions: set[str], search: str) -> dict[str, Any]:
        with self._db() as connection:
            rows = connection.execute("SELECT * FROM employees ORDER BY first_name, last_name").fetchall()
        if "employees.read" not in permissions:
            rows = [row for row in rows if self._can_access_employee(row, user, permissions, "employees")]
        term = search.casefold().strip()
        if term:
            rows = [
                row for row in rows
                if term in " ".join(str(row[key] or "") for key in ("employee_code", "first_name", "last_name", "email", "department", "title")).casefold()
            ]
        return {"items": [_employee_json(row) for row in rows], "total": len(rows)}

    def _get_employee(self, employee_id: int, user: dict[str, Any]) -> dict[str, Any]:
        with self._db() as connection:
            row = connection.execute("SELECT * FROM employees WHERE id = ?", (employee_id,)).fetchone()
        if not row:
            raise ApiError(404, "Employee not found.")
        permissions = self._permissions(user["id"])
        if not self._can_access_employee(row, user, permissions, "employees"):
            raise ApiError(403, "You cannot view this employee.")
        return _employee_json(row)

    def _create_employee(self, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        required = ("employee_code", "first_name", "last_name", "email", "department", "title")
        values = {key: str(body.get(key, "")).strip() for key in required}
        if any(not value for value in values.values()):
            raise ApiError(400, "Employee code, name, email, department, and title are required.")
        if not _valid_email(values["email"]):
            raise ApiError(400, "Enter a valid employee email address.")
        employment_type = _normalize_employment_type(body.get("employment_type", "Official Staff"))
        start_date = _date_string(body.get("start_date"), date.today().isoformat())
        manager_id = _optional_int(body.get("manager_id"))
        phone = str(body.get("phone", "")).strip()
        address = str(body.get("address", "")).strip()
        weekly_off_days = _weekly_off_days(body.get("weekly_off_days", []))
        if len(phone) > 40 or len(address) > 240:
            raise ApiError(400, "Phone or address is longer than the allowed limit.")
        status = str(body.get("status", "active"))
        if status not in {"active", "inactive", "on_leave"}:
            raise ApiError(400, "Employee status must be active, inactive, or on_leave.")
        now = _now()
        with self._db() as connection:
            if manager_id is not None and not connection.execute("SELECT 1 FROM employees WHERE id = ?", (manager_id,)).fetchone():
                raise ApiError(400, "The selected manager does not exist.")
            cursor = connection.execute(
                """INSERT INTO employees(employee_code, first_name, last_name, email, department, title,
                   employment_type, phone, address, weekly_off_days, status, start_date, manager_id,
                   created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    values["employee_code"], values["first_name"], values["last_name"], values["email"],
                    values["department"], values["title"], employment_type,
                    phone, address, weekly_off_days, status, start_date, manager_id, now, now,
                ),
            )
            employee_id = int(cursor.lastrowid)
            row = connection.execute("SELECT * FROM employees WHERE id = ?", (employee_id,)).fetchone()
        result = _employee_json(row)
        self._audit(user["id"], "employee.created", "employee", employee_id, {"employee_code": result["employee_code"]}, remote)
        return result

    def _update_employee(self, employee_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        allowed = {
            "employee_code", "first_name", "last_name", "email", "department", "title",
            "employment_type", "phone", "address", "weekly_off_days", "status", "start_date", "manager_id",
        }
        updates = {key: value for key, value in body.items() if key in allowed}
        if not updates:
            raise ApiError(400, "No editable employee fields were supplied.")
        with self._db() as connection:
            current = connection.execute("SELECT * FROM employees WHERE id = ?", (employee_id,)).fetchone()
            if not current:
                raise ApiError(404, "Employee not found.")
            normalized: dict[str, Any] = {}
            for key, value in updates.items():
                if key == "manager_id":
                    normalized[key] = _optional_int(value)
                elif key == "start_date":
                    normalized[key] = _date_string(value)
                elif key == "weekly_off_days":
                    normalized[key] = _weekly_off_days(value)
                elif key in {"phone", "address"}:
                    normalized[key] = str(value or "").strip()
                    limit = 40 if key == "phone" else 240
                    if len(normalized[key]) > limit:
                        raise ApiError(400, f"{key.capitalize()} is longer than the allowed limit.")
                elif key == "status":
                    value = str(value)
                    if value not in {"active", "inactive", "on_leave"}:
                        raise ApiError(400, "Employee status must be active, inactive, or on_leave.")
                    normalized[key] = value
                elif key == "email":
                    value = str(value).strip().lower()
                    if not _valid_email(value):
                        raise ApiError(400, "Enter a valid employee email address.")
                    normalized[key] = value
                elif key == "employment_type":
                    normalized[key] = _normalize_employment_type(value)
                else:
                    normalized[key] = str(value).strip()
                    if not normalized[key]:
                        raise ApiError(400, f"{key.replace('_', ' ').capitalize()} cannot be empty.")
            manager_id = normalized.get("manager_id")
            if manager_id is not None and manager_id == employee_id:
                raise ApiError(400, "An employee cannot report to themselves.")
            if manager_id is not None and not connection.execute("SELECT 1 FROM employees WHERE id = ?", (manager_id,)).fetchone():
                raise ApiError(400, "The selected manager does not exist.")
            assignments = ", ".join(f"{key} = ?" for key in normalized)
            connection.execute(
                f"UPDATE employees SET {assignments}, updated_at = ? WHERE id = ?",
                (*normalized.values(), _now(), employee_id),
            )
            row = connection.execute("SELECT * FROM employees WHERE id = ?", (employee_id,)).fetchone()
            if row["user_id"] is not None and {"first_name", "last_name"}.intersection(normalized):
                employee_name = f"{row['first_name']} {row['last_name']}".strip()
                connection.execute(
                    "UPDATE users SET full_name = ? WHERE id = ?", (employee_name, row["user_id"])
                )
        self._audit(user["id"], "employee.updated", "employee", employee_id, {"fields": sorted(normalized)}, remote)
        return _employee_json(row)

    def _deactivate_employee(self, employee_id: int, user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        with self._db() as connection:
            row = connection.execute("SELECT * FROM employees WHERE id = ?", (employee_id,)).fetchone()
            if not row:
                raise ApiError(404, "Employee not found.")
            open_punch = connection.execute(
                "SELECT 1 FROM attendance_records WHERE employee_id = ? AND punch_out_at IS NULL LIMIT 1",
                (employee_id,),
            ).fetchone()
            if open_punch:
                raise ApiError(409, "This employee has an open attendance punch. Check them out before deactivation.")
            connection.execute("UPDATE employees SET status = 'inactive', updated_at = ? WHERE id = ?", (_now(), employee_id))
            updated = connection.execute("SELECT * FROM employees WHERE id = ?", (employee_id,)).fetchone()
        self._audit(user["id"], "employee.deactivated", "employee", employee_id, {"employee_code": row["employee_code"]}, remote)
        return _employee_json(updated)

    def _list_team(self, query: dict[str, str]) -> dict[str, Any]:
        requested_date = _date_string(
            query.get("date"), datetime.now(timezone.utc).date().isoformat()
        )
        target_date = date.fromisoformat(requested_date)
        department_filter = query.get("department", "").strip().casefold()
        search = query.get("q", "").strip().casefold()
        next_window = (target_date + timedelta(days=90)).isoformat()
        with self._db() as connection:
            employees = connection.execute(
                "SELECT * FROM employees WHERE status != 'inactive' ORDER BY first_name, last_name"
            ).fetchall()
            attendance_rows = connection.execute(
                """SELECT employee_id, punch_in_at, punch_out_at FROM attendance_records
                   WHERE substr(punch_in_at, 1, 10) = ? ORDER BY punch_in_at DESC""",
                (requested_date,),
            ).fetchall()
            approved_leave_rows = connection.execute(
                """SELECT lr.employee_id, lr.start_date, lr.end_date, lt.name AS leave_type
                   FROM leave_requests lr JOIN leave_types lt ON lt.id = lr.leave_type_id
                   JOIN employees e ON e.id = lr.employee_id
                   WHERE e.status != 'inactive' AND lr.status = 'approved'
                   AND lr.start_date <= ? AND lr.end_date >= ?
                   ORDER BY lr.start_date, e.first_name, e.last_name""",
                (next_window, requested_date),
            ).fetchall()
            shift_rows = connection.execute(
                """SELECT a.employee_id, s.name AS shift_name, s.start_time, s.end_time
                   FROM shift_assignments a JOIN shift_templates s ON s.id = a.shift_id
                   WHERE a.work_date = ? AND a.is_active = 1""",
                (requested_date,),
            ).fetchall()

        departments = list(dict.fromkeys([
            *DEPARTMENT_OPTIONS,
            *[str(row["department"]) for row in employees if row["department"]],
        ]))
        attendance_by_employee: dict[int, sqlite3.Row] = {}
        for row in attendance_rows:
            attendance_by_employee.setdefault(int(row["employee_id"]), row)
        leave_by_employee: dict[int, sqlite3.Row] = {}
        for row in approved_leave_rows:
            if row["start_date"] <= requested_date <= row["end_date"]:
                leave_by_employee.setdefault(int(row["employee_id"]), row)
        shift_by_employee = {int(row["employee_id"]): row for row in shift_rows}

        visible_rows = [
            row for row in employees
            if (not department_filter or str(row["department"]).casefold() == department_filter)
            and (
                not search
                or search in " ".join(str(row[key] or "") for key in (
                    "employee_code", "first_name", "last_name", "department", "title"
                )).casefold()
            )
        ]
        items: list[dict[str, Any]] = []
        for employee in visible_rows:
            employee_id = int(employee["id"])
            punch = attendance_by_employee.get(employee_id)
            leave = leave_by_employee.get(employee_id)
            weekly_days = _parse_weekly_off_days(employee["weekly_off_days"])
            if leave or employee["status"] == "on_leave":
                presence = "on_leave"
            elif _WEEKDAYS[target_date.weekday()] in weekly_days:
                presence = "weekly_off"
            elif punch:
                presence = "present" if punch["punch_out_at"] is None else "checked_out"
            else:
                presence = "not_punched"
            shift = shift_by_employee.get(employee_id)
            items.append({
                "id": employee_id,
                "employee_code": employee["employee_code"],
                "full_name": f"{employee['first_name']} {employee['last_name']}".strip(),
                "department": employee["department"],
                "title": employee["title"],
                "employment_type": employee["employment_type"],
                "employment_category_label": (
                    "Yellow Card Staff (15 EL Only)"
                    if _safe_employment_type(employee["employment_type"]) == "Yellow Card"
                    else "Official Staff"
                ),
                "status": employee["status"],
                "weekly_off_days": weekly_days,
                "presence": presence,
                "punch_in_at": punch["punch_in_at"] if punch else None,
                "punch_out_at": punch["punch_out_at"] if punch else None,
                "shift_name": shift["shift_name"] if shift else None,
                "shift_start_time": shift["start_time"] if shift else None,
                "shift_end_time": shift["end_time"] if shift else None,
            })

        upcoming_leaves = []
        for leave in approved_leave_rows:
            employee = next((row for row in employees if int(row["id"]) == int(leave["employee_id"])), None)
            if employee is None:
                continue
            if department_filter and str(employee["department"]).casefold() != department_filter:
                continue
            name = f"{employee['first_name']} {employee['last_name']}".strip()
            if search and search not in " ".join((name, employee["employee_code"], employee["department"], employee["title"])).casefold():
                continue
            upcoming_leaves.append({
                "employee_id": employee["id"],
                "employee_name": name,
                "employee_code": employee["employee_code"],
                "department": employee["department"],
                "leave_type": leave["leave_type"],
                "start_date": leave["start_date"],
                "end_date": leave["end_date"],
                "is_current": leave["start_date"] <= requested_date <= leave["end_date"],
            })

        summary = {
            "total": len(items),
            "present": sum(item["presence"] == "present" for item in items),
            "checked_out": sum(item["presence"] == "checked_out" for item in items),
            "on_leave": sum(item["presence"] == "on_leave" for item in items),
            "weekly_off": sum(item["presence"] == "weekly_off" for item in items),
            "not_punched": sum(item["presence"] == "not_punched" for item in items),
        }
        return {
            "date": requested_date,
            "summary": summary,
            "items": items,
            "departments": departments,
            "upcoming_leaves": upcoming_leaves,
        }

    def _list_id_cards(
        self, user: dict[str, Any], permissions: set[str], query: dict[str, str]
    ) -> dict[str, Any]:
        own_id = self._employee_id(user["id"])
        with self._db() as connection:
            rows = connection.execute(
                "SELECT * FROM employees WHERE status != 'inactive' ORDER BY first_name, last_name"
            ).fetchall()
        if "idcard.read" not in permissions and "idcard.update" not in permissions:
            if "idcard.read.team" in permissions and own_id is not None:
                rows = [row for row in rows if row["id"] == own_id or row["manager_id"] == own_id]
            elif "idcard.read.self" in permissions and own_id is not None:
                rows = [row for row in rows if row["id"] == own_id]
            else:
                rows = []
        employee_id = _optional_int(query.get("employee_id"))
        if employee_id is not None:
            rows = [row for row in rows if int(row["id"]) == employee_id]
            if not rows:
                raise ApiError(404, "Employee ID card not found or not available to your role.")
        search = query.get("q", "").strip().casefold()
        if search:
            rows = [
                row for row in rows
                if search in " ".join(str(row[key] or "") for key in (
                    "employee_code", "first_name", "last_name", "department", "title", "email"
                )).casefold()
            ]
        global_reader = "idcard.read" in permissions or "idcard.update" in permissions
        return {
            "items": [
                _id_card_json(row, include_private=global_reader or row["user_id"] == user["id"])
                for row in rows
            ],
            "total": len(rows),
            "can_edit": "idcard.update" in permissions,
        }

    def _update_id_card(
        self, employee_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None
    ) -> dict[str, Any]:
        updates = {key: body[key] for key in ("phone", "address") if key in body}
        if not updates:
            raise ApiError(400, "Supply a phone number or mailing address to update.")
        normalized = {key: str(value or "").strip() for key, value in updates.items()}
        if len(normalized.get("phone", "")) > 40 or len(normalized.get("address", "")) > 240:
            raise ApiError(400, "Phone or address is longer than the allowed limit.")
        with self._db() as connection:
            if not connection.execute("SELECT 1 FROM employees WHERE id = ?", (employee_id,)).fetchone():
                raise ApiError(404, "Employee not found.")
            assignments = ", ".join(f"{key} = ?" for key in normalized)
            connection.execute(
                f"UPDATE employees SET {assignments}, updated_at = ? WHERE id = ?",
                (*normalized.values(), _now(), employee_id),
            )
            row = connection.execute("SELECT * FROM employees WHERE id = ?", (employee_id,)).fetchone()
        self._audit(user["id"], "id_card.updated", "employee", employee_id, {"fields": sorted(normalized)}, remote)
        return _id_card_json(row)

    def _list_kra_templates(self, user: dict[str, Any], permissions: set[str]) -> dict[str, Any]:
        own = self._employee_for_user(user["id"])
        can_view_templates = (
            "kra.manage" in permissions or "kra.read" in permissions or not own
            or _safe_employment_type(own["employment_type"]) == "Official Staff"
        )
        if not can_view_templates:
            return {
                "items": [], "total": 0, "applicable": False,
                "notice": "Official Staff KRAs/appraisals are separate. Yellow Card performance is tracked through shift attendance and output logs.",
            }
        with self._db() as connection:
            rows = connection.execute(
                "SELECT * FROM kra_templates WHERE is_active = 1 ORDER BY department, role_title, title"
            ).fetchall()
        items = [_kra_template_json(row) for row in rows]
        return {"items": items, "total": len(items), "applicable": True}

    def _kra_template(self, template_id: int) -> dict[str, Any] | None:
        with self._db() as connection:
            row = connection.execute("SELECT * FROM kra_templates WHERE id = ?", (template_id,)).fetchone()
        return _kra_template_json(row) if row else None

    @staticmethod
    def _kra_template_values(body: dict[str, Any], partial: bool) -> dict[str, Any]:
        allowed = {"department", "role_title", "title", "description", "weight_percent", "is_active"}
        supplied = {key: value for key, value in body.items() if key in allowed}
        required = {"department", "role_title", "title", "weight_percent"}
        if not partial and not required.issubset(supplied):
            raise ApiError(400, "Department, role title, KRA title, and weight are required.")
        data: dict[str, Any] = {}
        for key, value in supplied.items():
            if key == "weight_percent":
                weight = _as_int(value, "KRA weight")
                if not 1 <= weight <= 100:
                    raise ApiError(400, "KRA weight must be between 1 and 100 percent.")
                data[key] = weight
            elif key == "is_active":
                data[key] = _boolean_setting(value, "Template active state")
            else:
                text = str(value or "").strip()
                limit = 120 if key in {"department", "role_title", "title"} else 1200
                if key in {"department", "role_title", "title"} and not text:
                    raise ApiError(400, f"{key.replace('_', ' ').capitalize()} cannot be empty.")
                if len(text) > limit:
                    raise ApiError(400, f"{key.replace('_', ' ').capitalize()} cannot exceed {limit} characters.")
                data[key] = text
        if not partial:
            data.setdefault("description", "")
            data.setdefault("is_active", 1)
        return data

    def _create_kra_template(self, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        data = self._kra_template_values(body, partial=False)
        now = _now()
        with self._db() as connection:
            cursor = connection.execute(
                """INSERT INTO kra_templates
                   (department, role_title, title, description, weight_percent, is_active, created_by, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (data["department"], data["role_title"], data["title"], data["description"],
                 data["weight_percent"], data["is_active"], user["id"], now, now),
            )
            template_id = int(cursor.lastrowid)
        result = self._kra_template(template_id)
        self._audit(user["id"], "kra.template_created", "kra_template", template_id, {"role_title": result["role_title"]}, remote)
        return result

    def _update_kra_template(self, template_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        if not self._kra_template(template_id):
            raise ApiError(404, "KRA template not found.")
        updates = self._kra_template_values(body, partial=True)
        if not updates:
            raise ApiError(400, "No editable KRA template fields were supplied.")
        assignments = ", ".join(f"{key} = ?" for key in updates)
        with self._db() as connection:
            connection.execute(
                f"UPDATE kra_templates SET {assignments}, updated_at = ? WHERE id = ?",
                (*updates.values(), _now(), template_id),
            )
        result = self._kra_template(template_id)
        self._audit(user["id"], "kra.template_updated", "kra_template", template_id, {"fields": sorted(updates)}, remote)
        return result

    def _list_kra_goals(self, user: dict[str, Any], permissions: set[str]) -> dict[str, Any]:
        own = self._employee_for_user(user["id"])
        if own and _safe_employment_type(own["employment_type"]) == "Yellow Card" and not permissions.intersection({"kra.manage", "kra.read"}):
            return {
                "items": [], "total": 0, "applicable": False,
                "notice": "Official Staff KRAs/appraisals are separate. Yellow Card performance is tracked through shift attendance and output logs.",
            }
        with self._db() as connection:
            rows = connection.execute(
                """SELECT g.*, e.employee_code, e.first_name, e.last_name, e.department,
                          e.title AS employee_title, e.employment_type, e.user_id, e.manager_id
                   FROM kra_goals g JOIN employees e ON e.id = g.employee_id
                   ORDER BY g.cycle DESC, e.first_name, g.id"""
            ).fetchall()
        rows = [row for row in rows if _safe_employment_type(row["employment_type"]) == "Official Staff"]
        if "kra.read" not in permissions and "kra.manage" not in permissions:
            own_id = int(own["id"]) if own else None
            if own_id is None:
                rows = []
            elif "kra.read.team" in permissions:
                rows = [row for row in rows if row["employee_id"] == own_id or row["manager_id"] == own_id]
            elif "kra.read.self" in permissions:
                rows = [row for row in rows if row["user_id"] == user["id"]]
            else:
                rows = []
        items = [_kra_goal_json(row) for row in rows]
        return {"items": items, "total": len(items), "applicable": True}

    def _create_kra_goal(self, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        employee_id = _as_int(body.get("employee_id"), "Employee ID")
        template_id = _optional_int(body.get("template_id"))
        cycle = str(body.get("cycle", date.today().year)).strip()
        if not re.fullmatch(r"\d{4}(?:-Q[1-4])?", cycle):
            raise ApiError(400, "KRA cycle must be a year or a quarter such as 2026 or 2026-Q1.")
        with self._db() as connection:
            employee = connection.execute(
                "SELECT id, status, employment_type FROM employees WHERE id = ?", (employee_id,)
            ).fetchone()
            if not employee or employee["status"] == "inactive":
                raise ApiError(404, "Active employee not found.")
            if _safe_employment_type(employee["employment_type"]) != "Official Staff":
                raise ApiError(400, "KRA assignments are for Official Staff; Yellow Card performance uses shift attendance and output logs.")
            template = None
            if template_id is not None:
                template = connection.execute(
                    "SELECT * FROM kra_templates WHERE id = ? AND is_active = 1", (template_id,)
                ).fetchone()
                if not template:
                    raise ApiError(404, "Active KRA template not found.")
            title = str(body.get("title", template["title"] if template else "")).strip()
            description = str(body.get("description", template["description"] if template else "")).strip()
            target = str(body.get("target", "")).strip()
            weight = _as_int(body.get("weight_percent", template["weight_percent"] if template else 0), "KRA weight")
            if not title or len(title) > 160:
                raise ApiError(400, "Goal title must be between 1 and 160 characters.")
            if len(description) > 1200 or len(target) > 500:
                raise ApiError(400, "Goal description or target is longer than the allowed limit.")
            if not 1 <= weight <= 100:
                raise ApiError(400, "KRA weight must be between 1 and 100 percent.")
            now = _now()
            cursor = connection.execute(
                """INSERT INTO kra_goals
                   (employee_id, template_id, title, description, cycle, target, weight_percent,
                    status, created_by, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, 'not_started', ?, ?, ?)""",
                (employee_id, template_id, title, description, cycle, target, weight, user["id"], now, now),
            )
            goal_id = int(cursor.lastrowid)
        result = self._kra_goal(goal_id)
        self._audit(user["id"], "kra.goal_created", "kra_goal", goal_id, {"employee_id": employee_id, "cycle": cycle}, remote)
        return result

    def _kra_goal(self, goal_id: int) -> dict[str, Any] | None:
        with self._db() as connection:
            row = connection.execute(
                """SELECT g.*, e.employee_code, e.first_name, e.last_name, e.department,
                          e.title AS employee_title, e.employment_type, e.user_id, e.manager_id
                   FROM kra_goals g JOIN employees e ON e.id = g.employee_id WHERE g.id = ?""",
                (goal_id,),
            ).fetchone()
        return _kra_goal_json(row) if row else None

    def _update_kra_goal(self, goal_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        with self._db() as connection:
            row = connection.execute(
                """SELECT g.*, e.employment_type, e.user_id, e.manager_id
                   FROM kra_goals g JOIN employees e ON e.id = g.employee_id WHERE g.id = ?""",
                (goal_id,),
            ).fetchone()
        if not row:
            raise ApiError(404, "KRA goal not found.")
        if _safe_employment_type(row["employment_type"]) != "Official Staff":
            raise ApiError(403, "This employee category does not use KRA appraisals.")
        permissions = self._permissions(user["id"])
        own_id = self._employee_id(user["id"])
        is_manager = own_id is not None and row["manager_id"] == own_id
        is_self = row["user_id"] == user["id"]
        can_manage = "kra.manage" in permissions
        can_update_self = is_self and "kra.update.self" in permissions
        can_update_team = is_manager and "kra.update.team" in permissions
        if not (can_manage or can_update_self or can_update_team):
            raise ApiError(403, "You cannot update this KRA goal.")
        updates: dict[str, Any] = {}
        if "progress_percent" in body:
            if not (can_manage or can_update_self):
                raise ApiError(403, "Only the employee or People Ops can update self progress.")
            progress = _as_int(body["progress_percent"], "Progress")
            if not 0 <= progress <= 100:
                raise ApiError(400, "Progress must be between 0 and 100 percent.")
            updates["progress_percent"] = progress
        if "self_comment" in body:
            if not (can_manage or can_update_self):
                raise ApiError(403, "Only the employee or People Ops can update the self comment.")
            comment = str(body["self_comment"] or "").strip()
            if len(comment) > 1200:
                raise ApiError(400, "Self comment cannot exceed 1200 characters.")
            updates["self_comment"] = comment
        if "manager_score" in body:
            if not (can_manage or can_update_team):
                raise ApiError(403, "Only a reporting manager or People Ops can score this goal.")
            score = _as_int(body["manager_score"], "Manager score")
            if not 0 <= score <= 100:
                raise ApiError(400, "Manager score must be between 0 and 100.")
            updates["manager_score"] = score
        if "manager_comment" in body:
            if not (can_manage or can_update_team):
                raise ApiError(403, "Only a reporting manager or People Ops can update the review comment.")
            comment = str(body["manager_comment"] or "").strip()
            if len(comment) > 1200:
                raise ApiError(400, "Manager comment cannot exceed 1200 characters.")
            updates["manager_comment"] = comment
        if "status" in body:
            status = str(body["status"]).strip().lower()
            allowed_statuses = {"not_started", "in_progress", "completed"}
            if can_manage or can_update_team:
                allowed_statuses.add("reviewed")
            if status not in allowed_statuses:
                raise ApiError(400, "Goal status is not valid for your role.")
            updates["status"] = status
        if not updates:
            raise ApiError(400, "No editable KRA goal fields were supplied.")
        assignments = ", ".join(f"{key} = ?" for key in updates)
        with self._db() as connection:
            connection.execute(
                f"UPDATE kra_goals SET {assignments}, updated_at = ? WHERE id = ?",
                (*updates.values(), _now(), goal_id),
            )
        result = self._kra_goal(goal_id)
        self._audit(user["id"], "kra.goal_updated", "kra_goal", goal_id, {"fields": sorted(updates)}, remote)
        return result

    def _list_output_logs(
        self, user: dict[str, Any], permissions: set[str], query: dict[str, str]
    ) -> dict[str, Any]:
        limit = min(max(_optional_int(query.get("limit")) or 100, 1), 300)
        conditions: list[str] = []
        params: list[Any] = []
        if query.get("from"):
            conditions.append("o.work_date >= ?")
            params.append(_date_string(query["from"]))
        if query.get("to"):
            conditions.append("o.work_date <= ?")
            params.append(_date_string(query["to"]))
        if query.get("employee_id") and permissions.intersection({"output.read", "output.manage"}):
            conditions.append("o.employee_id = ?")
            params.append(_as_int(query["employee_id"], "Employee ID"))
        sql = """SELECT o.*, e.employee_code, e.first_name, e.last_name, e.department,
                        e.employment_type, e.user_id, e.manager_id
                 FROM production_output_logs o JOIN employees e ON e.id = o.employee_id"""
        if conditions:
            sql += " WHERE " + " AND ".join(conditions)
        sql += " ORDER BY o.work_date DESC, o.created_at DESC LIMIT ?"
        params.append(limit)
        with self._db() as connection:
            rows = connection.execute(sql, params).fetchall()
            own = connection.execute("SELECT id FROM employees WHERE user_id = ?", (user["id"],)).fetchone()
        if not permissions.intersection({"output.read", "output.manage"}):
            own_id = int(own["id"]) if own else None
            if own_id is None:
                rows = []
            elif "output.read.team" in permissions:
                rows = [row for row in rows if row["employee_id"] == own_id or row["manager_id"] == own_id]
            elif "output.read.self" in permissions or "output.create.self" in permissions:
                rows = [row for row in rows if row["user_id"] == user["id"]]
            else:
                rows = []
        items = [_output_log_json(row) for row in rows]
        return {"items": items, "total": len(items)}

    def _create_output_log(
        self, body: dict[str, Any], user: dict[str, Any], remote: str | None
    ) -> dict[str, Any]:
        permissions = self._permissions(user["id"])
        own_employee = self._employee_for_user(user["id"])
        if not own_employee or own_employee["status"] == "inactive":
            raise ApiError(409, "Your account is not linked to an active employee profile.")
        employee_id = int(own_employee["id"])
        if "output.manage" in permissions and body.get("employee_id") is not None:
            employee_id = _as_int(body["employee_id"], "Employee ID")
        elif body.get("employee_id") is not None and _as_int(body["employee_id"], "Employee ID") != employee_id:
            raise ApiError(403, "You may only add an output log to your own employee profile.")
        work_date = _date_string(body.get("work_date"))
        output_item = str(body.get("output_item", "")).strip()
        unit = str(body.get("unit", "")).strip()
        notes = str(body.get("notes", "")).strip()
        if not output_item or len(output_item) > 120:
            raise ApiError(400, "Output item must be between 1 and 120 characters.")
        if not unit or len(unit) > 40:
            raise ApiError(400, "Output unit must be between 1 and 40 characters.")
        if len(notes) > 500:
            raise ApiError(400, "Output note cannot exceed 500 characters.")
        try:
            quantity = float(body.get("quantity"))
            target_quantity = float(body["target_quantity"]) if body.get("target_quantity") not in {None, ""} else None
        except (TypeError, ValueError):
            raise ApiError(400, "Output quantity and target must be numbers.") from None
        if not math.isfinite(quantity) or not 0 < quantity <= 1_000_000_000:
            raise ApiError(400, "Output quantity must be greater than zero and at most 1,000,000,000.")
        if target_quantity is not None and (not math.isfinite(target_quantity) or target_quantity < 0):
            raise ApiError(400, "Target quantity must be a non-negative number.")
        with self._db() as connection:
            employee = connection.execute(
                "SELECT id, status FROM employees WHERE id = ?", (employee_id,)
            ).fetchone()
            if not employee or employee["status"] == "inactive":
                raise ApiError(404, "Active employee not found.")
            now = _now()
            cursor = connection.execute(
                """INSERT INTO production_output_logs
                   (employee_id, work_date, output_item, quantity, unit, target_quantity, notes, logged_by, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (employee_id, work_date, output_item, quantity, unit, target_quantity, notes, user["id"], now, now),
            )
            log_id = int(cursor.lastrowid)
        result = self._output_log(log_id)
        self._audit(
            user["id"], "output.log_created", "output_log", log_id,
            {"employee_id": employee_id, "work_date": work_date, "output_item": output_item}, remote,
        )
        return result

    def _output_log(self, log_id: int) -> dict[str, Any] | None:
        with self._db() as connection:
            row = connection.execute(
                """SELECT o.*, e.employee_code, e.first_name, e.last_name, e.department,
                          e.employment_type, e.user_id, e.manager_id
                   FROM production_output_logs o JOIN employees e ON e.id = o.employee_id
                   WHERE o.id = ?""",
                (log_id,),
            ).fetchone()
        return _output_log_json(row) if row else None

    def _list_kyc_documents(self, user: dict[str, Any], permissions: set[str]) -> dict[str, Any]:
        conditions = []
        params: list[Any] = []
        if not permissions.intersection({"kyc.read", "kyc.manage"}):
            own_id = self._employee_id(user["id"])
            if own_id is None:
                return {"items": [], "total": 0, "document_types": list(KYC_DOCUMENT_TYPES)}
            conditions.append("d.employee_id = ?")
            params.append(own_id)
        sql = """SELECT d.*, e.employee_code, e.first_name, e.last_name, e.department
                 FROM employee_kyc_documents d JOIN employees e ON e.id = d.employee_id"""
        if conditions:
            sql += " WHERE " + " AND ".join(conditions)
        sql += " ORDER BY CASE WHEN d.status = 'pending' THEN 0 ELSE 1 END, d.created_at DESC LIMIT 300"
        with self._db() as connection:
            rows = connection.execute(sql, params).fetchall()
        items = [_kyc_document_json(row) for row in rows]
        return {"items": items, "total": len(items), "document_types": list(KYC_DOCUMENT_TYPES)}

    def _create_kyc_document(
        self, body: dict[str, Any], user: dict[str, Any], remote: str | None
    ) -> dict[str, Any]:
        own_employee = self._employee_for_user(user["id"])
        if not own_employee or own_employee["status"] == "inactive":
            raise ApiError(409, "Your account is not linked to an active employee profile.")
        permissions = self._permissions(user["id"])
        employee_id = int(own_employee["id"])
        if "kyc.manage" in permissions and body.get("employee_id") is not None:
            employee_id = _as_int(body["employee_id"], "Employee ID")
        elif body.get("employee_id") is not None and _as_int(body["employee_id"], "Employee ID") != employee_id:
            raise ApiError(403, "You may only add a KYC item to your own employee profile.")
        document_type = str(body.get("document_type", "")).strip()
        canonical_type = next((item for item in KYC_DOCUMENT_TYPES if item.casefold() == document_type.casefold()), None)
        if canonical_type is None:
            raise ApiError(400, "Choose a supported KYC document type.")
        last_four = str(body.get("last_four", "")).strip()
        if last_four and not re.fullmatch(r"[0-9]{4}", last_four):
            raise ApiError(400, "Only the last four digits may be recorded; do not enter a full document number.")
        expiry_date = _date_string(body["expiry_date"]) if body.get("expiry_date") else None
        with self._db() as connection:
            employee = connection.execute(
                "SELECT id, status FROM employees WHERE id = ?", (employee_id,)
            ).fetchone()
            if not employee or employee["status"] == "inactive":
                raise ApiError(404, "Active employee not found.")
            cursor = connection.execute(
                """INSERT INTO employee_kyc_documents
                   (employee_id, document_type, last_four, expiry_date, status, created_by, created_at)
                   VALUES (?, ?, ?, ?, 'pending', ?, ?)""",
                (employee_id, canonical_type, last_four, expiry_date, user["id"], _now()),
            )
            document_id = int(cursor.lastrowid)
        result = self._kyc_document(document_id)
        self._audit(
            user["id"], "kyc.document_created", "kyc_document", document_id,
            {"employee_id": employee_id, "document_type": canonical_type}, remote,
        )
        return result

    def _kyc_document(self, document_id: int) -> dict[str, Any] | None:
        with self._db() as connection:
            row = connection.execute(
                """SELECT d.*, e.employee_code, e.first_name, e.last_name, e.department
                   FROM employee_kyc_documents d JOIN employees e ON e.id = d.employee_id
                   WHERE d.id = ?""",
                (document_id,),
            ).fetchone()
        return _kyc_document_json(row) if row else None

    def _verify_kyc_document(
        self, document_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None
    ) -> dict[str, Any]:
        decision = str(body.get("decision", "")).strip().lower()
        if decision not in {"verified", "rejected"}:
            raise ApiError(400, "Decision must be verified or rejected.")
        note = str(body.get("note", "")).strip()
        if len(note) > 300:
            raise ApiError(400, "Verification note cannot exceed 300 characters.")
        with self._db() as connection:
            current = connection.execute(
                "SELECT status FROM employee_kyc_documents WHERE id = ?", (document_id,)
            ).fetchone()
            if not current:
                raise ApiError(404, "KYC record not found.")
            connection.execute(
                """UPDATE employee_kyc_documents SET status = ?, verified_by = ?, verified_at = ?,
                   verification_note = ? WHERE id = ?""",
                (decision, user["id"], _now(), note, document_id),
            )
        result = self._kyc_document(document_id)
        self._audit(
            user["id"], f"kyc.document_{decision}", "kyc_document", document_id,
            {"note_length": len(note)}, remote,
        )
        return result

    def _list_locations(self) -> dict[str, Any]:
        with self._db() as connection:
            rows = connection.execute("SELECT * FROM work_locations ORDER BY is_active DESC, name").fetchall()
        return {"items": [dict(row) | {"is_active": bool(row["is_active"])} for row in rows], "total": len(rows)}

    def _location(self, location_id: int) -> dict[str, Any] | None:
        with self._db() as connection:
            row = connection.execute("SELECT * FROM work_locations WHERE id = ?", (location_id,)).fetchone()
        return dict(row) | {"is_active": bool(row["is_active"])} if row else None

    def _create_location(self, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        data = self._location_values(body, partial=False)
        now = _now()
        with self._db() as connection:
            cursor = connection.execute(
                """INSERT INTO work_locations(name, address, latitude, longitude, radius_m, timezone,
                   is_active, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (*data.values(), now, now),
            )
            location_id = int(cursor.lastrowid)
        result = self._location(location_id)
        self._audit(user["id"], "location.created", "work_location", location_id, {"name": result["name"]}, remote)
        return result

    def _update_location(self, location_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        with self._db() as connection:
            current = connection.execute("SELECT * FROM work_locations WHERE id = ?", (location_id,)).fetchone()
        if not current:
            raise ApiError(404, "Work location not found.")
        data = self._location_values(body, partial=True)
        if not data:
            raise ApiError(400, "No editable location fields were supplied.")
        assignments = ", ".join(f"{key} = ?" for key in data)
        with self._db() as connection:
            connection.execute(
                f"UPDATE work_locations SET {assignments}, updated_at = ? WHERE id = ?",
                (*data.values(), _now(), location_id),
            )
        result = self._location(location_id)
        self._audit(user["id"], "location.updated", "work_location", location_id, {"fields": sorted(data)}, remote)
        return result

    def _deactivate_location(self, location_id: int, user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        with self._db() as connection:
            row = connection.execute("SELECT * FROM work_locations WHERE id = ?", (location_id,)).fetchone()
            if not row:
                raise ApiError(404, "Work location not found.")
            connection.execute("UPDATE work_locations SET is_active = 0, updated_at = ? WHERE id = ?", (_now(), location_id))
        result = self._location(location_id)
        self._audit(user["id"], "location.deactivated", "work_location", location_id, {"name": row["name"]}, remote)
        return result

    @staticmethod
    def _location_values(body: dict[str, Any], partial: bool) -> dict[str, Any]:
        allowed = {"name", "address", "latitude", "longitude", "radius_m", "timezone", "is_active"}
        supplied = {key: value for key, value in body.items() if key in allowed}
        if not partial and not {"name", "address", "latitude", "longitude", "radius_m"}.issubset(supplied):
            raise ApiError(400, "Name, address, coordinates, and geofence radius are required.")
        data: dict[str, Any] = {}
        for key in ("name", "address", "latitude", "longitude", "radius_m", "timezone", "is_active"):
            if key not in supplied:
                continue
            value = supplied[key]
            if key in {"latitude", "longitude"}:
                try:
                    number = float(value)
                except (ValueError, TypeError):
                    raise ApiError(400, f"{key.capitalize()} must be a number.") from None
                if not math.isfinite(number) or (key == "latitude" and not -90 <= number <= 90) or (key == "longitude" and not -180 <= number <= 180):
                    raise ApiError(400, f"{key.capitalize()} is outside the valid coordinate range.")
                data[key] = number
            elif key == "radius_m":
                radius = _as_int(value, "Radius")
                if radius < 1 or radius > 100_000:
                    raise ApiError(400, "Radius must be between 1 and 100000 metres.")
                data[key] = radius
            elif key == "is_active":
                if isinstance(value, str):
                    lowered = value.strip().lower()
                    if lowered not in {"true", "false", "1", "0"}:
                        raise ApiError(400, "is_active must be a boolean.")
                    data[key] = int(lowered in {"true", "1"})
                elif isinstance(value, (bool, int)):
                    data[key] = int(bool(value))
                else:
                    raise ApiError(400, "is_active must be a boolean.")
            else:
                text = str(value).strip()
                if key in {"name", "address"} and not text:
                    raise ApiError(400, f"{key.capitalize()} cannot be empty.")
                data[key] = text
        if not partial:
            data.setdefault("timezone", "UTC")
            data.setdefault("is_active", 1)
        return data

    def _list_holidays(self) -> dict[str, Any]:
        with self._db() as connection:
            rows = connection.execute(
                "SELECT * FROM holidays WHERE is_active = 1 ORDER BY holiday_date, name LIMIT 500"
            ).fetchall()
        items = [_holiday_json(row) for row in rows]
        return {"items": items, "total": len(items)}

    def _holiday(self, holiday_id: int) -> dict[str, Any] | None:
        with self._db() as connection:
            row = connection.execute("SELECT * FROM holidays WHERE id = ?", (holiday_id,)).fetchone()
        return _holiday_json(row) if row else None

    def _create_holiday(self, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        data = self._holiday_values(body, partial=False)
        now = _now()
        with self._db() as connection:
            cursor = connection.execute(
                """INSERT INTO holidays(name, holiday_date, description, is_active, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (data["name"], data["holiday_date"], data["description"], data["is_active"], now, now),
            )
            holiday_id = int(cursor.lastrowid)
        result = self._holiday(holiday_id)
        self._audit(user["id"], "holiday.created", "holiday", holiday_id, {"name": result["name"], "date": result["holiday_date"]}, remote)
        return result

    def _update_holiday(self, holiday_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        if not self._holiday(holiday_id):
            raise ApiError(404, "Holiday not found.")
        data = self._holiday_values(body, partial=True)
        if not data:
            raise ApiError(400, "No editable holiday fields were supplied.")
        assignments = ", ".join(f"{key} = ?" for key in data)
        with self._db() as connection:
            connection.execute(
                f"UPDATE holidays SET {assignments}, updated_at = ? WHERE id = ?",
                (*data.values(), _now(), holiday_id),
            )
        result = self._holiday(holiday_id)
        self._audit(user["id"], "holiday.updated", "holiday", holiday_id, {"fields": sorted(data)}, remote)
        return result

    def _deactivate_holiday(self, holiday_id: int, user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        current = self._holiday(holiday_id)
        if not current:
            raise ApiError(404, "Holiday not found.")
        with self._db() as connection:
            connection.execute(
                "UPDATE holidays SET is_active = 0, updated_at = ? WHERE id = ?",
                (_now(), holiday_id),
            )
        result = self._holiday(holiday_id)
        self._audit(user["id"], "holiday.deactivated", "holiday", holiday_id, {"name": current["name"]}, remote)
        return result

    @staticmethod
    def _holiday_values(body: dict[str, Any], partial: bool) -> dict[str, Any]:
        allowed = {"name", "holiday_date", "description", "is_active"}
        supplied = {key: value for key, value in body.items() if key in allowed}
        if not partial and not {"name", "holiday_date"}.issubset(supplied):
            raise ApiError(400, "Holiday name and date are required.")
        data: dict[str, Any] = {}
        for key, value in supplied.items():
            if key == "holiday_date":
                data[key] = _date_string(value)
            elif key == "is_active":
                if isinstance(value, str):
                    normalized = value.strip().lower()
                    if normalized not in {"true", "false", "1", "0"}:
                        raise ApiError(400, "is_active must be a boolean.")
                    data[key] = int(normalized in {"true", "1"})
                elif isinstance(value, (bool, int)):
                    data[key] = int(bool(value))
                else:
                    raise ApiError(400, "is_active must be a boolean.")
            else:
                text = str(value).strip()
                limit = 120 if key == "name" else 1000
                if key == "name" and not text:
                    raise ApiError(400, "Holiday name cannot be empty.")
                if len(text) > limit:
                    raise ApiError(400, f"{key.replace('_', ' ').capitalize()} cannot exceed {limit} characters.")
                data[key] = text
        if not partial:
            data.setdefault("description", "")
            data.setdefault("is_active", 1)
        return data

    def _list_shift_templates(self) -> dict[str, Any]:
        with self._db() as connection:
            rows = connection.execute(
                "SELECT * FROM shift_templates ORDER BY is_active DESC, name"
            ).fetchall()
        items = [_shift_template_json(row) for row in rows]
        return {"items": items, "total": len(items)}

    def _shift_template(self, shift_id: int) -> dict[str, Any] | None:
        with self._db() as connection:
            row = connection.execute("SELECT * FROM shift_templates WHERE id = ?", (shift_id,)).fetchone()
        return _shift_template_json(row) if row else None

    def _create_shift_template(self, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        data = self._shift_template_values(body, partial=False)
        now = _now()
        with self._db() as connection:
            cursor = connection.execute(
                """INSERT INTO shift_templates(name, start_time, end_time, break_minutes, is_active, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (data["name"], data["start_time"], data["end_time"], data["break_minutes"], data["is_active"], now, now),
            )
            shift_id = int(cursor.lastrowid)
        result = self._shift_template(shift_id)
        self._audit(user["id"], "shift_template.created", "shift_template", shift_id, {"name": result["name"]}, remote)
        return result

    def _update_shift_template(self, shift_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        if not self._shift_template(shift_id):
            raise ApiError(404, "Shift template not found.")
        data = self._shift_template_values(body, partial=True)
        if not data:
            raise ApiError(400, "No editable shift fields were supplied.")
        assignments = ", ".join(f"{key} = ?" for key in data)
        with self._db() as connection:
            connection.execute(
                f"UPDATE shift_templates SET {assignments}, updated_at = ? WHERE id = ?",
                (*data.values(), _now(), shift_id),
            )
        result = self._shift_template(shift_id)
        self._audit(user["id"], "shift_template.updated", "shift_template", shift_id, {"fields": sorted(data)}, remote)
        return result

    def _deactivate_shift_template(self, shift_id: int, user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        current = self._shift_template(shift_id)
        if not current:
            raise ApiError(404, "Shift template not found.")
        with self._db() as connection:
            connection.execute(
                "UPDATE shift_templates SET is_active = 0, updated_at = ? WHERE id = ?",
                (_now(), shift_id),
            )
        result = self._shift_template(shift_id)
        self._audit(user["id"], "shift_template.deactivated", "shift_template", shift_id, {"name": current["name"]}, remote)
        return result

    @staticmethod
    def _shift_template_values(body: dict[str, Any], partial: bool) -> dict[str, Any]:
        allowed = {"name", "start_time", "end_time", "break_minutes", "is_active"}
        supplied = {key: value for key, value in body.items() if key in allowed}
        required = {"name", "start_time", "end_time"}
        if not partial and not required.issubset(supplied):
            raise ApiError(400, "Shift name, start time, and end time are required.")
        data: dict[str, Any] = {}
        for key, value in supplied.items():
            if key in {"start_time", "end_time"}:
                text = str(value).strip()
                if not re.fullmatch(r"(?:[01][0-9]|2[0-3]):[0-5][0-9]", text):
                    raise ApiError(400, f"{key.replace('_', ' ').capitalize()} must use 24-hour HH:MM format.")
                data[key] = text
            elif key == "break_minutes":
                minutes = _as_int(value, "Break duration")
                if minutes < 0 or minutes > 600:
                    raise ApiError(400, "Break duration must be between 0 and 600 minutes.")
                data[key] = minutes
            elif key == "is_active":
                if isinstance(value, str):
                    normalized = value.strip().lower()
                    if normalized not in {"true", "false", "1", "0"}:
                        raise ApiError(400, "is_active must be a boolean.")
                    data[key] = int(normalized in {"true", "1"})
                elif isinstance(value, (bool, int)):
                    data[key] = int(bool(value))
                else:
                    raise ApiError(400, "is_active must be a boolean.")
            else:
                name = str(value).strip()
                if not name or len(name) > 120:
                    raise ApiError(400, "Shift name must be between 1 and 120 characters.")
                data[key] = name
        if not partial:
            data.setdefault("break_minutes", 0)
            data.setdefault("is_active", 1)
        return data

    def _list_shift_assignments(
        self,
        user: dict[str, Any],
        permissions: set[str],
        query: dict[str, str],
    ) -> dict[str, Any]:
        own_id = self._employee_id(user["id"])
        global_read = bool(permissions.intersection({"shifts.read", "shifts.manage"}))
        team_read = "shifts.read.team" in permissions
        self_read = "shifts.read.self" in permissions
        employee_ids: list[int] | None
        if global_read:
            employee_ids = None
        elif team_read and own_id is not None:
            with self._db() as connection:
                rows = connection.execute(
                    "SELECT id FROM employees WHERE id = ? OR manager_id = ?", (own_id, own_id)
                ).fetchall()
            employee_ids = [row["id"] for row in rows]
        elif self_read and own_id is not None:
            employee_ids = [own_id]
        else:
            employee_ids = []

        conditions = ["a.is_active = 1"]
        params: list[Any] = []
        if employee_ids == []:
            return {"items": [], "total": 0}
        if employee_ids is not None:
            placeholders = ",".join("?" for _ in employee_ids)
            conditions.append(f"a.employee_id IN ({placeholders})")
            params.extend(employee_ids)
        if query.get("date"):
            conditions.append("a.work_date = ?")
            params.append(_date_string(query["date"]))
        else:
            if query.get("from"):
                conditions.append("a.work_date >= ?")
                params.append(_date_string(query["from"]))
            if query.get("to"):
                conditions.append("a.work_date <= ?")
                params.append(_date_string(query["to"]))
        if query.get("from") and query.get("to") and _date_string(query["to"]) < _date_string(query["from"]):
            raise ApiError(400, "The roster end date must be on or after its start date.")
        limit = min(max(_optional_int(query.get("limit")) or 300, 1), 500)
        params.append(limit)
        with self._db() as connection:
            rows = connection.execute(
                """SELECT a.*, s.name AS shift_name, s.start_time, s.end_time, s.break_minutes,
                   e.employee_code, e.first_name, e.last_name, e.department, w.name AS location_name
                   FROM shift_assignments a JOIN shift_templates s ON s.id = a.shift_id
                   JOIN employees e ON e.id = a.employee_id
                   LEFT JOIN work_locations w ON w.id = a.work_location_id
                   WHERE """ + " AND ".join(conditions) + " ORDER BY a.work_date, s.start_time, e.first_name LIMIT ?",
                params,
            ).fetchall()
        items = [_shift_assignment_json(row) for row in rows]
        return {"items": items, "total": len(items)}

    def _shift_assignment(self, assignment_id: int) -> dict[str, Any] | None:
        with self._db() as connection:
            row = connection.execute(
                """SELECT a.*, s.name AS shift_name, s.start_time, s.end_time, s.break_minutes,
                   e.employee_code, e.first_name, e.last_name, e.department, w.name AS location_name
                   FROM shift_assignments a JOIN shift_templates s ON s.id = a.shift_id
                   JOIN employees e ON e.id = a.employee_id
                   LEFT JOIN work_locations w ON w.id = a.work_location_id WHERE a.id = ?""",
                (assignment_id,),
            ).fetchone()
        return _shift_assignment_json(row) if row else None

    def _assign_shift(self, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        employee_id = _as_int(body.get("employee_id"), "Employee ID")
        shift_id = _as_int(body.get("shift_id"), "Shift ID")
        work_date = _date_string(body.get("work_date"))
        location_id = _optional_int(body.get("work_location_id"))
        with self._db() as connection:
            employee = connection.execute("SELECT status FROM employees WHERE id = ?", (employee_id,)).fetchone()
            if not employee or employee["status"] == "inactive":
                raise ApiError(400, "Choose an active employee for the roster.")
            if not connection.execute(
                "SELECT 1 FROM shift_templates WHERE id = ? AND is_active = 1", (shift_id,)
            ).fetchone():
                raise ApiError(400, "Choose an active shift template.")
            if location_id is not None and not connection.execute(
                "SELECT 1 FROM work_locations WHERE id = ? AND is_active = 1", (location_id,)
            ).fetchone():
                raise ApiError(400, "Choose an active work location or leave it blank.")
            cursor = connection.execute(
                """INSERT INTO shift_assignments(employee_id, shift_id, work_date, work_location_id,
                   is_active, assigned_by, created_at, updated_at) VALUES (?, ?, ?, ?, 1, ?, ?, ?)""",
                (employee_id, shift_id, work_date, location_id, user["id"], _now(), _now()),
            )
            assignment_id = int(cursor.lastrowid)
        result = self._shift_assignment(assignment_id)
        self._audit(
            user["id"], "shift.assigned", "shift_assignment", assignment_id,
            {"employee_id": employee_id, "shift_id": shift_id, "work_date": work_date}, remote,
        )
        return result

    def _deactivate_shift_assignment(self, assignment_id: int, user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        current = self._shift_assignment(assignment_id)
        if not current or not current["is_active"]:
            raise ApiError(404, "Shift assignment not found.")
        with self._db() as connection:
            connection.execute(
                "UPDATE shift_assignments SET is_active = 0, updated_at = ? WHERE id = ?",
                (_now(), assignment_id),
            )
        result = self._shift_assignment(assignment_id)
        self._audit(
            user["id"], "shift.unassigned", "shift_assignment", assignment_id,
            {"employee_id": current["employee_id"], "work_date": current["work_date"]}, remote,
        )
        return result

    def _punch_in(self, user: dict[str, Any], body: dict[str, Any], remote: str | None) -> dict[str, Any]:
        employee = self._employee_for_user(user["id"])
        if not employee:
            raise ApiError(409, "Your account is not linked to an employee profile.")
        if employee["status"] != "active":
            raise ApiError(403, "Inactive employees cannot start a new attendance punch.")
        latitude, longitude, accuracy = _coordinates(body)
        with self._db() as connection:
            active = connection.execute(
                "SELECT id FROM attendance_records WHERE employee_id = ? AND punch_out_at IS NULL ORDER BY punch_in_at DESC LIMIT 1",
                (employee["id"],),
            ).fetchone()
            if active:
                raise ApiError(409, "You are already punched in.")
            location, distance = self._nearest_location(connection, latitude, longitude, accuracy_m=accuracy)
            if not location:
                raise ApiError(403, "Punch in is blocked because your location is outside or too imprecise to confirm an active work geofence.", {
                    "nearest_location": distance["name"] if distance else None,
                    "distance_m": round(distance["distance_m"]) if distance else None,
                    "accuracy_m": round(accuracy) if accuracy is not None else None,
                })
            now = _now()
            cursor = connection.execute(
                """INSERT INTO attendance_records(employee_id, work_location_id, punch_in_at,
                   punch_in_latitude, punch_in_longitude, punch_in_accuracy_m, punch_in_distance_m, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                (employee["id"], location["id"], now, latitude, longitude, accuracy, distance["distance_m"], now),
            )
            record_id = int(cursor.lastrowid)
        self._audit(user["id"], "attendance.punched_in", "attendance", record_id, {"location_id": location["id"]}, remote)
        return self._attendance_record(record_id)

    def _punch_out(self, user: dict[str, Any], body: dict[str, Any], remote: str | None) -> dict[str, Any]:
        employee = self._employee_for_user(user["id"])
        if not employee:
            raise ApiError(409, "Your account is not linked to an employee profile.")
        latitude, longitude, accuracy = _coordinates(body)
        with self._db() as connection:
            active = connection.execute(
                "SELECT * FROM attendance_records WHERE employee_id = ? AND punch_out_at IS NULL ORDER BY punch_in_at DESC LIMIT 1",
                (employee["id"],),
            ).fetchone()
            if not active:
                raise ApiError(409, "There is no open punch to check out from.")
            location, distance = self._nearest_location(
                connection, latitude, longitude, active["work_location_id"], accuracy_m=accuracy
            )
            if not location:
                raise ApiError(403, "Punch out is blocked because your location is outside or too imprecise to confirm the assigned work geofence.", {
                    "distance_m": round(distance["distance_m"]) if distance else None,
                    "accuracy_m": round(accuracy) if accuracy is not None else None,
                })
            connection.execute(
                """UPDATE attendance_records SET punch_out_at = ?, punch_out_latitude = ?,
                   punch_out_longitude = ?, punch_out_accuracy_m = ?, punch_out_distance_m = ? WHERE id = ?""",
                (_now(), latitude, longitude, accuracy, distance["distance_m"], active["id"]),
            )
            record_id = int(active["id"])
        self._audit(user["id"], "attendance.punched_out", "attendance", record_id, {"location_id": location["id"]}, remote)
        return self._attendance_record(record_id)

    @staticmethod
    def _nearest_location(
        connection: sqlite3.Connection,
        latitude: float,
        longitude: float,
        required_id: int | None = None,
        accuracy_m: float | None = None,
    ) -> tuple[sqlite3.Row | None, dict[str, Any] | None]:
        # New punches require an active work site. An employee already punched
        # in can still punch out at its assigned site after that site is disabled.
        sql = "SELECT * FROM work_locations WHERE is_active = 1" if required_id is None else "SELECT * FROM work_locations WHERE id = ?"
        params: tuple[Any, ...] = () if required_id is None else (required_id,)
        locations = connection.execute(sql, params).fetchall()
        nearest: tuple[sqlite3.Row, float] | None = None
        for location in locations:
            distance = _haversine_m(latitude, longitude, location["latitude"], location["longitude"])
            if nearest is None or distance < nearest[1]:
                nearest = (location, distance)
        if nearest is None:
            return None, None
        location, distance = nearest
        # Treat reported location accuracy as uncertainty, not as a reason to
        # expand the geofence. This allows a balanced-accuracy retry only when
        # its fix still places the full uncertainty radius inside the work site.
        uncertainty_m = max(accuracy_m or 0.0, 0.0)
        verified_distance = distance + uncertainty_m
        distance_info = {
            "name": location["name"],
            "distance_m": distance,
            "accuracy_m": accuracy_m,
            "verified_distance_m": verified_distance,
        }
        return (location, distance_info) if verified_distance <= location["radius_m"] else (None, distance_info)

    def _list_attendance(self, user: dict[str, Any], permissions: set[str], query: dict[str, str]) -> dict[str, Any]:
        limit = min(max(_optional_int(query.get("limit")) or 50, 1), 200)
        conditions: list[str] = []
        params: list[Any] = []
        if query.get("date"):
            day = _date_string(query["date"])
            conditions.append("substr(a.punch_in_at, 1, 10) = ?")
            params.append(day)
        else:
            if query.get("from"):
                conditions.append("substr(a.punch_in_at, 1, 10) >= ?")
                params.append(_date_string(query["from"]))
            if query.get("to"):
                conditions.append("substr(a.punch_in_at, 1, 10) <= ?")
                params.append(_date_string(query["to"]))
        if query.get("employee_id"):
            conditions.append("a.employee_id = ?")
            params.append(_as_int(query["employee_id"], "Employee ID"))
        sql = """SELECT a.*, e.employee_code, e.first_name, e.last_name, e.user_id, e.manager_id,
                 w.name AS location_name FROM attendance_records a
                 JOIN employees e ON e.id = a.employee_id LEFT JOIN work_locations w ON w.id = a.work_location_id"""
        if conditions:
            sql += " WHERE " + " AND ".join(conditions)
        sql += " ORDER BY a.punch_in_at DESC LIMIT ?"
        params.append(limit)
        with self._db() as connection:
            rows = connection.execute(sql, params).fetchall()
            own = connection.execute("SELECT id FROM employees WHERE user_id = ?", (user["id"],)).fetchone()
        if "attendance.read" not in permissions and "attendance.manage" not in permissions:
            manager_id = own["id"] if own else None
            filtered = []
            for row in rows:
                can_see_self = row["user_id"] == user["id"] and "attendance.read.self" in permissions
                can_see_team = manager_id is not None and row["manager_id"] == manager_id and "attendance.read.team" in permissions
                can_punch_self = row["user_id"] == user["id"] and "attendance.punch" in permissions
                if can_see_self or can_see_team or can_punch_self:
                    filtered.append(row)
            rows = filtered
        items = [_attendance_json(row) for row in rows]
        active = next((item for item in items if item.get("employee_id") == (own["id"] if own else None) and not item.get("punch_out_at")), None)
        if active is None and own:
            with self._db() as connection:
                row = connection.execute(
                    """SELECT a.*, e.employee_code, e.first_name, e.last_name, e.user_id, e.manager_id,
                       w.name AS location_name FROM attendance_records a JOIN employees e ON e.id = a.employee_id
                       LEFT JOIN work_locations w ON w.id = a.work_location_id
                       WHERE a.employee_id = ? AND a.punch_out_at IS NULL ORDER BY a.punch_in_at DESC LIMIT 1""",
                    (own["id"],),
                ).fetchone()
            active = _attendance_json(row) if row else None
        return {"items": items, "active": active, "total": len(items)}

    def _attendance_record(self, record_id: int) -> dict[str, Any]:
        with self._db() as connection:
            row = connection.execute(
                """SELECT a.*, e.employee_code, e.first_name, e.last_name, e.user_id, e.manager_id,
                   w.name AS location_name FROM attendance_records a JOIN employees e ON e.id = a.employee_id
                   LEFT JOIN work_locations w ON w.id = a.work_location_id WHERE a.id = ?""",
                (record_id,),
            ).fetchone()
        return _attendance_json(row)

    def _list_attendance_requests(
        self, kind: str, user: dict[str, Any], permissions: set[str], query: dict[str, str]
    ) -> dict[str, Any]:
        if kind == "overtime":
            table = "overtime_requests"
            selected = "r.*, e.first_name, e.last_name, e.employee_code, e.user_id, e.manager_id"
        elif kind == "manual":
            table = "manual_punch_requests"
            selected = "r.*, e.first_name, e.last_name, e.employee_code, e.user_id, e.manager_id"
        else:
            raise ApiError(400, "Unknown attendance request type.")
        status_filter = query.get("status", "").strip().lower()
        if status_filter and status_filter not in {"pending", "approved", "rejected"}:
            raise ApiError(400, "Request status must be pending, approved, or rejected.")
        sql = f"SELECT {selected} FROM {table} r JOIN employees e ON e.id = r.employee_id"
        params: list[Any] = []
        if status_filter:
            sql += " WHERE r.status = ?"
            params.append(status_filter)
        sql += " ORDER BY CASE WHEN r.status = 'pending' THEN 0 ELSE 1 END, r.requested_at DESC LIMIT 200"
        with self._db() as connection:
            rows = connection.execute(sql, params).fetchall()
            own = connection.execute(
                "SELECT id FROM employees WHERE user_id = ?", (user["id"],)
            ).fetchone()
        if not permissions.intersection({"attendance.manage", "attendance.read"}):
            own_id = int(own["id"]) if own else None
            visible = []
            for row in rows:
                is_self = row["user_id"] == user["id"] and bool(permissions.intersection({
                    "attendance.request", "attendance.read.self", "attendance.punch"
                }))
                is_team = (
                    own_id is not None
                    and row["manager_id"] == own_id
                    and bool(permissions.intersection({"attendance.read.team", "attendance.approve"}))
                )
                if is_self or is_team:
                    visible.append(row)
            rows = visible
        return {"items": [_attendance_request_json(row) for row in rows], "total": len(rows)}

    def _create_overtime_request(
        self, body: dict[str, Any], user: dict[str, Any], remote: str | None
    ) -> dict[str, Any]:
        employee = self._employee_for_user(user["id"])
        if not employee or employee["status"] == "inactive":
            raise ApiError(409, "Your account is not linked to an active employee profile.")
        work_date = _date_string(body.get("work_date"))
        try:
            hours = float(body.get("hours"))
        except (TypeError, ValueError):
            raise ApiError(400, "Overtime hours must be a number.") from None
        if not math.isfinite(hours) or not 0 < hours <= 24:
            raise ApiError(400, "Overtime hours must be greater than zero and at most 24.")
        reason = str(body.get("reason", "")).strip()
        if not reason or len(reason) > 500:
            raise ApiError(400, "A reason of up to 500 characters is required.")
        requested_at = _now()
        with self._db() as connection:
            cursor = connection.execute(
                """INSERT INTO overtime_requests
                   (employee_id, work_date, hours, reason, status, requested_at)
                   VALUES (?, ?, ?, ?, 'pending', ?)""",
                (employee["id"], work_date, round(hours, 2), reason, requested_at),
            )
            request_id = int(cursor.lastrowid)
        result = self._attendance_request("overtime", request_id)
        self._audit(
            user["id"], "attendance.overtime_requested", "overtime_request", request_id,
            {"work_date": work_date, "hours": round(hours, 2)}, remote,
        )
        return result

    def _create_manual_punch_request(
        self, body: dict[str, Any], user: dict[str, Any], remote: str | None
    ) -> dict[str, Any]:
        employee = self._employee_for_user(user["id"])
        if not employee or employee["status"] == "inactive":
            raise ApiError(409, "Your account is not linked to an active employee profile.")
        work_date = _date_string(body.get("work_date"))
        punch_in = _datetime_string(body.get("punch_in"), "Punch-in time")
        punch_out = _datetime_string(body.get("punch_out"), "Punch-out time", optional=True)
        start = _parse_datetime(punch_in, "Punch-in time")
        end = _parse_datetime(punch_out, "Punch-out time") if punch_out else None
        if start.date().isoformat() != work_date:
            raise ApiError(400, "Punch-in time must fall on the selected work date.")
        now = datetime.now(timezone.utc)
        comparable_start = start if start.tzinfo else start.replace(tzinfo=timezone.utc)
        if comparable_start.astimezone(timezone.utc) > now + timedelta(hours=1):
            raise ApiError(400, "A manual punch cannot be more than one hour in the future.")
        if end:
            comparable_end = end if end.tzinfo else end.replace(tzinfo=timezone.utc)
            comparable_start = start if start.tzinfo else start.replace(tzinfo=timezone.utc)
            if comparable_end.astimezone(timezone.utc) <= comparable_start.astimezone(timezone.utc):
                raise ApiError(400, "Punch-out must be later than punch-in.")
            if comparable_end.astimezone(timezone.utc) - comparable_start.astimezone(timezone.utc) > timedelta(hours=24):
                raise ApiError(400, "A manual attendance entry cannot exceed 24 hours.")
            if comparable_end.astimezone(timezone.utc) > now + timedelta(hours=1):
                raise ApiError(400, "A manual punch-out cannot be more than one hour in the future.")
        reason = str(body.get("reason", "")).strip()
        if not reason or len(reason) > 500:
            raise ApiError(400, "A reason of up to 500 characters is required.")
        with self._db() as connection:
            duplicate = connection.execute(
                """SELECT 1 FROM manual_punch_requests
                   WHERE employee_id = ? AND work_date = ? AND status = 'pending' LIMIT 1""",
                (employee["id"], work_date),
            ).fetchone()
            if duplicate:
                raise ApiError(409, "You already have a pending manual-punch request for this date.")
            cursor = connection.execute(
                """INSERT INTO manual_punch_requests
                   (employee_id, work_date, requested_punch_in, requested_punch_out, reason, status, requested_at)
                   VALUES (?, ?, ?, ?, ?, 'pending', ?)""",
                (employee["id"], work_date, punch_in, punch_out, reason, _now()),
            )
            request_id = int(cursor.lastrowid)
        result = self._attendance_request("manual", request_id)
        self._audit(
            user["id"], "attendance.manual_punch_requested", "manual_punch_request", request_id,
            {"work_date": work_date}, remote,
        )
        return result

    def _attendance_request(self, kind: str, request_id: int) -> dict[str, Any]:
        table = "overtime_requests" if kind == "overtime" else "manual_punch_requests"
        with self._db() as connection:
            row = connection.execute(
                f"""SELECT r.*, e.first_name, e.last_name, e.employee_code
                    FROM {table} r JOIN employees e ON e.id = r.employee_id WHERE r.id = ?""",
                (request_id,),
            ).fetchone()
        if row is None:
            raise ApiError(404, "Attendance request not found.")
        return _attendance_request_json(row)

    def _decide_attendance_request(
        self, kind: str, request_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None
    ) -> dict[str, Any]:
        decision = str(body.get("decision", "")).strip().lower()
        if decision not in {"approved", "rejected"}:
            raise ApiError(400, "Decision must be approved or rejected.")
        table = "overtime_requests" if kind == "overtime" else "manual_punch_requests"
        with self._db() as connection:
            row = connection.execute(
                f"""SELECT r.*, e.user_id, e.manager_id FROM {table} r
                    JOIN employees e ON e.id = r.employee_id WHERE r.id = ?""",
                (request_id,),
            ).fetchone()
            if not row:
                raise ApiError(404, "Attendance request not found.")
            permissions = self._permissions(user["id"])
            if "attendance.manage" not in permissions:
                actor_employee = connection.execute(
                    "SELECT id FROM employees WHERE user_id = ?", (user["id"],)
                ).fetchone()
                if not actor_employee or row["manager_id"] != actor_employee["id"] or row["user_id"] == user["id"]:
                    raise ApiError(403, "You may only decide attendance requests from your reporting team.")
            if row["status"] != "pending":
                raise ApiError(409, "Only pending attendance requests can be decided.")
            note = str(body.get("note", "")).strip() or None
            attendance_record_id = None
            if kind == "manual" and decision == "approved":
                requested_start = _parse_datetime(row["requested_punch_in"], "Punch-in time")
                request_timezone = requested_start.tzinfo or timezone.utc
                employee_records = connection.execute(
                    """SELECT * FROM attendance_records
                       WHERE employee_id = ? ORDER BY punch_in_at DESC""",
                    (row["employee_id"],),
                ).fetchall()
                existing_rows = []
                for candidate in employee_records:
                    candidate_start = _parse_datetime(candidate["punch_in_at"], "Recorded punch-in time")
                    if candidate_start.tzinfo is None:
                        candidate_start = candidate_start.replace(tzinfo=timezone.utc)
                    if candidate_start.astimezone(request_timezone).date().isoformat() == row["work_date"]:
                        existing_rows.append(candidate)
                if len(existing_rows) > 1:
                    raise ApiError(409, "More than one attendance record exists for this date; ask HR to reconcile it.")
                existing = existing_rows[0] if existing_rows else None
                punch_out_at = row["requested_punch_out"]
                if existing:
                    if punch_out_at is None:
                        punch_out_at = existing["punch_out_at"]
                    if punch_out_at is not None:
                        requested_end = _parse_datetime(punch_out_at, "Punch-out time")
                        comparable_start = requested_start if requested_start.tzinfo else requested_start.replace(tzinfo=timezone.utc)
                        comparable_end = requested_end if requested_end.tzinfo else requested_end.replace(tzinfo=timezone.utc)
                        if comparable_end.astimezone(timezone.utc) <= comparable_start.astimezone(timezone.utc):
                            raise ApiError(400, "The corrected punch-out must be later than punch-in.")
                    active = connection.execute(
                        """SELECT id FROM attendance_records WHERE employee_id = ?
                           AND punch_out_at IS NULL AND id != ? LIMIT 1""",
                        (row["employee_id"], existing["id"]),
                    ).fetchone()
                    if active and punch_out_at is None:
                        raise ApiError(409, "This employee already has a different open attendance punch.")
                    connection.execute(
                        """UPDATE attendance_records SET punch_in_at = ?, punch_out_at = ?, punch_source = 'manual'
                           WHERE id = ?""",
                        (row["requested_punch_in"], punch_out_at, existing["id"]),
                    )
                    attendance_record_id = int(existing["id"])
                else:
                    if punch_out_at is None:
                        active = connection.execute(
                            "SELECT id FROM attendance_records WHERE employee_id = ? AND punch_out_at IS NULL LIMIT 1",
                            (row["employee_id"],),
                        ).fetchone()
                        if active:
                            raise ApiError(409, "This employee already has an open attendance punch.")
                    cursor = connection.execute(
                        """INSERT INTO attendance_records
                           (employee_id, work_location_id, punch_in_at, punch_in_latitude, punch_in_longitude,
                            punch_in_accuracy_m, punch_in_distance_m, punch_out_at, punch_source, created_at)
                           VALUES (?, NULL, ?, 0, 0, NULL, 0, ?, 'manual', ?)""",
                        (row["employee_id"], row["requested_punch_in"], punch_out_at, _now()),
                    )
                    attendance_record_id = int(cursor.lastrowid)
            connection.execute(
                f"""UPDATE {table} SET status = ?, decided_at = ?, approver_id = ?, decision_note = ?
                    {', attendance_record_id = ?' if kind == 'manual' else ''} WHERE id = ?""",
                (
                    (decision, _now(), user["id"], note, attendance_record_id, request_id)
                    if kind == "manual"
                    else (decision, _now(), user["id"], note, request_id)
                ),
            )
        self._audit(
            user["id"], f"attendance.{kind}_{decision}", f"{kind}_request", request_id,
            {"attendance_record_id": attendance_record_id} if attendance_record_id else {"note": note}, remote,
        )
        return self._attendance_request(kind, request_id)

    def _get_leave_policy(self) -> dict[str, Any]:
        with self._db() as connection:
            policy = connection.execute("SELECT * FROM leave_policy WHERE id = 1").fetchone()
            leave_types = connection.execute(
                "SELECT id, name, annual_allowance_days, is_paid, is_active FROM leave_types WHERE is_active = 1 ORDER BY name"
            ).fetchall()
            category_policies = connection.execute(
                """SELECT p.employment_type, p.leave_type_id AS id, lt.name,
                          p.annual_allowance_days, p.is_applicable, p.accrual_method,
                          p.monthly_reset, p.attendance_based
                   FROM employment_leave_type_policies p
                   JOIN leave_types lt ON lt.id = p.leave_type_id
                   WHERE lt.is_active = 1 ORDER BY p.employment_type, lt.name"""
            ).fetchall()
        return dict(policy) | {
            "count_weekends": bool(policy["count_weekends"]),
            "prorate_new_hires": bool(policy["prorate_new_hires"]),
            "carryover_enabled": bool(policy["carryover_enabled"]),
            "leave_type_allowances": [
                dict(row) | {"is_paid": bool(row["is_paid"]), "is_active": bool(row["is_active"])}
                for row in leave_types
            ],
            "category_leave_type_allowances": [
                dict(row) | {
                    "is_applicable": bool(row["is_applicable"]),
                    "monthly_reset": bool(row["monthly_reset"]),
                    "attendance_based": bool(row["attendance_based"]),
                }
                for row in category_policies
            ],
            "yellow_card_policy_text": YELLOW_CARD_LEAVE_RULE,
        }

    def _update_leave_policy(self, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        allowed = {
            "period_start_month", "count_weekends", "prorate_new_hires",
            "carryover_enabled", "carryover_limit_days", "leave_type_allowances",
            "category_leave_type_allowances",
        }
        unknown = sorted(set(body) - allowed)
        if unknown:
            raise ApiError(400, "One or more leave policy fields are not supported.", {"unknown": unknown})
        updates: dict[str, int] = {}
        if "period_start_month" in body:
            month = _as_int(body["period_start_month"], "Leave period start month")
            if not 1 <= month <= 12:
                raise ApiError(400, "Leave period start month must be between 1 and 12.")
            updates["period_start_month"] = month
        for key, label in (
            ("count_weekends", "Weekend counting"),
            ("prorate_new_hires", "New-hire proration"),
            ("carryover_enabled", "Carry-over"),
        ):
            if key in body:
                updates[key] = _boolean_setting(body[key], label)
        if "carryover_limit_days" in body:
            limit = _as_int(body["carryover_limit_days"], "Carry-over limit")
            if not 0 <= limit <= 365:
                raise ApiError(400, "Carry-over limit must be between 0 and 365 days.")
            updates["carryover_limit_days"] = limit

        allowance_updates: list[tuple[int, int]] = []
        if "leave_type_allowances" in body:
            raw_allowances = body["leave_type_allowances"]
            if not isinstance(raw_allowances, list):
                raise ApiError(400, "Leave type allowances must be an array.")
            seen: set[int] = set()
            for item in raw_allowances:
                if not isinstance(item, dict):
                    raise ApiError(400, "Each leave type allowance must contain an ID and annual days.")
                leave_type_id = _as_int(item.get("id"), "Leave type ID")
                allowance = _as_int(item.get("annual_allowance_days"), "Annual leave allowance")
                if leave_type_id in seen:
                    raise ApiError(400, "A leave type allowance may only be supplied once.")
                if not 0 <= allowance <= 3660:
                    raise ApiError(400, "Annual leave allowance must be between 0 and 3660 days.")
                seen.add(leave_type_id)
                allowance_updates.append((leave_type_id, allowance))

        category_allowance_updates: list[tuple[str, int, float, int, str, int, int]] = []
        if "category_leave_type_allowances" in body:
            raw_category_allowances = body["category_leave_type_allowances"]
            if not isinstance(raw_category_allowances, list):
                raise ApiError(400, "Category leave type allowances must be an array.")
            seen_category_types: set[tuple[str, int]] = set()
            for item in raw_category_allowances:
                if not isinstance(item, dict):
                    raise ApiError(400, "Each category allowance must include an employment type and leave type ID.")
                employment_type = _normalize_employment_type(item.get("employment_type"))
                leave_type_id = _as_int(item.get("id"), "Leave type ID")
                try:
                    allowance = float(item.get("annual_allowance_days"))
                except (TypeError, ValueError):
                    raise ApiError(400, "Annual leave allowance must be a number.") from None
                if not math.isfinite(allowance) or not 0 <= allowance <= 3660:
                    raise ApiError(400, "Annual leave allowance must be between 0 and 3660 days.")
                applicable = _boolean_setting(item.get("is_applicable", True), "Leave applicability")
                accrual_method = str(item.get("accrual_method", "annual")).strip().lower()
                if accrual_method not in {"annual", "monthly"}:
                    raise ApiError(400, "Accrual method must be annual or monthly.")
                monthly_reset = int(_boolean_setting(item.get("monthly_reset", False), "Monthly reset"))
                attendance_based = int(_boolean_setting(item.get("attendance_based", False), "Attendance-based accrual"))
                if monthly_reset and accrual_method != "monthly":
                    raise ApiError(400, "Monthly reset requires a monthly accrual method.")
                if monthly_reset and attendance_based:
                    raise ApiError(400, "Attendance-based leave cannot use a monthly allowance reset.")
                key = (employment_type, leave_type_id)
                if key in seen_category_types:
                    raise ApiError(400, "A category allowance may only be supplied once per leave type.")
                seen_category_types.add(key)
                category_allowance_updates.append((employment_type, leave_type_id, allowance, applicable, accrual_method, monthly_reset, attendance_based))
        if not updates and "leave_type_allowances" not in body and "category_leave_type_allowances" not in body:
            raise ApiError(400, "No leave policy fields were supplied.")

        with self._db() as connection:
            if updates:
                assignments = ", ".join(f"{key} = ?" for key in updates)
                connection.execute(
                    f"UPDATE leave_policy SET {assignments}, updated_at = ?, updated_by = ? WHERE id = 1",
                    (*updates.values(), _now(), user["id"]),
                )
            elif allowance_updates or category_allowance_updates:
                connection.execute(
                    "UPDATE leave_policy SET updated_at = ?, updated_by = ? WHERE id = 1",
                    (_now(), user["id"]),
                )
            for leave_type_id, allowance in allowance_updates:
                cursor = connection.execute(
                    "UPDATE leave_types SET annual_allowance_days = ? WHERE id = ? AND is_active = 1",
                    (allowance, leave_type_id),
                )
                if cursor.rowcount != 1:
                    raise ApiError(404, f"Active leave type {leave_type_id} was not found.")
            for employment_type, leave_type_id, allowance, applicable, accrual_method, monthly_reset, attendance_based in category_allowance_updates:
                if not connection.execute(
                    "SELECT 1 FROM leave_types WHERE id = ? AND is_active = 1", (leave_type_id,)
                ).fetchone():
                    raise ApiError(404, f"Active leave type {leave_type_id} was not found.")
                connection.execute(
                    """INSERT INTO employment_leave_type_policies
                       (employment_type, leave_type_id, annual_allowance_days, is_applicable,
                        accrual_method, monthly_reset, attendance_based)
                       VALUES (?, ?, ?, ?, ?, ?, ?)
                       ON CONFLICT(employment_type, leave_type_id) DO UPDATE SET
                         annual_allowance_days = excluded.annual_allowance_days,
                         is_applicable = excluded.is_applicable,
                         accrual_method = excluded.accrual_method,
                         monthly_reset = excluded.monthly_reset,
                         attendance_based = excluded.attendance_based""",
                    (employment_type, leave_type_id, allowance, applicable, accrual_method, monthly_reset, attendance_based),
                )
        self._audit(
            user["id"],
            "leave.policy_updated",
            "leave_policy",
            "1",
            {
                "fields": sorted(updates),
                "leave_type_ids": [item[0] for item in allowance_updates],
                "category_leave_type_ids": [
                    {"employment_type": item[0], "id": item[1]} for item in category_allowance_updates
                ],
            },
            remote,
        )
        return self._get_leave_policy()

    def _create_leave_balance_adjustment(
        self, body: dict[str, Any], user: dict[str, Any], remote: str | None
    ) -> dict[str, Any]:
        employee_id = _as_int(body.get("employee_id"), "Employee ID")
        leave_type_id = _as_int(body.get("leave_type_id"), "Leave type ID")
        try:
            days = float(body.get("days"))
        except (TypeError, ValueError):
            raise ApiError(400, "Adjustment days must be a number.") from None
        if not math.isfinite(days) or days == 0 or abs(days) > 365:
            raise ApiError(400, "Adjustment must be a non-zero amount between -365 and 365 days.")
        reason = str(body.get("reason", "")).strip()
        if not reason or len(reason) > 500:
            raise ApiError(400, "A reason of up to 500 characters is required for a balance adjustment.")
        with self._db() as connection:
            employee = connection.execute(
                "SELECT id, employment_type FROM employees WHERE id = ? AND status != 'inactive'", (employee_id,)
            ).fetchone()
            leave_type = connection.execute(
                "SELECT id, name FROM leave_types WHERE id = ? AND is_active = 1", (leave_type_id,)
            ).fetchone()
            if not employee:
                raise ApiError(404, "Active employee not found.")
            if not leave_type:
                raise ApiError(404, "Active leave type not found.")
            type_policy = self._leave_type_policy(
                connection, _safe_employment_type(employee["employment_type"]), leave_type_id
            )
            if not type_policy["is_applicable"]:
                raise ApiError(400, "The employee category is not eligible for this leave type.")
            policy = connection.execute("SELECT period_start_month FROM leave_policy WHERE id = 1").fetchone()
            today = datetime.now(timezone.utc).date()
            if type_policy["monthly_reset"]:
                period_start = date(today.year, today.month, 1)
            else:
                period_start, _ = _leave_period_bounds(today, int(policy["period_start_month"]))
            cursor = connection.execute(
                """INSERT INTO leave_balance_adjustments
                   (employee_id, leave_type_id, period_start, days, reason, adjusted_by, adjusted_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (employee_id, leave_type_id, period_start.isoformat(), days, reason, user["id"], _now()),
            )
            adjustment_id = int(cursor.lastrowid)
        result = {
            "id": adjustment_id,
            "employee_id": employee_id,
            "leave_type_id": leave_type_id,
            "leave_type": leave_type["name"],
            "period_start": period_start.isoformat(),
            "days": days,
            "reason": reason,
        }
        self._audit(
            user["id"], "leave.balance_adjusted", "leave_balance_adjustment", adjustment_id,
            {"employee_id": employee_id, "leave_type_id": leave_type_id, "days": days}, remote,
        )
        return result

    def _leave_type_policy(self, connection: sqlite3.Connection, employment_type: str, leave_type_id: int) -> dict[str, Any]:
        override = connection.execute(
            """SELECT annual_allowance_days, is_applicable, accrual_method,
                      monthly_reset, attendance_based
               FROM employment_leave_type_policies
               WHERE employment_type = ? AND leave_type_id = ?""",
            (employment_type, leave_type_id),
        ).fetchone()
        if override:
            return {
                "annual_allowance_days": float(override["annual_allowance_days"]),
                "is_applicable": bool(override["is_applicable"]),
                "accrual_method": override["accrual_method"],
                "monthly_reset": bool(override["monthly_reset"]),
                "attendance_based": bool(override["attendance_based"]),
            }
        global_type = connection.execute(
            "SELECT annual_allowance_days FROM leave_types WHERE id = ?", (leave_type_id,)
        ).fetchone()
        return {
            "annual_allowance_days": float(global_type["annual_allowance_days"]) if global_type else 0.0,
            "is_applicable": True,
            "accrual_method": "annual",
            "monthly_reset": False,
            "attendance_based": False,
        }

    def _validate_special_leave_request(
        self,
        connection: sqlite3.Connection,
        employee_id: int,
        employment_type: str,
        leave_type_id: int,
        start_date: date,
        end_date: date,
        exclude_request_id: int | None = None,
    ) -> None:
        type_policy = self._leave_type_policy(connection, employment_type, leave_type_id)
        if not type_policy["monthly_reset"] and not type_policy["attendance_based"]:
            return
        policy = connection.execute("SELECT count_weekends FROM leave_policy WHERE id = 1").fetchone()
        count_weekends = bool(policy["count_weekends"])
        exclude_clause = " AND id != ?" if exclude_request_id is not None else ""
        params: tuple[Any, ...] = (employee_id, leave_type_id, exclude_request_id) if exclude_request_id is not None else (employee_id, leave_type_id)
        existing_rows = connection.execute(
            """SELECT start_date, end_date FROM leave_requests
               WHERE employee_id = ? AND leave_type_id = ? AND status IN ('pending', 'approved')""" + exclude_clause,
            params,
        ).fetchall()

        if type_policy["monthly_reset"]:
            base_monthly_allowance = type_policy["annual_allowance_days"] / 12
            month_start = date(start_date.year, start_date.month, 1)
            while month_start <= end_date:
                if month_start.month == 12:
                    next_month = date(month_start.year + 1, 1, 1)
                else:
                    next_month = date(month_start.year, month_start.month + 1, 1)
                month_end = next_month - timedelta(days=1)
                adjustment = connection.execute(
                    """SELECT COALESCE(SUM(days), 0) FROM leave_balance_adjustments
                       WHERE employee_id = ? AND leave_type_id = ? AND period_start = ?""",
                    (employee_id, leave_type_id, month_start.isoformat()),
                ).fetchone()[0]
                monthly_limit = max(0.0, base_monthly_allowance + float(adjustment or 0))
                reserved = _leave_date_set(existing_rows, month_start, month_end, count_weekends)
                requested = _requested_leave_dates(start_date, end_date, month_start, month_end, count_weekends)
                if len(reserved | requested) > monthly_limit:
                    raise ApiError(
                        400,
                        f"This leave type is limited to {monthly_limit:g} days per calendar month; unused days do not carry over.",
                    )
                month_start = next_month

        if type_policy["attendance_based"]:
            employee = connection.execute(
                "SELECT weekly_off_days FROM employees WHERE id = ?", (employee_id,)
            ).fetchone()
            weekly_off_days = _parse_weekly_off_days(employee["weekly_off_days"] if employee else [])
            earned_dates = _completed_weekly_off_dates(
                connection, employee_id, weekly_off_days, datetime.now(timezone.utc).date()
            )
            adjustment = connection.execute(
                """SELECT COALESCE(SUM(days), 0) FROM leave_balance_adjustments
                   WHERE employee_id = ? AND leave_type_id = ?""",
                (employee_id, leave_type_id),
            ).fetchone()[0]
            earned_balance = max(0.0, len(earned_dates) + float(adjustment or 0))
            reserved = _leave_date_set(existing_rows, date.min, date.max, count_weekends)
            requested = _requested_leave_dates(start_date, end_date, date.min, date.max, count_weekends)
            if len(reserved | requested) > earned_balance:
                raise ApiError(
                    400,
                    "Compensatory Leave is available only for completed attendance on a scheduled weekly off day.",
                )

    def _list_leave_types(self, user: dict[str, Any]) -> dict[str, Any]:
        with self._db() as connection:
            rows = connection.execute("SELECT * FROM leave_types WHERE is_active = 1 ORDER BY name").fetchall()
            employee = connection.execute(
                "SELECT employment_type FROM employees WHERE user_id = ?", (user["id"],)
            ).fetchone()
            employment_type = _safe_employment_type(employee["employment_type"] if employee else "Official Staff")
            items = []
            for row in rows:
                policy = self._leave_type_policy(connection, employment_type, int(row["id"]))
                if policy["is_applicable"]:
                    items.append(dict(row) | {
                        "is_paid": bool(row["is_paid"]),
                        "monthly_accrual_days": round(policy["annual_allowance_days"] / 12, 2)
                        if policy["accrual_method"] == "monthly" else 0,
                    } | policy)
        return {"items": items, "total": len(items), "employment_type": employment_type}

    def _list_leave_requests(self, user: dict[str, Any], permissions: set[str], query: dict[str, str]) -> dict[str, Any]:
        sql = """SELECT lr.*, e.employee_code, e.first_name, e.last_name, e.user_id, e.manager_id,
                 lt.name AS leave_type, COALESCE(NULLIF(TRIM(approver_employee.first_name || ' ' || approver_employee.last_name), ''), u.full_name) AS approver_name
                 FROM leave_requests lr JOIN employees e ON e.id = lr.employee_id
                 JOIN leave_types lt ON lt.id = lr.leave_type_id LEFT JOIN users u ON u.id = lr.approver_id
                   LEFT JOIN employees approver_employee ON approver_employee.user_id = u.id"""
        conditions: list[str] = []
        params: list[Any] = []
        if query.get("status"):
            conditions.append("lr.status = ?")
            params.append(query["status"])
        if conditions:
            sql += " WHERE " + " AND ".join(conditions)
        sql += " ORDER BY CASE WHEN lr.status = 'pending' THEN 0 ELSE 1 END, lr.requested_at DESC LIMIT 200"
        with self._db() as connection:
            rows = connection.execute(sql, params).fetchall()
            own = connection.execute("SELECT id FROM employees WHERE user_id = ?", (user["id"],)).fetchone()
        if "leave.read" not in permissions and "leave.manage" not in permissions:
            manager_id = own["id"] if own else None
            rows = [
                row for row in rows
                if (row["user_id"] == user["id"] and ("leave.read.self" in permissions or "leave.create" in permissions))
                or (manager_id is not None and row["manager_id"] == manager_id and ("leave.read.team" in permissions or "leave.approve" in permissions))
            ]
        items = [_leave_json(row) for row in rows]
        return {"items": items, "total": len(items)}

    def _get_leave_request(self, request_id: int, user: dict[str, Any]) -> dict[str, Any]:
        row = self._leave_row(request_id)
        if not row:
            raise ApiError(404, "Leave request not found.")
        if not self._can_access_leave(row, user, self._permissions(user["id"])):
            raise ApiError(403, "You cannot view this leave request.")
        return _leave_json(row)

    def _leave_row(self, request_id: int) -> sqlite3.Row | None:
        with self._db() as connection:
            return connection.execute(
                """SELECT lr.*, e.employee_code, e.first_name, e.last_name, e.user_id, e.manager_id,
                   lt.name AS leave_type, COALESCE(NULLIF(TRIM(approver_employee.first_name || ' ' || approver_employee.last_name), ''), u.full_name) AS approver_name FROM leave_requests lr
                   JOIN employees e ON e.id = lr.employee_id JOIN leave_types lt ON lt.id = lr.leave_type_id
                   LEFT JOIN users u ON u.id = lr.approver_id
                   LEFT JOIN employees approver_employee ON approver_employee.user_id = u.id WHERE lr.id = ?""",
                (request_id,),
            ).fetchone()

    def _can_access_leave(self, row: sqlite3.Row, user: dict[str, Any], permissions: set[str]) -> bool:
        if "leave.read" in permissions or "leave.manage" in permissions:
            return True
        own_id = self._employee_id(user["id"])
        own = row["user_id"] == user["id"] and bool(permissions.intersection({"leave.read.self", "leave.create"}))
        team = own_id is not None and row["manager_id"] == own_id and bool(permissions.intersection({"leave.read.team", "leave.approve"}))
        return own or team

    def _create_leave_request(self, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        employee = self._employee_for_user(user["id"])
        if not employee:
            raise ApiError(409, "Your account is not linked to an employee profile.")
        leave_type_id = _as_int(body.get("leave_type_id"), "Leave type")
        start_date = _date_string(body.get("start_date"))
        end_date = _date_string(body.get("end_date"))
        if end_date < start_date:
            raise ApiError(400, "End date must be on or after the start date.")
        reason = str(body.get("reason", "")).strip()
        if not reason:
            raise ApiError(400, "A reason is required for a leave request.")
        with self._db() as connection:
            leave_type = connection.execute("SELECT id FROM leave_types WHERE id = ? AND is_active = 1", (leave_type_id,)).fetchone()
            if not leave_type:
                raise ApiError(400, "The selected leave type is unavailable.")
            employee_type = _safe_employment_type(employee["employment_type"])
            type_policy = self._leave_type_policy(connection, employee_type, leave_type_id)
            if not type_policy["is_applicable"]:
                raise ApiError(400, f"{employee_type} employees are not eligible for this leave type.")
            self._validate_special_leave_request(
                connection,
                int(employee["id"]),
                employee_type,
                leave_type_id,
                date.fromisoformat(start_date),
                date.fromisoformat(end_date),
            )
            cursor = connection.execute(
                """INSERT INTO leave_requests(employee_id, leave_type_id, start_date, end_date, reason,
                   status, requested_at) VALUES (?, ?, ?, ?, ?, 'pending', ?)""",
                (employee["id"], leave_type_id, start_date, end_date, reason, _now()),
            )
            request_id = int(cursor.lastrowid)
        self._audit(user["id"], "leave.requested", "leave_request", request_id, {"start_date": start_date, "end_date": end_date}, remote)
        return _leave_json(self._leave_row(request_id))

    def _update_leave_request(self, request_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        row = self._leave_row(request_id)
        if not row:
            raise ApiError(404, "Leave request not found.")
        if row["user_id"] != user["id"] or row["status"] != "pending":
            raise ApiError(403, "Only your own pending leave request can be edited.")
        updates: dict[str, Any] = {}
        for key in ("start_date", "end_date"):
            if key in body:
                updates[key] = _date_string(body[key])
        if "reason" in body:
            reason = str(body["reason"]).strip()
            if not reason:
                raise ApiError(400, "A reason is required for a leave request.")
            updates["reason"] = reason
        if "leave_type_id" in body:
            updates["leave_type_id"] = _as_int(body["leave_type_id"], "Leave type")
        start = updates.get("start_date", row["start_date"])
        end = updates.get("end_date", row["end_date"])
        if end < start:
            raise ApiError(400, "End date must be on or after the start date.")
        if not updates:
            raise ApiError(400, "No editable leave request fields were supplied.")
        with self._db() as connection:
            target_employee = connection.execute(
                "SELECT employment_type FROM employees WHERE id = ?", (row["employee_id"],)
            ).fetchone()
            leave_type_id = int(updates.get("leave_type_id", row["leave_type_id"]))
            leave_type = connection.execute(
                "SELECT 1 FROM leave_types WHERE id = ? AND is_active = 1", (leave_type_id,)
            ).fetchone()
            if not target_employee or not leave_type:
                raise ApiError(400, "The selected leave type is unavailable.")
            employment_type = _safe_employment_type(target_employee["employment_type"])
            type_policy = self._leave_type_policy(connection, employment_type, leave_type_id)
            if not type_policy["is_applicable"]:
                raise ApiError(400, "Your employee category is not eligible for this leave type.")
            self._validate_special_leave_request(
                connection,
                int(row["employee_id"]),
                employment_type,
                leave_type_id,
                date.fromisoformat(start),
                date.fromisoformat(end),
                exclude_request_id=request_id,
            )
            assignment = ", ".join(f"{key} = ?" for key in updates)
            connection.execute(f"UPDATE leave_requests SET {assignment} WHERE id = ?", (*updates.values(), request_id))
        self._audit(user["id"], "leave.updated", "leave_request", request_id, {"fields": sorted(updates)}, remote)
        return _leave_json(self._leave_row(request_id))

    def _decide_leave(self, request_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        decision = str(body.get("decision", "")).lower()
        if decision not in {"approved", "rejected"}:
            raise ApiError(400, "Decision must be approved or rejected.")
        row = self._leave_row(request_id)
        if not row:
            raise ApiError(404, "Leave request not found.")
        if row["status"] != "pending":
            raise ApiError(409, "Only pending leave requests can be decided.")
        permissions = self._permissions(user["id"])
        if "leave.manage" not in permissions:
            own = self._employee_for_user(user["id"])
            if not own or row["manager_id"] != own["id"]:
                raise ApiError(403, "You can only decide leave requests from your reporting team.")
        note = str(body.get("note", "")).strip() or None
        with self._db() as connection:
            if decision == "approved":
                target = connection.execute(
                    "SELECT employment_type FROM employees WHERE id = ?", (row["employee_id"],)
                ).fetchone()
                if not target:
                    raise ApiError(404, "Employee profile not found for this leave request.")
                employment_type = _safe_employment_type(target["employment_type"])
                type_policy = self._leave_type_policy(connection, employment_type, int(row["leave_type_id"]))
                if not type_policy["is_applicable"]:
                    raise ApiError(400, "This employee category is not eligible for the requested leave type.")
                self._validate_special_leave_request(
                    connection,
                    int(row["employee_id"]),
                    employment_type,
                    int(row["leave_type_id"]),
                    date.fromisoformat(row["start_date"]),
                    date.fromisoformat(row["end_date"]),
                    exclude_request_id=request_id,
                )
            connection.execute(
                "UPDATE leave_requests SET status = ?, decided_at = ?, approver_id = ?, decision_note = ? WHERE id = ?",
                (decision, _now(), user["id"], note, request_id),
            )
        self._audit(user["id"], f"leave.{decision}", "leave_request", request_id, {"note": note}, remote)
        return _leave_json(self._leave_row(request_id))

    def _list_gate_passes(
        self, user: dict[str, Any], permissions: set[str], query: dict[str, str]
    ) -> dict[str, Any]:
        status_filter = query.get("status", "").strip().lower()
        if status_filter and status_filter not in {"pending", "approved", "rejected"}:
            raise ApiError(400, "Gate-pass status must be pending, approved, or rejected.")
        sql = """SELECT p.*, e.first_name, e.last_name, e.employee_code, e.department, e.title,
                 e.user_id, e.manager_id FROM gate_passes p
                 JOIN employees e ON e.id = p.employee_id"""
        params: list[Any] = []
        if status_filter:
            sql += " WHERE p.status = ?"
            params.append(status_filter)
        sql += " ORDER BY CASE WHEN p.status = 'pending' THEN 0 ELSE 1 END, p.requested_at DESC LIMIT 200"
        with self._db() as connection:
            rows = connection.execute(sql, params).fetchall()
            own = connection.execute("SELECT id FROM employees WHERE user_id = ?", (user["id"],)).fetchone()
        if not permissions.intersection({"gatepass.read", "gatepass.manage"}):
            own_id = int(own["id"]) if own else None
            visible = []
            for row in rows:
                is_self = row["user_id"] == user["id"] and bool(permissions.intersection({
                    "gatepass.read.self", "gatepass.create"
                }))
                is_team = (
                    own_id is not None
                    and row["manager_id"] == own_id
                    and bool(permissions.intersection({"gatepass.read.team", "gatepass.approve"}))
                )
                if is_self or is_team:
                    visible.append(row)
            rows = visible
        return {"items": [_gate_pass_json(row) for row in rows], "total": len(rows)}

    def _create_gate_pass(
        self, body: dict[str, Any], user: dict[str, Any], remote: str | None
    ) -> dict[str, Any]:
        permissions = self._permissions(user["id"])
        requested_employee_id = _optional_int(body.get("employee_id"))
        if "gatepass.manage" in permissions and requested_employee_id is not None:
            employee_id = requested_employee_id
        else:
            employee = self._employee_for_user(user["id"])
            if not employee:
                raise ApiError(409, "Your account is not linked to an employee profile.")
            employee_id = int(employee["id"])
            if requested_employee_id is not None and requested_employee_id != employee_id:
                raise ApiError(403, "You may only request a gate pass for your own employee profile.")
        pass_type = str(body.get("pass_type", "")).strip().lower()
        if pass_type not in {"personal_exit", "official_duty", "visitor"}:
            raise ApiError(400, "Choose a supported gate-pass type.")
        purpose = str(body.get("purpose", "")).strip()
        if not purpose or len(purpose) > 500:
            raise ApiError(400, "A purpose of up to 500 characters is required.")
        valid_from = _datetime_string(body.get("valid_from"), "Valid-from time")
        valid_until = _datetime_string(body.get("valid_until"), "Valid-until time")
        starts_at = _parse_datetime(valid_from, "Valid-from time")
        ends_at = _parse_datetime(valid_until, "Valid-until time")
        comparable_start = starts_at if starts_at.tzinfo else starts_at.replace(tzinfo=timezone.utc)
        comparable_end = ends_at if ends_at.tzinfo else ends_at.replace(tzinfo=timezone.utc)
        now = datetime.now(timezone.utc)
        if comparable_start.astimezone(timezone.utc) < now - timedelta(hours=1):
            raise ApiError(400, "A gate pass cannot begin more than one hour in the past.")
        if comparable_end.astimezone(timezone.utc) <= comparable_start.astimezone(timezone.utc):
            raise ApiError(400, "The gate-pass end time must be after its start time.")
        if comparable_end.astimezone(timezone.utc) - comparable_start.astimezone(timezone.utc) > timedelta(days=7):
            raise ApiError(400, "A gate pass cannot be valid for more than seven days.")
        with self._db() as connection:
            employee_row = connection.execute(
                "SELECT status FROM employees WHERE id = ?", (employee_id,)
            ).fetchone()
            if not employee_row or employee_row["status"] == "inactive":
                raise ApiError(404, "Active employee not found.")
            cursor = connection.execute(
                """INSERT INTO gate_passes
                   (employee_id, requested_by, pass_type, purpose, valid_from, valid_until, status, requested_at)
                   VALUES (?, ?, ?, ?, ?, ?, 'pending', ?)""",
                (employee_id, user["id"], pass_type, purpose, valid_from, valid_until, _now()),
            )
            pass_id = int(cursor.lastrowid)
        result = self._gate_pass(pass_id)
        self._audit(
            user["id"], "gate_pass.requested", "gate_pass", pass_id,
            {"employee_id": employee_id, "pass_type": pass_type}, remote,
        )
        return result

    def _gate_pass(self, pass_id: int) -> dict[str, Any]:
        with self._db() as connection:
            row = connection.execute(
                """SELECT p.*, e.first_name, e.last_name, e.employee_code, e.department, e.title
                   FROM gate_passes p JOIN employees e ON e.id = p.employee_id WHERE p.id = ?""",
                (pass_id,),
            ).fetchone()
        if row is None:
            raise ApiError(404, "Gate pass not found.")
        return _gate_pass_json(row)

    def _decide_gate_pass(
        self, pass_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None
    ) -> dict[str, Any]:
        decision = str(body.get("decision", "")).strip().lower()
        if decision not in {"approved", "rejected"}:
            raise ApiError(400, "Decision must be approved or rejected.")
        with self._db() as connection:
            row = connection.execute(
                """SELECT p.*, e.user_id, e.manager_id FROM gate_passes p
                   JOIN employees e ON e.id = p.employee_id WHERE p.id = ?""",
                (pass_id,),
            ).fetchone()
            if not row:
                raise ApiError(404, "Gate pass not found.")
            permissions = self._permissions(user["id"])
            if "gatepass.manage" not in permissions:
                actor_employee = connection.execute(
                    "SELECT id FROM employees WHERE user_id = ?", (user["id"],)
                ).fetchone()
                if not actor_employee or row["manager_id"] != actor_employee["id"] or row["user_id"] == user["id"]:
                    raise ApiError(403, "You may only review gate passes from your reporting team.")
            if row["status"] != "pending":
                raise ApiError(409, "Only pending gate passes can be decided.")
            note = str(body.get("note", "")).strip() or None
            reference_code = f"FFGP-{secrets.token_hex(4).upper()}" if decision == "approved" else None
            connection.execute(
                """UPDATE gate_passes SET status = ?, decided_at = ?, decided_by = ?,
                   decision_note = ?, reference_code = ? WHERE id = ?""",
                (decision, _now(), user["id"], note, reference_code, pass_id),
            )
        self._audit(
            user["id"], f"gate_pass.{decision}", "gate_pass", pass_id,
            {"reference_issued": decision == "approved"}, remote,
        )
        return self._gate_pass(pass_id)

    def _list_users(self) -> dict[str, Any]:
        with self._db() as connection:
            rows = connection.execute(
                """SELECT u.id, u.email,
                          COALESCE(NULLIF(TRIM(e.first_name || ' ' || e.last_name), ''), u.full_name) AS full_name,
                          u.is_active, u.created_at, e.id AS employee_id, e.employee_code
                   FROM users u LEFT JOIN employees e ON e.user_id = u.id ORDER BY full_name"""
            ).fetchall()
            role_rows = connection.execute(
                "SELECT ur.user_id, r.id, r.name FROM user_roles ur JOIN roles r ON r.id = ur.role_id ORDER BY r.name"
            ).fetchall()
            role_options = connection.execute("SELECT id, name, description FROM roles ORDER BY name").fetchall()
        roles_by_user: dict[int, list[dict[str, str]]] = {}
        for role in role_rows:
            roles_by_user.setdefault(role["user_id"], []).append({"id": role["id"], "name": role["name"]})
        items = []
        for row in rows:
            item = dict(row)
            item["is_active"] = bool(item["is_active"])
            item["roles"] = roles_by_user.get(item["id"], [])
            items.append(item)
        return {"items": items, "total": len(items), "role_options": [dict(role) for role in role_options]}

    def _create_user(self, body: dict[str, Any], actor: dict[str, Any], remote: str | None) -> dict[str, Any]:
        email = str(body.get("email", "")).strip().lower()
        full_name = str(body.get("full_name", "")).strip()
        password = str(body.get("password", ""))
        role_ids = body.get("role_ids")
        if not isinstance(role_ids, list) or not role_ids:
            role_id = body.get("role_id")
            role_ids = [role_id] if role_id else []
        role_ids = list(dict.fromkeys(str(role_id) for role_id in role_ids if role_id))
        if not _valid_email(email) or not full_name or len(password) < 10 or not role_ids:
            raise ApiError(400, "Name, valid email, a password of at least 10 characters, and a role are required.")
        employee_id = _optional_int(body.get("employee_id"))
        now = _now()
        with self._db() as connection:
            for role_id in role_ids:
                if not connection.execute("SELECT 1 FROM roles WHERE id = ?", (role_id,)).fetchone():
                    raise ApiError(400, f"Role '{role_id}' does not exist.")
            if employee_id is not None:
                employee = connection.execute(
                    "SELECT user_id, first_name, last_name FROM employees WHERE id = ?", (employee_id,)
                ).fetchone()
                if not employee:
                    raise ApiError(400, "The selected employee does not exist.")
                if employee["user_id"] is not None:
                    raise ApiError(409, "That employee is already linked to a user account.")
                full_name = f"{employee['first_name']} {employee['last_name']}".strip()
            cursor = connection.execute(
                "INSERT INTO users(email, password_hash, full_name, is_active, created_at) VALUES (?, ?, ?, 1, ?)",
                (email, _hash_password(password), full_name, now),
            )
            user_id = int(cursor.lastrowid)
            connection.executemany("INSERT INTO user_roles(user_id, role_id) VALUES (?, ?)", [(user_id, role) for role in role_ids])
            if employee_id is not None:
                connection.execute("UPDATE employees SET user_id = ?, updated_at = ? WHERE id = ?", (user_id, now, employee_id))
        self._audit(actor["id"], "user.created", "user", user_id, {"email": email, "role_ids": role_ids}, remote)
        return next(item for item in self._list_users()["items"] if item["id"] == user_id)

    def _update_user(self, target_id: int, body: dict[str, Any], actor: dict[str, Any], remote: str | None) -> dict[str, Any]:
        with self._db() as connection:
            target = connection.execute("SELECT * FROM users WHERE id = ?", (target_id,)).fetchone()
            if not target:
                raise ApiError(404, "User account not found.")
            current_roles = {row[0] for row in connection.execute("SELECT role_id FROM user_roles WHERE user_id = ?", (target_id,))}
        is_active = body.get("is_active")
        role_ids = body.get("role_ids")
        if role_ids is None and body.get("role_id"):
            role_ids = [body["role_id"]]
        if role_ids is not None and (not isinstance(role_ids, list) or not role_ids):
            raise ApiError(400, "A user must retain at least one role.")
        normalized_roles = list(dict.fromkeys(str(role) for role in role_ids)) if role_ids is not None else None
        with self._db() as connection:
            if normalized_roles is not None:
                for role_id in normalized_roles:
                    if not connection.execute("SELECT 1 FROM roles WHERE id = ?", (role_id,)).fetchone():
                        raise ApiError(400, f"Role '{role_id}' does not exist.")
                if "super_admin" in current_roles and "super_admin" not in normalized_roles:
                    active_super_admins = connection.execute(
                        """SELECT COUNT(DISTINCT u.id) FROM users u JOIN user_roles ur ON ur.user_id = u.id
                           WHERE ur.role_id = 'super_admin' AND u.is_active = 1"""
                    ).fetchone()[0]
                    if active_super_admins <= 1:
                        raise ApiError(409, "The final active Super Admin cannot be demoted.")
                connection.execute("DELETE FROM user_roles WHERE user_id = ?", (target_id,))
                connection.executemany("INSERT INTO user_roles(user_id, role_id) VALUES (?, ?)", [(target_id, role) for role in normalized_roles])
            if is_active is not None:
                if not bool(is_active) and "super_admin" in current_roles:
                    active_super_admins = connection.execute(
                        """SELECT COUNT(DISTINCT u.id) FROM users u JOIN user_roles ur ON ur.user_id = u.id
                           WHERE ur.role_id = 'super_admin' AND u.is_active = 1"""
                    ).fetchone()[0]
                    if active_super_admins <= 1:
                        raise ApiError(409, "The final active Super Admin cannot be deactivated.")
                connection.execute("UPDATE users SET is_active = ? WHERE id = ?", (int(bool(is_active)), target_id))
            if "full_name" in body:
                full_name = str(body["full_name"]).strip()
                if not full_name:
                    raise ApiError(400, "Full name cannot be empty.")
                connection.execute("UPDATE users SET full_name = ? WHERE id = ?", (full_name, target_id))
                employee = connection.execute(
                    "SELECT id FROM employees WHERE user_id = ?", (target_id,)
                ).fetchone()
                if employee:
                    name_parts = full_name.split(maxsplit=1)
                    first_name = name_parts[0]
                    last_name = name_parts[1] if len(name_parts) > 1 else ""
                    connection.execute(
                        "UPDATE employees SET first_name = ?, last_name = ?, updated_at = ? WHERE id = ?",
                        (first_name, last_name, _now(), employee["id"]),
                    )
        self._audit(actor["id"], "user.updated", "user", target_id, {"fields": sorted(body)}, remote)
        return next(item for item in self._list_users()["items"] if item["id"] == target_id)

    def _list_roles(self) -> dict[str, Any]:
        with self._db() as connection:
            roles = connection.execute("SELECT * FROM roles ORDER BY name").fetchall()
            catalog = connection.execute("SELECT key, module, action, label FROM permissions ORDER BY module, label").fetchall()
            grants = connection.execute("SELECT role_id, permission_key FROM role_permissions").fetchall()
        permissions_by_role: dict[str, set[str]] = {}
        for grant in grants:
            permissions_by_role.setdefault(grant["role_id"], set()).add(grant["permission_key"])
        permission_keys = {row["key"] for row in catalog}
        role_items = []
        for role in roles:
            keys = permissions_by_role.get(role["id"], set())
            if role["id"] == "super_admin":
                keys = permission_keys
            role_items.append({
                "id": role["id"], "name": role["name"], "description": role["description"],
                "is_system": bool(role["is_system"]), "permissions": sorted(keys),
            })
        return {"roles": role_items, "permission_catalog": [dict(row) for row in catalog]}

    def _create_role(self, body: dict[str, Any], actor: dict[str, Any], remote: str | None) -> dict[str, Any]:
        name = str(body.get("name", "")).strip()
        description = str(body.get("description", "")).strip()
        role_id = str(body.get("id", "")).strip().lower() or re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
        if not name or not role_id or len(role_id) > 48 or not re.fullmatch(r"[a-z0-9_-]+", role_id):
            raise ApiError(400, "A role name and a simple unique role id are required.")
        with self._db() as connection:
            connection.execute(
                "INSERT INTO roles(id, name, description, is_system, created_at) VALUES (?, ?, ?, 0, ?)",
                (role_id, name, description, _now()),
            )
        self._audit(actor["id"], "role.created", "role", role_id, {"name": name}, remote)
        return next(role for role in self._list_roles()["roles"] if role["id"] == role_id)

    def _update_role_permissions(self, role_id: str, body: dict[str, Any], actor: dict[str, Any], remote: str | None) -> dict[str, Any]:
        permission_keys = body.get("permissions")
        if not isinstance(permission_keys, list):
            raise ApiError(400, "Permissions must be supplied as an array of permission keys.")
        permission_keys = list(dict.fromkeys(str(key) for key in permission_keys))
        if role_id == "super_admin":
            raise ApiError(409, "Super Admin is protected and always has every catalog permission.")
        with self._db() as connection:
            if not connection.execute("SELECT 1 FROM roles WHERE id = ?", (role_id,)).fetchone():
                raise ApiError(404, "Role not found.")
            known = {row[0] for row in connection.execute("SELECT key FROM permissions")}
            unknown = sorted(set(permission_keys) - known)
            if unknown:
                raise ApiError(400, "One or more permission keys are not in the catalog.", {"unknown": unknown})
            connection.execute("DELETE FROM role_permissions WHERE role_id = ?", (role_id,))
            connection.executemany(
                "INSERT INTO role_permissions(role_id, permission_key) VALUES (?, ?)",
                [(role_id, key) for key in permission_keys],
            )
        self._audit(actor["id"], "role.permissions_updated", "role", role_id, {"permission_count": len(permission_keys)}, remote)
        return next(role for role in self._list_roles()["roles"] if role["id"] == role_id)

    def _dashboard(self, user: dict[str, Any]) -> dict[str, Any]:
        today_date = datetime.now(timezone.utc).date()
        today = today_date.isoformat()
        permissions = self._permissions(user["id"])
        with self._db() as connection:
            own_row = connection.execute("SELECT id, start_date, employment_type, weekly_off_days FROM employees WHERE user_id = ?", (user["id"],)).fetchone()
            own_id = own_row["id"] if own_row else None
            policy_row = connection.execute("SELECT * FROM leave_policy WHERE id = 1").fetchone()
            period_start_month = int(policy_row["period_start_month"])
            count_weekends = bool(policy_row["count_weekends"])
            prorate_new_hires = bool(policy_row["prorate_new_hires"])
            carryover_enabled = bool(policy_row["carryover_enabled"])
            carryover_limit_days = int(policy_row["carryover_limit_days"])
            period_start, period_end = _leave_period_bounds(today_date, period_start_month)
            previous_period_end = period_start - timedelta(days=1)
            previous_period_start, _ = _leave_period_bounds(previous_period_end, period_start_month)
            period_label = (
                f"{period_start.year} calendar year"
                if period_start_month == 1
                else f"{period_start.year}–{period_end.year} leave period"
            )
            leave_policy_summary = " · ".join((
                "weekends included" if count_weekends else "weekdays only",
                "new-hire proration on" if prorate_new_hires else "no new-hire proration",
                f"carry-over up to {carryover_limit_days} days" if carryover_enabled and carryover_limit_days else "no carry-over",
            ))

            def scoped_employee_ids(global_read: bool, team_read: bool, self_read: bool) -> list[int] | None:
                if global_read:
                    return None
                if team_read and own_id is not None:
                    rows = connection.execute(
                        "SELECT id FROM employees WHERE id = ? OR manager_id = ?", (own_id, own_id)
                    ).fetchall()
                    return [row["id"] for row in rows]
                if self_read and own_id is not None:
                    return [own_id]
                return []

            employee_ids = scoped_employee_ids("employees.read" in permissions, "employees.read.team" in permissions, "employees.read.self" in permissions)
            attendance_ids = scoped_employee_ids(
                bool(permissions.intersection({"attendance.read", "attendance.manage"})),
                "attendance.read.team" in permissions,
                bool(permissions.intersection({"attendance.read.self", "attendance.punch"})),
            )
            leave_ids = scoped_employee_ids(
                bool(permissions.intersection({"leave.read", "leave.manage"})),
                bool(permissions.intersection({"leave.read.team", "leave.approve"})),
                bool(permissions.intersection({"leave.read.self", "leave.create"})),
            )
            own_attendance = None
            if own_id is not None and permissions.intersection({
                "attendance.read", "attendance.manage", "attendance.read.self", "attendance.punch",
            }):
                own_attendance_row = connection.execute(
                    """SELECT a.*, e.employee_code, e.first_name, e.last_name, e.user_id, e.manager_id,
                       w.name AS location_name FROM attendance_records a JOIN employees e ON e.id = a.employee_id
                       LEFT JOIN work_locations w ON w.id = a.work_location_id
                       WHERE a.employee_id = ? AND a.punch_out_at IS NULL
                       ORDER BY a.punch_in_at DESC LIMIT 1""",
                    (own_id,),
                ).fetchone()
                own_attendance = _attendance_json(own_attendance_row)
            own_shift = None
            if own_id is not None and permissions.intersection({"shifts.read", "shifts.read.self", "shifts.manage"}):
                own_shift_row = connection.execute(
                    """SELECT a.*, s.name AS shift_name, s.start_time, s.end_time, s.break_minutes,
                       e.employee_code, e.first_name, e.last_name, e.department, w.name AS location_name
                       FROM shift_assignments a JOIN shift_templates s ON s.id = a.shift_id
                       JOIN employees e ON e.id = a.employee_id
                       LEFT JOIN work_locations w ON w.id = a.work_location_id
                       WHERE a.employee_id = ? AND a.work_date = ? AND a.is_active = 1 LIMIT 1""",
                    (own_id, today),
                ).fetchone()
                own_shift = _shift_assignment_json(own_shift_row)

            def scoped_count(sql: str, ids: list[int] | None, tail_params: tuple[Any, ...] = ()) -> int:
                if ids == []:
                    return 0
                if ids is None:
                    return int(connection.execute(sql.replace("__SCOPE__", " IS NOT NULL"), tail_params).fetchone()[0])
                placeholders = ",".join("?" for _ in ids)
                scoped_sql = sql.replace("__SCOPE__", f" IN ({placeholders})")
                return int(connection.execute(scoped_sql, (*ids, *tail_params)).fetchone()[0])

            employees = scoped_count(
                "SELECT COUNT(*) FROM employees WHERE id__SCOPE__ AND status = 'active'", employee_ids
            )
            present = scoped_count(
                "SELECT COUNT(DISTINCT employee_id) FROM attendance_records WHERE employee_id__SCOPE__ AND substr(punch_in_at, 1, 10) = ?",
                attendance_ids,
                (today,),
            )
            pending = scoped_count(
                "SELECT COUNT(*) FROM leave_requests WHERE employee_id__SCOPE__ AND status = 'pending'", leave_ids
            )
            on_leave_today = scoped_count(
                """SELECT COUNT(DISTINCT employee_id) FROM leave_requests
                   WHERE employee_id__SCOPE__ AND status = 'approved'
                   AND start_date <= ? AND end_date >= ?""",
                leave_ids,
                (today, today),
            )
            leave_balance_year = period_start.year
            leave_balance_period = {
                "start_date": period_start.isoformat(),
                "end_date": period_end.isoformat(),
                "label": period_label,
                "policy_summary": leave_policy_summary,
            }
            leave_balances: list[dict[str, Any]] = []
            if own_id is not None and (leave_ids is None or own_id in leave_ids):
                leave_types = connection.execute(
                    "SELECT id, name, annual_allowance_days FROM leave_types WHERE is_active = 1 ORDER BY name"
                ).fetchall()
                hire_date = date.fromisoformat(own_row["start_date"])
                employment_type = _safe_employment_type(own_row["employment_type"])
                for leave_type in leave_types:
                    type_policy = self._leave_type_policy(
                        connection, employment_type, int(leave_type["id"])
                    )
                    if not type_policy["is_applicable"]:
                        continue
                    annual_allowance = float(type_policy["annual_allowance_days"])
                    balance_period_start = period_start
                    balance_period_end = period_end
                    balance_period_label = period_label
                    balance_policy_note = (
                        f"{annual_allowance:g} days per year"
                        if type_policy["accrual_method"] == "annual" else
                        f"{annual_allowance / 12:g} days accrued monthly"
                    )
                    pending_reserved = 0

                    if type_policy["attendance_based"]:
                        request_rows = connection.execute(
                            """SELECT start_date, end_date FROM leave_requests
                               WHERE employee_id = ? AND leave_type_id = ? AND status = 'approved'""",
                            (own_id, leave_type["id"]),
                        ).fetchall()
                        current_used = _approved_leave_day_count(
                            request_rows, date.min, date.max, count_weekends
                        )
                        pending_rows = connection.execute(
                            """SELECT start_date, end_date FROM leave_requests
                               WHERE employee_id = ? AND leave_type_id = ? AND status = 'pending'""",
                            (own_id, leave_type["id"]),
                        ).fetchall()
                        pending_reserved = _approved_leave_day_count(
                            pending_rows, date.min, date.max, count_weekends
                        )
                        earned_days = _completed_weekly_off_dates(
                            connection,
                            int(own_id),
                            _parse_weekly_off_days(own_row["weekly_off_days"]),
                            today_date,
                        )
                        current_base = float(len(earned_days))
                        adjustment_row = connection.execute(
                            """SELECT COALESCE(SUM(days), 0) FROM leave_balance_adjustments
                               WHERE employee_id = ? AND leave_type_id = ?""",
                            (own_id, leave_type["id"]),
                        ).fetchone()
                        current_adjustment = round(float(adjustment_row[0] or 0), 2)
                        previous_used = 0
                        previous_base = 0
                        previous_adjustment = 0
                        carryover = 0
                        balance_period_start = hire_date
                        balance_period_end = today_date
                        balance_period_label = "Earned from completed weekly-off shifts"
                        balance_policy_note = "One compensatory day is earned for each completed attendance record on a scheduled weekly off."
                    elif type_policy["monthly_reset"]:
                        balance_period_start = date(today_date.year, today_date.month, 1)
                        next_month_start = (
                            date(today_date.year + 1, 1, 1)
                            if today_date.month == 12 else
                            date(today_date.year, today_date.month + 1, 1)
                        )
                        balance_period_end = next_month_start - timedelta(days=1)
                        balance_period_label = f"{today_date.strftime('%B %Y')} monthly allowance"
                        request_rows = connection.execute(
                            """SELECT start_date, end_date FROM leave_requests
                               WHERE employee_id = ? AND leave_type_id = ? AND status = 'approved'
                               AND start_date <= ? AND end_date >= ?""",
                            (own_id, leave_type["id"], balance_period_end.isoformat(), balance_period_start.isoformat()),
                        ).fetchall()
                        current_used = _approved_leave_day_count(
                            request_rows, balance_period_start, balance_period_end, count_weekends
                        )
                        pending_rows = connection.execute(
                            """SELECT start_date, end_date FROM leave_requests
                               WHERE employee_id = ? AND leave_type_id = ? AND status = 'pending'
                               AND start_date <= ? AND end_date >= ?""",
                            (own_id, leave_type["id"], balance_period_end.isoformat(), balance_period_start.isoformat()),
                        ).fetchall()
                        pending_reserved = _approved_leave_day_count(
                            pending_rows, balance_period_start, balance_period_end, count_weekends
                        )
                        current_base = round(annual_allowance / 12, 2)
                        current_adjustment_row = connection.execute(
                            """SELECT COALESCE(SUM(days), 0) FROM leave_balance_adjustments
                               WHERE employee_id = ? AND leave_type_id = ? AND period_start = ?""",
                            (own_id, leave_type["id"], balance_period_start.isoformat()),
                        ).fetchone()
                        current_adjustment = round(float(current_adjustment_row[0] or 0), 2)
                        previous_used = 0
                        previous_base = 0
                        previous_adjustment = 0
                        carryover = 0
                        balance_policy_note = f"{current_base:g} days per calendar month; unused days reset at month-end."
                    else:
                        request_rows = connection.execute(
                            """SELECT start_date, end_date FROM leave_requests
                               WHERE employee_id = ? AND leave_type_id = ? AND status = 'approved'
                               AND start_date <= ? AND end_date >= ?""",
                            (own_id, leave_type["id"], period_end.isoformat(), previous_period_start.isoformat()),
                        ).fetchall()
                        current_used = _approved_leave_day_count(
                            request_rows, period_start, period_end, count_weekends
                        )
                        previous_used = _approved_leave_day_count(
                            request_rows, previous_period_start, previous_period_end, count_weekends
                        )
                        if type_policy["accrual_method"] == "monthly":
                            current_base = _monthly_accrued_allowance(
                                annual_allowance, hire_date, period_start, today_date, prorate_new_hires
                            )
                            previous_base = _monthly_accrued_allowance(
                                annual_allowance, hire_date, previous_period_start, previous_period_end, prorate_new_hires
                            )
                        else:
                            current_base = _period_allowance(
                                annual_allowance, hire_date, period_start, period_end, prorate_new_hires
                            )
                            previous_base = _period_allowance(
                                annual_allowance, hire_date, previous_period_start, previous_period_end, prorate_new_hires
                            )
                        current_adjustment_row = connection.execute(
                            """SELECT COALESCE(SUM(days), 0) FROM leave_balance_adjustments
                               WHERE employee_id = ? AND leave_type_id = ? AND period_start = ?""",
                            (own_id, leave_type["id"], period_start.isoformat()),
                        ).fetchone()
                        previous_adjustment_row = connection.execute(
                            """SELECT COALESCE(SUM(days), 0) FROM leave_balance_adjustments
                               WHERE employee_id = ? AND leave_type_id = ? AND period_start = ?""",
                            (own_id, leave_type["id"], previous_period_start.isoformat()),
                        ).fetchone()
                        current_adjustment = round(float(current_adjustment_row[0] or 0), 2)
                        previous_adjustment = round(float(previous_adjustment_row[0] or 0), 2)
                        carryover = min(
                            max(previous_base + previous_adjustment - previous_used, 0), carryover_limit_days
                        ) if carryover_enabled else 0

                    allowance = round(current_base + carryover + current_adjustment, 2)
                    remaining = round(allowance - current_used - pending_reserved, 2)
                    leave_balances.append({
                        "leave_type_id": leave_type["id"],
                        "leave_type": leave_type["name"],
                        "base_allowance_days": current_base,
                        "annual_allowance_days": annual_allowance,
                        "accrual_method": type_policy["accrual_method"],
                        "monthly_accrual_days": round(annual_allowance / 12, 2) if type_policy["accrual_method"] == "monthly" else 0,
                        "monthly_reset": type_policy["monthly_reset"],
                        "attendance_based": type_policy["attendance_based"],
                        "policy_note": balance_policy_note,
                        "balance_period_start": balance_period_start.isoformat(),
                        "balance_period_end": balance_period_end.isoformat(),
                        "balance_period_label": balance_period_label,
                        "carryover_days": carryover,
                        "adjustment_days": current_adjustment,
                        "allowance_days": allowance,
                        "accrued_days": round(current_base + current_adjustment, 2),
                        "used_days": current_used,
                        "reserved_days": pending_reserved,
                        "remaining_days": remaining,
                    })
            locations = connection.execute("SELECT COUNT(*) FROM work_locations WHERE is_active = 1").fetchone()[0] if "locations.read" in permissions else 0
            upcoming_holiday = None
            if "calendar.read" in permissions:
                holiday_row = connection.execute(
                    """SELECT * FROM holidays WHERE is_active = 1 AND holiday_date >= ?
                       ORDER BY holiday_date, name LIMIT 1""",
                    (today,),
                ).fetchone()
                upcoming_holiday = _holiday_json(holiday_row)
                if upcoming_holiday is not None:
                    upcoming_holiday["days_until"] = (
                        date.fromisoformat(upcoming_holiday["holiday_date"]) - date.fromisoformat(today)
                    ).days

            if attendance_ids == []:
                recent = []
            else:
                recent_sql = """SELECT a.*, e.employee_code, e.first_name, e.last_name, e.user_id, e.manager_id,
                       w.name AS location_name FROM attendance_records a JOIN employees e ON e.id = a.employee_id
                       LEFT JOIN work_locations w ON w.id = a.work_location_id"""
                params: list[Any] = []
                if attendance_ids is not None:
                    placeholders = ",".join("?" for _ in attendance_ids)
                    recent_sql += f" WHERE a.employee_id IN ({placeholders})"
                    params.extend(attendance_ids)
                recent_sql += " ORDER BY a.punch_in_at DESC LIMIT 6"
                recent = connection.execute(recent_sql, params).fetchall()

            if leave_ids == []:
                leave_rows = []
            else:
                leave_sql = """SELECT lr.*, e.employee_code, e.first_name, e.last_name, e.user_id, e.manager_id,
                       lt.name AS leave_type, COALESCE(NULLIF(TRIM(approver_employee.first_name || ' ' || approver_employee.last_name), ''), u.full_name) AS approver_name FROM leave_requests lr
                       JOIN employees e ON e.id = lr.employee_id JOIN leave_types lt ON lt.id = lr.leave_type_id
                       LEFT JOIN users u ON u.id = lr.approver_id
                   LEFT JOIN employees approver_employee ON approver_employee.user_id = u.id WHERE lr.status = 'pending'"""
                params = []
                if leave_ids is not None:
                    placeholders = ",".join("?" for _ in leave_ids)
                    leave_sql += f" AND lr.employee_id IN ({placeholders})"
                    params.extend(leave_ids)
                leave_sql += " ORDER BY lr.requested_at DESC LIMIT 4"
                leave_rows = connection.execute(leave_sql, params).fetchall()
        return {
            "stats": {
                "active_employees": employees,
                "present_today": present,
                "pending_leave": pending,
                "on_leave_today": on_leave_today,
                "active_locations": locations,
            },
            "recent_attendance": [_attendance_json(row) for row in recent],
            "pending_requests": [_leave_json(row) for row in leave_rows],
            "my_attendance": own_attendance,
            "my_shift": own_shift,
            "my_leave_balances": leave_balances,
            "leave_balance_year": leave_balance_year,
            "leave_balance_period": leave_balance_period,
            "upcoming_holiday": upcoming_holiday,
            "generated_at": _now(),
        }

    def _list_social_posts(self, user: dict[str, Any]) -> dict[str, Any]:
        limit = 100
        with self._db() as connection:
            rows = connection.execute(
                """SELECT p.id, p.author_user_id, p.body, p.created_at, p.updated_at,
                          COALESCE(NULLIF(TRIM(e.first_name || ' ' || e.last_name), ''), u.full_name) AS author_name,
                          COUNT(DISTINCT l.user_id) AS like_count,
                          SUM(CASE WHEN l.user_id = ? THEN 1 ELSE 0 END) AS liked_by_me,
                          COUNT(DISTINCT c.id) AS comment_count
                   FROM social_posts p JOIN users u ON u.id = p.author_user_id
                   LEFT JOIN employees e ON e.user_id = u.id
                   LEFT JOIN social_post_likes l ON l.post_id = p.id
                   LEFT JOIN social_post_comments c ON c.post_id = p.id
                   WHERE p.is_active = 1
                   GROUP BY p.id ORDER BY p.created_at DESC, p.id DESC LIMIT ?""",
                (user["id"], limit),
            ).fetchall()
            items = []
            for row in rows:
                comments = connection.execute(
                    """SELECT c.id, c.body, c.created_at,
                              COALESCE(NULLIF(TRIM(e.first_name || ' ' || e.last_name), ''), u.full_name) AS author_name
                       FROM social_post_comments c JOIN users u ON u.id = c.author_user_id
                       LEFT JOIN employees e ON e.user_id = u.id
                       WHERE c.post_id = ? ORDER BY c.created_at DESC, c.id DESC LIMIT 5""",
                    (row["id"],),
                ).fetchall()
                item = dict(row)
                item["liked_by_me"] = bool(item["liked_by_me"])
                item["comments"] = [dict(comment) for comment in reversed(comments)]
                items.append(item)
        return {"items": items, "total": len(items)}

    def _social_post(self, post_id: int, user_id: int) -> dict[str, Any]:
        with self._db() as connection:
            row = connection.execute(
                """SELECT p.id, p.author_user_id, p.body, p.created_at, p.updated_at,
                          COALESCE(NULLIF(TRIM(e.first_name || ' ' || e.last_name), ''), u.full_name) AS author_name,
                          (SELECT COUNT(*) FROM social_post_likes l WHERE l.post_id = p.id) AS like_count,
                          EXISTS(SELECT 1 FROM social_post_likes l WHERE l.post_id = p.id AND l.user_id = ?) AS liked_by_me,
                          (SELECT COUNT(*) FROM social_post_comments c WHERE c.post_id = p.id) AS comment_count
                   FROM social_posts p JOIN users u ON u.id = p.author_user_id
                   LEFT JOIN employees e ON e.user_id = u.id WHERE p.id = ? AND p.is_active = 1""",
                (user_id, post_id),
            ).fetchone()
            if not row:
                raise ApiError(404, "Social Wall post not found.")
            comments = connection.execute(
                """SELECT c.id, c.body, c.created_at,
                          COALESCE(NULLIF(TRIM(e.first_name || ' ' || e.last_name), ''), u.full_name) AS author_name
                   FROM social_post_comments c JOIN users u ON u.id = c.author_user_id
                   LEFT JOIN employees e ON e.user_id = u.id
                   WHERE c.post_id = ? ORDER BY c.created_at DESC, c.id DESC LIMIT 20""",
                (post_id,),
            ).fetchall()
        item = dict(row)
        item["liked_by_me"] = bool(item["liked_by_me"])
        item["comments"] = [dict(comment) for comment in reversed(comments)]
        return item

    def _create_social_post(self, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        text = str(body.get("body", "")).strip()
        if not text or len(text) > 2000:
            raise ApiError(400, "Post text must be between 1 and 2,000 characters.")
        now = _now()
        with self._db() as connection:
            cursor = connection.execute(
                "INSERT INTO social_posts(author_user_id, body, created_at, updated_at) VALUES (?, ?, ?, ?)",
                (user["id"], text, now, now),
            )
            post_id = int(cursor.lastrowid)
        self._audit(user["id"], "social.post_created", "social_post", post_id, {}, remote)
        return self._social_post(post_id, user["id"])

    def _toggle_social_like(self, post_id: int, user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        now = _now()
        with self._db() as connection:
            if not connection.execute("SELECT 1 FROM social_posts WHERE id = ? AND is_active = 1", (post_id,)).fetchone():
                raise ApiError(404, "Social Wall post not found.")
            liked = connection.execute(
                "SELECT 1 FROM social_post_likes WHERE post_id = ? AND user_id = ?", (post_id, user["id"])
            ).fetchone()
            if liked:
                connection.execute("DELETE FROM social_post_likes WHERE post_id = ? AND user_id = ?", (post_id, user["id"]))
                is_liked = False
            else:
                connection.execute(
                    "INSERT INTO social_post_likes(post_id, user_id, created_at) VALUES (?, ?, ?)",
                    (post_id, user["id"], now),
                )
                is_liked = True
        self._audit(user["id"], "social.post_liked" if is_liked else "social.post_unliked", "social_post", post_id, {}, remote)
        return {"liked": is_liked, "post": self._social_post(post_id, user["id"])}

    def _create_social_comment(self, post_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        text = str(body.get("body", "")).strip()
        if not text or len(text) > 1000:
            raise ApiError(400, "Comment text must be between 1 and 1,000 characters.")
        now = _now()
        with self._db() as connection:
            if not connection.execute("SELECT 1 FROM social_posts WHERE id = ? AND is_active = 1", (post_id,)).fetchone():
                raise ApiError(404, "Social Wall post not found.")
            cursor = connection.execute(
                "INSERT INTO social_post_comments(post_id, author_user_id, body, created_at) VALUES (?, ?, ?, ?)",
                (post_id, user["id"], text, now),
            )
            comment_id = int(cursor.lastrowid)
        self._audit(user["id"], "social.comment_created", "social_post_comment", comment_id, {"post_id": post_id}, remote)
        return self._social_post(post_id, user["id"])

    def _deactivate_social_post(self, post_id: int, user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        with self._db() as connection:
            changed = connection.execute(
                "UPDATE social_posts SET is_active = 0, updated_at = ? WHERE id = ? AND is_active = 1", (_now(), post_id)
            ).rowcount
        if not changed:
            raise ApiError(404, "Social Wall post not found.")
        self._audit(user["id"], "social.post_moderated", "social_post", post_id, {}, remote)
        return {"id": post_id, "is_active": False}

    def _can_manage_helpdesk(self, user: dict[str, Any]) -> bool:
        with self._db() as connection:
            row = connection.execute(
                """SELECT 1 FROM user_roles WHERE user_id = ? AND role_id IN ('super_admin', 'hr_admin', 'people_ops') LIMIT 1""",
                (user["id"],),
            ).fetchone()
        return row is not None and "helpdesk.manage" in self._permissions(user["id"])

    def _helpdesk_ticket(self, ticket_id: int, include_comments: bool = False, manager_view: bool = False) -> dict[str, Any] | None:
        with self._db() as connection:
            row = connection.execute(
                """SELECT t.*, e.employee_code,
                          COALESCE(NULLIF(TRIM(e.first_name || ' ' || e.last_name), ''), u.full_name) AS requester_name,
                          COALESCE(NULLIF(TRIM(assigned_employee.first_name || ' ' || assigned_employee.last_name), ''), assigned_user.full_name) AS assigned_to_name
                   FROM helpdesk_tickets t JOIN users u ON u.id = t.requester_user_id
                   LEFT JOIN employees e ON e.id = t.employee_id
                   LEFT JOIN users assigned_user ON assigned_user.id = t.assigned_to
                   LEFT JOIN employees assigned_employee ON assigned_employee.user_id = t.assigned_to
                   WHERE t.id = ?""",
                (ticket_id,),
            ).fetchone()
            if not row:
                return None
            item = dict(row)
            item["is_confidential"] = bool(item["is_confidential"])
            if include_comments:
                comments = connection.execute(
                    """SELECT c.id, c.body, c.is_internal, c.created_at,
                              COALESCE(NULLIF(TRIM(e.first_name || ' ' || e.last_name), ''), u.full_name) AS author_name
                       FROM helpdesk_ticket_comments c JOIN users u ON u.id = c.author_user_id
                       LEFT JOIN employees e ON e.user_id = u.id WHERE c.ticket_id = ?
                         AND (? = 1 OR c.is_internal = 0) ORDER BY c.created_at, c.id""",
                    (ticket_id, int(manager_view)),
                ).fetchall()
                item["comments"] = [dict(comment) for comment in comments]
            return item

    def _get_helpdesk_ticket(self, ticket_id: int, user: dict[str, Any]) -> dict[str, Any]:
        manager_view = self._can_manage_helpdesk(user)
        ticket = self._helpdesk_ticket(ticket_id, include_comments=True, manager_view=manager_view)
        if not ticket or (ticket["requester_user_id"] != user["id"] and not manager_view):
            # Do not disclose whether another user's confidential grievance exists.
            raise ApiError(404, "Helpdesk ticket not found.")
        return ticket

    def _list_helpdesk_tickets(self, user: dict[str, Any], permissions: set[str], query: dict[str, str]) -> dict[str, Any]:
        status = query.get("status", "").strip()
        if status and status not in {"open", "in_progress", "resolved", "closed"}:
            raise ApiError(400, "Ticket status filter is invalid.")
        limit = min(max(_optional_int(query.get("limit")) or 100, 1), 300)
        conditions: list[str] = []
        params: list[Any] = []
        if not self._can_manage_helpdesk(user):
            conditions.append("t.requester_user_id = ?")
            params.append(user["id"])
        if status:
            conditions.append("t.status = ?")
            params.append(status)
        where = " AND ".join(conditions) if conditions else "1 = 1"
        params.append(limit)
        with self._db() as connection:
            rows = connection.execute(
                f"""SELECT t.id, t.requester_user_id, t.employee_id, t.category, t.title, t.description,
                           t.is_confidential, t.priority, t.status, t.assigned_to, t.created_at, t.updated_at, t.closed_at,
                           e.employee_code,
                           COALESCE(NULLIF(TRIM(e.first_name || ' ' || e.last_name), ''), u.full_name) AS requester_name,
                           COALESCE(NULLIF(TRIM(ae.first_name || ' ' || ae.last_name), ''), au.full_name) AS assigned_to_name
                    FROM helpdesk_tickets t JOIN users u ON u.id = t.requester_user_id
                    LEFT JOIN employees e ON e.id = t.employee_id
                    LEFT JOIN users au ON au.id = t.assigned_to
                    LEFT JOIN employees ae ON ae.user_id = t.assigned_to
                    WHERE {where} ORDER BY t.created_at DESC, t.id DESC LIMIT ?""",
                params,
            ).fetchall()
        items = []
        for row in rows:
            item = dict(row)
            item["is_confidential"] = bool(item["is_confidential"])
            items.append(item)
        return {"items": items, "total": len(items)}

    def _create_helpdesk_ticket(self, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        category = str(body.get("category", "other")).strip().lower()
        if category not in {"payroll", "attendance", "leave", "shift", "workplace", "grievance", "other"}:
            raise ApiError(400, "Choose a valid helpdesk category.")
        title = str(body.get("title", "")).strip()
        description = str(body.get("description", "")).strip()
        if not title or len(title) > 160 or not description or len(description) > 5000:
            raise ApiError(400, "Ticket subject (1–160 characters) and details (1–5,000 characters) are required.")
        priority = str(body.get("priority", "normal")).strip().lower()
        if priority not in {"low", "normal", "high"}:
            raise ApiError(400, "Choose low, normal, or high priority.")
        confidential_value = body.get("is_confidential", False)
        if isinstance(confidential_value, str):
            confidential_value = confidential_value.strip().lower() in {"true", "1", "yes"}
        is_confidential = bool(confidential_value) or category == "grievance"
        employee = self._employee_for_user(user["id"])
        now = _now()
        with self._db() as connection:
            cursor = connection.execute(
                """INSERT INTO helpdesk_tickets(requester_user_id, employee_id, category, title, description,
                   is_confidential, priority, status, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, 'open', ?, ?)""",
                (user["id"], employee["id"] if employee else None, category, title, description,
                 int(is_confidential), priority, now, now),
            )
            ticket_id = int(cursor.lastrowid)
            # Notify only users explicitly assigned the helpdesk management permission.
            managers = connection.execute(
                """SELECT DISTINCT user_id FROM user_roles
                   WHERE role_id IN ('super_admin', 'hr_admin', 'people_ops') AND user_id <> ?""",
                (user["id"],),
            ).fetchall()
            for manager in managers:
                self._insert_notification(connection, manager["user_id"], "New helpdesk ticket", title,
                                          "helpdesk_ticket", ticket_id, now)
        self._audit(user["id"], "helpdesk.ticket_created", "helpdesk_ticket", ticket_id,
                    {"category": category, "confidential": is_confidential}, remote)
        return self._get_helpdesk_ticket(ticket_id, user)

    def _update_helpdesk_ticket(self, ticket_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        current = self._helpdesk_ticket(ticket_id)
        if not current:
            raise ApiError(404, "Helpdesk ticket not found.")
        allowed = {"open", "in_progress", "resolved", "closed"}
        status = str(body.get("status", current["status"])).strip().lower()
        priority = str(body.get("priority", current["priority"])).strip().lower()
        if status not in allowed or priority not in {"low", "normal", "high"}:
            raise ApiError(400, "Ticket status or priority is invalid.")
        assigned_to = current["assigned_to"]
        if "assigned_to" in body:
            assigned_to = _optional_int(body.get("assigned_to"))
            if assigned_to is not None:
                with self._db() as connection:
                    if not connection.execute("SELECT 1 FROM users WHERE id = ? AND is_active = 1", (assigned_to,)).fetchone():
                        raise ApiError(400, "Choose an active support user or leave the ticket unassigned.")
        now = _now()
        closed_at = now if status in {"resolved", "closed"} else None
        with self._db() as connection:
            connection.execute(
                "UPDATE helpdesk_tickets SET status = ?, priority = ?, assigned_to = ?, updated_at = ?, closed_at = ? WHERE id = ?",
                (status, priority, assigned_to, now, closed_at, ticket_id),
            )
        self._audit(user["id"], "helpdesk.ticket_updated", "helpdesk_ticket", ticket_id,
                    {"status": status, "priority": priority}, remote)
        return self._get_helpdesk_ticket(ticket_id, user)

    def _create_helpdesk_comment(self, ticket_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        ticket = self._get_helpdesk_ticket(ticket_id, user)
        text = str(body.get("body", "")).strip()
        if not text or len(text) > 2000:
            raise ApiError(400, "Comment text must be between 1 and 2,000 characters.")
        is_internal = bool(body.get("is_internal", False))
        if is_internal and not self._can_manage_helpdesk(user):
            raise ApiError(403, "Only People Ops, HR Admin, and Super Admin can add internal notes.")
        with self._db() as connection:
            cursor = connection.execute(
                "INSERT INTO helpdesk_ticket_comments(ticket_id, author_user_id, body, is_internal, created_at) VALUES (?, ?, ?, ?, ?)",
                (ticket_id, user["id"], text, int(is_internal), _now()),
            )
            comment_id = int(cursor.lastrowid)
        self._audit(user["id"], "helpdesk.comment_created", "helpdesk_ticket_comment", comment_id,
                    {"ticket_id": ticket_id, "internal": is_internal}, remote)
        return self._get_helpdesk_ticket(ticket_id, user)

    def _list_recognition_awards(self, query: dict[str, str]) -> dict[str, Any]:
        period = query.get("period", "").strip()
        if period and not re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])", period):
            raise ApiError(400, "Recognition period must use YYYY-MM format.")
        conditions = ["1 = 1"]
        params: list[Any] = []
        if period:
            conditions.append("a.period = ?")
            params.append(period)
        limit = min(max(_optional_int(query.get("limit")) or 200, 1), 500)
        params.append(limit)
        with self._db() as connection:
            rows = connection.execute(
                f"""SELECT a.*, e.employee_code, e.first_name, e.last_name, e.department,
                           COALESCE(NULLIF(TRIM(issuer.first_name || ' ' || issuer.last_name), ''), u.full_name) AS awarded_by_name
                    FROM recognition_awards a JOIN employees e ON e.id = a.employee_id
                    JOIN users u ON u.id = a.awarded_by LEFT JOIN employees issuer ON issuer.user_id = a.awarded_by
                    WHERE {' AND '.join(conditions)} ORDER BY a.period DESC, a.created_at DESC, a.id DESC LIMIT ?""",
                params,
            ).fetchall()
        items = []
        for row in rows:
            item = dict(row)
            item["employee_name"] = f"{row['first_name']} {row['last_name']}".strip()
            item.pop("first_name", None)
            item.pop("last_name", None)
            items.append(item)
        return {"items": items, "total": len(items)}

    def _create_recognition_award(self, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        employee_id = _as_int(body.get("employee_id"), "Employee ID")
        category = str(body.get("category", "star_worker")).strip().lower()
        if category not in {"star_worker", "perfect_attendance", "safety", "shift_output", "teamwork"}:
            raise ApiError(400, "Choose a valid recognition award category.")
        period = str(body.get("period", date.today().strftime("%Y-%m"))).strip()
        if not re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])", period):
            raise ApiError(400, "Recognition period must use YYYY-MM format.")
        citation = str(body.get("citation", "")).strip()
        if not citation or len(citation) > 1000:
            raise ApiError(400, "Award citation must be between 1 and 1,000 characters.")
        with self._db() as connection:
            employee = connection.execute("SELECT status FROM employees WHERE id = ?", (employee_id,)).fetchone()
            if not employee or employee["status"] != "active":
                raise ApiError(400, "Choose an active employee for recognition.")
            cursor = connection.execute(
                """INSERT INTO recognition_awards(employee_id, category, period, citation, awarded_by, created_at)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (employee_id, category, period, citation, user["id"], _now()),
            )
            award_id = int(cursor.lastrowid)
        self._audit(user["id"], "recognition.award_issued", "recognition_award", award_id,
                    {"employee_id": employee_id, "category": category, "period": period}, remote)
        rows = self._list_recognition_awards({"period": period})["items"]
        return next(item for item in rows if item["id"] == award_id)

    def _list_shift_swap_options(self, query: dict[str, str]) -> dict[str, Any]:
        today = date.today().isoformat()
        start = _date_string(query.get("from"), today)
        end = _date_string(query.get("to"), start)
        if end < start:
            raise ApiError(400, "The swap-options end date must be on or after the start date.")
        if start < today or date.fromisoformat(end) > date.today() + timedelta(days=90):
            raise ApiError(400, "Shift-swap options are available only for today through the next 90 days.")
        with self._db() as connection:
            rows = connection.execute(
                """SELECT a.id AS assignment_id, a.employee_id, a.work_date,
                          e.employee_code, e.first_name || ' ' || e.last_name AS employee_name,
                          s.id AS shift_id, s.name AS shift_name, s.start_time, s.end_time, s.break_minutes,
                          w.name AS location_name
                   FROM shift_assignments a JOIN employees e ON e.id = a.employee_id
                   JOIN shift_templates s ON s.id = a.shift_id
                   LEFT JOIN work_locations w ON w.id = a.work_location_id
                   WHERE a.is_active = 1 AND e.status = 'active' AND e.user_id IS NOT NULL
                     AND a.work_date BETWEEN ? AND ?
                   ORDER BY a.work_date, s.start_time, e.first_name LIMIT 500""",
                (start, end),
            ).fetchall()
        return {"items": [dict(row) for row in rows], "total": len(rows)}

    def _list_shift_swap_requests(self, user: dict[str, Any], permissions: set[str], query: dict[str, str]) -> dict[str, Any]:
        status = query.get("status", "").strip()
        valid_statuses = {"pending_target", "pending_manager", "approved", "rejected", "cancelled"}
        if status and status not in valid_statuses:
            raise ApiError(400, "Shift-swap status filter is invalid.")
        conditions = []
        params: list[Any] = []
        if "shifts.manage" not in permissions:
            own_employee = self._employee_id(user["id"])
            if own_employee is None:
                return {"items": [], "total": 0}
            if "shifts.swap.approve" in permissions:
                conditions.append("(r.requester_employee_id = ? OR r.target_employee_id = ? OR requester.manager_id = ? OR target.manager_id = ?)")
                params.extend((own_employee, own_employee, own_employee, own_employee))
            else:
                conditions.append("(r.requester_employee_id = ? OR r.target_employee_id = ?)")
                params.extend((own_employee, own_employee))
        if status:
            conditions.append("r.status = ?")
            params.append(status)
        limit = min(max(_optional_int(query.get("limit")) or 200, 1), 500)
        params.append(limit)
        where = " AND ".join(conditions) if conditions else "1 = 1"
        with self._db() as connection:
            rows = connection.execute(
                f"""SELECT r.id, r.requester_employee_id, r.target_employee_id,
                           r.requester_assignment_id, r.target_assignment_id, r.reason, r.status,
                           r.target_decided_at, r.manager_decided_at, r.decided_by, r.decision_note,
                           r.requested_at, r.updated_at,
                           requester.first_name || ' ' || requester.last_name AS requester_name,
                           target.first_name || ' ' || target.last_name AS target_name,
                           requester_assignment.work_date,
                           requester_shift.name AS requester_shift_name, requester_shift.start_time AS requester_start_time,
                           requester_shift.end_time AS requester_end_time,
                           target_shift.name AS target_shift_name, target_shift.start_time AS target_start_time,
                           target_shift.end_time AS target_end_time
                    FROM shift_swap_requests r
                    JOIN employees requester ON requester.id = r.requester_employee_id
                    JOIN employees target ON target.id = r.target_employee_id
                    JOIN shift_assignments requester_assignment ON requester_assignment.id = r.requester_assignment_id
                    JOIN shift_templates requester_shift ON requester_shift.id = requester_assignment.shift_id
                    JOIN shift_assignments target_assignment ON target_assignment.id = r.target_assignment_id
                    JOIN shift_templates target_shift ON target_shift.id = target_assignment.shift_id
                    WHERE {where} ORDER BY r.requested_at DESC, r.id DESC LIMIT ?""",
                params,
            ).fetchall()
        return {"items": [dict(row) for row in rows], "total": len(rows)}

    def _create_shift_swap_request(self, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        requester = self._employee_for_user(user["id"])
        if not requester or requester["status"] != "active":
            raise ApiError(400, "Your active employee profile is required to request a shift swap.")
        target_employee_id = _as_int(body.get("target_employee_id"), "Target employee ID")
        requester_assignment_id = _as_int(body.get("requester_assignment_id"), "Your assignment ID")
        target_assignment_id = _as_int(body.get("target_assignment_id"), "The other assignment ID")
        reason = str(body.get("reason", "")).strip()
        if not reason or len(reason) > 1000:
            raise ApiError(400, "A shift-swap reason between 1 and 1,000 characters is required.")
        if target_employee_id == requester["id"]:
            raise ApiError(400, "Choose another employee for a shift swap.")
        now = _now()
        with self._db() as connection:
            target = connection.execute(
                "SELECT id, user_id, status FROM employees WHERE id = ?", (target_employee_id,)
            ).fetchone()
            if not target or target["status"] != "active" or not target["user_id"]:
                raise ApiError(400, "The selected colleague must have an active app account to consent to the swap.")
            requester_assignment = connection.execute(
                "SELECT * FROM shift_assignments WHERE id = ? AND employee_id = ? AND is_active = 1",
                (requester_assignment_id, requester["id"]),
            ).fetchone()
            target_assignment = connection.execute(
                "SELECT * FROM shift_assignments WHERE id = ? AND employee_id = ? AND is_active = 1",
                (target_assignment_id, target_employee_id),
            ).fetchone()
            if not requester_assignment or not target_assignment:
                raise ApiError(400, "Both selected assignments must still be active and belong to the named employees.")
            if requester_assignment["work_date"] != target_assignment["work_date"]:
                raise ApiError(400, "Shift swaps must be for the same work date.")
            if requester_assignment["work_date"] < date.today().isoformat():
                raise ApiError(400, "Past shift assignments cannot be swapped.")
            conflict = connection.execute(
                """SELECT 1 FROM shift_swap_requests WHERE status IN ('pending_target', 'pending_manager')
                   AND (requester_assignment_id IN (?, ?) OR target_assignment_id IN (?, ?)
                        OR requester_assignment_id = ? OR target_assignment_id = ?) LIMIT 1""",
                (requester_assignment_id, target_assignment_id, requester_assignment_id, target_assignment_id,
                 requester_assignment_id, target_assignment_id),
            ).fetchone()
            if conflict:
                raise ApiError(409, "One of these shifts already has a pending swap request.")
            cursor = connection.execute(
                """INSERT INTO shift_swap_requests(requester_employee_id, target_employee_id,
                   requester_assignment_id, target_assignment_id, reason, status, requested_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, 'pending_target', ?, ?)""",
                (requester["id"], target_employee_id, requester_assignment_id, target_assignment_id, reason, now, now),
            )
            request_id = int(cursor.lastrowid)
            self._insert_notification(connection, target["user_id"], "Shift swap consent requested",
                                      f"{requester['first_name']} {requester['last_name']} requested a shift swap for {requester_assignment['work_date']}.",
                                      "shift_swap", request_id, now)
        self._audit(user["id"], "shift_swap.requested", "shift_swap_request", request_id,
                    {"target_employee_id": target_employee_id}, remote)
        return self._get_shift_swap_request(request_id)

    def _get_shift_swap_request(self, request_id: int) -> dict[str, Any]:
        with self._db() as connection:
            row = connection.execute(
                """SELECT r.id, r.requester_employee_id, r.target_employee_id,
                           r.requester_assignment_id, r.target_assignment_id, r.reason, r.status,
                           r.target_decided_at, r.manager_decided_at, r.decided_by, r.decision_note,
                           r.requested_at, r.updated_at,
                           requester.first_name || ' ' || requester.last_name AS requester_name,
                           target.first_name || ' ' || target.last_name AS target_name,
                           requester_assignment.work_date,
                           requester_shift.name AS requester_shift_name, requester_shift.start_time AS requester_start_time,
                           requester_shift.end_time AS requester_end_time,
                           target_shift.name AS target_shift_name, target_shift.start_time AS target_start_time,
                           target_shift.end_time AS target_end_time
                    FROM shift_swap_requests r
                    JOIN employees requester ON requester.id = r.requester_employee_id
                    JOIN employees target ON target.id = r.target_employee_id
                    JOIN shift_assignments requester_assignment ON requester_assignment.id = r.requester_assignment_id
                    JOIN shift_templates requester_shift ON requester_shift.id = requester_assignment.shift_id
                    JOIN shift_assignments target_assignment ON target_assignment.id = r.target_assignment_id
                    JOIN shift_templates target_shift ON target_shift.id = target_assignment.shift_id
                    WHERE r.id = ?""",
                (request_id,),
            ).fetchone()
        if not row:
            raise ApiError(404, "Shift-swap request not found.")
        return dict(row)

    def _decide_shift_swap_target(self, request_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        decision = str(body.get("decision", "")).strip().lower()
        if decision not in {"accept", "reject"}:
            raise ApiError(400, "Target decision must be accept or reject.")
        now = _now()
        with self._db() as connection:
            row = connection.execute(
                """SELECT r.*, e.user_id AS target_user_id FROM shift_swap_requests r
                   JOIN employees e ON e.id = r.target_employee_id WHERE r.id = ?""", (request_id,)
            ).fetchone()
            if not row:
                raise ApiError(404, "Shift-swap request not found.")
            if row["target_user_id"] != user["id"]:
                raise ApiError(403, "Only the colleague named in this request can respond to it.")
            if row["status"] != "pending_target":
                raise ApiError(409, "This shift-swap request is no longer awaiting colleague consent.")
            status = "pending_manager" if decision == "accept" else "rejected"
            note = str(body.get("note", "")).strip()[:500]
            connection.execute(
                "UPDATE shift_swap_requests SET status = ?, target_decided_at = ?, decision_note = ?, updated_at = ? WHERE id = ?",
                (status, now, note or None, now, request_id),
            )
            if decision == "accept":
                managers = connection.execute(
                    """SELECT DISTINCT manager.user_id FROM employees person
                       JOIN employees manager ON manager.id = person.manager_id
                       WHERE person.id IN (?, ?) AND manager.user_id IS NOT NULL""",
                    (row["requester_employee_id"], row["target_employee_id"]),
                ).fetchall()
                for manager in managers:
                    self._insert_notification(connection, manager["user_id"], "Shift swap needs approval",
                                              "A colleague accepted a shift swap and is waiting for manager approval.",
                                              "shift_swap", request_id, now)
        self._audit(user["id"], f"shift_swap.target_{decision}d", "shift_swap_request", request_id, {}, remote)
        return self._get_shift_swap_request(request_id)

    def _decide_shift_swap(self, request_id: int, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        decision = str(body.get("decision", "")).strip().lower()
        if decision not in {"approve", "reject"}:
            raise ApiError(400, "Manager decision must be approve or reject.")
        now = _now()
        with self._db() as connection:
            row = connection.execute(
                """SELECT r.*, requester.manager_id AS requester_manager_id,
                          target.manager_id AS target_manager_id,
                          requester_assignment.work_date,
                          requester_assignment.shift_id AS requester_shift_id,
                          requester_assignment.work_location_id AS requester_location_id,
                          requester_assignment.is_active AS requester_assignment_active,
                          target_assignment.shift_id AS target_shift_id,
                          target_assignment.work_location_id AS target_location_id,
                          target_assignment.is_active AS target_assignment_active
                   FROM shift_swap_requests r
                   JOIN employees requester ON requester.id = r.requester_employee_id
                   JOIN employees target ON target.id = r.target_employee_id
                   JOIN shift_assignments requester_assignment ON requester_assignment.id = r.requester_assignment_id
                   JOIN shift_assignments target_assignment ON target_assignment.id = r.target_assignment_id
                   WHERE r.id = ?""", (request_id,)
            ).fetchone()
            if not row:
                raise ApiError(404, "Shift-swap request not found.")
            permissions = self._permissions(user["id"])
            if "shifts.manage" not in permissions:
                manager_employee_id = self._employee_id(user["id"])
                if manager_employee_id in {row["requester_employee_id"], row["target_employee_id"]}:
                    raise ApiError(403, "A line manager who is part of the swap cannot approve their own exchange.")
                if manager_employee_id is None or manager_employee_id not in {
                    row["requester_manager_id"], row["target_manager_id"]
                }:
                    raise ApiError(403, "Only a manager of one of the employees can approve this swap.")
            if row["status"] != "pending_manager":
                raise ApiError(409, "This shift-swap request is not awaiting manager approval.")
            note = str(body.get("note", "")).strip()[:500]
            if decision == "approve":
                if not row["requester_assignment_active"] or not row["target_assignment_active"]:
                    raise ApiError(409, "One of the shift assignments is no longer active.")
                if row["work_date"] < date.today().isoformat():
                    raise ApiError(409, "Past shift assignments cannot be approved for swapping.")
                connection.execute(
                    """UPDATE shift_assignments SET shift_id = ?, work_location_id = ?, assigned_by = ?, updated_at = ? WHERE id = ?""",
                    (row["target_shift_id"], row["target_location_id"], user["id"], now, row["requester_assignment_id"]),
                )
                connection.execute(
                    """UPDATE shift_assignments SET shift_id = ?, work_location_id = ?, assigned_by = ?, updated_at = ? WHERE id = ?""",
                    (row["requester_shift_id"], row["requester_location_id"], user["id"], now, row["target_assignment_id"]),
                )
                status = "approved"
            else:
                status = "rejected"
            connection.execute(
                """UPDATE shift_swap_requests SET status = ?, manager_decided_at = ?, decided_by = ?,
                   decision_note = COALESCE(?, decision_note), updated_at = ? WHERE id = ?""",
                (status, now, user["id"], note or None, now, request_id),
            )
            employees = connection.execute(
                "SELECT user_id FROM employees WHERE id IN (?, ?) AND user_id IS NOT NULL",
                (row["requester_employee_id"], row["target_employee_id"]),
            ).fetchall()
            for employee in employees:
                self._insert_notification(connection, employee["user_id"],
                                          "Shift swap " + ("approved" if status == "approved" else "rejected"),
                                          "Your shift-swap request has been " + status + ".",
                                          "shift_swap", request_id, now)
        self._audit(user["id"], f"shift_swap.{status}", "shift_swap_request", request_id, {"note": note}, remote)
        return self._get_shift_swap_request(request_id)

    def _cancel_shift_swap(self, request_id: int, user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        own_employee_id = self._employee_id(user["id"])
        now = _now()
        with self._db() as connection:
            row = connection.execute("SELECT * FROM shift_swap_requests WHERE id = ?", (request_id,)).fetchone()
            if not row or row["requester_employee_id"] != own_employee_id:
                raise ApiError(404, "Shift-swap request not found.")
            if row["status"] not in {"pending_target", "pending_manager"}:
                raise ApiError(409, "Only pending shift-swap requests can be cancelled.")
            connection.execute(
                "UPDATE shift_swap_requests SET status = 'cancelled', updated_at = ? WHERE id = ?", (now, request_id)
            )
        self._audit(user["id"], "shift_swap.cancelled", "shift_swap_request", request_id, {}, remote)
        return self._get_shift_swap_request(request_id)

    @staticmethod
    def _insert_notification(connection: sqlite3.Connection, user_id: int, title: str, body: str,
                             entity_type: str | None = None, entity_id: int | None = None,
                             created_at: str | None = None) -> None:
        connection.execute(
            """INSERT INTO app_notifications(user_id, title, body, kind, entity_type, entity_id, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (user_id, title[:160], body[:1000], entity_type or "general", entity_type, entity_id, created_at or _now()),
        )

    def _list_notifications(self, user: dict[str, Any]) -> dict[str, Any]:
        with self._db() as connection:
            rows = connection.execute(
                "SELECT id, title, body, kind, entity_type, entity_id, created_at, read_at FROM app_notifications WHERE user_id = ? ORDER BY created_at DESC, id DESC LIMIT 100",
                (user["id"],),
            ).fetchall()
            unread = connection.execute(
                "SELECT COUNT(*) FROM app_notifications WHERE user_id = ? AND read_at IS NULL", (user["id"],)
            ).fetchone()[0]
        return {"items": [dict(row) for row in rows], "unread_count": int(unread)}

    def _create_test_notification(self, user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        now = _now()
        with self._db() as connection:
            self._insert_notification(
                connection, user["id"], "Attendance notification test",
                "This in-app test was delivered to FlavorFlow. Device push delivery is not configured.",
                "test", None, now,
            )
            row = connection.execute(
                "SELECT id, title, body, kind, entity_type, entity_id, created_at, read_at FROM app_notifications WHERE user_id = ? ORDER BY id DESC LIMIT 1",
                (user["id"],),
            ).fetchone()
        self._audit(user["id"], "notification.test_created", "notification", row["id"], {}, remote)
        return dict(row)

    def _mark_notification_read(self, notification_id: int, user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        with self._db() as connection:
            row = connection.execute(
                "SELECT id FROM app_notifications WHERE id = ? AND user_id = ?", (notification_id, user["id"])
            ).fetchone()
            if not row:
                raise ApiError(404, "Notification not found.")
            connection.execute(
                "UPDATE app_notifications SET read_at = COALESCE(read_at, ?) WHERE id = ? AND user_id = ?",
                (_now(), notification_id, user["id"]),
            )
            updated = connection.execute(
                "SELECT id, title, body, kind, entity_type, entity_id, created_at, read_at FROM app_notifications WHERE id = ?",
                (notification_id,),
            ).fetchone()
        self._audit(user["id"], "notification.read", "notification", notification_id, {}, remote)
        return dict(updated)

    def _list_audit_logs(self, query: dict[str, str]) -> dict[str, Any]:
        limit = min(max(_optional_int(query.get("limit")) or 100, 1), 300)
        with self._db() as connection:
            rows = connection.execute(
                """SELECT a.*,
                          COALESCE(NULLIF(TRIM(actor_employee.first_name || ' ' || actor_employee.last_name), ''), u.full_name) AS actor_name,
                          u.email AS actor_email FROM audit_logs a
                   LEFT JOIN users u ON u.id = a.actor_user_id
                   LEFT JOIN employees actor_employee ON actor_employee.user_id = u.id
                   ORDER BY a.created_at DESC, a.id DESC LIMIT ?""",
                (limit,),
            ).fetchall()
        items = []
        for row in rows:
            item = dict(row)
            item["details"] = json.loads(item.pop("details_json") or "{}")
            items.append(item)
        return {"items": items, "total": len(items)}

    def _audit(
        self,
        actor_id: int | None,
        action: str,
        entity_type: str,
        entity_id: int | str | None,
        details: dict[str, Any],
        remote: str | None,
    ) -> None:
        with self._db() as connection:
            connection.execute(
                """INSERT INTO audit_logs(actor_user_id, action, entity_type, entity_id, details_json,
                   remote_address, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (actor_id, action, entity_type, str(entity_id) if entity_id is not None else None,
                 json.dumps(details, separators=(",", ":"), sort_keys=True), remote, _now()),
            )


def _normalize_employment_type(value: Any) -> str:
    normalized = str(value or "").strip().casefold().replace("_", " ")
    if normalized in {"official staff", "full-time", "full time", "permanent"}:
        return "Official Staff"
    if normalized in {"yellow card", "yellow card staff", "yellow card staff (15 el only)"}:
        return "Yellow Card"
    raise ApiError(400, "Employment category must be Official Staff or Yellow Card Staff (15 EL Only).")


def _safe_employment_type(value: Any) -> str:
    try:
        return _normalize_employment_type(value)
    except ApiError:
        return "Official Staff"


def _employee_json(row: sqlite3.Row) -> dict[str, Any]:
    item = dict(row)
    item.pop("phone", None)
    item.pop("address", None)
    item["weekly_off_days"] = _parse_weekly_off_days(item.get("weekly_off_days"))
    item["full_name"] = f"{row['first_name']} {row['last_name']}".strip()
    try:
        category = _normalize_employment_type(item.get("employment_type", ""))
        item["employment_type"] = category
        item["employment_category_label"] = (
            "Yellow Card Staff (15 EL Only)" if category == "Yellow Card" else "Official Staff"
        )
    except ApiError:
        item["employment_category_label"] = str(item.get("employment_type") or "Unspecified")
    return item


def _output_log_json(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    item = dict(row)
    item["employee_name"] = f"{row['first_name']} {row['last_name']}".strip()
    item.pop("user_id", None)
    item.pop("manager_id", None)
    return item


def _kra_template_json(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    item = dict(row)
    item["is_active"] = bool(row["is_active"])
    return item


def _kra_goal_json(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    item = dict(row)
    item["employee_name"] = f"{row['first_name']} {row['last_name']}".strip()
    item.pop("user_id", None)
    item.pop("manager_id", None)
    return item


def _kyc_document_json(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    item = dict(row)
    last_four = str(item.pop("last_four", ""))
    item["masked_identifier"] = f"•••• {last_four}" if last_four else "Not provided"
    item["employee_name"] = f"{row['first_name']} {row['last_name']}".strip()
    return item


def _id_card_json(row: sqlite3.Row, include_private: bool = True) -> dict[str, Any]:
    item = {
        "id": row["id"],
        "employee_code": row["employee_code"],
        "first_name": row["first_name"],
        "last_name": row["last_name"],
        "full_name": f"{row['first_name']} {row['last_name']}".strip(),
        "email": row["email"],
        "department": row["department"],
        "title": row["title"],
        "employment_type": row["employment_type"],
        "employment_category_label": (
            "Yellow Card Staff (15 EL Only)"
            if _safe_employment_type(row["employment_type"]) == "Yellow Card"
            else "Official Staff"
        ),
        "status": row["status"],
        "start_date": row["start_date"],
    }
    if include_private:
        item["phone"] = row["phone"]
        item["address"] = row["address"]
    return item


def _attendance_request_json(row: sqlite3.Row) -> dict[str, Any]:
    item = dict(row)
    item.pop("user_id", None)
    item.pop("manager_id", None)
    item["employee_name"] = f"{row['first_name']} {row['last_name']}".strip()
    item.pop("first_name", None)
    item.pop("last_name", None)
    return item


def _gate_pass_json(row: sqlite3.Row) -> dict[str, Any]:
    item = dict(row)
    item.pop("user_id", None)
    item.pop("manager_id", None)
    item["employee_name"] = f"{row['first_name']} {row['last_name']}".strip()
    item.pop("first_name", None)
    item.pop("last_name", None)
    return item


def _attendance_json(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    item = dict(row)
    item["employee_name"] = f"{row['first_name']} {row['last_name']}".strip()
    return item


def _leave_json(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    item = dict(row)
    item["employee_name"] = f"{row['first_name']} {row['last_name']}".strip()
    return item


def _holiday_json(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    item = dict(row)
    item["is_active"] = bool(row["is_active"])
    return item


def _shift_template_json(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    item = dict(row)
    item["is_active"] = bool(row["is_active"])
    return item


def _shift_assignment_json(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    item = dict(row)
    item["is_active"] = bool(row["is_active"])
    item["employee_name"] = f"{row['first_name']} {row['last_name']}".strip()
    return item


def _header(headers: dict[str, str], name: str) -> str:
    for key, value in headers.items():
        if key.lower() == name.lower():
            return value
    return ""


def _hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    derived = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, PBKDF2_ROUNDS)
    return f"pbkdf2_sha256${PBKDF2_ROUNDS}${salt.hex()}${derived.hex()}"


def _verify_password(password: str, encoded: str) -> bool:
    try:
        algorithm, rounds, salt_hex, digest_hex = encoded.split("$", 3)
        if algorithm != "pbkdf2_sha256":
            return False
        actual = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), bytes.fromhex(salt_hex), int(rounds)).hex()
        return hmac.compare_digest(actual, digest_hex)
    except (ValueError, TypeError):
        return False


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _date_string(value: Any, default: str | None = None) -> str:
    if value is None or str(value).strip() == "":
        if default is not None:
            return default
        raise ApiError(400, "A date is required in YYYY-MM-DD format.")
    try:
        return date.fromisoformat(str(value)).isoformat()
    except ValueError:
        raise ApiError(400, "Dates must use YYYY-MM-DD format.") from None


def _parse_datetime(value: str, label: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if "T" not in value and " " not in value:
            raise ValueError
        return parsed
    except (ValueError, TypeError):
        raise ApiError(400, f"{label} must be a valid ISO date and time.") from None


def _datetime_string(value: Any, label: str, optional: bool = False) -> str | None:
    if value is None or str(value).strip() == "":
        if optional:
            return None
        raise ApiError(400, f"{label} is required.")
    raw = str(value).strip()
    parsed = _parse_datetime(raw, label)
    return parsed.isoformat(timespec="seconds").replace("+00:00", "Z")


def _leave_period_bounds(reference: date, start_month: int) -> tuple[date, date]:
    start_year = reference.year if reference.month >= start_month else reference.year - 1
    period_start = date(start_year, start_month, 1)
    next_period_start = date(start_year + 1, start_month, 1)
    return period_start, next_period_start - timedelta(days=1)


def _leave_date_set(
    rows: list[sqlite3.Row],
    period_start: date,
    period_end: date,
    count_weekends: bool,
) -> set[date]:
    used_dates: set[date] = set()
    for row in rows:
        start = max(date.fromisoformat(row["start_date"]), period_start)
        end = min(date.fromisoformat(row["end_date"]), period_end)
        day = start
        while day <= end:
            if count_weekends or day.weekday() < 5:
                used_dates.add(day)
            day += timedelta(days=1)
    return used_dates


def _requested_leave_dates(
    start: date,
    end: date,
    period_start: date,
    period_end: date,
    count_weekends: bool,
) -> set[date]:
    clipped_start = max(start, period_start)
    clipped_end = min(end, period_end)
    dates: set[date] = set()
    day = clipped_start
    while day <= clipped_end:
        if count_weekends or day.weekday() < 5:
            dates.add(day)
        day += timedelta(days=1)
    return dates


def _approved_leave_day_count(
    rows: list[sqlite3.Row],
    period_start: date,
    period_end: date,
    count_weekends: bool,
) -> int:
    return len(_leave_date_set(rows, period_start, period_end, count_weekends))


def _completed_weekly_off_dates(
    connection: sqlite3.Connection,
    employee_id: int,
    weekly_off_days: list[str],
    as_of: date,
) -> list[date]:
    weekly_off_weekdays = {
        index for index, weekday in enumerate(_WEEKDAYS) if weekday in set(weekly_off_days)
    }
    if not weekly_off_weekdays:
        return []
    rows = connection.execute(
            """SELECT substr(punch_in_at, 1, 10) AS work_date
           FROM attendance_records
           WHERE employee_id = ? AND punch_out_at IS NOT NULL
             AND substr(punch_in_at, 1, 10) <= ?""",
        (employee_id, as_of.isoformat()),
    ).fetchall()
    result: list[date] = []
    for row in rows:
        try:
            work_date = date.fromisoformat(row["work_date"])
        except (TypeError, ValueError):
            continue
        if work_date.weekday() in weekly_off_weekdays:
            result.append(work_date)
    return result


def _period_allowance(
    annual_allowance: float,
    hire_date: date,
    period_start: date,
    period_end: date,
    prorate_new_hires: bool,
) -> float:
    if not prorate_new_hires or hire_date <= period_start:
        return float(annual_allowance)
    eligible_start = max(hire_date, period_start)
    if eligible_start > period_end:
        return 0.0
    eligible_days = (period_end - eligible_start).days + 1
    period_days = (period_end - period_start).days + 1
    return round(annual_allowance * eligible_days / period_days, 2)


def _monthly_accrued_allowance(
    annual_allowance: float,
    hire_date: date,
    period_start: date,
    reference: date,
    prorate_new_hires: bool,
) -> float:
    """Accrue one twelfth on each elapsed monthly anniversary in the period."""
    accrual_start = max(period_start, hire_date) if prorate_new_hires else period_start
    if reference < accrual_start:
        return 0.0
    months = (reference.year - accrual_start.year) * 12 + reference.month - accrual_start.month
    if reference.day >= accrual_start.day:
        months += 1
    months = min(max(months, 0), 12)
    return round(annual_allowance * months / 12, 2)


_WEEKDAYS = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")


def _parse_weekly_off_days(value: Any) -> list[str]:
    if isinstance(value, list):
        raw_days = value
    elif isinstance(value, str):
        try:
            decoded = json.loads(value or "[]")
            raw_days = decoded if isinstance(decoded, list) else []
        except json.JSONDecodeError:
            raw_days = []
    else:
        raw_days = []
    by_key = {day.casefold(): day for day in _WEEKDAYS}
    by_key.update({day[:3].casefold(): day for day in _WEEKDAYS})
    result: list[str] = []
    for raw in raw_days:
        if isinstance(raw, int) and not isinstance(raw, bool) and 0 <= raw <= 6:
            day = _WEEKDAYS[raw]
        else:
            day = by_key.get(str(raw).strip().casefold())
        if day and day not in result:
            result.append(day)
    return [day for day in _WEEKDAYS if day in result]


def _weekly_off_days(value: Any) -> str:
    if value is None:
        value = []
    if isinstance(value, str):
        try:
            decoded = json.loads(value)
        except json.JSONDecodeError:
            decoded = [part.strip() for part in value.split(",") if part.strip()]
        value = decoded
    if not isinstance(value, list):
        raise ApiError(400, "Weekly-off days must be supplied as a list of weekday names.")
    # Reject unknown input instead of silently persisting a typo as a schedule.
    normalized = _parse_weekly_off_days(value)
    if len(normalized) != len({str(item).strip().casefold() for item in value}):
        raise ApiError(400, "Choose valid weekday names for the weekly off.")
    return json.dumps(normalized, separators=(",", ":"))


def _optional_int(value: Any) -> int | None:
    if value is None or str(value).strip() == "":
        return None
    return _as_int(value, "Value")


def _as_int(value: Any, label: str) -> int:
    try:
        if isinstance(value, bool):
            raise ValueError
        return int(value)
    except (ValueError, TypeError):
        raise ApiError(400, f"{label} must be an integer.") from None


def _boolean_setting(value: Any, label: str) -> int:
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int) and value in {0, 1}:
        return value
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"true", "1"}:
            return 1
        if normalized in {"false", "0"}:
            return 0
    raise ApiError(400, f"{label} must be a boolean.")


def _valid_email(email: str) -> bool:
    return bool(re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email))


def _coordinates(body: dict[str, Any]) -> tuple[float, float, float | None]:
    try:
        latitude = float(body["latitude"])
        longitude = float(body["longitude"])
        accuracy = float(body["accuracy_m"]) if body.get("accuracy_m") is not None else None
    except (KeyError, ValueError, TypeError):
        raise ApiError(400, "Latitude and longitude coordinates are required.") from None
    if not math.isfinite(latitude) or not math.isfinite(longitude) or not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
        raise ApiError(400, "GPS coordinates are outside the valid range.")
    if accuracy is not None and (not math.isfinite(accuracy) or accuracy < 0):
        raise ApiError(400, "GPS accuracy must be a non-negative number.")
    return latitude, longitude, accuracy


def _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    earth_radius_m = 6_371_000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    a = math.sin(delta_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
    return earth_radius_m * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


class _Handler(BaseHTTPRequestHandler):
    app: HRMSApplication
    server_version = "FlavorFlowHRMS/1.0"

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        self._handle("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._handle("POST")

    def do_PATCH(self) -> None:  # noqa: N802
        self._handle("PATCH")

    def do_DELETE(self) -> None:  # noqa: N802
        self._handle("DELETE")

    def _handle(self, method: str) -> None:
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length > 1_000_000:
                self._send(413, {"error": {"message": "Request body is too large."}})
                return
            raw = self.rfile.read(length) if length else b"{}"
            try:
                body = json.loads(raw.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                self._send(400, {"error": {"message": "Request body must be valid JSON."}})
                return
            if not isinstance(body, dict):
                self._send(400, {"error": {"message": "Request body must be a JSON object."}})
                return
            status, response = self.app.handle(
                method, self.path, dict(self.headers.items()), body, self.client_address[0]
            )
            self._send(status, response)
        except (BrokenPipeError, ConnectionResetError):
            return

    def _send(self, status: int, data: dict[str, Any]) -> None:
        payload = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format_string: str, *args: Any) -> None:
        print(f"[{self.log_date_time_string()}] {self.client_address[0]} {format_string % args}")


def _make_handler(app: HRMSApplication) -> type[_Handler]:
    return type("BoundHRMSHandler", (_Handler,), {"app": app})


def main() -> None:
    host = os.environ.get("HRMS_HOST", "0.0.0.0")
    port = int(os.environ.get("HRMS_PORT", "8080"))
    db_path = os.environ.get("HRMS_DB_PATH", str(DEFAULT_DB))
    app = HRMSApplication(db_path)
    server = ThreadingHTTPServer((host, port), _make_handler(app))
    print(f"FlavorFlow HRMS API listening on {host}:{port} (database: {db_path})")
    print("Seed account credentials are controlled by the HRMS_* environment variables.")
    print("Use development-only demo credentials only for local testing.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Stopping FlavorFlow HRMS API.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
