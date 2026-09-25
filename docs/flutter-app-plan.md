# HRMate — Flutter Native App Plan

**Status**: PLAN — waits for phase-wise mockup approval (mockup → approval → implement).
**Why Flutter**: one codebase, truly native performance, off-screen canvas for the
premium visual language, offline punch queue, camera/GPS/biometric native access —
the Capacitor APK remains the interim app until this ships.

---

## 1. High-level architecture

```
hrms/                        (existing Next.js repo — stays the single source of truth)
└── apps/
    └── hrmate_flutter/      (NEW Flutter workspace, same git repo)
        ├── lib/
        │   ├── core/        theme, tokens, router, dio client, secure storage, i18n
        │   └── features/
        │       ├── auth/            login, force-change-password, biometric unlock (P6)
        │       ├── home/            dashboard, live shift timer, alerts feed
        │       ├── punch/           GPS + selfie punch, offline queue, history
        │       ├── leaves/          balances, apply, my requests
        │       ├── approvals/       routed inbox (SM / AGM / super admin), decide
        │       ├── requests/        manual punch-in/out, OT, gate pass, shift swap
        │       ├── idcard/          digital ID, gate-pass QR (display + scan-verify)
        │       ├── roster/          staff view + edit (staff-only)
        │       ├── social/          wall, post, like, comment
        │       ├── payslip/         PDF slip viewer/download
        │       ├── people/          directory + permissions admin (super admin toggle UI)
        │       └── helpdesk/        tickets + chat
        ├── assets/          logo (new SVG), fonts, lang files
        └── test/
```

**State management**: Riverpod (providers per feature, `@riverpod` codegen).
**Networking**: `dio` + interceptors (bearer token auto-attach, 401 → re-login, auto
retry with idempotency key on POST punch).
**Secure storage**: `flutter_secure_storage` (token), shared_prefs (locale, last punch cache).
**Local DB**: `drift` (SQLite) for offline punch queue + attendance cache.
**Navigation**: `go_router` with a typed route guard:
```
splash → (no token) /login → (mustChangePassword) /set-password → /home
```
mirroring the web gate 1:1.

## 2. Design system (mockups come from this)

| Token | Value |
|---|---|
| Primary emerald | `#10d9a0` → `#0369a1` gradient (new logo plate) |
| Ink / dark blocks | `#0a1628` |
| Accent honey | `#f59e0b` |
| Surface | slate-50 cards, 16–24px radius, soft shadows |
| Type | Inter/Poppins (Latin) + Noto Sans Gurmukhi (Punjabi) |
| Motion | 200–250ms ease, punch button "breathing" ring, success haptic |

Every screen = **one mobile mockup image → your approval → code** (unchanged rule).

## 3. Backend API — what's ready, what's added (Phase 0)

Ready today: `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/auth/me`,
`POST /api/attendance` (+ `selfie` multipart), `GET /api/leaves`, payroll + report reads.

**To add in Phase 0** (small Next.js work, all token-auth like existing):
1. `GET /api/auth/me` → include `mustChangePassword` + the 6 permission booleans (so the
   app hides locked features exactly like the web). + `POST /api/auth/set-password`.
2. `GET /api/approvals` (route-scoped list — same `approverScope` logic extracted from
   server lib into a shared module) + `POST /api/approvals/decide` (`{kind,id,action}`).
3. `GET/POST /api/gate-pass`, `GET/POST /api/swaps`, `GET/POST /api/social` (+like/comment).
4. `GET /api/roster` (+ staff edit endpoint parity with the web action).
5. `GET /api/payslips` (+ signed PDF URL), `GET /api/holidays`, helpdesk CRUD.
6. `POST /api/push-token` (FCM token registry — used in Phase 6).

Everything else (business rules: yellow-card EL, route groups, geo-fence, OT math,
permission gates) stays server-side — the app is a thin, fast client. **Single
tenant, single company, Punjabi + English from day 1** (unchanged constraints).

## 4. Feature parity map (web → app)

| Web | App screen | Phase |
|---|---|---|
| /login, /set-password | Login + force-change | 1 |
| /dashboard punch (GPS+selfie, live timer) | Home hero punch | 1–2 |
| /attendance history, manual punch + OT | Attendance + Requests sheets | 2 |
| /leaves (balances + apply) | My Leaves | 3 |
| /approvals (leaved/gate/punch/swap, scoped to SM/AGM/admin) | Approvals inbox + decide | 3 |
| /idcard + gate pass QR + verify | ID & Gate Pass | 4 |
| /roster | Roster (week grid) | 4 |
| /social | Social Wall | 5 |
| /payslips | Payslip viewer | 5 |
| /employees (+ permission toggles), /departments | People (staff) | 5 |
| /helpdesk | Helpdesk | 5 |
| /team live presence, alerts bell | Alerts flyout (REST pull → FCM in P6) | 6 |

Offline-first punch: GPS fix + photo captured → queued in SQLite if network dies →
sync banner, auto-retry with expo-style backoff; server still enforces the geo-fence.

## 5. Phases, mocks & estimates (solo pace)

| Phase | Deliverable | Mockups needed | Effort |
|---|---|---|---|
| **P0** API hardening | endpoints above + Postman/curl verified | – | 3–4 days |
| **P1** Foundation | Flutter scaffold, theme/tokens, router+guards, i18n runtime (reuse web `en.json` → `app_pa.arb`), splash/app icons from **new logo**, login + set-password on device | splash, login, set-password | 3 days |
| **P2** Punch loop | home + live timer, GPS+selfie punch, offline queue, history | home (idle), home (punching), selfie preview, history | 1 week |
| **P3** Leaves & Approvals | balances, apply, inbox unified queue, decide w/ toast, scoped to your group | inbox, decide card, apply form | 4–5 days |
| **P4** ID / Gate / Roster | digital card share, QR display + **scan-verify gatekeeper mode**, swaps | id card, qr sheet, roster grid | 4 days |
| **P5** Social, Payslip, People, Helpdesk, Holidays | posting, Likes/comments, slip PDF, super-admin permission toggles on device | wall composer, slip view, toggle card | 4 days |
| **P6** Polish & Ship | FCM push (approval arrived / decided), biometric quick-unlock, Crashlytics, CI release APK (keystore in CircleCI env), internal distribution | – | 5–6 days |

**Total ≈ 4.5–5 working weeks** from P0 start, each phase demoed on device before the
next begins.

## 6. CI / delivery

- New CircleCI job `build-flutter` on `cimg/android` + pinned Flutter SDK install
  (fast: `flutter pub get` + `flutter build apk --debug/--release`).
- Debug APK after every merge (Artifacts tab, like today). Release AAB when Play
  listing is ready (keystore base64 → CI env, never in repo).
- Same repo `main`; Flutter app does **not** deploy the web app (paths-filtered
  pipelines so app pushes don't rebuild the VPS).

## 7. Risks & notes

- **Push approvals**: FCM needs `google-services.json` from Firebase console (2 min,
  do together at P6 start).
- **Selfie upload** compressed client-side (max ~600KB) → keeps punch < 2s on 3G.
- **Background location** for live presence — discuss policy at P6 (Android Play
  review is strict; recommend foreground-only pings + FCM instead).
- **Old APK**: Capacitor build stays downloadable until P2 lands; from P3 on the
  Flutter debug APK replaces it for your daily use.
- **Branding**: splash + launcher + in-app header all use the new HRMate logo
  (`public/hrmate-logo.svg` → exported PNGs).

## 8. What I need from you to start P0

1. ✅ This plan approved (or edits — diagonal Changelog below).
2. Firebase project name preference (now or at P6).
3. First mockup batch (P1): I'll generate **Splash, Login, Set-Password** next —
   approve those three and P0+P1 coding begins.

— Changelog: v1 initial plan (2026-09-24)

---

## Progress log

**2026-09-24** — P1 mockups APPROVED (mockups/p1-splash.png, p1-login.png, p1-setpass.png).

**P0 DONE + live-verified:**
- `GET /api/auth/me` — mustChangePassword, locale, approveScope (canApprove),
  permission booleans (app hides locked features exactly like web).
- `POST /api/auth/set-password` — self-chosen first password, old credential dies.
- `GET /api/approvals` — routed inbox (SM→group A, AGM→group B, admin→ALL).
- `POST /api/approvals/decide` {kind,id,action} — route-checked (cross-route 403, replay 404).
- Tested live: SM sees only Production requests, AGM only Mechanical, cross-decide 403,
  successful decide flips status, set-password full circle (flag→set→old login 401→new login 200).

**2026-09-25** — **P5 DONE** (mockups p5-social, p5-payslip, p5-holidays, p5-toggles).

API (all Bearer-token or web-cookie auth, shared helper `src/lib/api-auth.ts`):
- `GET/POST /api/social` (feed paged by `?before=`, `canPost` flag) · `DELETE /api/social/:id`
  (author or staff) · `POST /api/social/:id/like` (toggle) · `GET/POST /api/social/:id/comments`.
- `GET /api/payslips` (LOCKED only, `canViewPayslip`-gated) · `GET /api/payslips/:rowId`
  (earning/deduction lines + totals) · `POST /api/payslips/:rowId/share` (public token link → printable / PDF).
- `GET /api/holidays?year=` (+ next holiday, days left) · `POST` / `DELETE` for ADMIN/HR.
- `GET/POST /api/helpdesk` (mine, or `scope=inbox&status=` for staff) · `GET/POST/PATCH /api/helpdesk/:id`
  (thread + seen-marking, reply, staff status change).
- `GET /api/permissions?q=` · `GET/PUT /api/permissions/:employeeId` {key, allowed} — ADMIN only.

Flutter: `features/social`, `features/payslip`, `features/holidays`, `features/helpdesk`
(list + thread), `features/people` (permission picker + toggles); More tab entries; PA strings.
CI: `build-flutter` now also runs on branches so PRs get the gate before merge.

**2026-09-25** — **Pre-P6 fixes** (found while wiring P6):
- `middleware.ts` only read the `ff_session` cookie, so every Flutter call
  (Bearer token only) got a 401 before reaching the route. It now accepts
  `Authorization: Bearer` too. Also made public: `/share/payslip/*` (the P5 WhatsApp
  payslip link was bouncing to /login), static brand files (login-page logo), `/api/auth/logout`.
- Approving a manual punch from the app (`/api/approvals/decide`) only flipped the status —
  the attendance row was never written (the web action did it). One shared
  `src/lib/decide.ts` now handles both, so web and app behave the same.
- Bell alerts: SM/AGM heads (role EMPLOYEE) never saw their routed queue and ADMIN saw
  every route; now scoped by `approverScope` (same as the Approvals inbox), plus swap decisions.
- Flutter: a 401 now signs the phone out (was a dead home screen); More-tab nav highlight
  was wrong for non-approvers; splash no longer uses `ref` after it can be disposed;
  `withOpacity` → `withValues`.

**2026-09-25** — **P6 Polish & Ship — code DONE** (no mockups needed per plan).

API / server:
- `PushToken` table (migration `0019_push_tokens`, additive only).
- `POST /api/push-token {token}` · `DELETE /api/push-token {token}` (logout).
- `GET /api/alerts` — web bell feed for the app, each item has `appPath`.
- `src/lib/push.ts` — FCM HTTP v1 (service-account JWT, token cache, dead-token pruning).
  "New request" → routed approvers (SM for route A, AGM for B, ADMIN/HR when vacant/no route);
  "approved/declined" → the requester. Runs after the response (`after()`), never blocks.
  No `FCM_SERVICE_ACCOUNT` env → silent no-op.

Flutter (v0.6.0):
- Alerts bell on Home (badge + sheet, tap opens the right tab/screen).
- Push: permission prompt, token register/refresh, foreground banner, tap routing,
  unregister on logout. Only active in builds with `FIREBASE_ON=true`.
- Crashlytics: Flutter + platform errors (release builds), user id tag only.
- Biometric quick-unlock: opt-in in More (needs one successful scan to turn on),
  locks on cold start and after 3 min in background, "sign in with password instead".

CI:
- `tool/ci_prepare_android.py` replaces the inline heredoc: minSdk 24 (local_auth 3.x),
  USE_BIOMETRIC, `FlutterFragmentActivity`, optional Firebase + release signing.
- `build-flutter` now also runs `flutter test`.
- New `release-flutter` (main only): release APK, versionCode = CircleCI build number,
  artifact `HRMate-release.apk` = internal distribution.

### P6 — what you need to set up (one time)

1. **Firebase** (console.firebase.google.com): project → add Android app with package
   `in.flavorflow.hrmate` → download `google-services.json`.
   - CircleCI env `FIREBASE_GOOGLE_SERVICES_B64` = `base64 -w0 google-services.json`
     (turns on push + Crashlytics in the APK).
   - Project settings → Service accounts → Generate new private key → put the JSON
     (or its base64) in the VPS `/opt/hrms/app/.env` as `FCM_SERVICE_ACCOUNT=...`, then `pm2 restart hrms`.
2. **Release keystore** (once, keep it safe — lose it and you can't update the app):
   `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
   → CircleCI env `HRMATE_KEYSTORE_B64` (`base64 -w0 upload-keystore.jks`),
   `HRMATE_KEYSTORE_PASSWORD`, `HRMATE_KEY_ALIAS` (=upload), `HRMATE_KEY_PASSWORD`.
   Without it the release APK is debug-signed (OK for testing).
3. Until 1–2 are set everything else still works: bell alerts, biometric unlock, release APK.
