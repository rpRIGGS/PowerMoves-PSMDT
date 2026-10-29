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
