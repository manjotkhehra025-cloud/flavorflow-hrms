# P2 · Slice 2 — Live Team on mobile

**Date:** 2026-09-27

**Status:** DESIGN APPROVED + IMPLEMENTED ON BRANCH — backend tests/typecheck/compile checks passed; Flutter runtime, APK, CI and live verification pending. Not deployed.

This is **P2 slice 2 in the app–web parity plan**, not the older Flutter P2 punch-loop phase.

## Approved design

- [Mobile mockup (PNG)](../mockups/p2-s2-live-team.png)
- [Editable layout (SVG)](../mockups/p2-s2-live-team.svg)
- Web reference: `src/app/(app)/team/page.tsx` and `src/components/TeamBoard.tsx`.
- Standing requirements: [design-first delivery](../DESIGN-RULES.md) and [app–web parity](APP-WEB-PARITY.md), row 14.

The user approved this design with **“OK — implement karo”** on 2026-09-27, before application code was changed. The preview retains its original proposal caption as the approval reference.

All names, counts, dates and times in the mockup are **sample data**, not live employee records. The device frames and captions are presentation only. The application layouts are the two screens inside the frames.

## Approved scope

### Entry and access

- Add **Live Team** under **More**, alongside Employees; open a pushed `/team` route with a back button, not a new bottom-navigation tab.
- ADMIN and HR only, matching web `requireStaff`. Employee route-head/approver rights alone do not grant access.
- Enforce the restriction both in navigation and on the API; all reads and updates are scoped to the signed-in company.
- Reuse the existing navy header, emerald accents, slate background, rounded cards and English/Punjabi translation mechanism.

### Board tab

1. Four summary tiles, in web order: **Punched In / Punched Out / Not in yet / Shift done**.
2. Horizontally scrollable department chips with **All Departments** as the default.
3. Active-employee list, using the same ordering and presence calculation as web:
   - `IN`: has a check-in, or the existing attendance record is marked `PRESENT`, and has not checked out.
   - `OUT`: the preceding presence condition plus a check-out.
   - `ABSENT`: otherwise; displayed as **Not in yet**, not as a new attendance decision.
   - **Done** is a subset of checked-out employees, not a fourth mutually exclusive status. Do not add all four counters into a headcount.
   - Counters reflect the selected department.
4. Each employee row shows photo/initial fallback, status dot, name, department/shift, available in/out times, status chip and Done chip when appropriate. Unlike the narrow web layout, keep timings/status visible on the phone by wrapping into multiple lines.
5. Tapping the employee name opens the existing employee profile from slice 1.
6. Amber **weekly-off selector** offers all seven days and saves to the existing `Employee.weeklyOff` field. Disable the selector while saving; show success/failure feedback and retain the last saved value on failure.
7. Toolbar refresh and pull-to-refresh reload real API data. This slice does not add background tracking or WebSocket/push presence.

### Upcoming Leaves tab

- Display approved leave requests overlapping the next 14 days, including leave already in progress, ordered by start date as on web.
- Preserve the existing web fields: employee name, department, from/to dates, total request days and leave type.
- Show the total request count in the tab badge; do not confuse it with days or unique employees.
- This tab is company-wide, like web: no department chips or board counters here.
- No apply/approve/edit controls on this read-only list.

### Required non-happy-path states

- Initial loading, refresh in progress, empty department and no upcoming approved leave.
- Network/API failure with a working retry control; do not present stale data as freshly loaded.
- Unauthorized/forbidden access, expired session and failed weekly-off save.
- Long names/departments, smaller screens, Punjabi text and large text sizes without clipping.
- Avoid stale responses overwriting newer department selections; refresh on returning from a related screen when needed.

## Implementation

No schema migration was added and no live data was changed during development. Only an explicit weekly-off action updates `Employee.weeklyOff`.

- Shared service: `src/lib/team.ts`; used by the web page, server action and both API routes.
- Flutter: `features/team/team_screen.dart` and `team_models.dart`; More entry, `/team` access guard, Punjabi strings and app version `0.8.0+8`.
- Photo URLs support relative and absolute addresses. Bearer headers are sent only to same-origin photos, never external legacy URLs.
- Reads are cancelled/versioned when filters change. Saves retain the previous value until success; reads are blocked during a save to prevent an older snapshot undoing the saved value.
- Foreground resume and return from an employee profile refresh the board.
- The shared board now uses the plant's explicit **Asia/Kolkata** day/times, including before 05:30 IST, rather than the old web page's UTC day slice. Attendance records and punch policy are not rewritten.

- Added staff-only `GET /api/team?dept=` returning board rows, filtered counters, departments and upcoming approved leaves.
- Added staff-only `PATCH /api/team/weekly-off` taking `{ employeeId, weeklyOff }`.
  - Accept only integer days `0..6` (Sunday through Saturday).
  - Reject invalid input; never silently convert invalid input to Sunday.
  - Return 401/403 for unauthenticated/non-staff callers and 404 for employees outside the caller's company or not found.
- Shared presence/date/count rules with web rather than introducing a second definition of attendance. The web weekly-off selector also restores the previous value on failure and shows save feedback.
- Out of scope: staff roster editing (P2 slice 3), employee creation and attendance-policy changes.

### API response contract

`GET /api/team?dept=` returns `date`, `asOf`, `timeZone`, `activeDept`, `rows`, `counts`, `departments` and company-wide `leaves`. Punch times are formatted in IST for both clients; leave dates remain ISO date-only strings. Responses use `Cache-Control: private, no-store`.

`PATCH /api/team/weekly-off` returns `{ employeeId, weeklyOff }` after a successful write. It invalidates the web team, employee profile and roster paths. Error responses are JSON with 400/401/403/404/500 statuses as appropriate.

## Verification

| Check | Result |
|---|---|
| `npm test` | **PASS — 50 tests** across `tests/team.test.ts` and `tests/team-auth.test.ts` |
| `npm run typecheck` | **PASS** |
| Next.js production compilation/static generation | **PASS with the sandbox-only Prisma caveat below** |
| `git diff --check` | **PASS** |
| Flutter widget tests | Added in `test/team_screen_test.dart`; **not executed** (SDK download blocked) |
| Flutter analyzer / APK / device screenshot comparison | **Pending** (SDK unavailable) |
| Real PostgreSQL API integration / production verification | **Not performed** |
| CI / deployment | Feature-branch verification queued next; deployment remains gated |

The backend tests use a mocked database, not live employees. They cover Bearer and cookie authentication (including middleware and token expiry), ADMIN/HR allow, EMPLOYEE deny, company scoping, department counts, legacy PRESENT rows, IST midnight/year boundaries, overlapping approved leave windows, all seven weekly-off values, malformed inputs, missing/cross-company employees and retryable server errors.

Flutter test cases cover counters/timings, tabs, filters, all seven weekly-off choices, pending/failed saves, employee profile navigation and return refresh, retry/pull refresh, loading/empty states, out-of-order filter responses, a narrow Punjabi layout at large text scale, date-only labels and same-origin-only photo authorization. Changed Dart files passed a syntax-parser check; **that is not a substitute for the Flutter analyzer or executing these tests**.

### Sandbox limitations

- Flutter SDK bootstrap / `flutter test` failed before tests could start: TLS connection to `storage.googleapis.com` failed (`curl: (35) SSL_ERROR_SYSCALL`). The mirror and `pub.dev` were also unreachable from the sandbox.
- Prisma's normal engine download from `binaries.prisma.sh` failed. Type generation and `npm run build` were checked with a **local, engine-less Prisma client** (`PRISMA_GENERATE_NO_ENGINE=1` with local engine-path overrides). This proves compilation, not a working database connection or a deployable local bundle. No engine overrides or generated clients were committed to the source tree.
- CI retains normal Prisma generation/build and now runs `npm test`; the existing Flutter analyze/test step will pick up the new UI suite when the branch is pushed.

### Remaining release gate

In a network-enabled environment, run the normal checks (without the sandbox engine overrides):

```sh
npm ci
npx prisma generate
npm test
npm run typecheck
npm run build

cd apps/hrmate_flutter
flutter pub get
flutter analyze --no-fatal-infos
flutter test
# Android wrapper/APK preparation is already handled by CircleCI.
```

Then verify the API against PostgreSQL, compare the native UI to the approved mockup, confirm every control on device, and use the existing push → CircleCI → deployment → live-verification pipeline. **Do not mark this slice shipped until these gates pass.**

## Remote verification continuation

The sandbox still cannot download the Flutter/Prisma engines. Verification is moving to the **existing CircleCI pipeline**, on the feature branch; pushing this branch cannot deploy production.

- Added `npm run test:integration` and an isolated PostgreSQL 16 `test-team-db` job. The integration runner refuses any host other than localhost and any database name other than `hrms_team_test`. It uses a real Prisma client and real signed Bearer sessions; only Next cache invalidation is stubbed.
- Fixtures are uniquely named per run and cleaned up; no production database URL, existing company or real employee is used.
- Production deploy now waits for backend build/tests, database integration and Flutter checks. Flutter logs are retained as CI artifacts for diagnosing failures.
- Baseline `main` at `de743d4` already had a failing `release-flutter` job ([217](https://circleci.com/gh/manjotkhehra025-cloud/flavorflow-hrms/217)); its build, deploy and debug-Flutter jobs succeeded. This existing release failure is tracked separately from the P2 S2 checks.

### First CI run (PR #9)

- [Backend build 224](https://circleci.com/gh/manjotkhehra025-cloud/flavorflow-hrms/224): passed with normal Prisma engines, all 50 unit/auth tests and typecheck.
- [Database integration 223](https://circleci.com/gh/manjotkhehra025-cloud/flavorflow-hrms/223): passed against isolated PostgreSQL 16 (seven integration cases).
- [Flutter 225](https://circleci.com/gh/manjotkhehra025-cloud/flavorflow-hrms/225): analyzer passed; two widget cases failed because they tapped an off-screen horizontal chip without scrolling. The harness now scrolls only the horizontal strip, treats missed taps as fatal, and asserts that the delayed request was actually made.
- Added optional CI render artifacts of both approved layouts using sample data and a checked-in OFL-licensed Roboto test font. Ordinary regression tests retain the stricter Ahem test font. These are Flutter-rendered previews, not live-device screenshots.

## Progress

- **2026-09-27:** Scope confirmed as parity P2 S2 (not the old punch-loop phase); two-screen mockup presented.
- **2026-09-27:** User selected **“OK — implement karo”**. Implemented the approved scope, added backend/UI tests and the CI backend test step. Local backend tests/typecheck/compile checks passed with the limitations above. **No schema migration, production write or deployment.**
