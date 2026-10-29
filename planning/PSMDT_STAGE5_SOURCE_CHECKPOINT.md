# Stage 5 source-development checkpoint — Public services

Date: October 29, 2026

**Stage 5 public-records source path implemented; automated CI and real FiveM acceptance are NOT yet verified.**

## Included
- Configurable qb-target public service locations with IA filing and public records intake/history.
- Citizenid-scoped intake and response retrieval.
- RecordsOfficer allowlist and agency-only review queue; default is no access.
- Staff records-office panel inside the existing PSMDT Svelte NUI, opened via a configured qb-target location (`records_office` service); no records-office slash command.
- Submitted → under_review → denied OR public-response-approved state changes.
- An explicitly authored public response is published to a single applicant; no raw operational data access.
- Additive SQL migration files for request, review audit and response tables.
- Source-contract and MariaDB smoke-test scripts included in existing CI workflow.

## Must pass before Stage 5 source signoff
- GitHub Actions Lua syntax and source-contract checks.
- MariaDB SQL migration and smoke tests; review duplicate/concurrent decision behavior under real transactions.
- Confirm no request can be marked approved without a recipient-scoped response row.
- Confirm audits are accurate under failed transactions and server disconnect.
- Confirm clean-install SQL for applicable QBCore/QBX schema includes Stage 5 tables OR documented migration installer applies them.

## Must pass before runtime signoff
Follow planning/PSMDT_STAGE5_ACCEPTANCE.md on a backed-up DEV server with actual QBCore jobs, PSMDT and qb-target/ox_lib.
Test qb-target public service counters and records-office MDT panel with two staff agencies and two civilian characters.
Do not deploy to production or move the Stage 5 *runtime* status to complete until approved.

## October 29 source hardening checkpoint
- Corrected the previously undefined server `src` variable in civilian counter authorization.
- Switched staff decisions and published responses to `MySQL.startTransaction` with row locking and affected-row checks, so 0-row updates/inserts cannot be mistaken for successful decisions.
- Added a lightweight staff entitlement recheck while the integrated MDT panel is open, clearing cached request details if the employee leaves the vector/poly location or loses access.
- Rechecked citizen identity and public-counter location after database reads before returning request details.
- Tightened client counter configuration validation and corrected request-history line formatting.
- Extended CI to cover Stage 5 staff transaction mocks, civilian character isolation, server circle/poly geometry, and temporary MariaDB uniqueness/rollback SQL.
- Added regression coverage for staff employer transfer during a locked transaction.

**Verification:** These files and test definitions were committed and inspected in GitHub. No passing result from the latest GitHub Actions workflow, real oxmysql transaction runtime, NUI build, or FiveM DEV server was available to verify here. The 13 source-wiring assertions reviewed in chat are static checks, not 13 runtime tests.
