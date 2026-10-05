import hashlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from backend.server import HRMSApplication, PERMISSION_CATALOG


class ApiTestCase(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.app = HRMSApplication(Path(self.temp_dir.name) / "test.sqlite3")
        self.admin = self.login("admin@flavorflow.com", "Admin123!")
        self.manager = self.login("manager@flavorflow.com", "Manager123!")
        self.employee = self.login("employee@flavorflow.com", "Employee123!")

    def tearDown(self):
        self.temp_dir.cleanup()

    def call(self, method, path, body=None, token=None):
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        return self.app.handle(method, f"/api/v1{path}", headers, body or {}, "127.0.0.1")

    def login(self, email, password):
        status, result = self.call("POST", "/auth/login", {"email": email, "password": password})
        self.assertEqual(status, 200, result)
        return result["token"]

    def test_super_admin_has_every_catalog_permission_and_role_is_protected(self):
        status, profile = self.call("GET", "/auth/me", token=self.admin)
        self.assertEqual(status, 200)
        self.assertEqual(set(profile["permissions"]), {item[0] for item in PERMISSION_CATALOG})
        self.assertIn("super_admin", profile["roles"])
        status, roles = self.call("GET", "/roles", token=self.admin)
        self.assertEqual(status, 200)
        admin_role = next(role for role in roles["roles"] if role["id"] == "super_admin")
        self.assertEqual(set(admin_role["permissions"]), {item[0] for item in PERMISSION_CATALOG})
        status, error = self.call(
            "PATCH", "/roles/super_admin/permissions", {"permissions": []}, self.admin
        )
        self.assertEqual(status, 409)
        self.assertIn("protected", error["error"]["message"])

    def test_manager_scope_is_limited_to_reporting_team(self):
        status, result = self.call("GET", "/employees", token=self.manager)
        self.assertEqual(status, 200)
        self.assertEqual({item["employee_code"] for item in result["items"]}, {"FF-003", "FF-004"})
        status, _ = self.call(
            "POST", "/employees", {
                "employee_code": "FF-999", "first_name": "Taylor", "last_name": "Test",
                "email": "taylor@example.com", "department": "Design", "title": "Designer",
            }, self.manager
        )
        self.assertEqual(status, 403)

    def test_permissions_are_editable_in_database_and_take_effect_on_api(self):
        status, roles = self.call("GET", "/roles", token=self.admin)
        self.assertEqual(status, 200)
        manager_role = next(role for role in roles["roles"] if role["id"] == "manager")
        updated = set(manager_role["permissions"])
        updated.add("employees.create")
        status, saved = self.call(
            "PATCH", "/roles/manager/permissions", {"permissions": sorted(updated)}, self.admin
        )
        self.assertEqual(status, 200)
        self.assertIn("employees.create", saved["permissions"])
        status, created = self.call(
            "POST", "/employees", {
                "employee_code": "FF-006", "first_name": "Taylor", "last_name": "Test",
                "email": "taylor@example.com", "department": "Design", "title": "Designer",
            }, self.manager
        )
        self.assertEqual(status, 201, created)

        updated.remove("employees.create")
        self.call("PATCH", "/roles/manager/permissions", {"permissions": sorted(updated)}, self.admin)
        status, _ = self.call(
            "POST", "/employees", {
                "employee_code": "FF-007", "first_name": "Robin", "last_name": "Test",
                "email": "robin@example.com", "department": "Design", "title": "Designer",
            }, self.manager
        )
        self.assertEqual(status, 403)

    def test_geofenced_punch_in_and_out(self):
        outside = {"latitude": 37.80, "longitude": -122.40, "accuracy_m": 9.4}
        status, error = self.call("POST", "/attendance/punch-in", outside, self.employee)
        self.assertEqual(status, 403)
        self.assertIn("geofence", error["error"]["message"])

        inside = {"latitude": 37.7952, "longitude": -122.3937, "accuracy_m": 7.0}
        status, record = self.call("POST", "/attendance/punch-in", inside, self.employee)
        self.assertEqual(status, 201, record)
        self.assertIsNone(record["punch_out_at"])
        self.assertLessEqual(record["punch_in_distance_m"], 250)
        status, dashboard = self.call("GET", "/dashboard", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual(dashboard["my_attendance"]["id"], record["id"])

        status, error = self.call("POST", "/attendance/punch-in", inside, self.employee)
        self.assertEqual(status, 409)
        status, error = self.call("POST", "/attendance/punch-out", outside, self.employee)
        self.assertEqual(status, 403)
        status, punched_out = self.call("POST", "/attendance/punch-out", inside, self.employee)
        self.assertEqual(status, 200, punched_out)
        self.assertIsNotNone(punched_out["punch_out_at"])

        status, history = self.call("GET", "/attendance", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual(len(history["items"]), 1)
        self.assertIsNone(history["active"])

    def test_holiday_calendar_is_managed_and_dashboard_uses_next_active_holiday(self):
        holiday_date = (datetime.now(timezone.utc).date() + timedelta(days=7)).isoformat()
        status, holiday = self.call("POST", "/holidays", {
            "name": "Company Foundation Day",
            "holiday_date": holiday_date,
            "description": "Company-wide closure",
        }, self.admin)
        self.assertEqual(status, 201, holiday)
        self.assertTrue(holiday["is_active"])

        status, items = self.call("GET", "/holidays", token=self.manager)
        self.assertEqual(status, 200)
        self.assertEqual(items["total"], 1)
        self.assertEqual(items["items"][0]["id"], holiday["id"])

        status, dashboard = self.call("GET", "/dashboard", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual(dashboard["upcoming_holiday"]["id"], holiday["id"])
        self.assertEqual(dashboard["upcoming_holiday"]["days_until"], 7)

        status, error = self.call("POST", "/holidays", {
            "name": "Not allowed", "holiday_date": holiday_date,
        }, self.employee)
        self.assertEqual(status, 403)

        status, duplicate = self.call("POST", "/holidays", {
            "name": "Company Foundation Day", "holiday_date": holiday_date,
        }, self.admin)
        self.assertEqual(status, 409)
        self.assertIn("already exists", duplicate["error"]["message"])

        status, disabled = self.call("DELETE", f"/holidays/{holiday['id']}", token=self.admin)
        self.assertEqual(status, 200)
        self.assertFalse(disabled["is_active"])
        status, dashboard = self.call("GET", "/dashboard", token=self.employee)
        self.assertEqual(status, 200)
        self.assertIsNone(dashboard["upcoming_holiday"])

    def test_leave_policy_is_admin_managed_and_applies_period_weekend_and_carryover_rules(self):
        status, policy = self.call("GET", "/leave-policy", token=self.admin)
        self.assertEqual(status, 200)
        self.assertEqual(policy["period_start_month"], 1)
        self.assertTrue(policy["count_weekends"])
        self.assertFalse(policy["prorate_new_hires"])
        self.assertFalse(policy["carryover_enabled"])

        status, _ = self.call("GET", "/leave-policy", token=self.manager)
        self.assertEqual(status, 403)
        status, error = self.call("PATCH", "/leave-policy", {"period_start_month": 13}, self.admin)
        self.assertEqual(status, 400)

        annual = next(item for item in policy["leave_type_allowances"] if item["name"] == "Annual leave")
        status, saved = self.call("PATCH", "/leave-policy", {
            "period_start_month": 4,
            "count_weekends": False,
            "prorate_new_hires": False,
            "carryover_enabled": True,
            "carryover_limit_days": 3,
            "leave_type_allowances": [{"id": annual["id"], "annual_allowance_days": 20}],
        }, self.admin)
        self.assertEqual(status, 200, saved)
        self.assertFalse(saved["count_weekends"])
        self.assertTrue(saved["carryover_enabled"])
        self.assertEqual(saved["carryover_limit_days"], 3)

        today = datetime.now(timezone.utc).date()
        start_year = today.year if today.month >= 4 else today.year - 1
        current_start = datetime(start_year, 4, 1, tzinfo=timezone.utc).date()
        previous_start = datetime(start_year - 1, 4, 1, tzinfo=timezone.utc).date()
        previous_end = current_start - timedelta(days=1)
        first_previous_monday = previous_start + timedelta(days=(7 - previous_start.weekday()) % 7)
        prior_leave_end = first_previous_monday + timedelta(days=4)
        first_current_saturday = current_start + timedelta(days=(5 - current_start.weekday()) % 7)
        current_leave_end = first_current_saturday + timedelta(days=2)
        with self.app._db() as connection:
            employee_id = connection.execute(
                "SELECT id FROM employees WHERE user_id = (SELECT id FROM users WHERE email = 'employee@flavorflow.com')"
            ).fetchone()[0]
            connection.execute("UPDATE employees SET start_date = '2020-01-01' WHERE id = ?", (employee_id,))
            connection.execute(
                """INSERT INTO leave_requests
                   (employee_id, leave_type_id, start_date, end_date, reason, status, requested_at)
                   VALUES (?, ?, ?, ?, 'Previous period usage', 'approved', ?)""",
                (employee_id, annual["id"], first_previous_monday.isoformat(), prior_leave_end.isoformat(), today.isoformat()),
            )
            connection.execute(
                """INSERT INTO leave_requests
                   (employee_id, leave_type_id, start_date, end_date, reason, status, requested_at)
                   VALUES (?, ?, ?, ?, 'Current period usage', 'approved', ?)""",
                (employee_id, annual["id"], first_current_saturday.isoformat(), current_leave_end.isoformat(), today.isoformat()),
            )

        status, dashboard = self.call("GET", "/dashboard", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual(dashboard["leave_balance_period"]["start_date"], current_start.isoformat())
        balance = next(item for item in dashboard["my_leave_balances"] if item["leave_type"] == "Annual leave")
        self.assertEqual(balance["base_allowance_days"], 20)
        self.assertEqual(balance["carryover_days"], 3)
        self.assertEqual(balance["allowance_days"], 23)
        self.assertEqual(balance["used_days"], 1)
        self.assertEqual(balance["remaining_days"], 22)

    def test_leave_policy_prorates_allowance_from_employee_start_date(self):
        _, policy = self.call("GET", "/leave-policy", token=self.admin)
        annual = next(item for item in policy["leave_type_allowances"] if item["name"] == "Annual leave")
        today = datetime.now(timezone.utc).date()
        start_month = today.month - 1 if today.month > 1 else 12
        status, _ = self.call("PATCH", "/leave-policy", {
            "period_start_month": start_month,
            "count_weekends": True,
            "prorate_new_hires": True,
            "carryover_enabled": False,
            "carryover_limit_days": 0,
            "leave_type_allowances": [{"id": annual["id"], "annual_allowance_days": 20}],
        }, self.admin)
        self.assertEqual(status, 200)
        with self.app._db() as connection:
            connection.execute(
                "UPDATE employees SET start_date = ? WHERE user_id = (SELECT id FROM users WHERE email = 'employee@flavorflow.com')",
                (today.isoformat(),),
            )

        status, dashboard = self.call("GET", "/dashboard", token=self.employee)
        self.assertEqual(status, 200)
        period_start = datetime.fromisoformat(dashboard["leave_balance_period"]["start_date"]).date()
        period_end = datetime.fromisoformat(dashboard["leave_balance_period"]["end_date"]).date()
        expected = round(20 * ((period_end - today).days + 1) / ((period_end - period_start).days + 1), 2)
        balance = next(item for item in dashboard["my_leave_balances"] if item["leave_type"] == "Annual leave")
        self.assertEqual(balance["base_allowance_days"], expected)
        self.assertEqual(balance["allowance_days"], expected)

    def test_shift_roster_is_role_scoped_and_dashboard_exposes_own_shift(self):
        today = datetime.now(timezone.utc).date().isoformat()
        status, template = self.call("POST", "/shift-templates", {
            "name": "Opening shift", "start_time": "07:00", "end_time": "15:30", "break_minutes": 30,
        }, self.admin)
        self.assertEqual(status, 201, template)

        status, assignment = self.call("POST", "/shift-assignments", {
            "employee_id": 3, "shift_id": template["id"], "work_date": today, "work_location_id": 1,
        }, self.admin)
        self.assertEqual(status, 201, assignment)
        self.assertEqual(assignment["shift_name"], "Opening shift")
        self.assertEqual(assignment["employee_name"], "Maya Patel")

        status, employee_roster = self.call("GET", f"/shift-assignments?date={today}", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual([item["id"] for item in employee_roster["items"]], [assignment["id"]])
        status, manager_roster = self.call("GET", f"/shift-assignments?date={today}", token=self.manager)
        self.assertEqual(status, 200)
        self.assertEqual([item["id"] for item in manager_roster["items"]], [assignment["id"]])

        status, dashboard = self.call("GET", "/dashboard", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual(dashboard["my_shift"]["id"], assignment["id"])

        status, _ = self.call("POST", "/shift-assignments", {
            "employee_id": 3, "shift_id": template["id"], "work_date": today,
        }, self.admin)
        self.assertEqual(status, 409)
        status, error = self.call("POST", "/shift-templates", {
            "name": "Unauthorized shift", "start_time": "09:00", "end_time": "17:00",
        }, self.employee)
        self.assertEqual(status, 403)

        status, removed = self.call("DELETE", f"/shift-assignments/{assignment['id']}", token=self.admin)
        self.assertEqual(status, 200)
        self.assertFalse(removed["is_active"])
        status, employee_roster = self.call("GET", f"/shift-assignments?date={today}", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual(employee_roster["items"], [])

    def test_leave_submission_and_manager_approval(self):
        status, types = self.call("GET", "/leave-types", token=self.employee)
        self.assertEqual(status, 200)
        annual = next(item for item in types["items"] if item["name"] == "Annual leave")
        status, request = self.call(
            "POST", "/leave-requests", {
                "leave_type_id": annual["id"], "start_date": "2026-10-12",
                "end_date": "2026-10-14", "reason": "Family trip",
            }, self.employee
        )
        self.assertEqual(status, 201, request)
        self.assertEqual(request["status"], "pending")
        status, visible = self.call("GET", "/leave-requests?status=pending", token=self.manager)
        self.assertEqual(status, 200)
        self.assertEqual([item["id"] for item in visible["items"]], [request["id"]])
        status, decided = self.call(
            "POST", f"/leave-requests/{request['id']}/decision", {"decision": "approved", "note": "Enjoy"}, self.manager
        )
        self.assertEqual(status, 200, decided)
        self.assertEqual(decided["status"], "approved")
        self.assertEqual(decided["decision_note"], "Enjoy")
        status, own = self.call("GET", f"/leave-requests/{request['id']}", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual(own["status"], "approved")

    def test_dashboard_respects_self_team_and_global_scope(self):
        types_status, types = self.call("GET", "/leave-types", token=self.employee)
        self.assertEqual(types_status, 200)
        annual = next(item for item in types["items"] if item["name"] == "Annual leave")
        status, _ = self.call("PATCH", "/leave-policy", {
            "leave_type_allowances": [{"id": annual["id"], "annual_allowance_days": 20}],
        }, self.admin)
        self.assertEqual(status, 200)
        leave_type = annual["id"]
        _, employee_request = self.call("POST", "/leave-requests", {
            "leave_type_id": leave_type, "start_date": "2026-11-02", "end_date": "2026-11-02", "reason": "Personal day",
        }, self.employee)
        _, admin_request = self.call("POST", "/leave-requests", {
            "leave_type_id": leave_type, "start_date": "2026-11-05", "end_date": "2026-11-05", "reason": "Admin leave",
        }, self.admin)

        today = datetime.now(timezone.utc).date().isoformat()
        _, employee_today_leave = self.call("POST", "/leave-requests", {
            "leave_type_id": leave_type, "start_date": today, "end_date": today, "reason": "Approved today",
        }, self.employee)
        status, _ = self.call(
            "POST", f"/leave-requests/{employee_today_leave['id']}/decision", {"decision": "approved"}, self.manager
        )
        self.assertEqual(status, 200)
        _, admin_today_leave = self.call("POST", "/leave-requests", {
            "leave_type_id": leave_type, "start_date": today, "end_date": today, "reason": "Admin approved today",
        }, self.admin)
        status, _ = self.call(
            "POST", f"/leave-requests/{admin_today_leave['id']}/decision", {"decision": "approved"}, self.admin
        )
        self.assertEqual(status, 200)

        status, employee_dashboard = self.call("GET", "/dashboard", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual(employee_dashboard["stats"]["active_employees"], 1)
        self.assertEqual(employee_dashboard["stats"]["pending_leave"], 1)
        self.assertEqual(employee_dashboard["stats"]["on_leave_today"], 1)
        annual_balance = next(
            item for item in employee_dashboard["my_leave_balances"]
            if item["leave_type"] == "Annual leave"
        )
        self.assertEqual(annual_balance["allowance_days"], 20)
        self.assertEqual(annual_balance["used_days"], 1)
        self.assertEqual(annual_balance["remaining_days"], 19)
        self.assertEqual([item["id"] for item in employee_dashboard["pending_requests"]], [employee_request["id"]])

        status, manager_dashboard = self.call("GET", "/dashboard", token=self.manager)
        self.assertEqual(status, 200)
        self.assertEqual(manager_dashboard["stats"]["pending_leave"], 1)
        self.assertEqual(manager_dashboard["stats"]["on_leave_today"], 1)
        self.assertEqual([item["id"] for item in manager_dashboard["pending_requests"]], [employee_request["id"]])

        status, admin_dashboard = self.call("GET", "/dashboard", token=self.admin)
        self.assertEqual(status, 200)
        self.assertEqual(admin_dashboard["stats"]["active_employees"], 5)
        self.assertEqual(admin_dashboard["stats"]["pending_leave"], 2)
        self.assertEqual(admin_dashboard["stats"]["on_leave_today"], 2)
        self.assertEqual({item["id"] for item in admin_dashboard["pending_requests"]}, {employee_request["id"], admin_request["id"]})

    def test_super_admin_soft_deactivation_is_audited_and_open_shifts_are_safe(self):
        inside = {"latitude": 37.7952, "longitude": -122.3937, "accuracy_m": 7.0}
        status, _ = self.call("POST", "/attendance/punch-in", inside, self.employee)
        self.assertEqual(status, 201)
        status, error = self.call("DELETE", "/employees/3", token=self.admin)
        self.assertEqual(status, 409)
        self.assertIn("open attendance", error["error"]["message"])

        status, _ = self.call("DELETE", "/locations/1", token=self.admin)
        self.assertEqual(status, 200)
        status, punched_out = self.call("POST", "/attendance/punch-out", inside, self.employee)
        self.assertEqual(status, 200, punched_out)
        status, result = self.call("DELETE", "/employees/3", token=self.admin)
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "inactive")
        status, _ = self.call("POST", "/attendance/punch-in", inside, self.employee)
        self.assertEqual(status, 403)

    def test_locations_are_editable_and_soft_disabled(self):
        status, location = self.call("POST", "/locations", {
            "name": "North Studio", "address": "1 Market Street", "latitude": 37.79,
            "longitude": -122.39, "radius_m": 180,
        }, self.admin)
        self.assertEqual(status, 201, location)
        self.assertEqual(location["timezone"], "UTC")
        self.assertTrue(location["is_active"])
        status, updated = self.call("PATCH", f"/locations/{location['id']}", {"radius_m": 225}, self.admin)
        self.assertEqual(status, 200)
        self.assertEqual(updated["radius_m"], 225)
        status, disabled = self.call("DELETE", f"/locations/{location['id']}", token=self.admin)
        self.assertEqual(status, 200)
        self.assertFalse(disabled["is_active"])

    def test_user_role_assignment_is_audited_and_role_options_are_returned(self):
        status, users = self.call("GET", "/users", token=self.admin)
        self.assertEqual(status, 200)
        self.assertIn("manager", {role["id"] for role in users["role_options"]})
        status, created = self.call("POST", "/users", {
            "email": "leo.account@example.com", "full_name": "Leo Kim",
            "password": "TemporaryPass123", "role_id": "employee", "employee_id": 4,
        }, self.admin)
        self.assertEqual(status, 201, created)
        self.assertEqual(created["roles"][0]["id"], "employee")
        status, updated = self.call("PATCH", f"/users/{created['id']}", {
            "full_name": "Leo K.", "role_ids": ["manager"], "is_active": True,
        }, self.admin)
        self.assertEqual(status, 200, updated)
        self.assertEqual(updated["full_name"], "Leo K.")
        self.assertEqual(updated["roles"][0]["id"], "manager")

    def test_employee_creation_is_audited_and_searchable(self):
        status, created = self.call(
            "POST", "/employees", {
                "employee_code": "FF-300", "first_name": "Devon", "last_name": "Reed",
                "email": "devon@example.com", "department": "Operations", "title": "Coordinator",
            }, self.admin
        )
        self.assertEqual(status, 201)
        status, result = self.call("GET", "/employees?q=devon", token=self.admin)
        self.assertEqual(status, 200)
        self.assertEqual(result["items"][0]["id"], created["id"])
        status, logs = self.call("GET", "/audit-logs", token=self.admin)
        self.assertEqual(status, 200)
        self.assertTrue(any(item["action"] == "employee.created" for item in logs["items"]))

    def test_biometric_login_uses_a_rotating_device_token_after_local_auth(self):
        status, login = self.call("POST", "/auth/login", {
            "email": "employee@flavorflow.com",
            "password": "Employee123!",
            "enable_biometrics": True,
        })
        self.assertEqual(status, 200, login)
        first_device_token = login["biometric_token"]
        with self.app._db() as connection:
            stored = connection.execute(
                "SELECT token_hash FROM biometric_login_tokens WHERE user_id = ?",
                (login["user"]["id"],),
            ).fetchone()
        self.assertEqual(
            stored["token_hash"], hashlib.sha256(first_device_token.encode()).hexdigest()
        )

        # An inactivity sign-out revokes the API token but leaves the separate
        # device credential available for biometric re-authentication.
        status, _ = self.call("POST", "/auth/logout", token=login["token"])
        self.assertEqual(status, 200)
        status, _ = self.call("GET", "/auth/me", token=login["token"])
        self.assertEqual(status, 401)

        status, refreshed = self.call("POST", "/auth/biometric-login", {
            "biometric_token": first_device_token,
        })
        self.assertEqual(status, 200, refreshed)
        self.assertNotEqual(refreshed["token"], login["token"])
        self.assertNotEqual(refreshed["biometric_token"], first_device_token)
        status, _ = self.call("GET", "/auth/me", token=refreshed["token"])
        self.assertEqual(status, 200)
        status, _ = self.call("POST", "/auth/biometric-login", {
            "biometric_token": first_device_token,
        })
        self.assertEqual(status, 401)

        status, revoked = self.call("POST", "/auth/biometric-revoke", {
            "biometric_token": refreshed["biometric_token"],
        })
        self.assertEqual(status, 200, revoked)
        status, _ = self.call("POST", "/auth/biometric-login", {
            "biometric_token": refreshed["biometric_token"],
        })
        self.assertEqual(status, 401)

    def test_legacy_authenticated_session_can_register_a_biometric_device_token(self):
        status, registration = self.call(
            "POST", "/auth/biometric-register", token=self.employee
        )
        self.assertEqual(status, 201, registration)
        self.assertTrue(registration["biometric_token"])
        status, refreshed = self.call("POST", "/auth/biometric-login", {
            "biometric_token": registration["biometric_token"],
            "previous_session_token": self.employee,
        })
        self.assertEqual(status, 200, refreshed)
        status, _ = self.call("GET", "/auth/me", token=self.employee)
        self.assertEqual(status, 401)

    def test_biometric_refresh_revokes_the_previous_api_session(self):
        status, login = self.call("POST", "/auth/login", {
            "email": "employee@flavorflow.com",
            "password": "Employee123!",
            "enable_biometrics": True,
        })
        self.assertEqual(status, 200, login)
        status, refreshed = self.call("POST", "/auth/biometric-login", {
            "biometric_token": login["biometric_token"],
            "previous_session_token": login["token"],
        })
        self.assertEqual(status, 200, refreshed)
        status, _ = self.call("GET", "/auth/me", token=login["token"])
        self.assertEqual(status, 401)
        status, _ = self.call("GET", "/auth/me", token=refreshed["token"])
        self.assertEqual(status, 200)

    def test_password_login_can_replace_an_existing_biometric_device_token(self):
        _, first = self.call("POST", "/auth/login", {
            "email": "employee@flavorflow.com",
            "password": "Employee123!",
            "enable_biometrics": True,
        })
        status, second = self.call("POST", "/auth/login", {
            "email": "employee@flavorflow.com",
            "password": "Employee123!",
            "enable_biometrics": True,
            "replace_biometric_token": first["biometric_token"],
        })
        self.assertEqual(status, 200, second)
        self.assertNotEqual(second["biometric_token"], first["biometric_token"])
        status, _ = self.call("POST", "/auth/biometric-login", {
            "biometric_token": first["biometric_token"],
        })
        self.assertEqual(status, 401)
        status, _ = self.call("POST", "/auth/biometric-login", {
            "biometric_token": second["biometric_token"],
        })
        self.assertEqual(status, 200)

    def test_sessions_are_revocable_and_failed_credentials_are_rejected(self):
        status, _ = self.call("POST", "/auth/login", {"email": "admin@flavorflow.com", "password": "bad"})
        self.assertEqual(status, 401)
        status, _ = self.call("POST", "/auth/logout", token=self.employee)
        self.assertEqual(status, 200)
        status, _ = self.call("GET", "/auth/me", token=self.employee)
        self.assertEqual(status, 401)

    def test_api_base_and_health_are_public(self):
        for path in ("", "/"):
            with self.subTest(path=path):
                status, payload = self.call("GET", path)
                self.assertEqual(status, 200)
                self.assertEqual(payload["status"], "ok")
                self.assertEqual(payload["health"], "/api/v1/health")

        status, payload = self.call("GET", "/health")
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "ok")


    def test_team_directory_uses_current_employee_records_without_personal_fields(self):
        status, team = self.call("GET", "/team", token=self.employee)
        self.assertEqual(status, 200, team)
        self.assertGreater(team["summary"]["total"], 0)
        self.assertTrue(all("full_name" in item and "presence" in item for item in team["items"]))
        self.assertTrue(all("address" not in item and "email" not in item for item in team["items"]))

        status, filtered = self.call(
            "GET", "/team?department=Product", token=self.employee
        )
        self.assertEqual(status, 200, filtered)
        self.assertTrue(all(item["department"] == "Product" for item in filtered["items"]))
        self.assertIn("Product", filtered["departments"])

    def test_id_cards_are_role_scoped_and_home_contact_details_are_separate(self):
        status, own_cards = self.call("GET", "/id-cards", token=self.employee)
        self.assertEqual(status, 200, own_cards)
        self.assertEqual(own_cards["total"], 1)
        own_card = own_cards["items"][0]
        self.assertTrue(own_card["employee_code"])
        self.assertEqual(own_card["address"], "")

        status, team_cards = self.call("GET", "/id-cards", token=self.manager)
        self.assertEqual(status, 200, team_cards)
        report_card = next(item for item in team_cards["items"] if item["employee_code"] == "FF-003")
        self.assertNotIn("address", report_card)
        self.assertNotIn("phone", report_card)

        status, employee_rows = self.call("GET", "/employees", token=self.employee)
        self.assertEqual(status, 200, employee_rows)
        self.assertNotIn("address", employee_rows["items"][0])
        self.assertNotIn("phone", employee_rows["items"][0])

        status, denied = self.call(
            "GET", f"/id-cards?employee_id=1", token=self.employee
        )
        self.assertEqual(status, 404)
        status, saved = self.call(
            "PATCH", f"/id-cards/{own_card['id']}", {"address": "Private test address"}, self.admin
        )
        self.assertEqual(status, 200, saved)
        self.assertEqual(saved["address"], "Private test address")
        status, _ = self.call(
            "PATCH", f"/id-cards/{own_card['id']}", {"address": "Not allowed"}, self.employee
        )
        self.assertEqual(status, 403)

    def test_leave_balance_adjustment_is_audited_and_applied_to_self_balance(self):
        status, employee_profile = self.call("GET", "/auth/me", token=self.employee)
        self.assertEqual(status, 200)
        status, employee_rows = self.call("GET", "/employees", token=self.admin)
        self.assertEqual(status, 200)
        employee = next(row for row in employee_rows["items"] if row["employee_code"] == "FF-003")
        status, leave_types = self.call("GET", "/leave-types", token=self.employee)
        self.assertEqual(status, 200)
        annual = next(item for item in leave_types["items"] if item["name"] == "Annual leave")

        status, adjustment = self.call("POST", "/leave-balance-adjustments", {
            "employee_id": employee["id"],
            "leave_type_id": annual["id"],
            "days": 2.5,
            "reason": "Approved policy correction",
        }, self.admin)
        self.assertEqual(status, 201, adjustment)
        self.assertEqual(adjustment["days"], 2.5)
        status, dashboard = self.call("GET", "/dashboard", token=self.employee)
        self.assertEqual(status, 200, dashboard)
        balance = next(item for item in dashboard["my_leave_balances"] if item["leave_type_id"] == annual["id"])
        self.assertEqual(balance["adjustment_days"], 2.5)
        self.assertEqual(balance["remaining_days"], 2.5)
        status, _ = self.call("POST", "/leave-balance-adjustments", {
            "employee_id": employee["id"], "leave_type_id": annual["id"],
            "days": 1, "reason": "Not authorized",
        }, self.employee)
        self.assertEqual(status, 403)

    def test_overtime_and_manual_punch_requests_follow_review_scopes(self):
        work_date = datetime.now(timezone.utc).date().isoformat()
        status, overtime = self.call("POST", "/attendance/overtime-requests", {
            "work_date": work_date, "hours": 2.5, "reason": "Approved production support",
        }, self.employee)
        self.assertEqual(status, 201, overtime)
        status, manager_queue = self.call(
            "GET", "/attendance/overtime-requests?status=pending", token=self.manager
        )
        self.assertEqual(status, 200, manager_queue)
        self.assertTrue(any(item["id"] == overtime["id"] for item in manager_queue["items"]))
        status, decided = self.call(
            "POST", f"/attendance/overtime-requests/{overtime['id']}/decision",
            {"decision": "approved", "note": "Reviewed"}, self.manager,
        )
        self.assertEqual(status, 200, decided)
        self.assertEqual(decided["status"], "approved")

        now = datetime.now(timezone.utc)
        punch_in = (now - timedelta(hours=10)).isoformat(timespec="seconds").replace("+00:00", "Z")
        punch_out = (now - timedelta(hours=2)).isoformat(timespec="seconds").replace("+00:00", "Z")
        status, manual = self.call("POST", "/attendance/manual-punch-requests", {
            "work_date": punch_in[:10], "punch_in": punch_in, "punch_out": punch_out,
            "reason": "The terminal was temporarily unavailable",
        }, self.employee)
        self.assertEqual(status, 201, manual)
        status, approved = self.call(
            "POST", f"/attendance/manual-punch-requests/{manual['id']}/decision",
            {"decision": "approved"}, self.manager,
        )
        self.assertEqual(status, 200, approved)
        self.assertEqual(approved["status"], "approved")

        corrected_in = (now - timedelta(hours=11)).isoformat(timespec="seconds").replace("+00:00", "Z")
        status, correction = self.call("POST", "/attendance/manual-punch-requests", {
            "work_date": punch_in[:10], "punch_in": corrected_in, "punch_out": None,
            "reason": "Correct the recorded arrival time",
        }, self.employee)
        self.assertEqual(status, 201, correction)
        status, corrected = self.call(
            "POST", f"/attendance/manual-punch-requests/{correction['id']}/decision",
            {"decision": "approved"}, self.manager,
        )
        self.assertEqual(status, 200, corrected)
        self.assertEqual(corrected["attendance_record_id"], approved["attendance_record_id"])

        status, history = self.call("GET", "/attendance?limit=100", token=self.employee)
        self.assertEqual(status, 200, history)
        manual_record = next(item for item in history["items"] if item["id"] == approved["attendance_record_id"])
        self.assertEqual(manual_record["punch_source"], "manual")
        self.assertEqual(manual_record["punch_in_at"], corrected_in)

    def test_gate_passes_issue_a_reference_code_only_after_authorized_approval(self):
        start = datetime.now(timezone.utc) + timedelta(hours=2)
        end = start + timedelta(hours=2)
        iso = lambda value: value.isoformat(timespec="seconds").replace("+00:00", "Z")
        status, request = self.call("POST", "/gate-passes", {
            "pass_type": "official_duty", "purpose": "Scheduled company work",
            "valid_from": iso(start), "valid_until": iso(end),
        }, self.employee)
        self.assertEqual(status, 201, request)
        self.assertIsNone(request["reference_code"])
        status, approved = self.call(
            "POST", f"/gate-passes/{request['id']}/decision", {"decision": "approved"}, self.manager
        )
        self.assertEqual(status, 200, approved)
        self.assertEqual(approved["status"], "approved")
        self.assertTrue(approved["reference_code"].startswith("FFGP-"))
        status, own_passes = self.call("GET", "/gate-passes", token=self.employee)
        self.assertEqual(status, 200, own_passes)
        self.assertTrue(any(item["id"] == request["id"] for item in own_passes["items"]))

if __name__ == "__main__":
    unittest.main()
