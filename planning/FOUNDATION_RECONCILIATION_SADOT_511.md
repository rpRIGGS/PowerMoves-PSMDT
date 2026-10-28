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
