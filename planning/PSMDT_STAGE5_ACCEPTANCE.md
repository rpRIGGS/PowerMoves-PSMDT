# Stage 5 — Public services and records: development handoff

Status: **Source implementation candidate — NOT runtime accepted** (October 29, 2026).

## Implemented in existing PSMDT
- Configurable public-service desks using qb-target and the existing IA complaint entry point.
- Civilian public-records request intake and request history, restricted to the initiating citizenid.
- Records-office queue accessible only to explicitly listed `Config.PublicServices.RecordsOfficers[job][citizenid]` members, subject to MDT auth.
- Review transitions from submitted to under_review, then denied or approved.
- Approved requests receive only records-office-authored public response text. No direct disclosure of cases, reports, evidence stashes, medical charts or IA records.
- Approved responses are scoped to the original requesting citizenid. Review and publication are written to the Stage 5 audit table.
- Records officers open the integrated PSMDT records-office panel through a configured in-world qb-target counter; civilians submit and check requests at public service counters. No records-office slash command or separate staff ox_lib menu.
- Source contract test: `tests/phase5/public_records_regression.cjs`, linked into GitHub Actions.

## Before testing
1. Back up DEV database and PSMDT.
2. Apply migrations in order:
   - `sql/migrations/2026-10-29-public-records-intake.sql`
   - `sql/migrations/2026-10-29-public-records-review.sql`
   - `sql/migrations/2026-10-29-public-records-response.sql`
3. Configure actual public desk coordinates, agency names and services (`public_records_request`, `public_records_status`, `records_office` for staff counters).
4. Explicitly allowlist real records officers. Default `RecordsOfficers = {}` means no reviewer has access.
5. Test separate characters, departments, on/off-duty access and resource restarts.

## Mandatory DEV acceptance
- Citizen A cannot view citizen B requests or published responses, including direct callback by request number.
- Agency A cannot review or decide agency B's requests.
- Unlisted staff, civilians and unauthorized job switches cannot open records-office queues.
- Two records officers racing the same decision cause only one state transition, response and audit entry.
- Responses cannot be published before review and cannot be duplicated.
- Approved response text contains only the reviewed publicly releasable information.
- Declined requests show denied status, while restricted source documents are never attached automatically.
- qb-target service zones recover after restart; civilian ox_lib forms and the integrated staff MDT panel render.
- Existing LEO, EMS, fire, DOJ, IA and evidence workflows remain unaffected.
- Run Lua syntax, CI source checks and MariaDB migration/integration tests; inspect FiveM F8 and server logs.

## Limitations / unresolved
- Source writes are committed, but current-turn GitHub Actions results and DEV FiveM results are not verified.
- Approval requires deliberate manual redaction by the authorized records officer. No document attachment, advanced legal exemptions, fee collection, notice mailing, or downloadable release package is provided.
- Decide whether Stage 5 scope requires additional public applications (business licensing and property services are allocated to Stage 6 in current roadmap).
- Production deployment and final Stage 5 acceptance require actual DEV test signoff. Do not treat this document as proof of working live functionality.
