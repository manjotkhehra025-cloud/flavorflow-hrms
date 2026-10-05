# FlavorFlow HRMS architecture

## Product and runtime

- **Client:** Flutter/Dart, rendered with native Android/iOS Flutter embeddings. No HTML, WebView, PWA, or browser-based UI.
- **API:** JSON REST under `/api/v1`, implemented with Python's standard library for a zero-dependency local deployment.
- **Persistence:** SQLite with foreign keys, explicit schema, indexes, seeded catalog, and application-level password hashing. The schema uses portable relational types and can be migrated to PostgreSQL.
- **Identity:** PBKDF2-SHA256 password hashes; random opaque bearer tokens are only stored as SHA-256 digests and expire after seven days. The Flutter app stores the bearer token in native secure storage.
- **Authorization:** The API owns the permission catalog and role assignments. Permission definitions, role grants, and user-role links are persisted in `permissions`, `role_permissions`, and `user_roles`. The app gets its catalog from `GET /roles` and effective permission keys from `GET /auth/me`; API guards remain authoritative.

## Route map

| Native app route | Screen | Capability gate |
|---|---|---|
| `/sign-in` | Sign in | Public |
| `/dashboard` | Overview, metrics, recent activity | `dashboard.read` |
| `/employees` | Employee directory and profile editor | `employees.read`, `employees.read.team`, or `employees.read.self` |
| `/employees/new` | Create employee | `employees.create` |
| `/employees/:id` | Employee details/edit | Read scope; edit requires `employees.update` |
| `/attendance` | GPS punch in/out and current shift | `attendance.punch` or an attendance read capability |
| `/attendance/history` | Attendance history | `attendance.read`, `attendance.read.team`, or `attendance.read.self` |
| `/shifts` | Date-based shift roster, templates, and employee assignments | `shifts.read`, `shifts.read.team`, `shifts.read.self`, or `shifts.manage` |
| `/locations` | Work locations and geofence editor | `locations.read`; writes require `locations.create`/`locations.update` |
| `/calendar` | Company holiday calendar | `calendar.read`; writes require `calendar.manage` |
| `/leave` | My/team/all leave requests and request form | Leave read scope or `leave.create` |
| `/leave-policy` | Editable leave-year, day-counting, proration, carry-over, and type allowances | `leave.policy.manage` |
| `/leave/new` | Submit leave request | `leave.create` |
| `/leave/:id` | Leave request details | Leave read scope |
| `/approvals` | Pending team/global leave decisions | `leave.approve` |
| `/admin/users` | User accounts and role assignment | `users.read`; writes additionally require `users.create`/`users.update` |
| `/admin/roles` | Role and permission editor | `rbac.read`; edits require `rbac.update` |
| `/admin/audit` | Audit timeline | `audit.read` |
| `/settings` | Session and app settings | Authenticated |

The Flutter shell filters navigation and controls buttons from the session's API-supplied capabilities. These client checks are UX only; each protected API operation repeats the permission check server-side.

## Database schema

The executable schema is `backend/schema.sql`.

| Table | Purpose / key relationships |
|---|---|
| `users` | Login identity, PBKDF2 digest, display name and active flag. |
| `employees` | Employee directory/profile; optional `user_id`; self-reference through `manager_id`. |
| `sessions` | Hashed opaque API bearer token, expiry, and user FK. |
| `biometric_login_tokens` | Hashed, rotating device credential used only after local biometric verification; expires 30 days after issue/use and cascades with its user. |
| `roles` | Named roles; `super_admin` is the protected system role. |
| `permissions` | Server-owned permission catalog: stable key, module, action and label. |
| `user_roles` | Many-to-many user/role assignments. |
| `role_permissions` | Many-to-many role/permission grants. |
| `work_locations` | Active work sites, WGS84 coordinates, radius in metres and timezone. |
| `attendance_records` | Punch-in/out timestamps, GPS coordinates, accuracy, geofence distance and work-site reference. |
| `shift_templates` | Admin-managed shift names, local start/end times, break duration, and active state. |
| `shift_assignments` | Date-specific employee/template/work-site assignments with soft deactivation and assigning user. |
| `leave_types` | Active leave categories, paid state, and admin-configured annual allowance. Demo seed allowances start at zero until configured. |
| `leave_policy` | Singleton editable leave-period start month, weekend counting, new-hire proration, carry-over switch/cap, and audit metadata. |
| `leave_requests` | Employee/date/reason/status and approval decision metadata. |
| `holidays` | HR-managed company holiday dates and descriptions; no company dates are seeded. |
| `audit_logs` | Actor, action, entity, JSON details, remote address and UTC timestamp. |

Audit rows are appended by mutating API operations; passwords and bearer tokens are never included in audit details. Attendance records retain the GPS coordinate and calculated distance at both punch events. New installations start with a generic January period, weekends counted, no proration/carry-over, and zero-day sample allowances; HR Admin can configure these values before applying a company policy. Holiday dates, shift templates, and employee assignments are not seeded. Balances recalculate using the currently saved policy, including the prior period used to determine one-period carry-over.

## Seed permission matrix

The table describes the initial editable grants. “Self” and “team” scope are also checked by employee/manager relationships on the server, not just by the grant name.

| Role | Employees | Attendance | Locations | Calendar | Shifts | Leave / policy | Users / RBAC | Audit |
|---|---|---|---|---|---|---|---|---|
| **Super Admin** | All actions and scopes | All actions and scopes | All actions | Read/manage | All actions and scopes | All actions, including policy | All actions | Read |
| **HR Admin** | Read/create/update all | Read/manage all | Read/create/update | Read/manage | Read/manage all | Read/manage/create/approve and configure policy | Read users | Read |
| **Manager** | Read direct team | Read direct team | Read | Read | Read own and direct team | Read own/team; create; approve direct team | None | None |
| **Employee** | Read self | Punch; read self | Read | Read | Read own roster | Read self; create | None | None |

Super Admin effective access is the complete live permission catalog even if catalog rows are added after deployment. Its role grants are kept in sync at startup, and edits to its role are rejected. Other role grants can be edited in the native app and take effect on the next API request/session permission refresh.

## API contract

Base URL: `http://<host>:8080/api/v1` (HTTPS in production). Except health/login and the device-credential biometric exchange/revoke endpoints, send `Authorization: Bearer <token>`. Requests/responses use JSON; list endpoints return `{"items": [...], "total": n}` unless noted. Errors return `{"error":{"message":"...","details":...}}` with an HTTP status. Dates use `YYYY-MM-DD`; API timestamps are UTC ISO-8601.

| Method + path | Required capability | Request / response summary |
|---|---|---|
| `GET /` | Public | API base status (`/api/v1` or `/api/v1/`); points to the health check. |
| `GET /health` | Public | Service status. |
| `POST /auth/login` | Public | `{email,password,enable_biometrics?,replace_biometric_token?}` → `{token,user,biometric_token?}`. The optional device token is issued only on password-authenticated opt-in. |
| `POST /auth/biometric-login` | Device credential | `{biometric_token,previous_session_token?}` → a new API token plus rotated biometric token; the app calls this only after local device authentication. |
| `POST /auth/biometric-register` | Authenticated | Issue a device token to migrate a still-valid biometric session from the earlier app version. |
| `POST /auth/biometric-revoke` | Device credential | Idempotently revoke the caller-supplied device token on explicit sign-out. |
| `POST /auth/logout` | Authenticated | Revoke current API bearer token; inactivity sign-out deliberately preserves the separate device credential. |
| `GET /auth/me` | Authenticated | Profile, role ids/names, employee id and effective permission keys. |
| `GET /dashboard` | `dashboard.read` | Scope-filtered metrics, caller's open punch and own shift, next holiday, and self leave balance calculated from the configured period/day-counting/proration/carry-over policy. |
| `GET /employees?q=` | Employee read scope | Search/list with self/team scope applied. |
| `POST /employees` | `employees.create` | Employee profile → created record. |
| `GET /employees/{id}` | Employee read scope | One employee profile. |
| `PATCH /employees/{id}` | `employees.update` | Partial profile fields. |
| `DELETE /employees/{id}` | `employees.delete` | Soft-deactivate the employee; blocked while there is an open punch. |
| `GET /locations` | `locations.read` | Active and inactive work sites. |
| `POST /locations` | `locations.create` | Name/address/latitude/longitude/radius/timezone. |
| `GET /locations/{id}` | `locations.read` | One work site. |
| `PATCH /locations/{id}` | `locations.update` | Partial site/geofence update. |
| `DELETE /locations/{id}` | `locations.delete` | Disable a site for new punches; an open shift can still check out there. |
| `GET /holidays` | `calendar.read` | Active company holidays, ordered by date. |
| `POST /holidays` | `calendar.manage` | `{name,holiday_date,description?}`. |
| `GET /holidays/{id}` | `calendar.read` | One company holiday. |
| `PATCH /holidays/{id}` | `calendar.manage` | Update a holiday name, date, description, or active state. |
| `DELETE /holidays/{id}` | `calendar.manage` | Soft-disable a holiday and keep its audit trail. |
| `GET /shift-templates` | Shift read scope | Read shift templates for the roster; inactive templates remain visible to administrators. |
| `POST /shift-templates` | `shifts.manage` | `{name,start_time,end_time,break_minutes?}`; times use 24-hour `HH:MM`. |
| `PATCH /shift-templates/{id}` | `shifts.manage` | Update a shift name, time range, break, or active state. |
| `DELETE /shift-templates/{id}` | `shifts.manage` | Soft-disable a template for new assignments. |
| `GET /shift-assignments?date=&from=&to=` | Shift read scope | Date-filtered assignments; global/team/self scope is enforced by the API. |
| `POST /shift-assignments` | `shifts.manage` | `{employee_id,shift_id,work_date,work_location_id?}`; one active assignment per employee/date. |
| `DELETE /shift-assignments/{id}` | `shifts.manage` | Soft-disable a date-specific assignment. |
| `POST /attendance/punch-in` | `attendance.punch` | `{latitude,longitude,accuracy_m?}`; server picks nearest active geofence and rejects out-of-range punches. |
| `POST /attendance/punch-out` | `attendance.punch` | Same GPS fields; server checks the assigned work-site geofence. |
| `GET /attendance?date=&employee_id=&limit=` | Attendance read/punch scope | History, own open record and applicable self/team/all scope. |
| `GET /leave-types` | Leave read/create/approve scope | Active leave categories. |
| `GET /leave-policy` | `leave.policy.manage` | Current configurable period rules and active leave-type allowances. |
| `PATCH /leave-policy` | `leave.policy.manage` | Set period start month, weekend counting, new-hire proration, carry-over and cap, and annual allowance values. |
| `GET /leave-requests?status=` | Leave read/create/approve scope | Own/team/all scope based on DB grants and reporting line. |
| `POST /leave-requests` | `leave.create` | `{leave_type_id,start_date,end_date,reason}`. |
| `GET /leave-requests/{id}` | Leave read scope | One request. |
| `PATCH /leave-requests/{id}` | Own pending request | Edit reason/dates/type. |
| `POST /leave-requests/{id}/decision` | `leave.approve` | `{decision:"approved"|"rejected",note?}`; manager must own the reporting line unless granted `leave.manage`. |
| `GET /users` | `users.read` | User accounts, assigned role names, and role names for the account editor. |
| `POST /users` | `users.create` | `{email,full_name,password,role_id,employee_id?}`. |
| `PATCH /users/{id}` | `users.update` | Edit account active state/name/role ids. Last active Super Admin cannot be removed or disabled. |
| `GET /roles` | `rbac.read` | Roles plus live permission catalog and grants. |
| `POST /roles` | `rbac.update` | `{name,description?,id?}`. |
| `PATCH /roles/{id}/permissions` | `rbac.update` | `{permissions:[permission_key,...]}`; catalog keys are validated; Super Admin is protected. |
| `GET /audit-logs?limit=` | `audit.read` | Most recent audit events. |

## Initial implementation plan

1. Create the native Flutter project shell, responsive premium design system, sign-in/session restore, route permissions, and native platform configuration.
2. Implement API bootstrap, SQLite schema/seed data, authentication, database-driven roles/permissions, and audit events.
3. Add employee profiles and user/role administration.
4. Add work locations/geofences, native runtime GPS permissions, server-side punch validation, and attendance history.
5. Add leave requests, manager/HR approvals, dynamic role editor, and audit timeline.
6. Add backend and Flutter tests, then run Flutter analyze/test and Android native build checks where the toolchain is available.

## Deployment notes and limitations

The included API is a useful local/dev foundation, not a hardened public HR platform: it does not yet provide refresh tokens, password reset/MFA, rate limiting, configurable retention, encryption-at-rest key management, or an enterprise database migration runner. GPS is checked against reported device coordinates and is not tamper-proof. Production rollout should add those controls, verified TLS, trusted admin provisioning and privacy/retention policy.
