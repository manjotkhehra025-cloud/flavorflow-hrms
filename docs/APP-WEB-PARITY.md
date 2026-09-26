# 📱 = 🖥️ App–Web UI Parity (standing requirement)

> **User directive (2026-09-26, noted):** *"Menu app da UI same web wala chahida a with all working features and buttons eh chij note rkho."*
>
> Matlab: HRMate mobile app da UI **web warga hi** hovega — har screen, har button, har feature **working**. Koi placeholder / dead button nahi.

This file supplements [DESIGN-RULES.md](../DESIGN-RULES.md). Rule 4 (*Features MUST keep working*) applies **equally to the app**: a screen is "done" only when its UI matches web **and** every button/action works against the live API.

## The parity rule

1. **Same screens** — har web page da app counterpart (same data, same actions, mobile layout).
2. **Same brand** — navy `#0A1628` + emerald `#10B981` theme dono passe (already aligned).
3. **All buttons working** — jo web te karda hai (apply, approve, reject, save, delete, share…), oh app te vi kare. Same API, same permissions.
4. **Same roles** — staffOnly / approverOk / permission-switch rules app te vi laggu (web ton ulat kuch nahi).
5. **No app-only drift** — app te koi aisa label/flow nahi jo web de ulat hovega (jivein `MANUAL_OUT` raw enum — fixed 2026-09-26).

## Parity table (2026-09-26)

| # | Web page | App screen | Status |
|---|---|---|---|
| 1 | `/dashboard` | Home tab | ✅ present |
| 2 | `/social` | Social Wall | ✅ present |
| 3 | `/attendance` | Attendance history + punch flow | ✅ present |
| 4 | `/leaves` | Leaves tab (balances + apply) | ✅ present |
| 5 | `/approvals` | Approvals tab (leave/punch/gate/swap) | ✅ present |
| 6 | `/idcard` (badge + gate pass) | My ID card + Gatekeeper + GatePassCard (2026-09-26) | ✅ my-view done — request form + status list + verified chips (staff view-others = P2 row 13 naal) |
| 7 | `/roster` | My Roster + swap | ✅ present (my-view; staff roster board = row 20) |
| 8 | `/holidays` | Holidays (+add/delete for staff) | ✅ present |
| 9 | `/helpdesk`, `/helpdesk/[id]` | Helpdesk + thread | ✅ present |
| 10 | `/payslips`, `/payslips/[rowId]` | My payslips (+share/PDF link) | ✅ present |
| 11 | web bell (alerts) | Notifications sheet | ✅ present |
| 12 | employee toggles (web profile card) | Employee permissions | ✅ present |
| 13 | `/employees` (+ new, + `[id]`) | — | ❌ missing (directory, add-employee, full profile: KYC, letters, pay, permissions) |
| 14 | `/team` (Live Team) | — | ❌ missing (presence board) |
| 15 | `/payroll`, `/payroll/[id]` | — | ❌ missing (runs, draft edit, lock, excel) |
| 16 | `/departments` | — | ❌ missing (dept + designation editors) |
| 17 | `/reports` (+ gate-pass/late/leave-balance/ot) | — | ❌ missing (5 reports) |
| 18 | `/tops` (TOPS Weekly) | — | ❌ missing |
| 19 | `/kra`, `/kra/manage` | My KRA screen (2026-09-26) | ✅ my-view done — hero ring + goals + self-update + history (manage templates = P2 staff) |
| 20 | `/roster` (staff board) | — | ❌ missing (staff view; my-view exists — row 7) |
| 21 | `/star` (Employee of the Month) | — | ❌ missing |
| 22 | `/letters`, `/letters/[id]` | My Letters list + letter sheet + Share/PDF (2026-09-26) | ✅ present — list (own letters; staff all + names), full letterhead sheet, public share token link (LetterLink) + copy, web `/letters` page added same day |
| 23 | `/settings` | — | ❌ missing (shifts, policies, company) |
| 24 | `/activity` | — | ❌ missing (audit log) |

## Suggested build order (jub user OK kare)

1. **P1 — employee daily use:** row 6 gate-pass verify, row 19 my-KRA view, row 22 my letters.
2. **P2 — staff on phone:** row 13 employees (directory + profile view, add later), row 14 team presence, row 20 staff roster.
3. **P3 — full admin:** rows 15, 16, 17, 18, 21, 23, 24.

Har slice: **DESIGN (web screen reference) → APPROVE → IMPLEMENT (identical) → WORKING (har button test) → DEPLOY** — DESIGN-RULES mutabik, bina data-loss.
