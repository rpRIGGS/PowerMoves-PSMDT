# PowerMoves PSMDT foundation reconciliation and SADOT / 511 proposal
Status: October 28, 2026 — owner-reviewed architecture, implementation still pending. This document is a checkpoint; it is **not proof of FiveM runtime testing**.
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
- **Implemented on this review branch only**, not merged/deployed: `Config.MdtAccess.BossPermissionMode='legacy'` and matching `server/auth.lua` role lookup support for an opt-in `'explicit'` mode.
- **Legacy mode (current default):** QBCore bosses keep the original job-type permission ceiling; nonboss employees use stored `mdt_permission_roles` grants, with per-job/per-grade `Config.PermissionDefaults` fallback. This is **not yet a security fix when left in legacy mode**.
- **Explicit mode (future switch after migration):** Bosses also read the stored job/grade permissions or per-job/per-grade defaults. QBCore `isboss` itself remains unchanged for same-job employment administration. If an agency's boss role has no stored grants/defaults it receives no general operational permissions; judicial authority still follows the narrow existing judicial rule.
- Code audit verified that the two modified source files differ from default branch only by this migration mechanism and its config setting. No Lua execution tests or FiveM runtime validation performed.
- **Required before enabling explicit mode:** enumerate every active LEO/DOJ/Fire/EMS leadership grade; inspect existing SQL role rows; design approved grants and their statewide oversight scopes; populate them; test boss/nonboss permissions and cross-agency attempts in automated harness and then FiveM development environment. Never enable `'explicit'` globally before that work is done.
- Note: current `GetMdtAccess` and related callbacks need a separate source-level review of intersection of selected interface with actual allowed actions, and the future fire/ems domain reconciliation. Neither is addressed by this minimal change.
