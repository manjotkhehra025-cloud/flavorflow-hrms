# HRMate v3 — Design & Port Spec (approved 2026-09-21)

## Decisions
- **Merge:** HRMate app (com.gdfoods.hrmate prototype) vision → our controlled Next.js codebase
- **Brand:** HRMate, emerald-green + dark-navy consumer style
- **First slice:** Modules 1+2+3 → Punch 2.0 (+Shifts+Calendar), Leave Policy Engine, ID Card + Gate Pass

## Brand tokens
- Navy: #0A1628 (cards/hero), #0F2138 (panels)
- Emerald: #10B981 → #059669 gradients (CTA, punch button, ring)
- Amber only for warnings; slate text; rounded-2xl cards, soft shadows
- Mobile bottom nav: Home / Leaves / Punch(center FAB w/ fingerprint icon) / Team / More

## Extracted domain data (from 72 screenshots)
- Company: G.D. Foods Mfg. (I) Pvt. Ltd., Khadur Sahib, Tarn Taran  Punjab (letterhead: "Makers of Tops Brand Quality Food Products", Plant: Village Dhunda, Goindwal Road)
- Geofence: 31.42225, 75.08436, 150m radius
- Departments: Production, Quality - Lab, Agriculture, Security, Engineering, Accounts (also Production & Quality, Management)
- Staff categories: **Yellow Card** (EL-only, 15 EL/yr, auto-accrual 1.25/mo; no KRA/CL/SL) | **Official Staff** (KRAs apply)
- Shifts: General Day 08:00·9h · Night 19:00·12h · Season Day 07:00·12h
- Emp codes: WKH00416, NS000001/2 style
- Letter ref: GDF/HR/2026/WKH00416
- Roles: Super Admin / Admin / Manager / Employee
- Approvals hub tabs: Leave / Manual Punch / Overtime (OT) / Gate Pass
- ID card front: photo, QR(verify link), name, dept, role chip, ID, category badge, "VERIFIED"; back: DOJ, DOB, blood, emergency contact, instructions, factory address
- KRA: 25 role templates (dept+designation+weight+SLA) — captured from screenshots (Phase C)
- Known prototype bugs to NOT replicate: doubled text on headers, junk emp code `u_ec50a3...`, inconsistent stats math (Absent 27 vs 12 working days), missing Payroll everywhere

## Schema v3 additions (Prisma)
- Employee: employeeCode, category (YELLOW_CARD | OFFICIAL), dob, bloodGroup, emergencyPhone, photoUrl, weeklyOff (enum dow)
- Shift { id, companyId, name, startTime, hours }
- GatePass { employeeId, date, exitAt, returnAt, reason, status PENDING/APPROVED/REJECTED, approver, entryVerifiedAt }
- PunchRequest { employeeId, date, type MANUAL_IN/MANUAL_OUT/OT, time, reason, status }
- LeavePolicy: per-category accrual config (yellowCard: EL 15/yr @1.25/month from DOJ month; official: leaveType daysPerYear fixed)

## This milestone scope (M1)
1. Rebrand → HRMate name/logo, green+navy theme across app (sidebar dark navy, emerald CTAs)
2. Punch 2.0 — shift binding, live elapsed ring-style timer card, weekly-off logic, attendance month calendar w/ dots + day log table
3. Leave Engine — categories on employee, EL auto-accrual math (accrued vs used vs pending), balance cards w/ progress bars, admin "Adjust Balance"
4. ID Card & Gate Pass — flip-style front/back virtual badge (QR → public verify URL), gate pass request + approve + "ENTRY VERIFIED", printable card
5. Approvals hub — /approvals page with 4 tabs (Leave, Manual Punch, OT, Gate Pass)
6. Settings — shift management (add/edit shifts), weekly-off per employee

## Out of scope (later phases)
Phase B: KYC locker, Letters/TOPS PDF, Team presence v2, photos upload
Phase C: KRA templates (25, content captured), Reports v2 charts, Star Workers, Helpdesk, Social Wall, → Punjabi i18n
Phase D: Payroll (differentiator — exists nowhere yet)
