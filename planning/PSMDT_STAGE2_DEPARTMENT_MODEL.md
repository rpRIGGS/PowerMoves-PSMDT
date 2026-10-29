# PowerMoves-PSMDT — Stage 2 department ownership implementation

Date: October 28, 2026

## Stage transition: source development

Stage 2 **department-scoped source development is active** after a green Stage 1 code/CI baseline (GitHub Actions run 40794831472, commit db6a8b10). This is **not** a declaration that Stage 1 has passed live FiveM acceptance testing or that every interface has operational parity. Source tests run with mocked SQL and NUI; deployments and real database migrations remain the owner's test responsibility.

The foundational enabled fronts remain SADLE.net, SADOJ.net, SAFR.net, SAMS.net and SAGOV.net. SADOT.net is an explicitly disabled future sixth interface. Underlying QBCore jobs remain `leo`, `doj`, `fire`, `ems`, and individually named government jobs. No interface switch alters employment.

## Stage 2 implementation started: ownership boundaries

- Actual employer (QBCore job), not interface branding, controls normal departmental roster and SOP visibility. SADLE's exceptional statewide law-enforcement roster access requires exact approved oversight authority; FIB is not a statewide viewer.
- `mdt_cases.assigned_department` scopes ordinary case reads and mutations; the DOJ court interface has separate judicial-case visibility. Case attachments, notes and assignments must check the parent case. Creation cannot spoof another employer.
- Reports created now retain their originating employer using `mdt_reports_restrictions.type='owner'`. Explicit sharing does not silently transfer write authority. Legacy ownerless reports require safe reconciliation, not guessed ownership.
- Evidence backend uses a single set of callback registrations. Case-linked evidence searches are scoped through the assigned case employer; unlinked legacy evidence defaults to its collecting citizen until proper historical ownership is established. Known-ID mutations and stash access check the associated record.
- SAGOV now has employer-scoped personnel and a read-only SOP reader; government staff cannot invoke legacy police/medical SOP writes. Statewide government personnel oversight remains explicit, not a boss default.
- Agency-specific bulletins and FTO workflows already exist but need multi-employer behavioral regression tests.

## Remaining hard gates / migration work

1. Run FiveM scenarios with two different employers in LEO, fire and hospital families. Verify access denial, employer transfer, grade changes and restricted report/evidence sharing using real `ps_lib`, QBCore and oxmysql.
2. Introduce an employer-aware calendar ownership field non-destructively. Existing court and shared training events have only legacy `police` / `ems` domain markers; **do not** guess their original employers. Court scheduling remains separately accessible to authorized DOJ roles.
3. Reconcile and migrate ownerless historical reports, unlinked evidence and legacy IA complaints without leaking or deleting originals.
4. Build the remaining departmental module parity for SAGOV, SAFR and SAMS. Government read-only SOP and roster are not a complete government records/legislative platform. Approved `mdt_permission_roles` job-and-grade matrix is needed before retiring `BossPermissionMode='legacy'`.
5. Confirm generated `web/dist` build and the actual deployed resource, since passing CI does not update the user's FiveM server.

## Acceptance checks for the next Stage 2 increment

- LSPD cannot read or change BCSO's confidential in-progress case/evidence unless a specific explicit grant is recorded; SADLE oversight and DOJ access obey their own distinct checks.
- Fire and hospital records are isolated at employer level, despite shared legacy responder calendar internals.
- SAGOV/BCGOV/LSCGOV/LSGOV see only their employing government's internal SOP and rosters, except intentionally authorized state oversight.
- Historical records are preserved for owner-approved migration and never silently relabeled based on current employment.

All Stage 1 runtime sign-off remains pending. Stage 2 source work may continue without representing the untested server as production ready.
