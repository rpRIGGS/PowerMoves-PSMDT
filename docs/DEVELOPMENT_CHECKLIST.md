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

**Still to verify before changing authorization behavior:** report search/list filtering, all detail and attachment paths, write/update SQL race protection, event/callback bypass attempts, legacy reports without owner restrictions, and regression coverage for cross-agency disclosures. Do not mistake these initial guards for a complete security audit.

## Immediate next development slice

**LEO authorization and report lifecycle audit:** inspect the existing backend entry points and UI calls, identify actual gaps, then implement a coherent end-to-end correction with regression coverage. Do not begin unrelated portal features while this slice is open.

## Change log

- 2026-11-01 — Created this checklist from the current `config.lua`, `fxmanifest.lua`, README, and active jobs reference; unverified workflows deliberately remain unchecked.
