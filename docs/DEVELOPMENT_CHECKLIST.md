# PowerMoves PS-MDT — Development Inventory and Completion Checklist

Last reviewed: 2026-11-01
Source of truth: this repository's main branch, including `config.lua` and `planning-reference/jobs.lua`.

## Rules for checking off work

- [x] Establish a repository-based checklist instead of relying on chat summaries.
- [ ] Mark a workflow complete **only** after its UI, client/server integration, database handling (if applicable), permissions, and code-level validation have been inspected.
- [ ] Preserve working upstream PS-MDT functionality and existing data; avoid broad rewrites.
- [ ] Complete SADLE/LEO before moving into major new workflows for the other portals.
- [ ] Review existing open PR #2 against main before merging anything.
- [ ] Keep commits coherent and substantial; no artificial commit quota.

## Verified foundation (code/config inventory, not end-to-end signoff)

- [x] Six interface registry entries in `config.lua`: SADLE, SADOJ, SAMS, SAFR, SAGOV, SADOT.
- [x] Six separate sharing policies: `Config.Sharingleo`, `Sharingdoj`, `Sharingems`, `Sharingfire`, `Sharinggov`, `Sharingdot`.
- [x] Explicit oversight agency mappings in the interface registry.
- [x] QBCore job families configured as `leo`, `doj`, `ems`, `fire`, `gov`, and `mechanic` where applicable.
- [x] SADOT fleet configuration consolidated to `safleet`, `bcfleet`, `lscofleet`, `lscityfleet` (sharing and interface registry).
- [x] Public service desk configuration present, including intended vector-based counters.
- [x] Original PS-MDT runtime manifest and upstream feature base retained.
- [ ] Audit all runtime consumers of the six sharing policies and ensure they enforce the intended authorization server-side.
- [ ] Audit job names across every runtime module against the active `planning-reference/jobs.lua` entries.
- [ ] Confirm no stale references to retired fleet job names outside `config.lua`.

## Delivery order — complete features before defect hunts

1. **LEO foundation and configuration** — job roster, agency identity, SADLE oversight, access/permissions, sharing policy. This is the active deliverable.
2. **LEO operational records** — reports, investigations, evidence, warrants, BOLOs, and associated search workflows.
3. **LEO personnel operations** — rosters, ranks, training, certifications, FTO.
4. **LEO oversight and public access** — IA, complaints, public records, qb-target service counters.
5. **LEO integration and code-level acceptance** — regressions and completion review.

Only investigate incidental defects when they block the active deliverable; do not substitute defect-hunting commits for feature completion.

### LEO foundation inventory (2026-11-01)

- [x] **Configuration alignment inspected:** `Config.PoliceJobs` includes `police` (dev), `post`, `lspd`, `lspe`, `lscso`, `bcso`, `sahp`, `sasp`, `sadle`, `saspa`; each name is present in `planning-reference/jobs.lua`.
- [x] **Oversight configuration inspected:** `Config.Interfaces.sadle.OversightJobs` contains `sadle`; `Config.Sharingleo.OneWay` allows `sadle` to view configured LEO departments, including independent State Parks (`sasp`).
- [x] **Agency isolation policy inspected:** `Config.Sharingleo.Mutual.departments` is empty; peer agencies do not receive blanket mutual access from this configuration.
- [x] Officer callsign, radio, unit location and source-ID callbacks now require authenticated SADLE identity and configured LEO job (commit 0a05a34).
- [x] Inspected roster rank-change callback: `promoteOfficer` validates the requested grade against QBCore job definitions, checks department personnel authority, rejects self-promotion, and verifies the target session before `SetJob`. This is code inventory, not integrated signoff.
- [x] Revalidate requesting character and statewide oversight after roster loading; revoked statewide access cannot return cross-agency personnel from an in-flight roster request (commit 20d90b9).
- [ ] Trace the actual runtime access evaluator and permissions registry to verify the configuration is honored across the LEO interface.
- [ ] Inspect and complete agency rank/grade handling against the active jobs reference.
- [ ] Confirm all LEO modules use the configured oversight and sharing policies, rather than legacy hard-coded assumptions.
- [ ] Sign off LEO foundation as an integrated feature only after the above are validated.

## SADLE.net — LEO workflow completion (current priority)

### 1. Access, identity, and agency boundaries
- [ ] Trace MDT open/authentication from client to server; verify job, duty, rank, and agency checks.
- [ ] Confirm SADLE statewide oversight does not automatically expose restricted records beyond explicit authorization.
- [ ] Confirm San Andreas State Parks is treated as its own state-level LEO agency.
- [ ] Verify cross-agency report restrictions, tags, record visibility, and confidentiality at each server callback.
- [ ] Verify denied access cannot be bypassed by directly invoking callbacks/events.

### 2. Reports, investigations, and evidence
- [ ] Trace report creation, editing, retrieval, attachment, and deletion/archival workflows.
- [ ] Verify case links, evidence, warrants, BOLOs, and citizen/vehicle/weapon record access.
- [ ] Ensure record visibility is consistent in search, detail, and export paths.
- [ ] Preserve existing PS-MDT data structures and functionality.

### 3. Personnel and department operations
- [ ] Trace agency rosters, ranks, role management, and supervisor authority.
- [ ] Audit training, certifications, and FTO workflows and their persistence.
- [ ] Ensure cross-agency personnel changes are restricted to authorized roles.

### 4. Internal Affairs and public records
- [ ] Trace existing IA complaint submission, assignment, status, investigation, and audit handling.
- [ ] Verify configured qb-target/vector public service counters use the existing backend; no slash-command-only replacement.
- [ ] Trace public-records request intake, review, release, and protected-record redaction.
- [ ] Verify civilian and employee views never expose confidential material.

### 5. LEO integration signoff
- [ ] Validate relevant Lua/JS/TS/Svelte code paths and regression coverage.
- [ ] Review SQL migrations and backwards compatibility.
- [ ] Document remaining environment-only verification separately; do not claim live testing.
- [ ] Complete code-level LEO signoff before advancing portal development.

## Other portals (foundation exists; workflows not signed off)

- [ ] SADOJ.net — courts, prosecutors, cases, sealed records, and judicial access.
- [ ] SAFR.net — fire incidents, EMS runs, personnel, certifications, and oversight.
- [ ] SAMS.net — hospital charts, patient confidentiality, and EMS handoff.
- [ ] SAGOV.net — state/county/city jurisdiction, budgets, legislation, licensing, voting, and records publication.
- [ ] SADOT.net — oversight, mechanic licensing, jurisdictional fleet operations, and qualified towing.

## LEO report backend audit — first pass (2026-11-01)

Inspected `server/backend/reports.lua` (1,684 lines). These are verified code observations, **not** end-to-end signoff:

- `getEffectiveJobType` derives the record domain from authenticated interface access, distinguishing LEO, DOJ, EMS, and FIRE.
- `CanReadMdtReport` requires authenticated `reports_view` permission and delegates to `checkReportAccess`.
- `checkReportAccess` evaluates report restrictions and agency ownership; explicitly named disclosures are read-only.
- `checkReportWriteAccess` requires action-specific permission and blocks writes to records owned by another agency.
- The delete callback rechecks access and includes an owner constraint in its SQL delete operation.

**Implemented correction (commit d04febb):** Vehicle-plate report lookup now applies report-domain, agency-owner, and explicit restriction SQL checks **before** its 20-result limit, then revalidates each returned row through `CanReadMdtReport`. This prevents inaccessible records from consuming all result slots. Active named disclosures are now included in the plate-search SQL prefilter (commit 91e7296), with final per-row authorization still enforced. **Other list/search and analytics paths remain to be reconciled**, and the report workflow is **in progress**, not signed off.

**Still to verify before changing authorization behavior:** report search/list filtering, all detail and attachment paths, write/update SQL race protection, event/callback bypass attempts, legacy reports without owner restrictions, and regression coverage for cross-agency disclosures. Do not mistake these initial guards for a complete security audit.

## Immediate next development slice

**LEO authorization and report lifecycle audit:** inspect the existing backend entry points and UI calls, identify actual gaps, then implement a coherent end-to-end correction with regression coverage. Do not begin unrelated portal features while this slice is open.

## Change log

- 2026-11-01 — Created this checklist from the current `config.lua`, `fxmanifest.lua`, README, and active jobs reference; unverified workflows deliberately remain unchecked.
