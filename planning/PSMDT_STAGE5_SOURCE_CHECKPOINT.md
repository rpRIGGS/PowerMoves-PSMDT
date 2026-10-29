# Stage 5 source-development checkpoint — Public services

Date: October 29, 2026

**Stage 5 public-records source path implemented; automated CI and real FiveM acceptance are NOT yet verified.**

## Included
- Configurable qb-target public service locations with IA filing and public records intake/history.
- Citizenid-scoped intake and response retrieval.
- RecordsOfficer allowlist and agency-only review queue; default is no access.
- Staff /recordsdesk ox_lib UI.
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
Run service desk and /recordsdesk with two staff agencies and two civilian characters.
Do not deploy to production or move the Stage 5 *runtime* status to complete until approved.
