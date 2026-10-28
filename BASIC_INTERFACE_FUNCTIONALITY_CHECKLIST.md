# PowerMoves PSMDT — Basic Interface Functionality

Source review from the saved Phase 3 checkpoint, `602a7a3`, with the small interface fixes and subsequent shared EMS dashboard correction described below. This checklist describes code and connections, not a FiveM runtime acceptance test. All five interfaces remain part of one existing tablet, resource and backend.

“Implemented” means an existing page and callback path are connected, subject to their existing permissions and configuration. It does not mean every authorization boundary or integration has been verified in game.

## SADLE.net — Law enforcement

| Status | Functionality |
|---|---|
| Already implemented | Law-enforcement navigation and dashboard; reports, cases, evidence, warrants/BOLOs, citizen/vehicle/weapon records and charges. Existing roster, personnel administration, certification tags, PPR, FTO, IA, SOP and calendar pages are available through the established permission system. |
| Present but needing correction | PPR/FTO/IA list filtering is not consistently repeated by detail, history and mutation handlers. Some SOP writes identify a category or section without verifying its department. These existing boundaries need correction before broader reuse or access is enabled. |
| Not yet implemented / not established | A complete, separately configured statewide oversight workflow beyond the existing AG entry and permissions is not established by this review. No new oversight grants are introduced by this pass. |

Existing components: [navigation definitions](web/src/constants/index.ts), [dashboard](web/src/pages/Dashboard.svelte), [roster backend](server/backend/roster.lua), [PPR](server/backend/ppr.lua), [FTO](server/backend/fto.lua), [IA](server/backend/ia.lua), [SOP](server/backend/sop.lua).

## SADOJ.net — Justice and courts

| Status | Functionality |
|---|---|
| Already implemented | DOJ navigation and dashboard; court cases, calendar/hearings, warrant requests/review, court orders and legal documents; existing shared reports, citizen, case, evidence and charge pages. Phase 1 separates actual judicial actions from the AG's prosecution access. |
| Corrected in this pass | Dashboard response handling and shortcut routing; Preferences and Bulletin Board navigation. These reuse existing pages and callbacks. |
| Present but needing correction | A generic roster exists, but its current police/EMS domain selection would return police personnel for DOJ; it must not simply be exposed as a DOJ roster. Court Orders has a detail view, but its list response does not supply the order content that the view needs. DOJ management currently exposes only Permissions; its hardcoded section filter also hides other sections represented by existing role grants. |
| Not yet implemented | A correctly scoped DOJ personnel roster and its associated personnel interface. The generic personnel pages are not proof that DOJ staff selection or administration is complete. |

Existing components: [DOJ pages](web/src/pages/doj), [DOJ backend](server/backend/doj.lua), [shared roster selection](server/backend/roster.lua), [authorization](server/auth.lua).

## SAFR.net — Fire and rescue

| Status | Functionality |
|---|---|
| Already implemented | Distinct SAFR identity and fire-job routing. Existing EMS dashboard, reports, citizen/patient lookup, EMS-wide roster and certification tags, own-job personnel controls, bulletin board, dispatch/map and calendar are connected. The EMS calendar supports training, meetings and other appointments while excluding court events. Existing management includes permission roles, tags, templates, SOP and FTO-program configuration, subject to grants. |
| Corrected in the dashboard follow-up | EMS aggregate and individual dashboard reads enforce the EMS domain on the server. Reports and totals use existing record-sharing grants; appointments, department bulletins, EMS personnel counts and explicitly addressed dispatch remain available. Police cases, warrants, BOLOs, arrest/impound totals and unscoped operational feeds are excluded. |
| Present but needing correction | Existing PPR/FTO/IA pages are omitted from EMS navigation, and their incomplete detail/history/mutation scope checks must be addressed before exposing them. SOP reads are department-scoped and its management page exists, but the main SOP navigation entry is omitted and some writes lack department ownership checks. |
| Not yet implemented | Dedicated fire incident/report workflows and fire/EMS accreditation. Existing generic EMS reports and certification tags do not constitute those systems. |

SAFR retains the existing `ems` data domain; this pass does not split storage or grant additional record access. Sources: [interface routing](server/auth.lua), [EMS tabs and report types](web/src/constants/index.ts), [report editor](web/src/pages/ReportEditor.svelte), [calendar](server/backend/court.lua), [management](web/src/pages/Management.svelte).

## SAMS.net — Hospitals and medical services

| Status | Functionality |
|---|---|
| Already implemented | Distinct SAMS identity and hospital/medical-job routing. Existing EMS dashboard, medical/trauma/overdose/psychiatric/mass-casualty report types, patient lookup, EMS-wide roster and certification tags, own-job personnel controls, bulletin board, dispatch/map and calendar are connected. Existing management and training-program configuration are reusable. |
| Corrected in the dashboard follow-up | The same server-enforced EMS dashboard correction described for SAFR applies, retaining SAMS branding and hospital-job routing. Existing public reports and reports explicitly shared with the employee, job or EMS remain visible under existing report permissions. |
| Present but needing correction | The personnel access issues described for SAFR remain. Awards is currently police-stat-oriented and hidden from EMS; enabling that tab alone would not provide medical awards functionality. Hospital-specific privacy and interfacility sharing are not established by the shared EMS interface. |
| Not yet implemented | Clinical charting/patient medical-record workflows and medical accreditation. The existing ICU callback performs limited BOLO cleanup; it is not a clinical charting system. |

Sources: [EMS reporting](server/backend/reports.lua), [roster/certifications](server/backend/roster.lua), [shared dashboard](server/backend/dashboard.lua), [awards implementation](server/backend/management.lua), [ICU cleanup](server/backend/icu.lua).

## SAGOV.net — Government

| Status | Functionality |
|---|---|
| Already implemented | Personnel landing page/dashboard with search, refresh and runtime positions/grades. State, Blaine County, Los Santos County and City of Los Santos rosters are separated by actual government job. Explicit state roster oversight is read only. Phase 3 bosses can hire online unemployed players, change an online employee's grade and terminate employment within their own government job. |
| Present but needing configuration / verification | State oversight recipients must be explicitly assigned; boss status does not grant it. QBCore employment updates and persistence still require verification in a separate development environment. |
| Not yet implemented | Government reports, calendar/training events, certifications and richer personnel records. Existing operational versions of these pages are intentionally blocked for government and are not government implementations. Taxation, licensing, legislation and elections remain outside this basic-functionality pass. |

Existing components: [government page](web/src/pages/Government.svelte), [government service](web/src/services/governmentPersonnelService.svelte.ts), [government authorization](server/auth.lua), [government roster/employment backend](server/backend/roster.lua).

## Small corrections in this pass

- Restore existing DOJ dashboard data/shortcuts and its Preferences/Bulletin Board navigation.
- Let the personal Preferences page use its existing access path without requiring the administrative settings permission.
- Use the established canonical tab-visibility keys in the sidebar.
- Open an available, permitted management view, and recognize existing management-tag, SOP-management and FTO-management permissions at management-page entry.

Those initial review changes were frontend routing/visibility corrections. They did not introduce record permissions, new EMS tabs, backend employment changes, database tables or a new application.

## Completed follow-up — shared EMS dashboard

The shared dashboard now scopes aggregate and individual reads on the server, excludes police-only data for EMS and rejects responses after character, job, grade, duty, boss or permission changes. Report totals use the same public-or-explicit-sharing rules as existing report reads instead of global police caches. EMS calendar entries require the existing training permission and exclude court events. Dispatch requires an explicit EMS or current-job recipient even when global dispatch filtering is disabled, and returned unit details omit private personnel fields.

EMS dashboard bulletins use the existing department-scoped Bulletin Board and its view permission. The legacy global bulletin table has no department field, so its standalone read returns no rows for EMS; department-board IDs are never mixed with legacy management create/delete IDs. Warrant broadcasts now target eligible police/DOJ clients instead of every client. The NUI rejects stale responses and refreshes EMS data through scoped server endpoints rather than trusting unscoped pushed data. SAFR and SAMS retain separate identities within the same resource and database.

No further milestone has been started. Personnel detail/history/mutation scope corrections remain a separate follow-up before further personnel navigation is exposed.

## Validation status

| Check | Result |
|---|---|
| Automated regressions | **251 tests passed:** all 200 existing tests plus 29 EMS server tests (543 assertions) and 22 EMS frontend tests. New tests load production authorization, dashboard, warrant and frontend-service code with mocked framework/SQL/transport state. |
| Changed source syntax | Both changed Lua source files and the new Lua regression harness passed Lua 5.4 syntax checks. Both changed frontend files compiled with the installed Svelte/TypeScript tools. |
| Production web build | Passed: 435 modules transformed; build completed in 11.43 seconds. |
| Git whitespace check | Passed. |
| Full `npm run check` | Failed with **39 existing errors and 183 warnings in 37 files**. Comparison by source path and error text against the saved basic-review baseline found **zero new errors and zero removed errors**. |
| Chained TypeScript stage | Not run: the script stops when `svelte-check` fails. |

Remaining type errors include the missing `MAX_NUI_MESSAGE_SIZE` property and `MDTTab` type, plus existing component-prop and declaration-order issues. The complete type check is therefore not green despite the successful production build.

The dashboard follow-up changes `server/backend/dashboard.lua`, the warrant read/broadcast paths in `server/backend/warrants.lua`, `web/src/pages/Dashboard.svelte` and `web/src/services/dashboardService.svelte.ts`, and adds focused tests under `tests/ems_dashboard/`. Existing client forwarding already uses these server endpoints and required no change. Framework job definitions, unrelated permission policy and SQL schemas were not changed. No dependencies were installed, and no live-server operations, real-database integration tests or FiveM runtime tests occurred. A separate development environment is still required to verify actual dispatch-provider audiences, database queries, job/duty updates and rendering in game.
