# P2 · Slice 2 — Live Team on mobile

**Date:** 2026-09-27

**Status:** CI VERIFIED + MERGED — PR #9 merged as `7a53dc8e69a704cbcf2d8a5bcc6d6e253a2849f0`. Main production pipeline is running; deployment/public smoke verification pending.

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

Feature-branch results below are for the exact tested head `785d887869e19fba46606c43a29961480732226c`. Native analyzer, widget tests and both APKs were actually run by CircleCI despite the local SDK download restriction.

| Check | Result |
|---|---|
| `npm test` | **PASS — 50 tests** across `tests/team.test.ts` and `tests/team-auth.test.ts` |
| `npm run typecheck` | **PASS** |
| Next.js production compilation/static generation | **PASS with normal engines in CI [234](https://circleci.com/gh/manjotkhehra025-cloud/flavorflow-hrms/234)**; earlier local check was engine-less |
| `git diff --check` | **PASS** |
| Flutter widget tests | **PASS — 18 tests** in [235](https://circleci.com/gh/manjotkhehra025-cloud/flavorflow-hrms/235) |
| Flutter analyzer / APK | **PASS** — analyzer + debug APK [235](https://circleci.com/gh/manjotkhehra025-cloud/flavorflow-hrms/235), release APK [236](https://circleci.com/gh/manjotkhehra025-cloud/flavorflow-hrms/236) |
| Native previews / device checks | Both Flutter-rendered sample-data previews produced; physical-device/authenticated production spot-check not performed |
| Real PostgreSQL API integration | **PASS — 7 cases** against isolated PostgreSQL 16 in [233](https://circleci.com/gh/manjotkhehra025-cloud/flavorflow-hrms/233); production data was not used |
| Android CI resource helper tests | **PASS — 3 Python cases** |
| CI / deployment | All four feature-branch gates passed; [PR #9](https://github.com/manjotkhehra025-cloud/flavorflow-hrms/pull/9) merged. Main deployment still pending |

The backend tests use a mocked database, not live employees. They cover Bearer and cookie authentication (including middleware and token expiry), ADMIN/HR allow, EMPLOYEE deny, company scoping, department counts, legacy PRESENT rows, IST midnight/year boundaries, overlapping approved leave windows, all seven weekly-off values, malformed inputs, missing/cross-company employees and retryable server errors.

Flutter test cases cover counters/timings, tabs, filters, all seven weekly-off choices, pending/failed saves, employee profile navigation and return refresh, retry/pull refresh, loading/empty states, out-of-order filter responses, a narrow Punjabi layout at large text scale, date-only labels and same-origin-only photo authorization. The initial local syntax-parser check was followed by the real Flutter analyzer and execution of the full widget suite on CircleCI; no skipped/failing test was treated as a pass.

### Initial sandbox limitations (resolved for verification through CI)

- Flutter SDK bootstrap / `flutter test` failed before tests could start: TLS connection to `storage.googleapis.com` failed (`curl: (35) SSL_ERROR_SYSCALL`). The mirror and `pub.dev` were also unreachable from the sandbox.
- Prisma's normal engine download from `binaries.prisma.sh` failed. Type generation and `npm run build` were checked with a **local, engine-less Prisma client** (`PRISMA_GENERATE_NO_ENGINE=1` with local engine-path overrides). This proves compilation, not a working database connection or a deployable local bundle. No engine overrides or generated clients were committed to the source tree.
- CI retained normal Prisma generation/build and executed the new native suite. Both checks and the real PostgreSQL integration succeeded after the branch was pushed.

### Reproduce the checks

These checks have passed on CircleCI. To reproduce them in a network-enabled environment (without the sandbox engine overrides):

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

The PostgreSQL suite runs with `npm run test:integration` and a localhost-only `TEAM_TEST_DATABASE_URL` for `hrms_team_test`; CircleCI creates/migrates the disposable database.

**Remaining:** main deployment and post-deploy public smoke verification. Physical-device/authenticated production checks are not claimed by the CI tests or rendered previews.

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

### Release gate hardening

The baseline release failure was investigated: the log reports **“Gradle build daemon disappeared unexpectedly”** during `assembleRelease` (not a Firebase/keystore validation failure). Release workers now have 8 GiB, one Gradle worker and in-process Kotlin compilation to leave memory headroom for Flutter AOT/R8. Three Python tests cover resource-property validation and idempotence.

Release APK verification now runs on feature branches after the other checks, with artifacts only. Production deployment is still **main-only**, and now waits for that release gate too. This prevents merging a green debug APK while discovering a broken release only after deployment. The adjusted release build succeeded in [job 236](https://circleci.com/gh/manjotkhehra025-cloud/flavorflow-hrms/236).

The second Flutter run ([227](https://circleci.com/gh/manjotkhehra025-cloud/flavorflow-hrms/227)) rendered both preview PNGs and passed the filter interactions; its remaining race-test assertion ran before Dio dispatched its queued request. The test now explicitly waits a bounded number of frames for dispatch, asserts it happened, and then exercises the out-of-order response.

## Progress

- **2026-09-27:** Scope confirmed as parity P2 S2 (not the old punch-loop phase); two-screen mockup presented.
- **2026-09-27:** User selected **“OK — implement karo”**. Implemented the approved scope, added backend/UI tests and the CI backend test step. Local backend tests/typecheck/compile checks passed with the limitations above. **No schema migration, production write or deployment.**

- **2026-09-27:** Native suite passed all 18 tests; normal backend build, 7 real PostgreSQL cases, debug APK and release APK were green on `785d887`. User asked to continue. PR #9 was marked ready and merged only after checking the exact tested head and all four successful gates. Main deploy is being monitored on commit `7a53dc8`; the local session remains on its fixed feature branch.

## Final startup review follow-up

A pre-existing More-tab bug was identified after the first merge: `SessionStore` is a stable `Provider`, while its user flags arrive asynchronously. More did not subscribe to its notifications, and its initial-avatar expression dereferenced a null user during that loading interval. This can hide the new staff entry or produce a loading-time exception.

The follow-up (app `0.8.1+9`) listens to the existing store only inside More, uses a safe `?` avatar while loading, and preserves the same staff-only rules. It does not change the router/session architecture or backend. Three regression tests cover late ADMIN/HR flags with actual menu navigation and removing staff entries after a role change. The corrected APK must pass CI before it is the final deliverable.
