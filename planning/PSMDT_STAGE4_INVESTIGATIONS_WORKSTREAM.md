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
