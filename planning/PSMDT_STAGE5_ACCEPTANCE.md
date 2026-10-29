# Stage 5 — Public services and records: development handoff

Status: **Source implementation candidate — NOT runtime accepted** (October 29, 2026).

## Implemented in existing PSMDT
- Configurable public-service desks using qb-target and the existing IA complaint entry point.
- Civilian public-records request intake and request history, restricted to the initiating citizenid.
- Records-office queue accessible only to explicitly listed `Config.PublicServices.RecordsOfficers[job][citizenid]` members, subject to MDT auth.
- Review transitions from submitted to under_review, then denied or approved. Authorized records officers can inspect agency-scoped decision history inside the existing MDT panel.
- Approved requests receive only records-office-authored public response text. Denied requests receive a written public explanation addressed to the original applicant. No direct disclosure of cases, reports, evidence stashes, medical charts or IA records.
- Approved responses are scoped to the original requesting citizenid. Review and publication are written to the Stage 5 audit table.
- Approved requests can receive manually authored public release copies, each bound to the original applicant citizen ID, a fixed expiration (1–365 days), agency ownership, staff actor, and audited revocation. No raw confidential MDT document table or evidence stash is exposed.
- Records officers open the integrated PSMDT records-office panel through a configured in-world qb-target counter; civilians submit and check requests at public service counters. No records-office slash command or separate staff ox_lib menu.
- Source contract test: `tests/phase5/public_records_regression.cjs`, linked into GitHub Actions.
- Lua callback mocks cover citizen ownership, staff decision transactions, and server-side circle/poly geometry.
- The records-office panel rechecks counter proximity and staff entitlement while open; losing access clears cached request details.
- Decision and approval paths use `MySQL.startTransaction` with row locks and affected-row checks, rather than treating an empty update as success.

## Before testing
1. Back up DEV database and PSMDT.
2. On an **existing** PSMDT database, apply the additive Stage 5 migrations in order. On a fresh database install, `sql/qbcore.sql` and `sql/qbx.sql` already include these Stage 5 tables (choose the appropriate base schema):
   - `sql/migrations/2026-10-29-public-records-intake.sql`
   - `sql/migrations/2026-10-29-public-records-review.sql`
   - `sql/migrations/2026-10-29-public-records-response.sql`
   - `sql/migrations/2026-10-29-public-record-release-copies.sql`
3. Configure actual public desk coordinates, agency names and services (`public_records_request`, `public_records_status`, `records_office` for staff counters).
4. Explicitly allowlist real records officers. Default `RecordsOfficers = {}` means no reviewer has access.
5. Confirm oxmysql **v2.12.0 or newer**. `MySQL.startTransaction` was added to the Lua library in v2.12.0; earlier installations must not process Stage 5 records-office decisions. The server fails closed if the API is unavailable.
6. Test separate characters, departments, on/off-duty access and resource restarts.

## Mandatory DEV acceptance
- Citizen A cannot view citizen B requests or published responses, including direct callback by request number.
- Agency A cannot view, audit, review or decide agency B's requests, including direct history callback attempts.
- Unlisted staff, civilians and unauthorized job switches cannot open records-office queues.
- Two records officers racing the same decision cause only one state transition, response and audit entry.
- Responses cannot be published before review and cannot be duplicated. Denial notice, status and audit commit together, or all roll back.
- Approved response text contains only the reviewed publicly releasable information.
- Denied requests show their status and an applicant-scoped denial explanation; restricted source documents and internal audit rows are never attached automatically.
- Applicant A cannot list or retrieve applicant B's release copies by guessing a request number.
- Revoked copies disappear from the civilian view immediately on the next server fetch; expired copies fail the same server-side predicate.
- Issue/revoke actions require a live allowed agency job, records-office designation and physical counter proximity, including before transaction commit.
- Issue/revoke audits and copy state are atomic: failed audit writes roll back the corresponding copy issue or revocation.
- A single request cannot exceed 20 released copies; staff cannot issue a copy before the request is approved.
- QBCore and QBX fresh-install schemas, plus additive migrations, create the same release-copy table without removing existing PSMDT data.
- qb-target service zones recover after restart; civilian ox_lib forms and the integrated staff MDT panel render.
- Existing LEO, EMS, fire, DOJ, IA and evidence workflows remain unaffected.
- Run Lua syntax, CI source checks and MariaDB migration/integration tests; confirm both clean-install schema files and additive migrations. Inspect FiveM F8 and server logs.

## Limitations / unresolved
- Source writes are committed, but the latest GitHub Actions results and DEV FiveM results have **not** been independently verified. Do not describe unexecuted regressions as passing.
- Approval requires deliberate manual redaction by the authorized records officer. No document attachment, advanced legal exemptions, fee collection, notice mailing, or downloadable release package is provided.
- Decide whether Stage 5 scope requires additional public applications (business licensing and property services are allocated to Stage 6 in current roadmap).
- Production deployment and final Stage 5 acceptance require actual DEV test signoff. Do not treat this document as proof of working live functionality.
