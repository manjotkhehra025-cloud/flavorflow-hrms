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
