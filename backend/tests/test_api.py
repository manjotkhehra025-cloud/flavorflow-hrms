import tempfile
import unittest
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
        leave_type = types["items"][0]["id"]
        _, employee_request = self.call("POST", "/leave-requests", {
            "leave_type_id": leave_type, "start_date": "2026-11-02", "end_date": "2026-11-02", "reason": "Personal day",
        }, self.employee)
        _, admin_request = self.call("POST", "/leave-requests", {
            "leave_type_id": leave_type, "start_date": "2026-11-05", "end_date": "2026-11-05", "reason": "Admin leave",
        }, self.admin)

        status, employee_dashboard = self.call("GET", "/dashboard", token=self.employee)
        self.assertEqual(status, 200)
        self.assertEqual(employee_dashboard["stats"]["active_employees"], 1)
        self.assertEqual(employee_dashboard["stats"]["pending_leave"], 1)
        self.assertEqual([item["id"] for item in employee_dashboard["pending_requests"]], [employee_request["id"]])

        status, manager_dashboard = self.call("GET", "/dashboard", token=self.manager)
        self.assertEqual(status, 200)
        self.assertEqual(manager_dashboard["stats"]["pending_leave"], 1)
        self.assertEqual([item["id"] for item in manager_dashboard["pending_requests"]], [employee_request["id"]])

        status, admin_dashboard = self.call("GET", "/dashboard", token=self.admin)
        self.assertEqual(status, 200)
        self.assertEqual(admin_dashboard["stats"]["active_employees"], 5)
        self.assertEqual(admin_dashboard["stats"]["pending_leave"], 2)
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


if __name__ == "__main__":
    unittest.main()
