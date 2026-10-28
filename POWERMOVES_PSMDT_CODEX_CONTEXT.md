# PowerMoves RP — PS-MDT Development Context

**Status:** Planning reference, not proof that features have been implemented.  
**Platform:** FiveM, QBCore, Project Sloth PS-MDT as the existing base.  
**Working rule:** Inspect existing source and configurations before editing. Preserve originals and the working server. Use a separate development copy and incremental, testable changes.

## Goal

Extend the existing PS-MDT resource into **one shared system with five interfaces**, reusing existing capabilities rather than rebuilding them. The five interfaces share a backend/database as appropriate but enforce distinct agency, role, jurisdiction, and record-visibility permissions.

1. **SADLE.net** — San Andreas Division of Law Enforcement; LEO interface and statewide oversight, investigations, internal affairs, training, FTO, certifications, agency records, and appropriate restricted cross-agency access.
2. **SADOJ.net** — San Andreas Department of Justice; courts, cases, motions, hearings, orders, legal personnel, and judicial review. Separate from SADLE oversight.
3. **SAFR.net** — San Andreas Fire Rescue; fire departments and EMS operations, personnel, training/certifications, incident and EMS reports.
4. **SAMS.net** — San Andreas Medical Service; hospital and medical personnel, certifications/training, patient records and medical charting, subject to medical access controls.
5. **SAGOV.net** — San Andreas Government; statewide, county, and municipal government administration, legislation, records, budgets, taxes, licensing, permits, appointments, and jurisdiction-specific workflows.

These are five interfaces **within one PS-MDT system**, not five unrelated resources. Keep the established QBCore framework; do not pursue a custom FiveM framework.

## Start with existing QBCore jobs.lua

The owner will supply the actual `jobs.lua` (or relevant jobs configuration). **Job names, grades/ranks, and titles in that file are authoritative starting points** for agency structures and access. Do not invent or replace established agencies/ranks. Government offices such as the Tax Assessor's Office may be assignments/permissions **within an existing government job (e.g., Governor's Office)**, not necessarily separate QBCore jobs. Determine exact mapping only after examining the configuration and existing PS-MDT permission system.

## Government hierarchy and jurisdiction

- **State of San Andreas** — statewide authority and authorized statewide oversight.
  - **Blaine County** — its own county government.
  - **Los Santos County** — separate peer county government.
    - **City of Los Santos** — municipality within Los Santos County.
- Allow future municipalities, such as Grapeseed, without redesigning the hierarchy.
- State-authorized roles can have oversight/visibility across jurisdictions, subject to their defined permissions. County and municipal officials ordinarily cannot view one another's unpublished internal work. Officially published/approved public records can have broader visibility.
- Local governments should have meaningful control of their own departments, appointments, legislation, ordinances/codes, taxes, fees, permits, and business licensing, subject to applicable higher law.
- The Mayor of Los Santos exercises municipal authority over LSPD; Los Santos County government exercises county authority over its Sheriff's Office. Preserve distinctions between administrative oversight in SAGOV and operational law-enforcement records in SADLE.
- Each jurisdiction can establish applicable rates and fees through its authorized roles/processes. The hierarchy determines which jurisdictions may apply to a property or business; **not every tax automatically applies** simply because a higher jurisdiction exists.
- Proposed laws/ordinances, votes, approvals, publication, amendments, and legal status should be retained as records. SADOJ handles properly filed judicial challenges; it does not automatically preapprove all legislation.

## Property creation and State Tax Assessor's Office

- **No PolyZones for initial property jurisdiction assignment.** A realtor creating a property in PS Realtor selects its property type (e.g., residential, commercial, agricultural, industrial) and jurisdiction.
- The property is **not available for sale until assessed and approved**.
- New properties enter an assessment queue/notification in SAGOV.net.
- **State Tax Assessor's Office** operates under the **Governor's Office**, with appointees/authorized ranks, not a standalone QBCore job by default. The governor appoints appropriate officials; assessor permissions come from government job/rank/appointment rules, **not server admin permissions**.
- Authorized assessors verify/correct property type and taxable jurisdiction, record taxable classification and exemptions, and approve the assessment. They can later amend existing property records through documented due process, including special-use approvals (e.g., a residential property permitted to operate a beekeeping business).
- Maintain change history: who changed what, when, and why; preserve prior records and linked authorizations.
- A property marked government-owned should **not be automatically tax-exempt**; authorized assessment determines and records exemption status. Example: Mission Row PD may receive an approved exemption.
- **PS Realtor** creates/manages property listings and transactions. **PS Housing** supplies housing/ownership data. **SAGOV.net** manages government assessment/approval/tax records. Exact ownership of calculation and persistence logic must be decided after source inspection; calculations must be server-authoritative, not trusted to client UI.
- Existing historical PS Realtor/PS Housing fork READMEs contain earlier `pm-government` design notes. They are **planning artifacts**, not verified implemented code. They mention fields such as `property_type`, `owner_type`, and `is_tax_exempt`; confirm real schema before making assumptions.

## Business licensing, taxes, and fees

- People should be able to **apply online through public government services** for business licenses.
- Applicant supplies business information and selects the proposed local jurisdiction. The receiving licensing office verifies jurisdiction, corrects or transfers misrouted applications, and approves/denies under its government permissions.
- **One local business license** issued by the appropriate local jurisdiction is the initial preferred model (Option A), not mandatory separate licenses from state, county, and city for every business. Additional specialized licenses/permits may be considered later.
- Each local government can set its own licensing and permit fees and applicable tax rates. Example: a hot dog vendor permit in City of Los Santos can differ from one in Blaine County and authorizes work only within its scope.
- Business records link their approved jurisdiction and relevant licenses, fees, and taxes. Existing QBCore businesses are currently created manually; **do not assume a business-creator script exists or build one without agreement**.
- Distinguish **property tax** (assessor-verified property jurisdiction), **business tax** (registered business jurisdiction), and **sales tax** (location of transaction). The method for determining sales tax on NPC shops, vending machines, or other transactions remains **undecided**; PolyZones were discussed as a possible solution for transaction location, **not for property creation**.
- Tax rate-setting authority is separate from assessment authority. The assessor applies approved tax rules; the office does not unilaterally legislate rates.

## Court integration, enforcement, and permanent records

- **SADOJ.net court cases and their complete histories must be retained permanently when closed.** Verify whether the existing code deletes records or only hides closed cases; either way, closure must not erase history. Preserve motions, evidence, hearings, orders, rulings, and dispositions, with proper permissions and archival/search capabilities.
- Reuse the existing SADOJ court and motion-filing functionality rather than rebuilding it. Confirm capabilities in actual code.
- Authorized SAGOV personnel (e.g., State Tax Assessor's Office) should be able to initiate appropriate court proceedings for delinquent property taxes, regulatory violations, or related disputes, with links to relevant property/business/government records.
- The assessor can pursue legal process but **cannot unilaterally confiscate property**. Collection, liens, foreclosure/seizure, or other remedies require the established due process and judicial authorization where applicable.
- SADOJ also handles challenges to municipal/county/state actions and constitutional questions under the roleplay legal framework, generally inspired by U.S. law. Preserve original legislation and its history even when later amended or invalidated by a court ruling.
- Prefer links/references between government and court records over copying divergent versions of the same data.

## Other PS-MDT design context

- Preserve existing PS-MDT LEO and DOJ capabilities where possible: reports, cases, attachments, warrants/BOLOs, rosters, SOPs, certifications, FTO, internal affairs, and court workflows, subject to actual source verification.
- SADLE has specially authorized cross-agency oversight/investigative visibility; ordinary agencies remain restricted. Do not assume blanket access to all records for all government users.
- Expand SAFR/SAMS personnel management, certifications, training, EMS reporting, and medical charting after auditing current features and relevant privacy boundaries.
- Configurable public-service access via `qb-target` locations/kiosks was discussed; civilians should not require a full government MDT tablet. Public service workflows and exact UX are not yet implemented or finalized.
- Existing `icu.lua` was previously discussed as limited ICU/BOLO cleanup logic, **not evidence of a full medical charting system**; verify actual source.

## Development order and guardrails

1. Inspect existing PS-MDT code and configuration, plus the user's real QBCore `jobs.lua`.
2. Inventory existing functions by interface and identify what already works, what needs changes, and what is missing.
3. Agree on permissions, agencies, ranks, and boundaries before changing code.
4. Work in a separate development copy; preserve upstream/reference code and the user's live server. Use version control and small, testable commits.
5. Ask before destructive changes, schema migrations, major refactors, or changes to existing functional systems.
6. User tests in their own FiveM development server and provides runtime/F8/server-console errors. Do not claim to have tested in FiveM without actually doing so.
7. Respect Project Sloth and other upstream licensing and attribution. Avoid publishing private development architecture in public profile READMEs.

## Repositories and reference material

- Personal working fork: `https://github.com/rpRIGGS/PowerMoves-PSMDT`
- Related personal forks: `PowerMoves-PSDispatch`, `PowerMoves-PSRealtor`, `PowerMoves-PSHousing` under `rpRIGGS`.
- Older planning notes in the READMEs of `https://github.com/PowerMoves-Development/ps-realtor` and `https://github.com/PowerMoves-Development/ps-housing`. Do not delete or assume those README plans are implemented.

**Important:** This is a summary of the discussions and should guide investigation, not substitute for source review. Where a requirement is uncertain, ask the owner before deciding or coding.

---

# October 27, 2026 — Latest decisions and implementation status

The original planning specification above remains intact. The section below adds newer decisions and clarifications. If any older statement conflicts, use the newer decision, but verify job grades against the current project files.

## Architecture: one system, five interfaces

One existing PSMDT tablet/resource and shared backend/database, with separate role-specific entry points and scoped access:

- **SADLE.net** — San Andreas Division of Law Enforcement: agency reports, investigations, warrants/BOLOs, evidence, personnel, FTO, certifications, internal affairs and specially authorized statewide law-enforcement oversight.
- **SADOJ.net** — San Andreas Department of Justice: courts, filings, cases, motions, hearings, orders, prosecutors, defense and judges. Separate from law-enforcement oversight.
- **SAFR.net** — San Andreas Fire Rescue: statewide fire/EMS oversight, accreditation, incident and EMS run reports, personnel, training and certifications; supports fire departments across state/county/city.
- **SAMS.net** — San Andreas Medical Service: hospital and medical personnel, accreditation, patient records/charting, training and certifications, with clinical access boundaries.
- **SAGOV.net** — San Andreas Government: state, county and municipal administration, staff/rosters, appointments, legislation, votes, public records, licensing, permits, taxes, budgets and related workflows.

Existing civilian-facing capabilities should not be lost. Public government services may eventually be accessible through locations/kiosks rather than issuing a government tablet to every civilian; exact experience is not finalized.

## Government jurisdiction and visibility

State of San Andreas is above two **peer counties**, Blaine County and Los Santos County. The City of Los Santos is nested within Los Santos County. Support future incorporated municipalities such as Grapeseed without redesigning the hierarchy.

Relevant existing government jobs include `sagov`, `bcgov`, `lscgov`, `lsgov`. State-authorized roles may oversee lower jurisdictions **within explicit government permissions**; county/municipal personnel do not automatically see each other's internal drafts or records. Published/approved public records may be visible more broadly. Government administrative oversight is not blanket access to operational SADLE records, judicial functions, or clinical SAMS records.

Local governments manage their own personnel, legislation/ordinances, fees, licenses, permits and applicable taxes, subject to higher law and assigned authority. Track drafts, votes, approvals, publication, amendments and status. Do not automatically send every law to SADOJ for preapproval; courts hear properly filed challenges.

## Agency, rank and access rules

Use the project's real `planning-reference/jobs.lua` and configuration as the source of truth for names and grade mappings; inspect before editing. `isboss` may identify a department manager but is **not** a universal cross-department permission bypass.

- Attorney General **Bryce Farlander** is `sadle` grade **11**, heading SADLE and supervising authorized SADOJ prosecution functions, including `sadoj` grades **5–6**. This is **not** judicial authority.
- `sadoj` includes District Judge grade **8**, Associate Justice **9**, and Chief Justice **10**. Judges and courts remain institutionally independent from AG prosecution oversight.
- `sagov` grades **0–9**, Governor grade **9**. Do not re-add the Attorney General as a duplicate SAGOV or SADOJ job grade.
- SADLE's authorized oversight can cross law-enforcement agencies; ordinary law-enforcement agencies remain restricted by default. Access is not simply 'same job vs different job': check role, interface, requested action, target agency, jurisdiction and record status.
- SAFR and SAMS accreditation and medical data sharing need precise issuer/visibility grants; do not infer blanket clinical access from job title or boss status.
- Preserve existing agency-specific rosters, SOPs, reports, attachments, permissions, training and certifications. Adapt existing personnel features for government, fire and medical rather than discarding them.

**Caution:** If a player database already stores grades, changing job grade numbers can have migration consequences. Inspect and plan rather than silently changing them.

## Government records and services: intended expansion

Government personnel should have ranks, rosters, training/certification and departmental administration analogous to existing PSMDT personnel functionality, but scoped by jurisdiction. Government functions include legislation, internal votes and public election ballots where appropriate, with publication distinguishing private drafts from public results.

Property administration: PS Realtor handles listings/transactions; PS Housing provides housing/ownership data; SAGOV handles assessment, approvals, classification, exemptions and tax records. Authorized assessors verify property type and jurisdiction, retain change history, and apply approved rules. Government-owned property is not automatically tax-exempt. The assessor cannot unilaterally set tax rates or confiscate property.

Business licensing: citizens can apply through public government services. Preferred initial model is **one local business license** from the correct local jurisdiction, with verification/rerouting by authorized officials; specialized permits can be added later. Do not invent a business-creation script. Distinguish property tax, business tax and sales tax; transaction-location calculation for NPC shops/vending remains undecided.

SADOJ court histories, including motions, evidence, hearings, orders and dispositions, must survive case closure. Government offices may initiate authorized legal proceedings with linked records, but seizures/foreclosures require the applicable process and judicial authority. Reuse existing court and motion features where possible.

## What is known about implementation, and what is not

The earlier source review described three staff-oriented experiences (law enforcement, DOJ and EMS), plus civilian functionality. It did **not** establish that all five branded interfaces or government/medical/fire expansions were already implemented.

Codex began **Phase 1** and reportedly changed these nine files before a usage interruption:

- `client/backend/dashboard.lua`
- `client/events.lua`
- `server/backend/court.lua`
- `server/backend/doj.lua`
- `server/backend/management.lua`
- `server/backend/officers.lua`
- `server/backend/roster.lua`
- `server/backend/warrants.lua`
- `server/functions.lua`

The report claimed initial job/interface routing, AG prosecution access checks, and narrower departmental administration. **Those claims are not yet independently verified.** The reported modified-file list contained no `web/src/` changes, so do not assert the full NUI is finished. Inspect the actual current diff. `server/backend/icu.lua` was previously identified as limited BOLO cleanup logic, not evidence of full hospital charting.

**No separate FiveM development server has been created yet.** Source checks can happen now; in-game testing cannot be claimed until a safe development environment exists.

## Immediate development priority

1. Inspect the current uncommitted changes and compare them with this document and the actual jobs/config.
2. Finish **only** Phase 1 foundation where appropriate: safe interface eligibility, scoped server authorization and preservation of existing functionality. Identify any UI work that remains; do not claim it is complete without evidence.
3. Provide a plain-English explanation of what a player can actually do, what is still only planned, and what was validated by static checks.
4. Establish a separate FiveM development server before runtime tests. Do not touch the live server.

## Unresolved details — do not invent decisions

Exact SADLE oversight grants beyond the AG; AG supervisory actions versus employment powers; judicial/clerk administrative grants; precise SAFR/SAMS accreditation issuers; interfacility medical sharing; some government delegation/publication authorities; detailed duty and department-sharing compatibility; sales-tax transaction-location mechanism; some public kiosk UX; and exact persistence ownership across PS Realtor/PS Housing/SAGOV require further review or user decisions.

## Working principles

Keep the existing working PSMDT features. Favor minimal changes, source inspection, server-side authorization and clear testable increments. Explain implementation in plain English and separate **designed**, **coded**, **checked**, and **tested in FiveM**. Preserve licensing/attribution and avoid publishing sensitive project design publicly without approval.
