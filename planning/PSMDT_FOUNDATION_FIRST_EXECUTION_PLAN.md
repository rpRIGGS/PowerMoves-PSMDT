# PowerMoves RP — PSMDT foundation-first execution plan
October 28, 2026. Reconciles the earlier five-interface original plan with SADOT as the later sixth interface and the subsequent October 27–28 implementation notes.

## This is the implementation order, not a new feature brainstorm
The project is ONE QBCore `ps-mdt` resource and shared database with six legitimate service-specific .net presentations. Start from the **original operational LEO MDT**, preserve all proven working features and adapt those workflows to new services. A selected UI never changes QBCore employment. Preserve live data; do not merge privileged records across agencies. User has explicitly requested incremental direct-to-main GitHub source commits with inspection, validation, and eventual owner FiveM testing. Do not claim runtime success from static scans.

## 0 — Verified baseline and freeze of feature jumping (CURRENT)
1. Confirm the original/reference and current PowerMoves PSMDT GitHub versions. Record exact source status by resource and interface; do not claim web dist is built, DB is migrated, or that an isolated FiveM test server exists.
2. Reconcile `planning-reference/jobs.lua`, `config.lua`, PSMDT auth, UI job types and permissions; inspect all active LEO, DOJ, fire, hospital, government, and proposed SADOT jobs and rank grades. No arbitrary rank edits.
3. Inventory real LEO functional workflows and dependencies: dashboard/dispatch; reports, evidence, case link, warrants/BOLOs, IA, SOPs, rosters, FTO, certifications, training/department calendars, court, bulletin, management, personnel profiles, audit, restrictions, public complaint.
4. Classify each feature: current working baseline / new committed source untested / absent, and document exactly which service inherits it and which service needs special rules.
5. Review commits already pushed to main for collision with original features; patch defects that could block building, then freeze unrelated feature additions.

## 1 — Complete the six-interface foundation (FIRST CODE PRIORITY)
1. Actual job-to-interface eligibility, current job/rank, jurisdiction, department and optional selected interface are authoritative on the server. Map `leo` to SADLE, `doj` to SADOJ, `fire` to SAFR, `ems` to SAMS, government to SAGOV. SADOT remains **disabled until permits/role validation**; neither QBCore `mechanic` nor browser branding is an authorization grant.
2. Give each eligible interface correct landing dashboard, complete navigation and agency styling, and a usable existing set of tabs. Reuse/copy **proven LEO UI workflows**, not just labels. Specifically fix current SAGOV Dashboard-only stub, SAFR shared EMS job classification leakage, incomplete and unrelated generic tabs, and unimplemented SADOT routing.
3. Enforce permission boundaries for every action on the server: interface + real job/grade + employer + role + target record + oversight authority; migrate from `BossPermissionMode='legacy'` only after exact approved permission matrix is populated and regression tested. Keep DOJ judicial authority separate from SADLE AG prosecution and government authority.
4. Finish one vertical at a time at baseline parity, not all six as a giant simultaneous refactor: existing SADLE preserved; SADOJ core court/navigation and personnel verified; SAFR fire personnel/operational base; SAMS hospital personnel/medical base; SAGOV government personnel base; SADOT base only when authorized.

**Done when:** workers in each enabled job open the intended interface with its real dashboard, existing functional roster, SOP, personnel/training, reports/cases/calendar where applicable; unrelated departments cannot read/edit each other's data; LEO and DOJ regression scenarios still pass.

## 2 — Department-based operating model and shared workflows
- A .net is an *agency family*, not an individual employer: each LSPD, BCSO, SASPA, LSFD, LSCFD, BCFD, Pillbox/Sandy/Paleto/Parsons hospital, SAGOV/BCGOV/LSCGOV/LSGOV agency maintains its own roster, SOP, daily activities, event calendar, training, reports and management. A single agency has multiple stations, firehouses/engine companies, patrol districts, units and shifts without mandatory duplicate QBCore jobs.
- Distinguish department-private data, authorized statewide oversight, and specifically shared documents. Approved/published public records are not synonymous with drafts, private notes, evidence, or patient charts.
- Match actual workplace authority, including authorized government oversight and accreditor inspection, without enabling global access for all bosses.
- Carry existing report tags, involved persons, report restriction grants (`citizenid`, `job`, `jobtype`), personnel roles, case links, evidence chain-of-custody, and audit through each interface.

**Done when:** roster/SOP/calendar ownership and permitted oversight work for concrete two-department and interagency scenarios, not just by generic LEO/EMS domain.

## 3 — Statewide standards, professional training and calendars
- **SADLE/POST:** SADLE sets and audits statewide standards, accredits agencies AND individuals; POST delivers academy, including corrections-specific pathways for SASPA; accredited employing departments are responsible for continuing field training, FTO evaluations and specialty credentials (motorcycle, SWAT, pilots). Person's permanent qualifications survive transfers; departmental DORs remain controlled and reviewable by appropriate oversight.
- **SAFR:** statewide fire academy, agency/individual certification, local-accredited employer ongoing instruction; actual state operational fire and aviation division.
- **SAMS:** statewide medical/clinical standards, individual/facility accreditation, hospital clinical training and certification; keep clinical chart permissions distinct from ordinary fire run reports.
- **SADOJ:** court clerk/law clerk training, legal mentorship/bar qualification, prosecutors, public defenders, independent counsel and judicial paths without police officer terminology.
- **SAGOV and SADOT:** government personnel training and service-specific operator qualifications, as applicable after the core parity.
- Existing FTO component should be adapted, not cloned into six disconnected engines. Credentials in `mdt_personal_accreditations` are **initial source additions**, not yet a completed accreditor/agency compliance engine.
- Agency-specific calendars: own departmental activities plus authorized statewide academy sessions and scheduled court events. Availability/streamer predictable shifts/timezone/tsunami schedule is **deferred optional expansion**, not in this stage.

**Done when:** actual employer supervisors can manage their permitted continuing training and view permanent credentials; state authority can audit its scope; calendars do not leak across employers.

## 4 — Investigations, DOJ and controlled cross-agency records
- Reuse existing investigative reports, warrant/BOLOs, evidence, `mdt_cases` + `mdt_case_reports`, DOJ `mdt_court_cases`, legal participant citizen IDs and court-hearing functionality. No replacement of working court engine.
- Department IA → explicitly authorized SADLE investigative referral queue and controlled record grants; SADLE → specific involved employer command disclosure without exposing full investigation. Existing **tags only categorize/search**, not guaranteed work-queue routing or grant.
- DOJ criminal/civil court case links investigation, all authorized reports/evidence/documents, prosecutor/judge/assigned defense; discovery offers case-specific approved document access (including independent lawyer), logging and revoke; closed cases stay permanent.
- Apply same secure sharing backbone to other agency types where justified; no blanket medical chart or government draft access. Audit previous source-level IA/case/report permission fixes with tests.

**Done when:** BCSO→SADLE and police→DOJ→defense scenarios function end to end with role-specific queues and access logs.

## 5 — Public services, records officers and intake
- Use configurable in-world vector3/radius circle zones and optional polygons through `qb-target`; existing civilian IA form, no civilian MDT tablet. The new `Config.PublicServices` / `client/backend/public_services.lua` is committed **without active real coordinates**, and not FiveM-tested.
- Agency-specific public intake services (public-records/FOIA requests, licenses/permits and future appropriate portals). Each agency has a designated records employee/role according to owner's written SOPs. Agency approves/denies/reviews; approved release copies/material grant specific requester citizen-ID access, record the decision, issuer, scope, revocation.
- No invented law, no automatic public release when a tag appears, no unnecessary new interfaces or fabricated request desk positions.

**Done when:** civilian can visit a configured desk, file, receive request reference, agency receives it, authorized officer decides, permitted record appears only to appropriate citizen and can be revoked.

## 6 — Full SAGOV & SADOT vertical integrations
- SAGOV state → peer counties Blaine/LS → city LS within LS County; future municipalities. Internal personnel, rosters, votes, legislation/codes, amendments/publication, elections where relevant, public records, public service appointments, business licensing/permits, rates and budgets.
- PS Realtor creates listings/transactions and specifies property type/jurisdiction; PS Housing supplies ownership; appointed SAGOV Tax Assessor staff review and approve assessments/jurisdictions/exemptions with history, not arbitrary admin powers. Government ownership ≠ automatic tax exemption; no property-creation PolyZones. One local business license by default; distinguish property/business/sales tax, sales location method still undecided.
- SADOT state oversight job/ranks need real `jobs.lua` definition before enabling access. Link SAGOV-issued business license to SADOT tow permit/driver/vehicle qualification and PS-Dispatch /511 claim, existing PSMDT tow ledger, inspection and original report/evidence/case history. No separate duplicate towreport form, no unverified physical garage/tow logic.
- SADOJ handles properly filed enforcement, government/court challenges and judicial process; assessor cannot auto-confiscate property.

**Done when:** agencies' approved government/business or transport workflows run end to end with source-of-truth integrations and correct jurisdictions.

## 7 — Optional later staffing availability
Employees/streamers may enter expected weekly/tsunami/timezone play availability. Station/company/precinct supervisors may view authorized staff availability to plan shifts. It does not itself assert duty status. Not a blocker.

## Honest current state (based on October 28 GitHub inspection)
- Existing source retains established LEO MDT and DOJ court internals, many reports/evidence/roster/SOP/FTO functions.
- Interface identity and auth routing partially present; **SAGOV tabs are Dashboard-only**, SAFR still maps internally to legacy EMS permission domain, SADOT is an inactive interface identity, and job/grade explicit access remains unpopulated/legacy. Six fully functional interfaces DO NOT exist yet.
- Recent main commits for FTO portability, permanent credentials, IA guards, /511 integrations and public-target zones are **source changes**; do not redirect the development order away from Stage 1. None have been demonstrated working via a FiveM runtime test. Existing `web/dist` build currency is unknown.
- The previous `planning/PSMDT_MASTER_WORKFLOW_AND_STAGES.md` put public-service requests before complete interface foundation; that **sequence is superseded by this foundation-first order**. Public zones code is retained for later use, not removed.

## Stage 1 first executed increment — employing-agency roster separation and interface navigation
Source committed directly to `main`:
- `server/backend/roster.lua`: SAFR/fire and SAMS/hospital rosters now use the **actual actor's employing agency**, not the shared legacy `ems` domain or an all-fire-plus-all-hospitals aggregate. DOJ legal rosters likewise use the caller's own employer (SADOJ staff are not automatically pooled with independent `lawyer` offices). LEO's existing roster fallback is preserved for a separate authorized oversight/agency-scope review.
- `web/src/constants/index.ts`: fire-specific navigation selection is based on the `safr` interface ID even while core authentication preserves existing `ems` compatibility; DOJ now exposes existing `Roster` and `SOP` UI entries alongside FTO.
- `web/src/components/NavigationPills.svelte`: forwards the **authorized interface ID** to the tab filter; source continues to use current server-provided job/permissions.
- Static checks **12/12 passed** against current repository after commits. This is **not** a compiled web/dist bundle or FiveM/runtime certification. Existing `Config.MedicalJobType='ems'`, `Config.FireJobType='fire'` and disabled SADOT remain unchanged.
- Follow-up Stage 1 priorities: fully reconcile LEO roster agency-vs-authorized SADLE oversight; check DOJ roster callbacks and all SOP views by employer; fix SAFR's `server/auth.lua` internal legacy `ems` permission identity and related report/calendars only as one carefully tested compatibility migration; build frontend; fill the government authorization and functional module gap **without** granting GOV blanket police/medical access. Do not claim six fully working interfaces.

## Stage 1 continued — framework membership and SAFR/SAMS report presentation
Direct-to-main source commits:
- `server/backend/roster.lua` Qbox/QBX roster assembly now rechecks the player's **current actual job** after collecting group/multijob members. Retaining secondary Qbox group membership for a different employer no longer alone causes personnel to appear in a roster for which their active job does not qualify. No change to underlying Qbox memberships.
- `web/src/constants/index.ts` adds initial SAFR-specific generic choices to the *existing* report editor (`Fire Incident Report`, `Rescue Report`, `Fire Investigation Report`, `EMS Run Report`); SAMS keeps the existing medical report choice list. Specific template content remains a future SOP/configuration task, not something auto-generated here.
- `web/src/components/ContentArea.svelte` → `pages/Reports.svelte` → `pages/ReportEditor.svelte` → `components/report-editor/ReportMetadata.svelte` now forwards authorized `interfaceId`, avoiding the broad legacy `ems` label conflating SAFR and SAMS in the report selection UI. Original storage, editor, content/evidence attachments, LEO and DOJ report options are preserved.
- Source checks **13/13 passed** on refetched files. **No frontend compilation, Lua/SQL execution, FiveM test, or deployment yet.** This is a UI report-type presentation change, **not** a complete server-side medical/fire report privacy split.
- Next foundation work: audit first-party LEO roster statewide visibility against approved SADLE and FIB oversight rules; explicit boss-grade permission migration; separate fire/medical authorization, agency data ownership, and gov modular interface integration without granting new operational police/clinical access.

## Stage 1 continued — LEO employer roster and precise state oversight (Oct 28)
Committed on `main`: `server/auth.lua` defines `CanViewStatewideLeoRoster(source)`; `config.lua` restricts eligibility to `sadle`/`fib`; `server/backend/roster.lua` now defaults ordinary LEO roster queries to the caller's actual police employer. The exact configured SADLE Attorney General grade retains statewide roster visibility. Other approved SADLE/FIB job+grade roles must **explicitly** contain `leo_roster_oversight` in `mdt_permission_roles.permissions` for cross-agency read-only roster visibility. Neither generic LEO membership nor the legacy boss permission ceiling grants that override. Rechecks live identity after SQL yields.

Source checks 10/10 passed. **Not** a FiveM or SQL integration test and no live role grants were inserted. This governs this roster callback only; other LEO personnel/report/search callbacks remain subject to their own permission and agency audits. The existing Qbox and SQL roster implementations remain.

## Stage 1 — SAFR/SAMS permission authority separation (October 28)
Committed directly to main: `config.lua` adds a dedicated `Config.MdtAccess.PermissionSets.fire`, initially preserving the same available legacy responder capabilities as `ems` so existing fire/medical MDT actions aren't abruptly removed. `server/auth.lua:rolePermissions` selects `fire` as the ceiling **only** for the actual SAFR primary interface/job, while SAMS continues `ems`. The QBCore job types remain `fire` and `ems`, and the existing internal `jobType='ems'` routing compatibility remains for untouched legacy backend. Stored `mdt_permission_roles` grants still apply per real job/grade; this change alone does not create any new grants or authorize cross-employer records.

`GetMdtAccess` now rechecks live citizen, employer job, grade, duty, and primary interface after role database lookup; it rejects stale permissions if the caller switched characters/employment while the SQL query yielded.

Static source checks 15/15 passed. **No** FiveM runtime, SQL tests, Lua integration tests, frontend build or deployment. This is an **authorization ceiling split**, NOT completion of fire/hospital operational database separation. Next: audit server responder-domain reads/edits and permission-check paths per report/dispatch/calendar; preserve existing interagency dispatch/calls while isolating confidential medical records. Government remains restricted to its dedicated personnel backend and SADOT remains disabled.

## Stage 1 continued — report read and calendar mutation access (October 28)
- `server/backend/reports.lua`: direct report-by-ID access now uses the same **unrestricted report fallback families** as report listing. Listing also includes the actual `fire` framework type. Existing explicit citizen/job/jobtype restriction checks and DOJ's fire/medical private-report exception remain. Do **not** treat this as full employer-specific report isolation: reports with matching generic jobtype `fire` or `ems` still require a later departmental authorization and explicit sharing design.
- `server/backend/court.lua`: hearing deletion, single-attendee add/remove, and bulk-attendee add now check the parent hearing's existing `job_type` against the caller's calendar domain, matching the already-protected update and lifecycle callbacks. The removal path denies missing attendees rather than deleting on a missing parent. This closes cross-domain known-ID mutation routes; **fire and medical still share legacy `ems` calendar domain**, so separating fire/hospital *employer* calendars remains a distinct, migration-aware increment.
- Refetched source static checks 12/12 passed. No Lua syntax execution, SQL execution, browser compilation, FiveM test, or live deployment.

## Stage 1 continued — report read alignment, calendar mutations and permanent hearing history (Oct 28)
Commits on main:
- `server/backend/reports.lua` aligns direct report reads and general report-list default access to the same operational `leo`, `ems`, and `fire` categories; preserves explicit `citizenid`/`job`/`jobtype` grants and the DOJ restriction excluding fire/hospital reports without explicit access. This **does not** solve the still-broad intra-family access to reports that carry a generic `jobtype` restriction.
- `server/backend/court.lua` denies cross-domain deletion and attendee changes by known hearing/attendee ID. Four callbacks amended: `deleteHearing`, `addHearingAttendee`, `removeHearingAttendee`, `addHearingAttendeesBulk`.
- `config.lua`: `Config.Court.AutoStatus.DeleteOnComplete = false` retains completed court and service calendars, rather than automatically erasing hearings and attendee histories through the scheduler/manual status transitions. Historic records previously deleted cannot be reconstructed by this setting. Authorized deliberate deletion of an erroneous hearing remains a separate operation.
- Source checks 10/10 passed on refetched files after configuration update; prior 12/12 checks covered callback markers. **No compilation, Lua/SQL runtime test, FiveM deployment, data migration or user-server change.**
Next: agency-specific report ownership/privacy model and IA complaint routing must be designed against existing schema, preserving original records. Fire/hospital calendars still share the legacy `ems` calendar domain; split with a planned historical migration and authorized cross-employer invites, not by changing a single domain constant.
