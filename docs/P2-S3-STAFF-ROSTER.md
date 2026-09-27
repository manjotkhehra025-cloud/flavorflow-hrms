# P2 · Slice 3 — Staff Duty Roster on mobile

**Date:** 2026-09-27

**Status:** DESIGN APPROVED + IMPLEMENTED ON BRANCH — backend tests/typecheck pending in this environment; Flutter runtime, APK, CI and live verification pending. Not deployed.

This is **P2 slice 3 in the app–web parity plan** (row 20 staff roster board). Employee **My Roster** (row 7) is unchanged.

## Approved design

- [Mobile mockup (PNG)](../mockups/p2-s3-staff-roster.png)
- [Editable layout (SVG)](../mockups/p2-s3-staff-roster.svg)
- Web reference: `src/app/(app)/roster/page.tsx` and `src/app/(app)/roster/RosterGrid.tsx`.
- Standing requirements: [design-first delivery](../DESIGN-RULES.md) and [app–web parity](APP-WEB-PARITY.md), row 20.

The user approved this design with **“OK — implement karo”** on 2026-09-27, before application code was changed.

All names, counts, dates and times in the mockup are **sample data**, not live employee records.

## Approved scope

### Entry and access

- Add **Duty Roster** under **More**, alongside Live Team; open a pushed `/duty-roster` route with a back button, not a new bottom-navigation tab.
- Keep **My Roster** for every signed-in employee (self week + swap request).
- ADMIN and HR only for the staff board, matching web `requireStaff`. Employee route-head/approver rights alone do not grant access.
- Enforce the restriction both in navigation and on the API; all reads and updates are scoped to the signed-in company.
- Reuse the existing navy header, emerald accents, slate background, rounded cards and English/Punjabi translation mechanism.

### Roster Grid tab

1. Week navigator (previous / next) showing `dd–dd Month`, matching web.
2. Horizontally scrollable department chips with **All Departments** as the default (client-side filter; web groups by department).
3. Seven weekday headers; **today** uses the plant **Asia/Kolkata** date.
4. Each active employee card shows code, department, default shift, and seven tappable day chips:
   - **Def** — no `ShiftAssignment` row (uses the employee’s default shift). Sunday is **not** auto-off on the staff board.
   - Shift override — emerald chip with a short label + start time.
   - **OFF** — explicit `isOff` assignment.
5. Tap a chip → sheet: Default / every company shift / OFF. Dirty cells stay until Save or until they match the server again.
6. Navy **Save roster · N cells** bar sends only dirty cells. Disable refresh/week changes while saving; keep the dirty values on failure.
7. Cap of 120 active employees, same as web.

### Shift Swaps tab

- Company-wide, like web: no department chips here.
- Request form when the signed-in staff user has a linked employee profile (`POST /api/roster`).
- Pending queue with **Approve** / **Reject** (`POST /api/approvals/decide`, same routing as web).
- History chips for decided rows.
- Tab badge is the pending count from the current 30-row window, matching web `take: 30`.

### Required non-happy-path states

- Initial loading, refresh in progress, empty department and no pending swaps.
- Network/API failure with a working retry control; do not present stale data as freshly loaded.
- Unauthorized/forbidden access, expired session and failed roster save.
- Long names/departments, smaller screens, Punjabi text and large text sizes without clipping.
- Avoid stale week responses overwriting a newer week selection.

## Implementation

No schema migration was added and no live data was changed during development. Only an explicit Save writes `ShiftAssignment` rows.

- Shared service: `src/lib/roster.ts`; used by the web grid, server action and `GET`/`PATCH /api/roster/staff`.
- Flutter: `features/roster/staff_roster_screen.dart`; More entry, `/duty-roster` access guard, Punjabi strings and app version `0.9.0+9`.
- Reads are cancelled/versioned when the week changes. Saves retain dirty cells until success.
- The shared board now uses the plant’s explicit **Asia/Kolkata** week, including before 05:30 IST, rather than the old web page’s UTC `new Date()` slice. Assignment dates remain date-only UTC keys. Payroll/attendance policy is not rewritten.

### API response contract

`GET /api/roster/staff?w=` returns `timeZone`, `asOf`, `weekStart`, `weekEnd`, `prevW`, `nextW`, `today`, `days`, `departments`, `shifts`, `employees` (with per-day `cells`), `swaps`, `peers`, `myEmployeeId`, `canSwap` and `pendingSwapCount`. Responses use `Cache-Control: private, no-store`.

`PATCH /api/roster/staff` takes `{ entries: [{ employeeId, date, shiftId, isOff }] }` and returns `{ saved }`.

- Accept only real `YYYY-MM-DD` dates and boolean `isOff`.
- Unknown `shiftId` is **400**, not silently converted to default.
- Missing/cross-company employees are **404**.
- `isOff: true` stores `shiftId: null`. Restoring Default deletes the assignment row.
- Empty `entries` is a no-op success.

Error responses are JSON with 400/401/403/404/500 statuses as appropriate.

## Verification

See the test files `tests/roster.test.ts`, `tests/integration/roster.test.ts` and `apps/hrmate_flutter/test/staff_roster_test.dart`.

**Do not mark this slice shipped until CI, device comparison against the approved mockup, and live verification pass.**
