# PowerMoves PSMDT foundation reconciliation and SADOT / 511 proposal
Status: October 28, 2026 — owner-reviewed architecture; initial direct-to-main configuration and inactive SADOT identity added, operational implementation pending. This document is a checkpoint; it is **not proof of FiveM runtime testing**.
Scope: maintain one shared PSMDT, currently five interfaces; sixth SADOT.net is actively being explored. Never treat an unimplemented proposal as deployed.

## Binding principles
1. QBCore job type identifies service family; actual job name identifies employer/agency; rank plus explicit permissions determine actions and record visibility. `isboss` does not grant every MDT permission.
2. Statewide oversight is a separate **scoped grant**, not universal access for all workers at an oversight agency.
3. Existing agency jobs, grades, cases, histories, reports, permissions, and other working features are preserved unless a specific change is reviewed.
4. Separate interface identity from shared technical domains. Never equate `fire` and `ems` QBCore types without explicit scoped compatibility.
5. Changes: audit, implement in small review branches, regression-test, then owner-led FiveM runtime test. Never push speculative changes to the live server.

## Five interfaces and actual authorities
- **SADLE.net**: law enforcement; statewide standards, accreditation, certifications, investigations/internal affairs under authorized SADLE personnel. Head: Attorney General, QBCore `sadle` grade **11**; also authorized DOJ prosecution access, **not judicial authority**.
- **SADOJ.net**: courts, legal filings and personnel; judicial oversight led by **Chief Justice**, QBCore `sadoj` grade **10**. Judges: grades 8–10; prosecutors grades 5–6. Keep `lawyer` configured as future private legal practice placeholder. Existing `judge` legacy config pending review for removal; jobs.lua judge is commented out.
- **SAFR.net**: fire/rescue agencies; statewide fire/rescue oversight and accreditation under authorized SAFR personnel. QBCore type `fire`.
- **SAMS.net**: medical/hospitals; statewide medical oversight and accreditation under authorized SAMS personnel. QBCore type `ems`.
- **SAGOV.net**: civilian state, county and municipal government; own-jurisdiction powers and explicit cross-jurisdiction grants. State above parallel Blaine and Los Santos counties; City of Los Santos under Los Santos County.
Oversight must not automatically imply right to read every confidential case, medical chart, or departmental draft.

## Active agency inventory from planning-reference/jobs.lua
- LEO `leo`: `post`, `lspd`, `lspe`, `lscso`, `bcso`, `sahp`, `sasp`, `sadle`, `saspa`. Keep `fib` configured as future placeholder, not commented out.
- DOJ `doj`: `sadoj`. Keep `lawyer` in Config.DojJobs as future placeholder, not commented out.
- Fire `fire`: `safr`, `lsfd`, `lscfd`, `bcfd`.
- Medical `ems`: `pillboxmed`, `sandymed`, `paletomed`, `parsonsmed`.
- Government `gov`: `sagov`, `bcgov`, `lscgov`, `lsgov`.
- Generic `police`, `ambulance` are in planning-reference/jobs.lua but are not intended as operational MDT agencies; `gov` must not be a police agency. Do not delete live QBCore jobs based on this reference alone.
- `lspe` and `saspa` remain SADLE.net agencies, with appropriately restricted agency privileges.

## Verified foundation defects / review targets in GitHub
1. `server/auth.lua` rolePermissions currently grants a QBCore `isboss` worker their job-type ceiling, rather than using agency/rank permission grants. Remove that implicit blanket MDT grant **without breaking QBCore own-job employment authority**. Guard judicial authority separately.
2. `Config.MdtAccess.PermissionSets` has `leo`, `doj`, `ems`, `gov` but no independent `fire`. Current `server/auth.lua` normalizes recognized fire jobs to `ems` for legacy tabs. Preserve working EMS compatibility but audit all reads/writes against actual core job type and interface.
3. `server/backend/reports.lua` persists raw creator core job type as report restriction (e.g. `fire` vs `ems`); some report visibility queries still special-case `ems`. Compare every callback and ensure deliberate authorized sharing; do not expose police/medical reports improperly.
4. `server/backend/roster.lua` pulls a combined legacy EMS domain; audit agency-specific rosters and accreditation access. Government roster already has a separate explicit oversight grant `government_roster_oversight` and own-employer employment checks; reuse the explicit-authorization pattern where valid.
5. `config.lua` calendar `all_ems`, `ems_rookies`, `ems_on_duty` target raw `ems`, potentially excluding `fire`; audit dispatch audiences and training event recipients.
6. `config.lua` currently includes legacy `police`, `gov` in police job names, `ambulance` in medical, and `judge` in DOJ; track corrections separately from QBCore source jobs. Preserve configured `fib` and `lawyer`.
7. Audit Chief Justice court-wide management independently from general judicial case authority; audit AG's prosecution permissions independently from interface entry.
8. Do **not** infer that historical automated tests validate FiveM runtime. The user will test against a separate development server.

## SADOT.net — active design candidate (sixth interface), NOT yet implemented
Department of Transportation / towing / recovery / fleet maintenance; prospective oversight and operational records, without blanket police authority.
- All **on-duty QBCore `mechanic` type** jobs may receive public **511** calls. This includes authorized private garages and government fleet departments.
- Public caller uses **/511** (agreed service number). PS-Dispatch produces normal alert/blip, screen display, map, and response interaction, reusing existing **E** responder key.
- **First eligible mechanic to accept wins the tow assignment.** Must be a server-authoritative atomic claim: identify live source/job/type/duty and call status server-side. Concurrent later claimants receive already-assigned feedback. Do **not** rely on frontend E-button state for exclusivity.
- State transitions suggested for review: requested -> assigned -> responding/on-scene -> recovered/completed (plus cancelled/released). Record driver/employer, caller, requesting agency, plate, location, vehicle condition, destination, tow/impound audit history where applicable. Specific schema and vehicle-storage integration remain TBD.
- **Agency fleet maintenance requests** originate from their parent law-enforcement or government agency (not default 511 public queue). Dispatcher may route to its agency fleet staff by explicit job names.
- LEO / `lspe` may initiate towing or impound via existing MDT/PS-Dispatch integration. **Do not despawn immediately**: wait for a configurable confirmed recovery/impound workflow and retention/persistence rules; no working implementation yet.
- Departmental vehicle lookups, approved accident reports, tow audit reports, agency fleet records, and limited plate-reader data may eventually be available under distinct permissions. `lspe` remains `leo` for now; avoid redesigning its job classification.
- Potential SAGOV transportation position: absent from current state ranks; explore later, no rank changes authorized.
- Existing `mechanic` type includes private and government garages. The generic `tow` job is not shown as a `mechanic` type; it is **not** included by assumption in /511 eligibility.
- Current PS-Dispatch `shared/config.lua` has `Config.RespondKeybind='E'`, `Config.Jobs={'leo','ems'}` and `Config.OnDutyOnly=true`; no `mechanic` there yet. `server/main.lua` already has /911 and /311, no /511. `client/alerts.lua` maps phone calls to 911/311 audiences. `client/main.lua` E-respond currently checks only **job.type** against data.jobs, even though other dispatch parts support job names; fix as part of audience alignment. Existing `ps-dispatch:server:attach` allows several units per call and trusts client-supplied player data: cannot be reused unchanged for exclusive /511 claim. Introduce a dedicated validated flow while preserving multi-unit emergency calls.
- Future tow records/assignments should integrate with PSMDT; PS-Dispatch owns alerting and acceptance; actual towing/garage/impound resources own vehicle actions.

## Work sequence
A. Finish cross-interface permission and statewide accreditation audit (jobs/ranks -> permissions -> record scopes -> actual server callbacks).
B. Correct blanket boss grants with regression coverage and verify special AG/Chief Justice roles; do not remove existing employee management tools.
C. Reconcile `fire` vs `ems` domains and reporting/calendar/dispatch; update agency lists without dropping `fib`/`lawyer`.
D. Review separate SADOT.net architecture and /511 first-accept flow in PS-Dispatch; implement behind tests and feature flags or a separate branch when ready.
E. Owner-run integration tests on development FiveM server; no automatic merge/deploy.

Owner decisions captured October 28, 2026. Unresolved issues stay explicitly unresolved; avoid repeating previously answered questions.

## Implementation checkpoint — permission migration switch (October 28)
- **Implemented directly on main, not deployed:** `Config.MdtAccess.BossPermissionMode='legacy'` and matching `server/auth.lua` role lookup support for an opt-in `'explicit'` mode.
- **Legacy mode (current default):** QBCore bosses keep the original job-type permission ceiling; nonboss employees use stored `mdt_permission_roles` grants, with per-job/per-grade `Config.PermissionDefaults` fallback. This is **not yet a security fix when left in legacy mode**.
- **Explicit mode (future switch after migration):** Bosses also read the stored job/grade permissions or per-job/per-grade defaults. QBCore `isboss` itself remains unchanged for same-job employment administration. If an agency's boss role has no stored grants/defaults it receives no general operational permissions; judicial authority still follows the narrow existing judicial rule.
- The optional migration mechanism was committed directly to main; its default remains legacy. Other main-branch commits also remove obsolete generic agency entries and reserve disabled SADOT branding. No Lua execution tests or FiveM runtime validation performed.
- **Required before enabling explicit mode:** enumerate every active LEO/DOJ/Fire/EMS leadership grade; inspect existing SQL role rows; design approved grants and their statewide oversight scopes; populate them; test boss/nonboss permissions and cross-agency attempts in automated harness and then FiveM development environment. Never enable `'explicit'` globally before that work is done.
- Note: current `GetMdtAccess` and related callbacks need a separate source-level review of intersection of selected interface with actual allowed actions, and the future fire/ems domain reconciliation. Neither is addressed by this minimal change.

## Direct main implementation checkpoint
- `config.lua` removes obsolete MDT list entries `police`, generic `gov`, generic `ambulance`, and DOJ `judge`; retains both `fib` and `lawyer` enabled. QBCore `planning-reference/jobs.lua` was not modified.
- `config.lua` has `Config.MdtAccess.Transportation` marked `Enabled=false`; it reserves the `mechanic` job type and public `511` dispatch concept without granting access.
- `web/src/interfaces/IUser.ts` and `web/src/constants/index.ts` now recognize the `sadot` interface identifier/branding for future implementation; no new routing or live dashboard was added.
- `server/auth.lua` and `config.lua` add `BossPermissionMode='legacy'` default as a safe **opt-in** transition path to explicit job/grade permission grants. This does not cure overly broad boss permissions until the permission matrix is populated and `explicit` can be safely enabled.
- Direct-to-main workflow required by owner. No PR-based development, no server deployment, and no FiveM runtime claims.

## Foundation implementation checkpoint — Fire / EMS and DOJ calendar (October 28, main)
- Split Config.MedicalJobs into **four hospital jobs** and new Config.FireJobs into **four fire jobs**; defined QBCore `Config.FireJobType='fire'` and kept `Config.MdtAccess.FireJobs` as alias. `fib` and `lawyer` remain configured.
- Updated `server/auth.lua` to route QBCore type `fire` or configured FireJobs to SAFR.net and type `ems` or MedicalJobs to SAMS.net. Both still use the internal **legacy `ems` permissions/data domain** for compatibility until access and record sharing are redesigned and tested. No additional statewide accreditation grants were introduced.
- Updated `server/functions.lua` IsEmsJob compatibility classification to recognize actual `fire` and `ems` jobs. Shared roster in `server/backend/roster.lua` includes both agency lists; fire certification tag retrieval is now explicitly scoped using job_type `fire`, instead of returning every tag. Detailed personnel and accreditation permissions still need a separate security audit.
- Calendar groups now include all-fire and on-duty-fire within the existing EMS calendar domain. Corrected the old Judges group to `sadoj` grades 8–10; `server/backend/court.lua` supports optional minGrade/maxGrade selectors.
- DOJ general report list and dashboard filter now exclude restricted QBCore `fire` reports alongside `ems` reports. **Other report reads/access paths still require audit**; this is not a complete clinical/fire privacy implementation.
- Source retrieved after commits confirms intended markers in all seven edited files. **No runtime, Lua harness, TypeScript build, SQL integration or FiveM tests were executed**, so behavior remains unverified. No deployment occurred.
- Further priorities: scope direct report access consistently; validate fire certification write authority; fully audit personnel mutation and statewide accreditation; review exact owner-approved job/rank permission matrix before enabling BossPermissionMode='explicit'; update PSDispatch `fire` audience and later implement /511 with exclusive tow-claim. Do not enable SADOT.net or its mechanic access prematurely.

## Follow-up security correction — direct report reads (October 28, main)
- The `getReport` callback previously selected report details solely by ID after general MDT authentication; now it checks `checkReportAccess` before fetching content.
- `checkReportAccess` previously unconditionally allowed DOJ. It now permits ordinary non-private reports to DOJ while excluding raw `ems`/`fire` jobtype-restricted reports unless an explicit matching citizen, job, or job-type grant exists; the same principle is used by general report listings.
- This is a **source-level change only**, not confirmation of a complete role/record-security implementation. Audit all report-related endpoints (including by-plate, edits, other metadata) and regression-test DOJ case-workflows and intentionally shared reports. Existing stored reports were not migrated.

## Continued foundation fixes — DOJ roster and PS-Dispatch fire compatibility
- **PSMDT main:** `server/backend/roster.lua` now routes ordinary SADOJ employees to the DOJ job list and `doj` type, instead of falling through to the law-enforcement roster. Attorney General cross-interface roster access remains a separate outstanding authorization decision; no new DOJ employment privileges were granted.
- **PowerMoves-PSDispatch main:** `shared/config.lua` now allows QBCore `fire` to open dispatch; `client/main.lua` E-response accepts calls targeted either by job *type* or *agency name* while respecting `Config.OnDutyOnly`. This enables proper named-agency fire calls, but does not create /511 yet or authorize `mechanic` access.
- **Still outstanding:** server-side `ps-dispatch:server:attach` receives client player data and has no exclusive tow-claim logic. Before /511 first-accept dispatch, verify source identity/eligibility server-side, then add atomic claim and proper release/reassignment without modifying multi-unit emergency behavior. The complete report/roster and accreditation permission audit remains open.
- All changed files were read back from their default branches; automated Lua integration tests, FiveM runtime tests, and server deployment were NOT performed.

## PS-Dispatch /511 implementation checkpoint — October 28, direct main
**Implemented in separate repository** `rpRIGGS/PowerMoves-PSDispatch` on `main`:
- `/511 <message>` uses the existing caller/phone dispatch flow; its alert is `511call` targeting job type `mechanic` and has its own blip. QBCore on-duty mechanics can open the dispatch menu.
- Server verifies live QBCore citizen/job/duty when attaching; untrusted client-supplied player tables are ignored. Legacy police/fire/EMS calls remain multi-unit.
- `511call` is exclusive; the first eligible driver is confirmed by `ps-dispatch:callback:claimTow`. Both popup E and UI attach wait for confirmation before showing "Responding" and waypoint.
- A claimed tow is omitted from other mechanics' available-call results and removed from their active board; reassignment occurs after disconnect, detach, or changing to another dispatch. Separate 511 requests are never merged into one incident.
- Only the assigned on-duty tow driver can clear/manage an accepted 511 call; off-duty units can release their assignment.
- **Static source checks passed (12/12); Lua execution, database and FiveM runtime tests are NOT performed**. The stored dispatch call is not a durable tow audit record; it can expire, be cleared, or be lost on restart.
**Not implemented**: SADOT.net operational interface/access, vehicle condition reports, tow/impound completion integration, persistence/auditing, fleet-targeted MDT call buttons, automatic vehicle handling, 511 UI field specialization, cross-agency accident/vehicle-record permissions. Keep the `Config.MdtAccess.Transportation.Enabled=false` placeholder until ready.

## Persistent tow journal implementation — direct main commit, October 28
**PowerMoves-PSDispatch** now loads oxmysql (declared dependency) and includes `server/tow_records.lua`, creating `pm_sadot_tows` and `pm_sadot_tow_events` if missing. A server-generated `towRef` links each /511 dispatch call to the durable ledger. Request, first claim/assignment, driver release/requeue, dispatch completion and expiry are written with monotonic revisions and a unique per-revision audit event. Internal caller identity/revision are omitted from the client dispatch payload. Server-only exports `GetSadotTow(ref)`, `GetSadotTowEvents(ref)`, and `GetSadotTowByPlate(plate)` provide read access for future authorized SADOT integration.
**Critical distinction:** A driver's clearing of the dispatch call records *dispatch completion*, not proof that a physical vehicle has been towed or impounded. There is **no vehicle transport, storage, cleanup, impound integration, plate verification, or SADOT web page yet**. Add those only after inspecting the actual vehicle/garage/impound scripts and defining authoritative completion. Current tow dispatch state is still held in memory, and outstanding assignments are not restored as active blips after a server restart; the durable ledger is an audit trail, not full job-queue restoration.
Static source checks: 16/16 implementation markers present after fetch from main; NOT executable Lua/SQL/FiveM validation. Requires oxmysql DB permissions (CREATE TABLE for auto schema), actual resource start and restart tests, two mechanic claim race, release/requeue, offline behavior, and dispatch UI verification before production use.

## Assigned-driver 511 vehicle inspection — main implementation
**PowerMoves-PSDispatch/main** now has an in-game `/towreport` action for on-duty QBCore `mechanic` drivers assigned to an active 511 call. It finds their assigned call, opens an ox_lib dialog for plate, model, condition, destination and notes, and submits the report using a server callback that re-checks the live player job, duty and assignment. A separate `pm_sadot_tow_inspections` table preserves each submission without overwriting earlier inspection reports. The main tow ledger's plate field is also indexed/updated for plate lookup. Server-only `GetSadotTowInspections(ref)` fetches inspection history.
**Not completed:** Physical tow, garage transfer, storage/impound action, verified recovery confirmation, and a standalone SADOT.net user interface. This form creates *driver-reported observations*, not proof of vehicle removal. No towing/impound integration script was found among the accessible linked `rpRIGGS` repositories; connect the actual vehicle storage resource only after its interface is examined. 11/11 source markers checked, but Lua syntax, database execution and live FiveM flows are not validated.

## Execution checkpoint — reusing original LEO training/FTO (October 28)
Direct `main` commits:
- Enabled the existing `FTO` and `SOP` navigation for the EMS-family UI (which currently services SAFR and SAMS) and included existing `FTO` page under the DOJ navigation; this is **not** a new duplicate engine.
- Added `fto_view`/`fto_manage` to the DOJ permission ceiling, so qualified DOJ grades may be granted the same FTO workflow. It does not automatically grant all DOJ employees management permissions.
- FTO backend now uses distinct `police`, `ems`, `fire`, `doj` training families for newly written records, derived from real QBCore job types/names rather than screen branding. Existing police and medical legacy family values remain unchanged.
- The existing `mdt_fto_assignments` table gains nullable `agency_job` through `EnsureColumn`. New assignments save the creator's actual job; list/detail/history/mutation paths restrict them by job AND training family. Existing rows with NULL `agency_job` remain accessible under the older family-based policy pending a verified migration; do not assume historical job ownership.
- **Not yet implemented:** separate SAGOV and SADOT FTO navigation/authorization; overseer credential/qualification access across subordinate agencies; default medical/fire/legal phase templates; individual leadership permission defaults; dispatcher/license enforcement; QBCore job confirmation for selected trainers/trainees; actual testing/build.
- The existing LEO FTO engine, source callbacks and database are reused, not rewritten.
- Source-level re-fetch confirmed the file changes. No executable Lua, frontend build, SQL migration, or FiveM integration tests performed.

## Owner-directed agency training standards and calendar architecture — October 28
Verified in `planning-reference/jobs.lua`:
- `post` is the existing **Peace Officer Standards and Training** academy job under the SADLE law-enforcement oversight structure. Recruits complete POST before entering LSPD, sheriff, state and other law-enforcement agencies. The POST instructional/certification lifecycle is distinct from each employing agency's FTO period; completed POST records should follow the person via the shared qualifications registry.
- `safr` is the statewide fire standards/accreditation and operational state agency. Individual local/county fire jobs (`lsfd`, `lscfd`, `bcfd`) receive SAFR-defined academy/qualification standards but manage their own personnel and subsequent in-service training. SAFR can also operate statewide resources such as firefighting aircraft and pilots; do not restrict its duties to only accreditation. No invented new firefighter pilot grades yet.
- Hospital jobs (`pillboxmed`, `sandymed`, `paletomed`, `parsonsmed`) are `ems`. SAMS administers medical qualifications/accreditation statewide while actual hospitals keep separate personnel/training and medical access. Fire-department paramedics remain in `fire` and use their fire employer's records; corresponding medical qualifications can be recognized via SAMS without changing their QBCore job.
- `sadoj` grades 0–10: Needs Onboarding (0), Court Clerk (1), Law Clerk (2), Public Defender (3), Chief Public Defender (4), Assistant District Attorney (5), District Attorney (6), Clerk of the Court (7), District Judge (8), Associate Justice (9), Chief Justice (10). A law-clerk-to-legal-counsel path needs distinct training/education/Bar licensing evidence before legal appointment; no automatic law license on grade change. Private practice must rely on permitted lawyer role/license validation, not blanket DOJ employment access.
- **Do not label DOJ staff "officers"** or reuse law-enforcement-specific trainee names. Existing `FTO.svelte` now includes an initial conditional legal/fire/medical wording pass, preserving original LEO labels; full UI copy and training rubric work remain.

**Calendar correction:** existing `server/backend/court.lua` still groups LEO+DOJ into `police` and medical+fire into `ems` by `GetMdtDomain`. This **does not meet** the desired agency calendars. Preserve the existing court-event functionality while adding employer-specific internal events, fire academy / statewide training audiences, medical training audiences, and separate court judicial/prosecutor/defense scheduling. A shared event may explicitly invite approved personnel from other agencies rather than grant every agency read access to its organizer's calendar.

**Future availability feature (not yet implemented):** individuals record availability/unavailability against their identity and employer, with optional recurring patterns and exceptions. Fire leadership sees roster availability for its own department, SAFR oversight sees permitted statewide training availability, and SADOJ authorized court schedulers can inspect relevant invited lawyers/prosecutors/public defenders/judges for conflicts. Never treat availability as duty state; protect private details and avoid exposing calendars to unauthorized audiences. A future court scheduling assist should return conflicts/available slots but never book courts automatically without approval.

**Implementation order:** existing LEO/EMS/DOJ workflows and stored records remain baseline. Reuse FTO, training, roster, certification, report, and calendar components. Brand per interface and per agency. Separate internal record visibility and statewide standard-setting authority. Next coding priority: calendar agency-scope server authorization + migration preserving existing court cases/hearings, then department-specific training templates and credential milestones. No empty feature clones, no extra applications.

## Completed implementation checkpoint — personal training transcript
The existing PSMDT FTO screen now includes **My Training History**, backed by the existing FTO assignment table and the caller's live citizen ID. This is the *same* training UI used across the enabled service interfaces: **no separate application or duplicate training engine**.
- Existing server callback `getMyTrainingTranscript` returns trainee history across current and previous employers; does not expose private DOR notes/ratings.
- Existing `client/backend/fto.lua` now proxies the callback with an open-MDT guard; `web/src/constants/nuiEvents.ts` includes the action in its allowed event map.
- Existing `web/src/pages/FTO.svelte` now has a **My Training History** button and read-only history view with issuing/training agency job when known, service family, phase, start/end dates and status.
- The roster's earlier server-side `getOfficerFTOHistory` change allows authorized current-employer managers to read historical milestones after a transfer, while detailed DOR access stays agency-scoped.
- Source-level consistency checks 10/10 pass. **Frontend dist has not been rebuilt or deployed; no Lua execution, FiveM, or database tests have been run.** The visible feature requires rebuilding `web/dist` with the repo's existing frontend tooling. Existing certifications still use `mdt_profiles.certifications` JSON; issuing authority and accredited-agency standards/expiry remain future implementation.

## Executed next stage — personal statewide accreditation registry
Code directly committed to PSMDT `main`:
- `server/backend/accreditation.lua` stores append-only, person-owned statewide credentials in `mdt_personal_accreditations`, including code/title, service family, issuing job and citizen, issue/expiry dates, specialization and optional source reference. Existing roster certification tags in `mdt_profiles.certifications` remain intact and editable as before; those tags do **not** automatically become authoritative state certifications.
- Issuance is server-authorized only for credential officials working in `post`, `sadle` or `safr` **with** the existing `roster_manage_certifications` permission. Issuer family is recorded as `leo` or `fire`; no blanket permission from agency membership alone. The initial issuer form uses manual credential code and citizen ID, not yet a centrally approved standards catalog.
- Server callbacks `getMyAccreditations` and `getPersonnelAccreditations` allow self-read across job transfers and appropriate current-agency supervisory read. Cross-agency accreditation oversight policy and revocation/renewal management are not implemented.
- `client/backend/accreditation.lua`, `web/src/constants/nuiEvents.ts` and existing `web/src/pages/FTO.svelte` link the state credential view/issue form into the FTO page. `web/src/pages/Roster.svelte` shows read-only state certifications alongside editable legacy department tags.
- Credentials are append-only in this pass: **a credential is not automatically proof of active accreditation until expiry and later suspension/revocation policies are implemented**; do not implement vehicle/operator eligibility based on this primitive alone.
- Source validation 12/12 consistency markers passed, confirmed both backend client glob patterns in `fxmanifest.lua`. **No live MySQL runtime/FiveM tests or `web/dist` production build have been run**. A frontend build and live QA are mandatory for deployment.
