# PSMDT Stage 4 — investigations, DOJ and controlled disclosure

Stage 4 **source implementation** began on October 28, 2026. This is not live FiveM acceptance or completion of Stage 3. Employer-level training, credentials and calendar code is source-tested; academy requirements, qualifications, statewide accreditor acceptance and live integrations remain open.

## Existing engines to preserve
- Internal Affairs: `mdt_ia_complaints`, `mdt_ia_notes`, department ownership and SADLE's existing restricted police-family investigations.
- Investigative reports: `mdt_reports` plus existing `mdt_reports_restrictions` explicit grants; do not discard legacy restriction semantics.
- Criminal case data: `mdt_cases`, `mdt_case_reports`, case evidence and custody records.
- Court: `mdt_court_cases`, warrant/hearing and judicial authority. DOJ remains distinct from SADLE enforcement.
- Public complaint intake remains separate from authorized investigative and judicial record access.

## Current Stage 4 code
- IA complaint list/details now revalidate live job, identity and permissions after SQL returns, preventing disclosures after transfers.
- IA investigator assignment validates the target is an employee of the actor's authorized employer and rechecks after asynchronous profile lookup.
- Existing agency/oversight rules remain in effect. This does not create new cross-agency access for ordinary supervisors.

## Required remaining implementation and acceptance
1. Formal IA referral from local agency to specially authorized SADLE investigators, with status queue and per-record grants, without broadening other IA audiences.
2. Narrow disclosure to implicated agency command (specific case/report only). Controlled DOJ discovery including prosecutor, assigned defense, and independent counsel grants plus auditable revocation.
3. End-to-end evidence, report, warrant and case links, sharing restrictions, audit, transfer and closed-case permanence.
4. Live two-agency BCSO → SADLE, LEO → DOJ → defense test scenarios using actual QBCore, oxmysql and deployed NUI. Never infer runtime success from mocked CI.

No user server or production SQL was modified by these commits.

## Implemented IA referral increment

- Local IA managers can submit a reasoned referral of a **police-family complaint owned by their own employer** to SADLE. Duplicate complaint referrals are rejected by the unique SQL key.
- SADLE agents with existing authorized `ia_view` grants can read their statewide referral queue. Only SADLE `ia_manage` agents may accept a **pending** police referral. Acceptance is an atomic status transition, not a transfer of local record ownership.
- Local department IA staff can read only their own referral's status; this does not expose state investigation notes or other employers' complaints.
- NUI callback bridges and the IA page now expose submission, review, acceptance and originating-agency status; the existing IA complaint screen and underlying court engine remain in place.
- Database table is supplied both as an additive migration (`sql/migrations/2026-10-28-ia-referrals.sql`) and in fresh QBCore/QBX schema installs. Live database application has **not** occurred.
- Lua behavior tests in `tests/phase4/ia_referral_runtime.lua` exercise local submission, denial across departments, SADLE queue/acceptance and denial for unauthorized actors. Source contract tests verify the bridges and migrations.

**Next gates:** controlled complainant notification, department-command case-specific disclosures, SADLE referral assignment, record-level grants for DOJ prosecution/defense discovery, revoke and audit trail, plus real FiveM/SQL integration tests. Referral acceptance alone does not confer unrestricted permission to view private evidence or medical charts.

## Controlled case/report discovery implementation (source complete candidate)

New modules and NUI controls provide individually named, read-only disclosure for `mdt_cases` and `mdt_reports`:

- Case grant, revocation, management history and recipient inbox; the normal case detail callback validates the active grant after all database reads. Each cross-employer disclosed read creates an audit log.
- Report grant, revocation, management history and recipient inbox; the existing report access checker recognizes active grants without relaxing the owner restriction for writes. Disclosed report reads are reauthorized and audited.
- Both grant types bind the recipient's citizen ID **and original employing job**. Reemployment into a different agency does not silently transfer the discovery grant.
- Ordinary law-enforcement supervisors cannot manufacture a grant for another agency's case or report. Case grants require `cases_edit` and current case ownership; report grants use the existing privileged `reports_delete` capability and an explicit report `owner` marker. Legacy ownerless reports are not auto-shared.
- Grant records carry purpose, issuer, timestamps, and revocation information. Existing independent evidence, hospital charts and IA confidential notes are not automatically disclosed. Separate linked reports require their own grants.
- Migrations are additive: `sql/migrations/2026-10-28-case-disclosures.sql` and `2026-10-28-report-disclosures.sql`; clean QBCore/QBX install schemas contain both tables. Nothing has been installed on the user's server.
- Automated source/mocked-SQL tests live in `tests/phase4/` and GitHub Actions. The required real acceptance is documented at `planning/PSMDT_STAGE4_ACCEPTANCE.md`.

**Not approved for live Stage 4 sign-off yet:** court/DOJ role matrix decisions, cross-office prosecutorial/defense consent policies, full evidence discovery attachments, true database migration/runtime acceptance, audit retention and attorney assignment edge cases. Existing judicial permissions are intentionally preserved rather than silently narrowed by these changes.

## Stage 4 read-only discovery hardening

- Named cross-employer case grants now return a case summary **without** internal notes, attachment URLs, linked-report listings or officer details. Independent report/evidence access continues to require separate authorization.
- The case listing and case detail callbacks reject stale database results if a source switches character, employment or duty. The report list requires `reports_view` before SQL and rechecks identity and permissions before returning results.
- DOJ court-case list/detail callbacks also revalidate their exact character, employer, `court_view` permission and duty after SQL queries.
- `tests/phase4/disclosed_case_runtime.lua` exercises the real case callback under mocked SQL for active grants, redaction, revocation, changing jobs and character swaps. `tests/phase4/disclosure_regression.cjs` checks the associated security contracts. Both are in GitHub Actions.
- This protects the new named-grant route; it does not redefine the existing judicial docket visibility or create unapproved courtroom role permissions.

**Source quality and live acceptance remain separate.** Do not declare Stage 4 accepted until the real Stage 4 acceptance matrix has recorded passing tests against a development server, with agreed DOJ and defense role policies.
