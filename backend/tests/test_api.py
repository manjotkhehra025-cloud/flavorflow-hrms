import hashlib
import tempfile
import unittest
from datetime import date, datetime, timedelta, timezone
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
        self.assertEqual({item["employee_code"] for item in result["items"]}, {"FF-003"})
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

        # A coordinate near the boundary is rejected if its reported accuracy
        # radius could place the employee outside the work site.
        imprecise_near_edge = {"latitude": 37.7970, "longitude": -122.3937, "accuracy_m": 75.0}
        status, error = self.call("POST", "/attendance/punch-in", imprecise_near_edge, self.employee)
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
        status, future_report = self.call(
            "GET", "/attendance?from=2099-01-01&to=2099-01-31&limit=200", token=self.admin
        )
        self.assertEqual(status, 200)
        self.assertEqual(future_report["items"], [])

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
        # Exercise configurable Official Staff category allowances;
        # Yellow Card balances are covered by the category-specific policy test.
        with self.app._db() as connection:
            connection.execute(
                "UPDATE employees SET employment_type = 'Official Staff' WHERE user_id = (SELECT id FROM users WHERE email = 'employee@flavorflow.com')"
            )
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

        earned = next(
            item for item in policy["category_leave_type_allowances"]
            if item["employment_type"] == "Official Staff" and item["name"] == "Earned Leave (EL)"
        )
        status, saved = self.call("PATCH", "/leave-policy", {
            "period_start_month": 4,
            "count_weekends": False,
            "prorate_new_hires": False,
            "carryover_enabled": True,
            "carryover_limit_days": 3,
            "category_leave_type_allowances": [{
                "employment_type": "Official Staff", "id": earned["id"],
                "annual_allowance_days": 20, "is_applicable": True,
                "accrual_method": "annual", "monthly_reset": False, "attendance_based": False,
            }],
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
                (employee_id, earned["id"], first_previous_monday.isoformat(), prior_leave_end.isoformat(), today.isoformat()),
            )
            connection.execute(
                """INSERT INTO leave_requests
                   (employee_id, leave_type_id, start_date, end_date, reason, status, requested_at)
                   VALUES (?, ?, ?, ?, 'Current period usage', 'approved', ?)""",
                (employee_id, earned["id"], first_current_saturday.isoformat(), current_leave_end.isoformat(), today.isoformat()),
            )

        status, dashboard = self.call("GET", "/dashboard", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual(dashboard["leave_balance_period"]["start_date"], current_start.isoformat())
        balance = next(item for item in dashboard["my_leave_balances"] if item["leave_type"] == "Earned Leave (EL)")
        self.assertEqual(balance["base_allowance_days"], 20)
        self.assertEqual(balance["carryover_days"], 3)
        self.assertEqual(balance["allowance_days"], 23)
        self.assertEqual(balance["used_days"], 1)
        self.assertEqual(balance["remaining_days"], 22)

    def test_leave_policy_prorates_allowance_from_employee_start_date(self):
        with self.app._db() as connection:
            connection.execute(
                "UPDATE employees SET employment_type = 'Official Staff' WHERE user_id = (SELECT id FROM users WHERE email = 'employee@flavorflow.com')"
            )
        _, policy = self.call("GET", "/leave-policy", token=self.admin)
        earned = next(
            item for item in policy["category_leave_type_allowances"]
            if item["employment_type"] == "Official Staff" and item["name"] == "Earned Leave (EL)"
        )
        today = datetime.now(timezone.utc).date()
        start_month = today.month - 1 if today.month > 1 else 12
        status, _ = self.call("PATCH", "/leave-policy", {
            "period_start_month": start_month,
            "count_weekends": True,
            "prorate_new_hires": True,
            "carryover_enabled": False,
            "carryover_limit_days": 0,
            "category_leave_type_allowances": [{
                "employment_type": "Official Staff", "id": earned["id"],
                "annual_allowance_days": 20, "is_applicable": True,
                "accrual_method": "annual", "monthly_reset": False, "attendance_based": False,
            }],
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
        balance = next(item for item in dashboard["my_leave_balances"] if item["leave_type"] == "Earned Leave (EL)")
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
        self.assertEqual(assignment["employee_name"], "Rajwinder Singh")

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
        earned = next(item for item in types["items"] if item["name"] == "Earned Leave (EL)")
        status, request = self.call(
            "POST", "/leave-requests", {
                "leave_type_id": earned["id"], "start_date": "2026-10-12",
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

    def test_yellow_card_staff_gets_only_monthly_earned_leave(self):
        status, types = self.call("GET", "/leave-types", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual(types["employment_type"], "Yellow Card")
        self.assertEqual([item["name"] for item in types["items"]], ["Earned Leave (EL)"])
        earned = types["items"][0]
        self.assertEqual(earned["annual_allowance_days"], 15)
        self.assertEqual(earned["accrual_method"], "monthly")

        status, policy = self.call("GET", "/leave-policy", token=self.admin)
        self.assertEqual(status, 200)
        self.assertIn("1.25 days per elapsed month", policy["yellow_card_policy_text"])
        yellow_policy = [
            item for item in policy["category_leave_type_allowances"]
            if item["employment_type"] == "Yellow Card"
        ]
        self.assertTrue(next(item for item in yellow_policy if item["name"] == "Earned Leave (EL)")["is_applicable"])
        for item in yellow_policy:
            if item["name"] != "Earned Leave (EL)":
                self.assertFalse(item["is_applicable"], item["name"])

        annual = next(item for item in policy["leave_type_allowances"] if item["name"] == "Annual leave")
        status, error = self.call("POST", "/leave-requests", {
            "leave_type_id": annual["id"], "start_date": "2026-11-02",
            "end_date": "2026-11-02", "reason": "Not an eligible Yellow Card leave type",
        }, self.employee)
        self.assertEqual(status, 400, error)
        self.assertIn("not eligible", error["error"]["message"])

        status, request = self.call("POST", "/leave-requests", {
            "leave_type_id": earned["id"], "start_date": "2026-11-02",
            "end_date": "2026-11-02", "reason": "Earned leave request",
        }, self.employee)
        self.assertEqual(status, 201, request)
        status, dashboard = self.call("GET", "/dashboard", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual(len(dashboard["my_leave_balances"]), 1)
        balance = dashboard["my_leave_balances"][0]
        self.assertEqual(balance["leave_type"], "Earned Leave (EL)")
        self.assertEqual(balance["annual_allowance_days"], 15)
        self.assertEqual(balance["monthly_accrual_days"], 1.25)
        self.assertGreaterEqual(balance["base_allowance_days"], 0)
        self.assertLessEqual(balance["base_allowance_days"], 15)

    def test_official_staff_leave_rules_and_compensatory_credit(self):
        today = datetime.now(timezone.utc).date()
        days_since_sunday = (today.weekday() - 6) % 7 or 7
        completed_weekly_off = today - timedelta(days=days_since_sunday)
        incomplete_weekly_off = completed_weekly_off - timedelta(days=7)
        now = datetime.now(timezone.utc).isoformat()
        with self.app._db() as connection:
            employee = connection.execute(
                "SELECT id FROM employees WHERE user_id = (SELECT id FROM users WHERE email = 'employee@flavorflow.com')"
            ).fetchone()
            employee_id = int(employee["id"])
            connection.execute(
                "UPDATE employees SET employment_type = 'Official Staff', start_date = '2020-01-01', weekly_off_days = '[\"Sunday\"]' WHERE id = ?",
                (employee_id,),
            )
            connection.execute(
                """INSERT INTO attendance_records
                   (employee_id, work_location_id, punch_in_at, punch_in_latitude, punch_in_longitude,
                    punch_in_accuracy_m, punch_in_distance_m, punch_out_at, punch_out_latitude,
                    punch_out_longitude, punch_out_accuracy_m, punch_out_distance_m, punch_source, created_at)
                   VALUES (?, NULL, ?, 0, 0, 5, 0, ?, 0, 0, 5, 0, 'gps', ?)""",
                (employee_id, f"{completed_weekly_off.isoformat()}T08:00:00Z", f"{completed_weekly_off.isoformat()}T16:00:00Z", now),
            )
            connection.execute(
                """INSERT INTO attendance_records
                   (employee_id, work_location_id, punch_in_at, punch_in_latitude, punch_in_longitude,
                    punch_in_accuracy_m, punch_in_distance_m, punch_source, created_at)
                   VALUES (?, NULL, ?, 0, 0, 5, 0, 'gps', ?)""",
                (employee_id, f"{incomplete_weekly_off.isoformat()}T08:00:00Z", now),
            )

        status, leave_types = self.call("GET", "/leave-types", token=self.employee)
        self.assertEqual(status, 200, leave_types)
        self.assertEqual(leave_types["employment_type"], "Official Staff")
        types_by_name = {item["name"]: item for item in leave_types["items"]}
        self.assertEqual(set(types_by_name), {
            "Earned Leave (EL)", "Sick Leave (SL)", "Casual Leave (CL)",
            "Short Leave", "Compensatory Leave",
        })
        self.assertEqual(types_by_name["Earned Leave (EL)"]["annual_allowance_days"], 14)
        self.assertEqual(types_by_name["Sick Leave (SL)"]["annual_allowance_days"], 14)
        self.assertEqual(types_by_name["Casual Leave (CL)"]["annual_allowance_days"], 7)
        self.assertEqual(types_by_name["Short Leave"]["monthly_accrual_days"], 2)
        self.assertTrue(types_by_name["Short Leave"]["monthly_reset"])
        self.assertTrue(types_by_name["Compensatory Leave"]["attendance_based"])

        status, dashboard = self.call("GET", "/dashboard", token=self.employee)
        self.assertEqual(status, 200, dashboard)
        balances = {item["leave_type"]: item for item in dashboard["my_leave_balances"]}
        self.assertEqual(balances["Earned Leave (EL)"]["allowance_days"], 14)
        self.assertEqual(balances["Sick Leave (SL)"]["allowance_days"], 14)
        self.assertEqual(balances["Casual Leave (CL)"]["allowance_days"], 7)
        self.assertEqual(balances["Short Leave"]["allowance_days"], 2)
        self.assertEqual(balances["Short Leave"]["used_days"], 0)
        self.assertEqual(balances["Compensatory Leave"]["base_allowance_days"], 1)
        self.assertEqual(balances["Compensatory Leave"]["remaining_days"], 1)

        manual_weekly_off = completed_weekly_off - timedelta(days=14)
        manual_start = datetime.combine(manual_weekly_off, datetime.min.time(), tzinfo=timezone.utc) + timedelta(hours=8)
        manual_end = manual_start + timedelta(hours=8)
        to_iso = lambda value: value.isoformat(timespec="seconds").replace("+00:00", "Z")
        status, manual_request = self.call("POST", "/attendance/manual-punch-requests", {
            "work_date": manual_weekly_off.isoformat(),
            "punch_in": to_iso(manual_start),
            "punch_out": to_iso(manual_end),
            "reason": "Approved weekly-off shift correction",
        }, self.employee)
        self.assertEqual(status, 201, manual_request)
        status, before_manual_approval = self.call("GET", "/dashboard", token=self.employee)
        self.assertEqual(status, 200)
        comp_before = next(item for item in before_manual_approval["my_leave_balances"] if item["leave_type"] == "Compensatory Leave")
        self.assertEqual(comp_before["base_allowance_days"], 1)
        status, approved_manual = self.call(
            "POST", f"/attendance/manual-punch-requests/{manual_request['id']}/decision",
            {"decision": "approved"}, self.manager,
        )
        self.assertEqual(status, 200, approved_manual)
        self.assertEqual(approved_manual["status"], "approved")
        status, after_manual_approval = self.call("GET", "/dashboard", token=self.employee)
        self.assertEqual(status, 200)
        comp_after = next(item for item in after_manual_approval["my_leave_balances"] if item["leave_type"] == "Compensatory Leave")
        self.assertEqual(comp_after["base_allowance_days"], 2)

        short_id = types_by_name["Short Leave"]["id"]
        month_start = today.replace(day=1)
        status, two_days = self.call("POST", "/leave-requests", {
            "leave_type_id": short_id,
            "start_date": month_start.isoformat(),
            "end_date": (month_start + timedelta(days=1)).isoformat(),
            "reason": "Two monthly short-leave days",
        }, self.employee)
        self.assertEqual(status, 201, two_days)
        status, over_limit = self.call("POST", "/leave-requests", {
            "leave_type_id": short_id,
            "start_date": (month_start + timedelta(days=2)).isoformat(),
            "end_date": (month_start + timedelta(days=2)).isoformat(),
            "reason": "Exceed monthly short-leave limit",
        }, self.employee)
        self.assertEqual(status, 400)
        self.assertIn("2 days per calendar month", over_limit["error"]["message"])
        status, dashboard = self.call("GET", "/dashboard", token=self.employee)
        self.assertEqual(status, 200, dashboard)
        short_balance = next(item for item in dashboard["my_leave_balances"] if item["leave_type"] == "Short Leave")
        self.assertEqual(short_balance["reserved_days"], 2)
        self.assertEqual(short_balance["remaining_days"], 0)

        next_month = date(month_start.year + 1, 1, 1) if month_start.month == 12 else date(month_start.year, month_start.month + 1, 1)
        status, next_month_request = self.call("POST", "/leave-requests", {
            "leave_type_id": short_id,
            "start_date": next_month.isoformat(),
            "end_date": (next_month + timedelta(days=1)).isoformat(),
            "reason": "New monthly short-leave allowance",
        }, self.employee)
        self.assertEqual(status, 201, next_month_request)

        compensatory_id = types_by_name["Compensatory Leave"]["id"]
        status, comp_request = self.call("POST", "/leave-requests", {
            "leave_type_id": compensatory_id,
            "start_date": today.isoformat(),
            "end_date": today.isoformat(),
            "reason": "Compensation for weekly-off attendance",
        }, self.employee)
        self.assertEqual(status, 201, comp_request)
        status, second_comp_request = self.call("POST", "/leave-requests", {
            "leave_type_id": compensatory_id,
            "start_date": (today + timedelta(days=1)).isoformat(),
            "end_date": (today + timedelta(days=1)).isoformat(),
            "reason": "Second completed weekly-off attendance credit",
        }, self.employee)
        self.assertEqual(status, 201, second_comp_request)
        status, unearned = self.call("POST", "/leave-requests", {
            "leave_type_id": compensatory_id,
            "start_date": (today + timedelta(days=2)).isoformat(),
            "end_date": (today + timedelta(days=2)).isoformat(),
            "reason": "No third weekly-off credit",
        }, self.employee)
        self.assertEqual(status, 400)
        self.assertIn("completed attendance on a scheduled weekly off", unearned["error"]["message"])

    def test_dashboard_respects_self_team_and_global_scope(self):
        # Use an Official Staff category allowance for this scope test.
        with self.app._db() as connection:
            connection.execute(
                "UPDATE employees SET employment_type = 'Official Staff' WHERE user_id = (SELECT id FROM users WHERE email = 'employee@flavorflow.com')"
            )
        types_status, types = self.call("GET", "/leave-types", token=self.employee)
        self.assertEqual(types_status, 200)
        earned = next(item for item in types["items"] if item["name"] == "Earned Leave (EL)")
        status, _ = self.call("PATCH", "/leave-policy", {
            "category_leave_type_allowances": [{
                "employment_type": "Official Staff", "id": earned["id"],
                "annual_allowance_days": 20, "is_applicable": True,
                "accrual_method": "annual", "monthly_reset": False, "attendance_based": False,
            }],
        }, self.admin)
        self.assertEqual(status, 200)
        leave_type = earned["id"]
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
            if item["leave_type"] == "Earned Leave (EL)"
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
            "email": "manjot.account@example.com", "full_name": "Mismatched account name",
            "password": "TemporaryPass123", "role_id": "employee", "employee_id": 4,
        }, self.admin)
        self.assertEqual(status, 201, created)
        self.assertEqual(created["full_name"], "Manjot Singh")
        self.assertEqual(created["roles"][0]["id"], "employee")
        status, updated = self.call("PATCH", f"/users/{created['id']}", {
            "full_name": "Manjot K.", "role_ids": ["manager"], "is_active": True,
        }, self.admin)
        self.assertEqual(status, 200, updated)
        self.assertEqual(updated["full_name"], "Manjot K.")
        self.assertEqual(updated["roles"][0]["id"], "manager")
        status, employees = self.call("GET", "/employees", token=self.admin)
        self.assertEqual(status, 200, employees)
        linked_employee = next(row for row in employees["items"] if row["id"] == 4)
        self.assertEqual(linked_employee["full_name"], "Manjot K.")

    def test_employee_name_updates_stay_in_sync_with_linked_user(self):
        status, employees = self.call("GET", "/employees", token=self.admin)
        self.assertEqual(status, 200, employees)
        employee = next(row for row in employees["items"] if row["employee_code"] == "FF-003")
        status, users = self.call("GET", "/users", token=self.admin)
        self.assertEqual(status, 200, users)
        account = next(row for row in users["items"] if row["employee_code"] == "FF-003")

        # Existing databases may already have a stale user-name copy from an
        # earlier employee edit. Linked employee records are the display source.
        with self.app._db() as connection:
            connection.execute(
                "UPDATE users SET full_name = ? WHERE id = ?", ("Old Account Name", account["id"])
            )
        status, users = self.call("GET", "/users", token=self.admin)
        self.assertEqual(status, 200, users)
        account = next(row for row in users["items"] if row["employee_code"] == "FF-003")
        self.assertEqual(account["full_name"], "Rajwinder Singh")
        status, profile = self.call("GET", "/auth/me", token=self.employee)
        self.assertEqual(status, 200, profile)
        self.assertEqual(profile["full_name"], "Rajwinder Singh")

        status, updated_employee = self.call("PATCH", f"/employees/{employee['id']}", {
            "first_name": "Rajwinder", "last_name": "Kaur",
        }, self.admin)
        self.assertEqual(status, 200, updated_employee)
        self.assertEqual(updated_employee["full_name"], "Rajwinder Kaur")

        status, users = self.call("GET", "/users", token=self.admin)
        self.assertEqual(status, 200, users)
        account = next(row for row in users["items"] if row["employee_code"] == "FF-003")
        self.assertEqual(account["full_name"], "Rajwinder Kaur")
        status, profile = self.call("GET", "/auth/me", token=self.employee)
        self.assertEqual(status, 200, profile)
        self.assertEqual(profile["full_name"], "Rajwinder Kaur")
        status, team = self.call("GET", "/team", token=self.employee)
        self.assertEqual(status, 200, team)
        self.assertIn("Rajwinder Kaur", {row["full_name"] for row in team["items"]})
        status, cards = self.call("GET", "/id-cards", token=self.employee)
        self.assertEqual(status, 200, cards)
        self.assertEqual(cards["items"][0]["full_name"], "Rajwinder Kaur")

        status, updated_account = self.call("PATCH", f"/users/{account['id']}", {
            "full_name": "Rajwinder Kaur Singh",
        }, self.admin)
        self.assertEqual(status, 200, updated_account)
        self.assertEqual(updated_account["full_name"], "Rajwinder Kaur Singh")
        status, employees = self.call("GET", "/employees", token=self.admin)
        self.assertEqual(status, 200, employees)
        employee = next(row for row in employees["items"] if row["employee_code"] == "FF-003")
        self.assertEqual(employee["first_name"], "Rajwinder")
        self.assertEqual(employee["last_name"], "Kaur Singh")
        self.assertEqual(employee["full_name"], "Rajwinder Kaur Singh")

    def test_fresh_demo_roster_uses_the_screenshot_staff_profiles(self):
        status, result = self.call("GET", "/employees", token=self.admin)
        self.assertEqual(status, 200, result)
        profiles = {row["employee_code"]: row for row in result["items"]}
        self.assertEqual(len(profiles), 5)
        self.assertEqual(
            (profiles["FF-001"]["full_name"], profiles["FF-001"]["department"], profiles["FF-001"]["title"]),
            ("Super Admin", "Management", "Super Admin"),
        )
        self.assertEqual(
            (profiles["FF-002"]["full_name"], profiles["FF-002"]["department"], profiles["FF-002"]["title"]),
            ("Harpreet Singh", "Production", "Senior Executive"),
        )
        self.assertEqual(profiles["FF-002"]["weekly_off_days"], ["Saturday"])
        self.assertEqual(
            (profiles["FF-003"]["full_name"], profiles["FF-003"]["department"], profiles["FF-003"]["title"]),
            ("Rajwinder Singh", "Quality - Lab", "Lab Assistant"),
        )
        self.assertEqual(profiles["FF-003"]["employment_type"], "Yellow Card")
        self.assertEqual(profiles["FF-003"]["employment_category_label"], "Yellow Card Staff (15 EL Only)")
        self.assertEqual(profiles["FF-001"]["employment_category_label"], "Official Staff")
        status, options = self.call("GET", "/employee-options", token=self.admin)
        self.assertEqual(status, 200)
        self.assertEqual(options["departments"][:6], ["Production", "Agriculture", "Security", "Engineering", "Accounts", "Quality"])
        self.assertIn("Yellow Card Staff (15 EL Only)", {item["label"] for item in options["employment_types"]})
        self.assertEqual(
            (profiles["FF-004"]["full_name"], profiles["FF-004"]["department"], profiles["FF-004"]["title"]),
            ("Manjot Singh", "Production", "Super Admin"),
        )
        self.assertEqual(profiles["FF-004"]["employment_type"], "Yellow Card")
        self.assertEqual(
            (profiles["FF-005"]["full_name"], profiles["FF-005"]["department"], profiles["FF-005"]["title"]),
            ("Ravinder Singh", "Production & Quality", "Senior Manager Production"),
        )
        self.assertTrue(all(row["status"] == "active" for row in profiles.values()))

    def test_employee_creation_is_audited_and_searchable(self):
        status, created = self.call(
            "POST", "/employees", {
                "employee_code": "FF-300", "first_name": "Devon", "last_name": "Reed",
                "email": "devon@example.com", "department": "Security", "title": "Coordinator",
                "employment_type": "Yellow Card Staff (15 EL Only)",
            }, self.admin
        )
        self.assertEqual(status, 201)
        self.assertEqual(created["employment_type"], "Yellow Card")
        self.assertEqual(created["employment_category_label"], "Yellow Card Staff (15 EL Only)")
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
        self.assertEqual(team["departments"][:6], ["Production", "Agriculture", "Security", "Engineering", "Accounts", "Quality"])
        self.assertTrue(all(item["employment_category_label"] in {"Official Staff", "Yellow Card Staff (15 EL Only)"} for item in team["items"]))

        status, filtered = self.call(
            "GET", "/team?department=Production", token=self.employee
        )
        self.assertEqual(status, 200, filtered)
        self.assertTrue(all(item["department"] == "Production" for item in filtered["items"]))
        self.assertIn("Production", filtered["departments"])

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
        earned = next(item for item in leave_types["items"] if item["name"] == "Earned Leave (EL)")

        status, adjustment = self.call("POST", "/leave-balance-adjustments", {
            "employee_id": employee["id"],
            "leave_type_id": earned["id"],
            "days": 2.5,
            "reason": "Approved policy correction",
        }, self.admin)
        self.assertEqual(status, 201, adjustment)
        self.assertEqual(adjustment["days"], 2.5)
        status, dashboard = self.call("GET", "/dashboard", token=self.employee)
        self.assertEqual(status, 200, dashboard)
        balance = next(item for item in dashboard["my_leave_balances"] if item["leave_type_id"] == earned["id"])
        self.assertEqual(balance["adjustment_days"], 2.5)
        self.assertEqual(balance["remaining_days"], round(balance["base_allowance_days"] + 2.5, 2))
        status, _ = self.call("POST", "/leave-balance-adjustments", {
            "employee_id": employee["id"], "leave_type_id": earned["id"],
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

        manual_day = datetime.now(timezone.utc).date() - timedelta(days=1)
        now = datetime.combine(manual_day, datetime.min.time(), tzinfo=timezone.utc) + timedelta(hours=12)
        punch_in = (now - timedelta(hours=10)).isoformat(timespec="seconds").replace("+00:00", "Z")
        punch_out = (now - timedelta(hours=2)).isoformat(timespec="seconds").replace("+00:00", "Z")
        status, manual = self.call("POST", "/attendance/manual-punch-requests", {
            "work_date": punch_in[:10], "punch_in": punch_in, "punch_out": punch_out,
            "reason": "The terminal was temporarily unavailable",
        }, self.employee)
        self.assertEqual(status, 201, manual)
        self.assertEqual(manual["status"], "pending")
        self.assertIsNone(manual["attendance_record_id"])
        status, pre_approval_history = self.call("GET", "/attendance?limit=100", token=self.employee)
        self.assertEqual(status, 200, pre_approval_history)
        self.assertEqual(pre_approval_history["items"], [])
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

    def test_social_wall_posts_likes_comments_and_moderation(self):
        status, post = self.call("POST", "/social-posts", {"body": "Great work on the production launch!"}, self.employee)
        self.assertEqual(status, 201, post)
        self.assertEqual(post["author_name"], "Rajwinder Singh")
        self.assertEqual(post["like_count"], 0)

        status, feed = self.call("GET", "/social-posts", token=self.manager)
        self.assertEqual(status, 200, feed)
        self.assertEqual(feed["items"][0]["id"], post["id"])
        status, liked = self.call("POST", f"/social-posts/{post['id']}/like", {}, self.manager)
        self.assertEqual(status, 200, liked)
        self.assertTrue(liked["liked"])
        self.assertEqual(liked["post"]["like_count"], 1)

        status, commented = self.call(
            "POST", f"/social-posts/{post['id']}/comments", {"body": "Congratulations!"}, self.manager
        )
        self.assertEqual(status, 201, commented)
        self.assertEqual(commented["comment_count"], 1)
        self.assertEqual(commented["comments"][0]["author_name"], "Harpreet Singh")

        status, removed = self.call("DELETE", f"/social-posts/{post['id']}", token=self.admin)
        self.assertEqual(status, 200, removed)
        status, feed = self.call("GET", "/social-posts", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual(feed["items"], [])

    def test_output_logs_are_scoped_to_employee_and_reporting_team(self):
        work_date = datetime.now(timezone.utc).date().isoformat()
        status, log = self.call("POST", "/output-logs", {
            "work_date": work_date, "output_item": "Packing cases", "quantity": 125,
            "unit": "cases", "target_quantity": 150, "notes": "End-of-shift count",
        }, self.employee)
        self.assertEqual(status, 201, log)
        self.assertEqual(log["employee_name"], "Rajwinder Singh")
        self.assertEqual(log["quantity"], 125)

        status, own_logs = self.call("GET", "/output-logs", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual([item["id"] for item in own_logs["items"]], [log["id"]])
        status, team_logs = self.call("GET", "/output-logs", token=self.manager)
        self.assertEqual(status, 200)
        self.assertEqual([item["id"] for item in team_logs["items"]], [log["id"]])

        status, error = self.call("POST", "/output-logs", {
            "employee_id": 3, "work_date": work_date, "output_item": "Unauthorized", "quantity": 1, "unit": "unit",
        }, self.manager)
        self.assertEqual(status, 403)
        status, error = self.call("POST", "/output-logs", {
            "work_date": work_date, "output_item": "Invalid", "quantity": 0, "unit": "unit",
        }, self.employee)
        self.assertEqual(status, 400)

    def test_kra_templates_goals_and_role_scoped_reviews(self):
        with self.app._db() as connection:
            connection.execute("UPDATE employees SET employment_type = 'Official Staff' WHERE id = 3")
        status, templates = self.call("GET", "/kra/templates", token=self.admin)
        self.assertEqual(status, 200)
        self.assertEqual(templates["items"], [])
        status, template = self.call("POST", "/kra/templates", {
            "department": "Quality", "role_title": "Lab Assistant",
            "title": "Accurate lab records", "description": "Maintain approved records.",
            "weight_percent": 25,
        }, self.admin)
        self.assertEqual(status, 201, template)
        status, template = self.call("PATCH", f"/kra/templates/{template['id']}", {
            "description": "Verified monthly records.", "weight_percent": 30,
        }, self.admin)
        self.assertEqual(status, 200, template)
        self.assertEqual(template["weight_percent"], 30)
        status, goal = self.call("POST", "/kra/goals", {
            "employee_id": 3, "template_id": template["id"], "cycle": "2026",
            "target": "All scheduled records complete",
        }, self.admin)
        self.assertEqual(status, 201, goal)
        self.assertEqual(goal["employee_name"], "Rajwinder Singh")
        self.assertEqual(goal["status"], "not_started")

        status, own_goals = self.call("GET", "/kra/goals", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual([item["id"] for item in own_goals["items"]], [goal["id"]])
        status, updated = self.call("PATCH", f"/kra/goals/{goal['id']}", {
            "progress_percent": 55, "self_comment": "Records reviewed this month.", "status": "in_progress",
        }, self.employee)
        self.assertEqual(status, 200, updated)
        self.assertEqual(updated["progress_percent"], 55)

        status, manager_goals = self.call("GET", "/kra/goals", token=self.manager)
        self.assertEqual(status, 200)
        self.assertEqual([item["id"] for item in manager_goals["items"]], [goal["id"]])
        status, reviewed = self.call("PATCH", f"/kra/goals/{goal['id']}", {
            "manager_score": 82, "manager_comment": "Good progress.", "status": "reviewed",
        }, self.manager)
        self.assertEqual(status, 200, reviewed)
        self.assertEqual(reviewed["manager_score"], 82)
        self.assertEqual(reviewed["status"], "reviewed")

    def test_yellow_card_staff_are_not_assigned_kra_goals(self):
        status, goals = self.call("GET", "/kra/goals", token=self.employee)
        self.assertEqual(status, 200)
        self.assertFalse(goals["applicable"])
        self.assertEqual(goals["items"], [])
        status, result = self.call("POST", "/kra/goals", {
            "employee_id": 3, "title": "Not for Yellow Card", "cycle": "2026", "weight_percent": 10,
        }, self.admin)
        self.assertEqual(status, 400)
        self.assertIn("Official Staff", result["error"]["message"])

    def test_kyc_stores_only_masked_metadata_and_is_not_visible_to_managers(self):
        status, error = self.call("POST", "/kyc-documents", {
            "document_type": "Aadhaar", "last_four": "123456789012",
        }, self.employee)
        self.assertEqual(status, 400)
        self.assertIn("last four", error["error"]["message"])

        status, document = self.call("POST", "/kyc-documents", {
            "document_type": "Aadhaar", "last_four": "1234", "expiry_date": "2030-12-31",
        }, self.employee)
        self.assertEqual(status, 201, document)
        self.assertEqual(document["masked_identifier"], "•••• 1234")
        self.assertNotIn("last_four", document)
        self.assertEqual(document["status"], "pending")

        status, own_docs = self.call("GET", "/kyc-documents", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual([item["id"] for item in own_docs["items"]], [document["id"]])
        status, _ = self.call("GET", "/kyc-documents", token=self.manager)
        self.assertEqual(status, 403)

        status, verified = self.call("PATCH", f"/kyc-documents/{document['id']}/verification", {
            "decision": "verified", "note": "Document sighted in person",
        }, self.admin)
        self.assertEqual(status, 200, verified)
        self.assertEqual(verified["status"], "verified")
        status, all_docs = self.call("GET", "/kyc-documents", token=self.admin)
        self.assertEqual(status, 200)
        self.assertTrue(any(item["id"] == document["id"] for item in all_docs["items"]))

    def test_confidential_grievances_are_private_from_line_managers(self):
        status, ticket = self.call("POST", "/helpdesk-tickets", {
            "category": "grievance", "title": "Confidential workplace concern",
            "description": "Please review this privately.",
        }, self.employee)
        self.assertEqual(status, 201, ticket)
        self.assertTrue(ticket["is_confidential"])
        self.assertEqual(ticket["status"], "open")

        status, manager_tickets = self.call("GET", "/helpdesk-tickets", token=self.manager)
        self.assertEqual(status, 200, manager_tickets)
        self.assertEqual(manager_tickets["items"], [])
        status, manager_view = self.call("GET", f"/helpdesk-tickets/{ticket['id']}", token=self.manager)
        self.assertEqual(status, 404, manager_view)
        status, _ = self.call("POST", "/users", {
            "email": "people.ops@example.com", "full_name": "People Ops",
            "password": "PeopleOps123!", "role_id": "people_ops",
        }, self.admin)
        self.assertEqual(status, 201)
        people_ops = self.login("people.ops@example.com", "PeopleOps123!")
        status, people_ops_view = self.call("GET", f"/helpdesk-tickets/{ticket['id']}", token=people_ops)
        self.assertEqual(status, 200, people_ops_view)

        status, denied_note = self.call("POST", f"/helpdesk-tickets/{ticket['id']}/comments", {
            "body": "Private HR note", "is_internal": True,
        }, self.employee)
        self.assertEqual(status, 403, denied_note)
        status, saved_note = self.call("POST", f"/helpdesk-tickets/{ticket['id']}/comments", {
            "body": "We received your concern.",
        }, self.admin)
        self.assertEqual(status, 201, saved_note)
        self.assertEqual(len(saved_note["comments"]), 1)
        status, updated = self.call("PATCH", f"/helpdesk-tickets/{ticket['id']}", {
            "status": "in_progress", "priority": "high",
        }, self.admin)
        self.assertEqual(status, 200, updated)
        self.assertEqual(updated["status"], "in_progress")
        status, owner_view = self.call("GET", f"/helpdesk-tickets/{ticket['id']}", token=self.employee)
        self.assertEqual(status, 200, owner_view)
        self.assertEqual(owner_view["comments"][0]["body"], "We received your concern.")

    def test_recognition_awards_are_visible_but_admin_issued(self):
        status, denied = self.call("POST", "/recognition-awards", {
            "employee_id": 3, "category": "star_worker", "period": "2026-10",
            "citation": "Excellent work.",
        }, self.manager)
        self.assertEqual(status, 403, denied)
        status, award = self.call("POST", "/recognition-awards", {
            "employee_id": 3, "category": "star_worker", "period": "2026-10",
            "citation": "For consistent quality and teamwork.",
        }, self.admin)
        self.assertEqual(status, 201, award)
        self.assertEqual(award["employee_name"], "Rajwinder Singh")
        status, wall = self.call("GET", "/recognition-awards?period=2026-10", token=self.employee)
        self.assertEqual(status, 200, wall)
        self.assertEqual(wall["items"][0]["id"], award["id"])

    def test_shift_swap_requires_target_consent_then_manager_approval(self):
        work_date = (datetime.now(timezone.utc).date() + timedelta(days=5)).isoformat()
        status, morning = self.call("POST", "/shift-templates", {
            "name": "Swap Morning", "start_time": "08:00", "end_time": "16:00",
        }, self.admin)
        self.assertEqual(status, 201, morning)
        status, evening = self.call("POST", "/shift-templates", {
            "name": "Swap Evening", "start_time": "16:00", "end_time": "23:00",
        }, self.admin)
        self.assertEqual(status, 201, evening)
        status, target_employee = self.call("POST", "/employees", {
            "employee_code": "FF-900", "first_name": "Aman", "last_name": "Test",
            "email": "aman.test@example.com", "department": "Production", "title": "Operator",
            "manager_id": 2,
        }, self.admin)
        self.assertEqual(status, 201, target_employee)
        status, _ = self.call("POST", "/users", {
            "email": "aman.test@example.com", "full_name": "Aman Test",
            "password": "AmanTest123!", "role_id": "employee", "employee_id": target_employee["id"],
        }, self.admin)
        self.assertEqual(status, 201)
        target_token = self.login("aman.test@example.com", "AmanTest123!")

        status, requester_assignment = self.call("POST", "/shift-assignments", {
            "employee_id": 3, "shift_id": morning["id"], "work_date": work_date,
        }, self.admin)
        self.assertEqual(status, 201, requester_assignment)
        status, target_assignment = self.call("POST", "/shift-assignments", {
            "employee_id": target_employee["id"], "shift_id": evening["id"], "work_date": work_date,
        }, self.admin)
        self.assertEqual(status, 201, target_assignment)
        status, swap_options = self.call("GET", f"/shift-swap-options?from={work_date}&to={work_date}", token=self.employee)
        self.assertEqual(status, 200, swap_options)
        self.assertEqual({item["employee_id"] for item in swap_options["items"]}, {3, target_employee["id"]})

        status, request = self.call("POST", "/shift-swap-requests", {
            "target_employee_id": target_employee["id"],
            "requester_assignment_id": requester_assignment["id"],
            "target_assignment_id": target_assignment["id"],
            "reason": "I can cover the evening shift.",
        }, self.employee)
        self.assertEqual(status, 201, request)
        self.assertEqual(request["status"], "pending_target")
        status, denied = self.call("POST", f"/shift-swap-requests/{request['id']}/decision", {
            "decision": "approve",
        }, self.employee)
        self.assertEqual(status, 403, denied)
        status, accepted = self.call("POST", f"/shift-swap-requests/{request['id']}/target-decision", {
            "decision": "accept",
        }, target_token)
        self.assertEqual(status, 200, accepted)
        self.assertEqual(accepted["status"], "pending_manager")
        status, approved = self.call("POST", f"/shift-swap-requests/{request['id']}/decision", {
            "decision": "approve", "note": "Approved by the team manager.",
        }, self.manager)
        self.assertEqual(status, 200, approved)
        self.assertEqual(approved["status"], "approved")
        status, roster = self.call("GET", f"/shift-assignments?from={work_date}&to={work_date}", token=self.admin)
        self.assertEqual(status, 200, roster)
        by_employee = {item["employee_id"]: item for item in roster["items"]}
        self.assertEqual(by_employee[3]["shift_id"], evening["id"])
        self.assertEqual(by_employee[target_employee["id"]]["shift_id"], morning["id"])

    def test_in_app_notification_test_is_persisted_and_user_scoped(self):
        status, created = self.call("POST", "/notifications/test", {}, self.employee)
        self.assertEqual(status, 201, created)
        self.assertIn("Device push delivery is not configured", created["body"])
        status, own_notifications = self.call("GET", "/notifications", token=self.employee)
        self.assertEqual(status, 200, own_notifications)
        self.assertEqual(own_notifications["unread_count"], 1)
        status, hidden = self.call("PATCH", f"/notifications/{created['id']}", {}, self.manager)
        self.assertEqual(status, 404, hidden)
        status, marked = self.call("PATCH", f"/notifications/{created['id']}", {}, self.employee)
        self.assertEqual(status, 200, marked)
        status, updated = self.call("GET", "/notifications", token=self.employee)
        self.assertEqual(updated["unread_count"], 0)

if __name__ == "__main__":
    unittest.main()
