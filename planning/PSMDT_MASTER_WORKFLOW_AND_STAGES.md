# PowerMoves PSMDT — Master workflow, source checkpoints, and phased execution

> **IMPLEMENTATION ORDER SUPERSEDED (October 28, 2026):** The staged order below mistakenly prioritized civilian FOIA intake ahead of the original six-interface foundation. The current authoritative coding order is [`planning/PSMDT_FOUNDATION_FIRST_EXECUTION_PLAN.md`](PSMDT_FOUNDATION_FIRST_EXECUTION_PLAN.md): audit/source baseline, interface routing and scoped job/rank permissions, working module parity, agency ownership, training/calendar, interagency cases, then public-service intake and government/DOT vertical integrations. Preserve completed source work; do not mistake it for deployed/tested functionality.


Updated October 28, 2026. **This document is a consolidated implementation contract**, drawn from the existing `POWERMOVES_PSMDT_PROJECT_CONTEXT.md`, `POWERMOVES_PSMDT_CODEX_CONTEXT.md`, foundation checkpoints, and owner discussions. A planned capability is **not** a claim that code works in FiveM.

## Current execution-stage naming — October 29, 2026

The active sequential implementation plan is **not** identical to the older
workstream-number table retained below. Do not silently apply the historical
table's "Stage 5 — calendar scoping" label to current development.

- **Stage 4:** investigation/referral/discovery source checkpoint; DEV FiveM acceptance remains separate.
- **Stage 5 (active):** configurable `qb-target` public-service counters and civilian IA/public-records access, agency records-office MDT review, requests and assigned reviewers, applicant-scoped decision notices and explicitly granted, expiring/revocable public copies, with audit and privacy checks. Source validation and DEV acceptance must be separately recorded.
- **Stage 6 (next):** government/jurisdiction and transportation specialization (SAGOV/SADOT), preserving all shared MDT, permissions and agency boundaries. Do not imply SADOT is operational before its gates are implemented.

The historical workstream entries below still identify separate unfinished work
such as calendar scoping and government functions; they do **not** redefine
the current Stage 5 or authorize dropping those requirements.

## Non-negotiable foundation

- Remain on **QBCore**. One existing `ps-mdt` resource, shared database, interoperating with `PowerMoves-PSDispatch`; six agency-family interfaces `SADLE.net`, `SADOJ.net`, `SAFR.net`, `SAMS.net`, `SAGOV.net`, `SADOT.net`. Reuse the already working PSMDT LEO functions, adaptations, and proven handlers rather than starting a new MDT or six data stores.
- **Existing jobs.lua is authoritative**. Police job type is `leo`, hospitals `ems` (do NOT rename to `medical`), fire `fire`, DOJ `doj`, government `gov`, DOT mechanics `mechanic`. Actual employment is a QBCore job; selected .net interface never changes it.
- Departments own their daily operations: departmental rosters, SOPs, restricted case files, shift/station/unit assignments, and field training. They should appear together in the employee's one agency-facing interface. Stations/companies/districts are subordinate units of an employing department, not necessarily separate jobs.
- State oversight is **specific and authorized**, not universal cross-agency access. SADLE: state LEO accreditation, POST, state prison authority, IA and investigations under AG. SAFR: statewide fire academy/standards and operational state fire/aviation. SAMS: statewide clinical accreditation/medical authority and multiple hospitals. SAGOV: state/county/municipal governance. SADOT: transportation regulator and licensed towing operators. SADOJ: separate judicial branch / Chief Justice and court system.
- Agency and individual accreditation are distinct. POST prepares and qualifies LEO/corrections entrants to their proper classifications. Accredited employing agencies **continue state-standard training themselves** through their supervisors, trainers and FTOs; SADLE monitors compliance. Similar SAFR academy and accredited local/county fire training model. Credentials are permanent personal history; agency FTO/DORs carry authorship and appropriately scoped confidential notes. The same shared training component must be adapted for SAMS clinical training and SADOJ legal mentorship/bar pathways.
- Individual department calendars; authorized statewide academy events, court sessions, and shared invitations are separate visibility concepts. Personal/streamer **recurring availability**, shift planning and tsunami/timezone scheduling are valuable but **deferred**, not prerequisites for agency calendars.
- Report classification **tags** do not themselves grant access. Existing `mdt_reports_restrictions` can authorize a specific citizen ID, job, or job type. Existing case/report/evidence linking and DOJ participant assignment are starting points; **do not assume** that tagging, involving an officer, or assigning counsel creates an access grant or notification. Implement explicit, server-enforced routing, record visibility, audit, and revocation.
- Existing owner-defined department SOPs, IA/FTO standards, and roleplay law govern approvals. Do not rewrite policies or invent law. Each agency assigns appropriate records personnel to review/approve public-records/FOIA requests; approved material is disclosed to the authorized requester's **citizen ID**, with a release record/redactions where required. Do not expose unapproved internal reports or patient charts merely because a request exists.
- Public civilian services use configurable **in-world `vector3` + radius circle or polygon zones**, `qb-target` and existing public NUI, not an MDT tablet for every civilian. Multiple agency desks/locations support different services. They are **not** the property-jurisdiction PolyZones that were explicitly rejected for PS Realtor property setup.
- SAGOV jurisdictions: state over Blaine and Los Santos counties, the counties are peers; City of Los Santos within Los Santos County, future municipalities extensible. Separate unapproved drafts and published records. Property listings start in PS Realtor, PS Housing contributes ownership; SAGOV assessor queues/approval/taxes/licensing use authorized appointed government staff. One applicable local business license by default; towing requires **additional** SADOT operator qualifications.
- SADOT.net is the sixth interface but must stay disabled for broad mechanic access until permit/qualifications and authority checks are working. Existing /511 first-claim dispatch and persistent tow ledger integrate through PSMDT; future towing reports go into existing MDT reporting, not a new duplicate /towreport.
- Preserve old data, histories, warrant and case/evidence custody; test in a development environment. No broad re-permissioning of bosses without job-grade matrix; no untested migration of live schema, no uncontrolled public cross-agency reads. Direct commits to owner's `main` have been requested; source commits are **not** live server deployments.

## Real-world workflows — one shared engine, six presentations

### Citizen-facing intake
Citizen physically visits a configured lobby/counter/terminal or uses an explicitly permitted public interface. The configured services are displayed via `qb-target`. IA complaint uses existing standalone `ComplaintForm.svelte` and existing server complaint callback. Public-records/FOIA intake is **not** yet implemented. Other possible public modules include licensing, permits and appropriate citizen portals, only after their intake/approval flow exists. Intake must persist responsible jurisdiction/agency and requester identity and reach authorized assigned workers, with tracking/status and audit.

### Agency records and confidentiality
Agency employee creates ordinary or confidential report, attaches witnesses/personnel and evidence using original PSMDT. Department-only defaults remain. When an agency requests oversight/review, the resulting referral **queues** to designated authorized personnel at the receiving oversight agency. Its classification tag (e.g. referred to SADLE) is not itself the queue nor access permission. An explicit citizen/job/role grant permits selected documents to be opened. No implicit broad information access from supervisor `isboss` or generic screen switch.

### SADLE and corrections
BCSO/LSPD or another LEO department investigates locally and refers an IA/corruption matter to SADLE as appropriate. SADLE investigators review assigned restricted material; investigators may share an approved report/disclosure with specific departmental command members. SADLE and POST accredit *individuals and employing agencies*, including corrections-specific classifications for the San Andreas State Prison Authority. Agencies maintain their own continuing field training; POST/authority own statewide standards and compliance oversight. The existing IA complaint backend and report restrictions are reused and enhanced rather than replaced.

### DOJ case and discovery
Authorized prosecutor/clerk opens a DOJ court case; existing `mdt_court_cases` record stores judge, prosecutor, defense attorney citizen IDs/names, linked original investigative case ID and originating report ID. Original cases can link multiple `mdt_case_reports` and evidence. A **separate authorization check** is required before case participants can read each linked sensitive item. Prosecution, assigned public defenders and independent counsel receive case-specific discovery/disclosure packages as approved; access is revocable/audited. Retain all closed case and court history permanently; existing court hearing/calendar is reused.

### Public records/FOIA processing
Request goes to responsible agency; **that agency's designated records employee** reviews and approves/denies under its established SOPs. On approval, selected/releasable records or release copies receive an explicit grant to the requesting citizen ID. Request/decision/grant/access expiration and revocation are auditable. Applying an ordinary tag never grants access automatically. Medical, IA, personnel and pending court materials require their own agency-specific release restrictions—never universal publication.

### SAFR / SAMS
Fire departments maintain local stations, apparatus companies, shifts, personnel, SOPs and ongoing instruction under SAFR standards. SAMS is independent statewide hospital/medical accreditation and clinical charting oversight; hospitals have their own rosters, SOPs, medical training, case records and schedules. Preserve QBCore `fire` vs `ems` distinction and protect patient/clinical records. Fire/EMS incident cross-citations do not automatically share confidential hospital charts.

### SAGOV / SADOT
Government agencies at each jurisdiction manage their own records and public service responsibilities while state roles have explicitly granted oversight. Assessors under State of San Andreas review PS Realtor properties, jurisdictions, exemption approvals and tax histories. Local business licensing and permits are scoped to appropriate authority. SADOT oversees tow permits, qualified operators/vehicles, 511 recovery history and accessible vehicle records; user permits precede enabling mechanic MDT access.

## Staged execution: each stage must ship a usable result, not only a heading

| Stage | Work | Completion criterion | State |
| --- | --- | --- | --- |
| 0 | Reconcile requirements against real repo, jobs, sources, and prior notes | This document and source audit; no invented jobs or rewritten policy | Completed for baseline; continuous audit |
| 1A | Configurable in-world civilian service access | Configurable `vector3` circles/radii and polygon zones; `qb-target` opens existing IA complaint form; no fictional coordinates | **Committed source**; needs config location and in-game QA |
| 1B | Public records request intake | Persist request, requester citizen ID, receiving agency, status, responsible officer; public NUI from same location service handler | Not implemented |
| 1C | Agency records administration | Permission-controlled review/decision, per-record release, citizen-ID grants, audit and revocation; requester only sees approved release material | Not implemented |
| 2 | Unified referral / discovery permissions | Route tagged-and-explicitly-referred IA/report/case tasks to authorized receiving work queues; proof of access, case participant grants, evidence/docs, court discovery | Existing associations only; not fully implemented |
| 3 | Agency-specific core parity | For all six: usable dashboard, reports, searches, rosters, SOPs, calendars and actual service-tailored forms; preserve legacy LEO | Partial; SADOT remains disabled |
| 4 | Accreditation / continuing training | Agency-accreditation standards and accredited employer supervision; personal state credentials; SOP/FTO/department-specific rubrics for SADLE/SAFR/SAMS/DOJ and licensed DOT | Personal credential registry + FTO work in source; SAMS/others incomplete |
| 5 | Department and statewide calendar scoping | Own department calendar plus authorized training/court invitations; no cross-agency calendar leaks | Existing broad legacy police/EMS domains; needs migration |
| 6 | Government + transportation verticals | SAGOV applications, assessors, publication/FOIA and license processing; SADOT qualified operators, 511 reports and records via existing MDT | Foundation partial, interface functions incomplete |
| 7 | Optional staffing availability | Recurring individual play schedules, supervisor forecasts by station/shift, timezone and server tsunami cycles | Deferred explicitly |

## Stage 1A implementation checkpoint — October 28, 2026

- `config.lua:Config.PublicServices`: enabled feature with empty actual locations; circle `coords = vector3(...)` and `radius`, or polygon `points = {vector2(...)}` and `minZ/maxZ`, location ID, agency, allowed service IDs, interaction distance.
- `client/backend/public_services.lua`: reads zones, supports `qb-target:AddCircleZone` and `AddPolyZone`, registers when target is available, cleans up on stop, ignores nonexistent service handlers. The implemented `ia_complaint` service opens the **original** public complaint NUI. Old `/complaint` command and export remain intact.
- No actual location is enabled until the server owner fills coordinates. There is deliberately **no working FOIA button yet**, because an unimplemented request form must not be advertised as functioning. The agency/location metadata will be needed for agency-specific request routing in Stage 1B. No property-zone code is affected.
- These are GitHub **source commits**, not confirmed FiveM runtime behavior. Build/launch and `qb-target` integration require in-game testing. Record actual config coordinates from the user's MLOs when available.

## Release/test gates

1. Inspect actual `fxmanifest.lua` client load glob and `config.lua` options.
2. Add test coordinates *only in a development setup*, then use target at circular counter and polygon counter, confirm single menu item, actual existing complaint form, successful DB complaint, proper close, no duplicated target zones after reload, and no options for unfinished services.
3. Verify no tablet entitlement needed; disabled/missing target resource fails safely, no errors after resource stop/restart.
4. Continue stage 1B only by extending the same public-service entrypoint with real agency-scoped request data/permissions; do not invent a second NUI/MDT system.
5. Reconcile and test manager permissions, case access, evidence read/write paths, and confidentiality separately before claiming a complete secure disclosure or discovery release.

## Source boundaries / known limitations

- Existing report `tags` categorize/search; `mdt_reports_restrictions` grants by `citizenid`, `job`, `jobtype`. Case links (`mdt_case_reports`) and court assigned legal parties do not **themselves** prove authorization or notifications. The current source has access-control gaps on some case/report/IA paths; no untested UI should promote unrestricted sharing.
- Existing `roster_manage_certifications` and new `mdt_personal_accreditations` cover only part of the desired standards. Issuance currently recognizes POST, SADLE and SAFR, **not SAMS yet**, and lacks official standard catalogs and revocation. Do not equate roster tags with authoritative qualifications.
- IA complaint records use domain scope but not yet robust per-employer ownership, case-level referrals, or command disclosure.
- No claim of browser compilation, Lua execution, database schema migration, actual UI dist rebuild or FiveM validation is made by these source commits.
