# Stage 4 — Investigations and controlled discovery acceptance

Status: source implementation candidate; **NOT live accepted**.
Updated: October 29, 2026. Runtime FiveM deployment remains with the server owner.

## Source modules
- Local/internal IA complaint owner scope and SADLE referral/triage/acceptance: `server/backend/ia.lua`, `client/backend/ia.lua`, `web/src/pages/IA.svelte`.
- Explicit individual read-only case grants/revoke/read-audit and personal inbox: `server/backend/cases.lua`, `client/backend/cases.lua`, `web/src/components/CaseDisclosureManager.svelte`, `web/src/components/DisclosedCaseInbox.svelte`.
- Explicit individual read-only report grants/revoke/read-audit and personal inbox: `server/backend/reports.lua`, `client/backend/reports.lua`, `web/src/components/ReportDisclosureManager.svelte`, `web/src/components/DisclosedReportInbox.svelte`.
- Original report restrictions and DOJ case/warrant/court tables remain intact. Grants do not transfer ownership or grant write access.
- Grants are bound to recipient **citizenid AND employer**; reassignment to another employer must invalidate access. Privileged grant management uses existing `cases_edit` or `reports_delete` permission and exact originating employer.
- A new grant is valid only with a real, positive SQL insert ID; revocation is audited and next read checks current status.

## Installation on test server — never unreviewed production

1. Back up MariaDB and the existing PSMDT folder. Confirm dependencies and exact current jobs.lua and management permissions.
2. Review and install additive migrations: `sql/migrations/2026-10-28-ia-referrals.sql`, `2026-10-28-case-disclosures.sql`, `2026-10-28-report-disclosures.sql`, `2026-10-29-evidence-disclosures.sql`. These create new tables and do not modify existing record ownership.
3. Deploy updated code and built NUI; restart the resource on a DEV FiveM server. Verify no F8/client/server console errors.
4. Create or choose two test law-enforcement employers (e.g. LSPD and BCSO), authorized SADLE IA personnel, and a separate authorized SADOJ prosecutor / defense counsel. Use actual configured jobs and grade permissions, not hypothetical boss behavior.
5. Give each test character appropriate on-duty status and only the exact permissions intended. Log the source character/citizenid and employer.

## Required end-to-end scenarios (record a pass/fail and console logs)

| ID | Test | Expected outcome |
|---|---|---|
| IA-01 | BCSO IA manager refers BCSO police complaint to SADLE | Success, unique pending referral; original complaint retains BCSO |
| IA-02 | LSPD IA manager attempts to refer BCSO complaint | Denied |
| IA-03 | Unauthorized SADLE or off-duty actor reads/accepts referral | Denied |
| IA-04 | Authorized SADLE accepts pending referral twice | First succeeds, second denied; original complaint retains employer |
| IA-05 | BCSO views own referral status; LSPD attempts to view it | BCSO sees status only; LSPD denied; confidential state notes withheld |
| CASE-01 | LSPD manager grants one LSPD case to a named SADOJ attorney | Attorney sees only explicitly shared case in personal inbox |
| CASE-02 | Attorney attempts to change case, evidence, linked reports without separate grants | Denied; case grant alone does not confer edits or independent report reads |
| CASE-03 | Grant is revoked, attorney refreshes/read-by-ID | Case vanishes from inbox, direct read denied |
| CASE-04 | Attorney changes to another employing job, then back | Other job denied; original job only if grant still active and authorized |
| CASE-05 | BCSO attempts to grant or revoke an LSPD case | Denied |
| REPORT-01 | LSPD authorized manager shares one owned report with named counsel | Report appears in recipient inbox and opens in existing editor view |
| REPORT-02 | Counsel tries modifying/deleting report | Denied |
| REPORT-03 | LSPD revokes share; counsel retries read-by-ID | Denied; read audit and revocation audit recorded |
| REPORT-04 | Legacy ownerless report sharing attempt via new endpoint | Denied pending manual ownership reconciliation |
| REPORT-05 | Transfer counsel to a different job with same citizenid | Grant inaccessible |
| EVID-01 | LSPD grants a single evidence item to named SADOJ counsel | Metadata and custody history available; stash/inventory identifier withheld |
| EVID-02 | Counsel attempts evidence transfer, delete, image upload or stash access | Denied; view grant never authorizes mutation |
| EVID-03 | LSPD revokes evidence disclosure | Subsequent inbox/detail reads denied; audited |
| EVID-04 | Recipient switches to a new job, or evidence is reassigned to another case employer | Access denied |
| EVID-05 | BCSO attempts to grant LSPD evidence | Denied |
| DOJ-01 | LEO → prosecutor → assigned defense case/report discovery chain | Only explicitly granted documents available; existing judicial docket policy remains unchanged |
| REG-01 | Routine LEO / EMS / fire / DOJ / SAGOV nav and basic reports/cases still work | No regression in original modules |

## Scope and limitations

- This code does **not** automatically disclose evidence stashes, medical charts, internal IA notes, or linked standalone reports through a case grant.
- Existing broad DOJ court permissions, defense roster assignments and legal-discovery approval/notice rules are **not redefined**. A court/attorney permission matrix still requires sign-off before tightening access that previously existed.
- Source test CI uses mocked SQL. It cannot prove real MySQL transactional isolation, migration success, GTA client rendering, cross-resource calls or role/job behavior.
- No production migrations, FiveM runtime acceptance or user deployment has been performed in this conversation. Do not mark Stage 4 fully accepted until the rows above have actual PASS results.
