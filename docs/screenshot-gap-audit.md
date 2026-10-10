# Screenshot-driven feature audit

This is a feature/wording comparison against the supplied screenshot set, not a pixel-perfect reproduction checklist. FlavorFlow branding is intentionally retained; screenshot-specific module names and workflows are followed where compatible.

## Employee categories and departments

- Employee categories shown: **Official Staff** and **Yellow Card Staff (15 EL Only)**.
- Department choices shown: **Production, Agriculture, Security, Engineering, Accounts, Quality**.
- The employee editor previously accepted arbitrary text for both fields. It now has category and department dropdowns, shows the category on employee profiles and ID cards, and keeps already-used department values selectable so existing records are not orphaned.
- Yellow Card leave wording: “Yellow Card staff members strictly receive 15 Earned Leaves (EL) per year, accrued monthly at 1.25 days per elapsed month. Casual Leaves (CL), Sick Leaves (SL), Optional Holidays, and Short Leaves are not applicable.”
- Official Staff rules confirmed by the user: EL 14/year, SL 14/year, CL 7/year, Short Leave 2 days/month with unused days resetting monthly, and Compensatory Leave earned for completed attendance on a scheduled weekly off.
- Both categories are enforced by API category policies, rather than treating Yellow Card leave types as global Official Staff defaults. Official Staff sees exactly EL, SL, CL, Short Leave, and Compensatory Leave; legacy Annual leave/Optional Holiday records remain in history but are inapplicable for new Official Staff requests. Short Leave is capped at 2 days per calendar month. Compensatory Leave earns one day per completed attendance record on a scheduled weekly off; no expiry was specified, so earned credits remain available until used.
- Yellow Card policy remains enforced by the API and shown in the leave-policy screen: 15 days/year of Earned Leave (EL), accrued monthly; the other leave types are not applicable.
- Legacy departments **Management**, **Quality - Lab**, and **Production & Quality** remain available for existing profiles.

## Module comparison

| Screenshot area | Existing implementation before this pass | Current state |
| --- | --- | --- |
| ID Card & Pass | Already implemented: front/back ID cards, employee contact details, PDF print/share, gate-pass request and review | Kept; category label now appears on the card. This module was not missing. |
| Attendance | GPS geofence and manager-approved manual-punch requests already implemented | Retained. Normal punches remain geofenced; manual requests do not write attendance until approval. |
| Leave balances and policy | Global leave types and policy editor existed; no employee-category override | Explicit Official Staff allowances, monthly-reset Short Leave, and attendance-earned Compensatory Leave added; Yellow Card remains 15 EL only. API eligibility and balances are category-aware. |
| Team departments | Team directory existed, but department choices were not a controlled employee-form field | Screenshot department choices are selectable; legacy values are preserved. |
| Mobile navigation | Four-item NavigationBar plus a text list in a bottom sheet | Changed to Home / Leaves / Punch / Team / More and a three-column More-module grid. |
| KRA & Goals | No screen or API found | Added a role-template editor with correction/edit support, goal assignment/progress, employee self updates, and manager review with API scopes. Templates are intentionally not pre-seeded: the reference calls out 25 role templates, but their complete wording/weights still needs verified transcription rather than guesses. Yellow Card employees are excluded from KRA/appraisal. |
| KYC & Letters | No screen or API found | Added a role-scoped metadata checklist, last-four-only validation, HR review status, and local PDF letter drafts. This is not file upload or encrypted storage; that limitation is stated in the UI. |
| Reports | No dedicated screen or API found | Added workforce/attendance/leave summaries, department counts, selectable attendance period, and opt-in CSV copy. Existing API scopes remain enforced. |
| Yellow Card output tracking | No output-log feature found | Added scoped daily production output logs alongside existing shift/attendance tracking; self, manager-team, and HR visibility are enforced by the API. |
| Language, theme, typography settings | Not available as working app-wide preferences | A persisted text-size control now scales app text while retaining device accessibility scaling. Language and theme preferences remain outstanding; avoid adding nonfunctional selectors. Existing 15-minute inactivity default and biometric login flow are retained. |

## Safety and implementation notes

- Screenshot personal identifiers are not embedded in code or demo seeds. The current SQLite backend does not provide encryption at rest, so a KYC document store should not be represented as encrypted until that infrastructure exists.
- The existing demo roster remains intact. Existing database values and attendance/leave history are preserved during the category and leave-policy migration.
- The “More” grid follows the screenshot layout while retaining FlavorFlow branding and the existing permission-based module visibility.
- Remaining work: verify/transcribe all 25 KRA role templates and their weights; design protected document storage before supporting KYC file uploads; implement app-wide language/theme preferences if they remain in scope. Reports and the persisted text-size preference are implemented. Flutter compilation is not verified in this environment.
