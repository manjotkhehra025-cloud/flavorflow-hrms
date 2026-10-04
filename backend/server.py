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
    ("attendance.read", "attendance", "read", "View all attendance"),
    ("attendance.read.team", "attendance", "read team", "View team attendance"),
    ("attendance.read.self", "attendance", "read self", "View own attendance"),
    ("attendance.punch", "attendance", "punch", "Punch in and out"),
    ("attendance.manage", "attendance", "manage", "Manage attendance records"),
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
    ("users.read", "users", "read", "View user accounts"),
    ("users.create", "users", "create", "Create user accounts"),
    ("users.update", "users", "update", "Update user accounts"),
    ("rbac.read", "rbac", "read", "View roles and permission catalog"),
    ("rbac.update", "rbac", "update", "Create roles and edit permissions"),
    ("audit.read", "audit", "read", "View audit log"),
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
            "attendance.read", "attendance.manage", "locations.read", "locations.create",
            "locations.update", "calendar.read", "calendar.manage", "shifts.read", "shifts.manage",
            "leave.read", "leave.create",
            "leave.approve", "leave.manage", "leave.policy.manage",
            "users.read", "audit.read",
        },
    ),
    "manager": (
        "Manager",
        "Team-level visibility and leave approvals.",
        {
            "dashboard.read", "employees.read.team", "attendance.read.team", "locations.read",
            "calendar.read", "shifts.read.team", "shifts.read.self", "leave.read.team",
            "leave.read.self", "leave.create", "leave.approve",
        },
    ),
    "employee": (
        "Employee",
        "Self-service attendance and leave access.",
        {
            "dashboard.read", "employees.read.self", "attendance.read.self", "attendance.punch",
            "locations.read", "calendar.read", "shifts.read.self", "leave.read.self", "leave.create",
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

    def _seed_demo_data(self, connection: sqlite3.Connection, now: str) -> None:
        admin_email = os.environ.get("HRMS_ADMIN_EMAIL", "admin@flavorflow.com").strip().lower()
        manager_email = os.environ.get("HRMS_MANAGER_EMAIL", "manager@flavorflow.com").strip().lower()
        employee_email = os.environ.get("HRMS_EMPLOYEE_EMAIL", "employee@flavorflow.com").strip().lower()
        admin_password = os.environ.get("HRMS_ADMIN_PASSWORD", "Admin123!")
        manager_password = os.environ.get("HRMS_MANAGER_PASSWORD", "Manager123!")
        employee_password = os.environ.get("HRMS_EMPLOYEE_PASSWORD", "Employee123!")
        admin_id = self._insert_user(connection, admin_email, admin_password, "Jordan Lee", "super_admin", now)
        manager_id = self._insert_user(connection, manager_email, manager_password, "Avery Chen", "manager", now)
        employee_id = self._insert_user(connection, employee_email, employee_password, "Maya Patel", "employee", now)

        today = date.today().isoformat()
        seed_employees = (
            ("FF-001", "Jordan", "Lee", admin_email, "People & Culture", "People Operations Lead", None, admin_id),
            ("FF-002", "Avery", "Chen", manager_email, "Product", "Engineering Manager", None, manager_id),
            ("FF-003", "Maya", "Patel", employee_email, "Product", "Product Designer", 2, employee_id),
            ("FF-004", "Leo", "Kim", "leo.kim@flavorflow.com", "Product", "Software Engineer", 2, None),
            ("FF-005", "Nina", "Brooks", "nina.brooks@flavorflow.com", "People & Culture", "Recruiter", 1, None),
        )
        for code, first, last, email, department, title, manager, user_id in seed_employees:
            connection.execute(
                """INSERT INTO employees
                   (employee_code, first_name, last_name, email, department, title, employment_type,
                    status, start_date, manager_id, user_id, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, 'Full-time', 'active', ?, ?, ?, ?, ?)""",
                (code, first, last, email, department, title, today, manager, user_id, now, now),
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
            user = self._authenticate(headers)
            if endpoint == "/auth/logout" and method == "POST":
                return 200, self._logout(user, headers, remote_address)
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
            return 200, self._list_leave_types()
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
        with self._db() as connection:
            row = connection.execute("SELECT * FROM users WHERE email = ? COLLATE NOCASE", (email,)).fetchone()
            if not row or not row["is_active"] or not _verify_password(password, row["password_hash"]):
                raise ApiError(401, "Email or password is incorrect.")
            token = secrets.token_urlsafe(36)
            token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
            now = datetime.now(timezone.utc)
            expires = (now + timedelta(days=7)).isoformat(timespec="seconds").replace("+00:00", "Z")
            connection.execute(
                "INSERT INTO sessions(token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)",
                (token_hash, row["id"], expires, _now()),
            )
        self._audit(row["id"], "auth.login", "session", None, {"email": email}, remote_address)
        return {"token": token, "user": self._session_payload(row["id"])}

    def _logout(self, user: dict[str, Any], headers: dict[str, str], remote_address: str | None) -> dict[str, Any]:
        token = _header(headers, "authorization").removeprefix("Bearer ").strip()
        if token:
            with self._db() as connection:
                connection.execute("DELETE FROM sessions WHERE token_hash = ?", (hashlib.sha256(token.encode()).hexdigest(),))
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
                """SELECT u.id, u.email, u.full_name, u.is_active
                   FROM sessions s JOIN users u ON u.id = s.user_id
                   WHERE s.token_hash = ? AND s.expires_at > ?""",
                (token_hash, _now()),
            ).fetchone()
        if not row or not row["is_active"]:
            raise ApiError(401, "Session expired or user is inactive. Please sign in again.")
        return dict(row)

    def _session_payload(self, user_id: int) -> dict[str, Any]:
        with self._db() as connection:
            row = connection.execute(
                "SELECT id, email, full_name, is_active FROM users WHERE id = ?", (user_id,)
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
        start_date = _date_string(body.get("start_date"), date.today().isoformat())
        manager_id = _optional_int(body.get("manager_id"))
        status = str(body.get("status", "active"))
        if status not in {"active", "inactive", "on_leave"}:
            raise ApiError(400, "Employee status must be active, inactive, or on_leave.")
        now = _now()
        with self._db() as connection:
            if manager_id is not None and not connection.execute("SELECT 1 FROM employees WHERE id = ?", (manager_id,)).fetchone():
                raise ApiError(400, "The selected manager does not exist.")
            cursor = connection.execute(
                """INSERT INTO employees(employee_code, first_name, last_name, email, department, title,
                   employment_type, status, start_date, manager_id, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    values["employee_code"], values["first_name"], values["last_name"], values["email"],
                    values["department"], values["title"], str(body.get("employment_type", "Full-time")),
                    status, start_date, manager_id, now, now,
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
            "employment_type", "status", "start_date", "manager_id",
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
                   e.employee_code, e.first_name, e.last_name, w.name AS location_name
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
                   e.employee_code, e.first_name, e.last_name, w.name AS location_name
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
            location, distance = self._nearest_location(connection, latitude, longitude)
            if not location:
                raise ApiError(403, "Punch in is blocked because you are outside every active work geofence.", {
                    "nearest_location": distance["name"] if distance else None,
                    "distance_m": round(distance["distance_m"]) if distance else None,
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
            location, distance = self._nearest_location(connection, latitude, longitude, active["work_location_id"])
            if not location:
                raise ApiError(403, "Punch out is blocked because you are outside the assigned work geofence.", {
                    "distance_m": round(distance["distance_m"]) if distance else None,
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
        connection: sqlite3.Connection, latitude: float, longitude: float, required_id: int | None = None
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
        distance_info = {"name": location["name"], "distance_m": distance}
        return (location, distance_info) if distance <= location["radius_m"] else (None, distance_info)

    def _list_attendance(self, user: dict[str, Any], permissions: set[str], query: dict[str, str]) -> dict[str, Any]:
        limit = min(max(_optional_int(query.get("limit")) or 50, 1), 200)
        conditions: list[str] = []
        params: list[Any] = []
        if query.get("date"):
            day = _date_string(query["date"])
            conditions.append("substr(a.punch_in_at, 1, 10) = ?")
            params.append(day)
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

    def _get_leave_policy(self) -> dict[str, Any]:
        with self._db() as connection:
            policy = connection.execute("SELECT * FROM leave_policy WHERE id = 1").fetchone()
            leave_types = connection.execute(
                "SELECT id, name, annual_allowance_days, is_paid, is_active FROM leave_types WHERE is_active = 1 ORDER BY name"
            ).fetchall()
        return dict(policy) | {
            "count_weekends": bool(policy["count_weekends"]),
            "prorate_new_hires": bool(policy["prorate_new_hires"]),
            "carryover_enabled": bool(policy["carryover_enabled"]),
            "leave_type_allowances": [
                dict(row) | {"is_paid": bool(row["is_paid"]), "is_active": bool(row["is_active"])}
                for row in leave_types
            ],
        }

    def _update_leave_policy(self, body: dict[str, Any], user: dict[str, Any], remote: str | None) -> dict[str, Any]:
        allowed = {
            "period_start_month", "count_weekends", "prorate_new_hires",
            "carryover_enabled", "carryover_limit_days", "leave_type_allowances",
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
        if not updates and "leave_type_allowances" not in body:
            raise ApiError(400, "No leave policy fields were supplied.")

        with self._db() as connection:
            if updates:
                assignments = ", ".join(f"{key} = ?" for key in updates)
                connection.execute(
                    f"UPDATE leave_policy SET {assignments}, updated_at = ?, updated_by = ? WHERE id = 1",
                    (*updates.values(), _now(), user["id"]),
                )
            elif allowance_updates:
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
        self._audit(
            user["id"],
            "leave.policy_updated",
            "leave_policy",
            "1",
            {"fields": sorted(updates), "leave_type_ids": [item[0] for item in allowance_updates]},
            remote,
        )
        return self._get_leave_policy()

    def _list_leave_types(self) -> dict[str, Any]:
        with self._db() as connection:
            rows = connection.execute("SELECT * FROM leave_types WHERE is_active = 1 ORDER BY name").fetchall()
        return {"items": [dict(row) | {"is_paid": bool(row["is_paid"])} for row in rows]}

    def _list_leave_requests(self, user: dict[str, Any], permissions: set[str], query: dict[str, str]) -> dict[str, Any]:
        sql = """SELECT lr.*, e.employee_code, e.first_name, e.last_name, e.user_id, e.manager_id,
                 lt.name AS leave_type, u.full_name AS approver_name
                 FROM leave_requests lr JOIN employees e ON e.id = lr.employee_id
                 JOIN leave_types lt ON lt.id = lr.leave_type_id LEFT JOIN users u ON u.id = lr.approver_id"""
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
                   lt.name AS leave_type, u.full_name AS approver_name FROM leave_requests lr
                   JOIN employees e ON e.id = lr.employee_id JOIN leave_types lt ON lt.id = lr.leave_type_id
                   LEFT JOIN users u ON u.id = lr.approver_id WHERE lr.id = ?""",
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
            connection.execute(
                "UPDATE leave_requests SET status = ?, decided_at = ?, approver_id = ?, decision_note = ? WHERE id = ?",
                (decision, _now(), user["id"], note, request_id),
            )
        self._audit(user["id"], f"leave.{decision}", "leave_request", request_id, {"note": note}, remote)
        return _leave_json(self._leave_row(request_id))

    def _list_users(self) -> dict[str, Any]:
        with self._db() as connection:
            rows = connection.execute(
                """SELECT u.id, u.email, u.full_name, u.is_active, u.created_at, e.id AS employee_id,
                   e.employee_code FROM users u LEFT JOIN employees e ON e.user_id = u.id ORDER BY u.full_name"""
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
                employee = connection.execute("SELECT user_id FROM employees WHERE id = ?", (employee_id,)).fetchone()
                if not employee:
                    raise ApiError(400, "The selected employee does not exist.")
                if employee["user_id"] is not None:
                    raise ApiError(409, "That employee is already linked to a user account.")
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
            own_row = connection.execute("SELECT id, start_date FROM employees WHERE user_id = ?", (user["id"],)).fetchone()
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
                       e.employee_code, e.first_name, e.last_name, w.name AS location_name
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
                for leave_type in leave_types:
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
                    annual_allowance = int(leave_type["annual_allowance_days"])
                    current_base = _period_allowance(
                        annual_allowance, hire_date, period_start, period_end, prorate_new_hires
                    )
                    previous_base = _period_allowance(
                        annual_allowance, hire_date, previous_period_start, previous_period_end, prorate_new_hires
                    )
                    carryover = min(
                        max(previous_base - previous_used, 0), carryover_limit_days
                    ) if carryover_enabled else 0
                    allowance = round(current_base + carryover, 2)
                    remaining = round(allowance - current_used, 2)
                    leave_balances.append({
                        "leave_type_id": leave_type["id"],
                        "leave_type": leave_type["name"],
                        "base_allowance_days": current_base,
                        "carryover_days": carryover,
                        "allowance_days": allowance,
                        "used_days": current_used,
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
                       lt.name AS leave_type, u.full_name AS approver_name FROM leave_requests lr
                       JOIN employees e ON e.id = lr.employee_id JOIN leave_types lt ON lt.id = lr.leave_type_id
                       LEFT JOIN users u ON u.id = lr.approver_id WHERE lr.status = 'pending'"""
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

    def _list_audit_logs(self, query: dict[str, str]) -> dict[str, Any]:
        limit = min(max(_optional_int(query.get("limit")) or 100, 1), 300)
        with self._db() as connection:
            rows = connection.execute(
                """SELECT a.*, u.full_name AS actor_name, u.email AS actor_email FROM audit_logs a
                   LEFT JOIN users u ON u.id = a.actor_user_id ORDER BY a.created_at DESC, a.id DESC LIMIT ?""",
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


def _employee_json(row: sqlite3.Row) -> dict[str, Any]:
    item = dict(row)
    item["full_name"] = f"{row['first_name']} {row['last_name']}".strip()
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


def _leave_period_bounds(reference: date, start_month: int) -> tuple[date, date]:
    start_year = reference.year if reference.month >= start_month else reference.year - 1
    period_start = date(start_year, start_month, 1)
    next_period_start = date(start_year + 1, start_month, 1)
    return period_start, next_period_start - timedelta(days=1)


def _approved_leave_day_count(
    rows: list[sqlite3.Row],
    period_start: date,
    period_end: date,
    count_weekends: bool,
) -> int:
    used_dates: set[date] = set()
    for row in rows:
        start = max(date.fromisoformat(row["start_date"]), period_start)
        end = min(date.fromisoformat(row["end_date"]), period_end)
        day = start
        while day <= end:
            if count_weekends or day.weekday() < 5:
                used_dates.add(day)
            day += timedelta(days=1)
    return len(used_dates)


def _period_allowance(
    annual_allowance: int,
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
