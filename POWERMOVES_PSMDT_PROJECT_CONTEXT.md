# PowerMoves RP — PS-MDT Development Context

**Status:** Planning reference, not proof that features have been implemented.  
**Platform:** FiveM, QBCore, Project Sloth PS-MDT as the existing base.  
**Working rule:** Inspect existing source and configurations before editing. Preserve originals and the working server. Use a separate development copy and incremental, testable changes.

## Goal

Extend the existing PS-MDT resource into **one shared system with six interfaces**, reusing existing capabilities rather than rebuilding them. The six interfaces share a backend/database as appropriate but enforce distinct agency, role, jurisdiction, and record-visibility permissions.

1. **SADLE.net** — San Andreas Division of Law Enforcement; LEO interface and statewide oversight, investigations, internal affairs, training, FTO, certifications, agency records, and appropriate restricted cross-agency access.
2. **SADOJ.net** — San Andreas Department of Justice; courts, cases, motions, hearings, orders, legal personnel, and judicial review. Separate from SADLE oversight.
3. **SAFR.net** — San Andreas Fire Rescue; fire departments and EMS operations, personnel, training/certifications, incident and EMS reports.
4. **SAMS.net** — San Andreas Medical Service; hospital and medical personnel, certifications/training, patient records and medical charting, subject to medical access controls.
5. **SAGOV.net** — San Andreas Government; statewide, county, and municipal government administration, legislation, records, budgets, taxes, licensing, permits, appointments, and jurisdiction-specific workflows.
6. **SADOT.net** — San Andreas Department of Transportation; transportation oversight, licensed mechanic/towing companies, fleet management, 511 recovery records, towing/impound audit histories and authorized vehicle/accident report views. The interface remains inactive until agency-scoped permission and license checks are implemented.

These are six interfaces **within one PS-MDT system**, not five unrelated resources. Keep the established QBCore framework; do not pursue a custom FiveM framework.

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

## Six-interface shared-service boundaries (updated October 28, 2026)
All six interfaces extend the existing shared MDT capability; do not clone scripts or create parallel record stores merely to build an interface.

- **SADLE.net**: original operational law enforcement MDT. Keep its reports, evidence, cases, warrants, LEO agencies, dispatch/callsigns, internal affairs, training/FTO and certifications. The Attorney General heads SADLE, but special statewide investigative/oversight privileges require explicit authorization. State/federal visibility must be audited against existing FIB/government restrictions, not assumed for every boss or employee.
- **SADOJ.net**: judges, prosecutors, court staff, litigation and evidence intake from LEO and permitted other sources. Chief Justice heads SADOJ; judicial authority is not the same as statewide prosecutor/investigator access. Extend the existing FTO-like program to legal training with own phases and competency rubric when scoped agency data is ready.
- **SAFR.net**: fire/rescue departmental operations and statewide fire professional accreditation; reuses appropriately scoped personnel, callsigns, dispatch, incident reports, training/FTO engine, certifications, bulletin/SOP systems. `fire` remains the QBCore job type, distinct from `ems`.
- **SAMS.net**: hospitals/medical personnel and statewide medical professional accreditation; same shared components with medical training stages, certification, EMS dispatch where appropriate, and restricted medical charts. `ems` remains the QBCore medical job type.
- **SAGOV.net**: state, county, and municipal agencies, personnel, appointments, decisions, public service requests, property/business assessment, business registration and licensing. Government approval never automatically grants unrelated operational police or transportation access.
- **SADOT.net**: public 511 towing/roadside operations, licensed mechanic-shop and fleet personnel, agency-authorized tow/recovery and vehicle inspections, permitted accident/vehicle information, transport compliance and accreditation. `mechanic` is a broad framework job type but not by itself an operational license or full MDT authorization.

### Tow-operator establishment and authorizations
1. Real estate/property system records the selected/owned commercial property.
2. Appropriate local government receives and approves a business proposal and business license in SAGOV.net, within jurisdiction rules. This does not automatically issue a towing permit.
3. SADOT verifies the business's specific **tow operator permit** and qualified personnel/vehicles. Only compliant licensed operators receive transportation operations access and eligibility for public 511 tow assignments, subject to on-duty status.
4. A tow assignment is dispatched by PS-Dispatch but assigned/recorded by PSMDT; the operator uses **existing MDT report templates**, not a separate /towreport form, to submit vehicle condition/recovery documentation.
5. If police tow or impound a vehicle during an investigation, its authorized vehicle/tow report links to the **original criminal case and related SADOJ court file** by reference, retaining evidence custody and immutable history. Do not copy inconsistent report histories across agencies.
6. Towing to garages, storing, deleting, or impounding physical vehicles requires validated integration with the actual vehicle/storage scripts. No such integration has been established yet.

### Shared component strategy, not code duplication
Dispatch, callsigns, report templates, personnel roster, SOPs/bulletins, training/FTO, certifications and ordinary case/document links should each have one implementation with agency/service configuration and **server-enforced ownership/oversight policy**. Six labels, navigation routes and future specialized templates are appropriate placeholders; copying entire CRUD workflows is not.

**Verified technical limitation:** The existing FTO backend stores assignments with broad `job_type` domain (`police` or `ems`) and phases/competencies by actual `job`. Tight domain isolation for direct reads/writes was added as a first safeguard, but true employer/agency-level FTO isolation and scoped statewide accreditation still require new data ownership and authorization controls. Do not enable a sixth interface before these are available.

**Correction:** SADOT ledger schema/record exports now reside in PSMDT `server/backend/sadot_records.lua`; PS-Dispatch forwards lifecycle events via `exports['ps-mdt']:RecordSadotTowEvent`. The dispatch-side tow journal and duplicate `/towreport` form were removed; existing database data was **not deleted**. This integration is not yet runtime-tested and loses durable transitions while PSMDT is stopped. The full SADOT browser UI, licensing enforcement and records/report integration are not implemented.

## Implementation method — owner-directed LEO replication
The **existing working LEO MDT is the functional template**. For every additional interface, copy/replicate its established *interface workflows and proven coding patterns* first (dashboards, agency-specific dispatch/callsigns, personnel/rosters, reports/templates, FTO/training, certifications, SOPs, permissions, auditing), then customize the cloned workflow to that service's jobs, ranks, terminology, branding, templates and operational functions. Do not replace working features with speculative new engines or merely create blank labels when functional LEO code is already available. Deliver usable service-specific counterparts incrementally on main.

Preserve the **one PSMDT resource and shared database/integrations**: replication means functional agency-specific UI/modules and configurations, **not six unrelated deployments or redundant copies of sensitive shared storage**. Each service's staff/records must be scoped to its own agencies; statewide or federal cross-agency oversight is separately permissioned. Existing LEO capabilities stay intact. Adapt hospital EMS and fire paramedic handling without renaming QBCore `ems` or `fire` job types. SADOT towing report functionality belongs in the existing MDT reporting system, not PS-Dispatch.

## Accredited-agency training authority (confirmed October 28, 2026)
**Critical original-design distinction:** SADLE sets statewide peace-officer and corrections training/accreditation standards; POST delivers initial state-accredited academy pathways. SADLE accredits **both individuals and employing agencies**. After the academy, agencies such as LSPD, sheriff departments, SAHP and the prison authority are **trusted accredited training providers**, obligated to maintain SADLE standards and record continuing training. The employing agency's authorized FTOs, supervisors, instructors and command are responsible for conducting, reviewing and approving ongoing training. SADLE audits compliance and may govern/accredit academy or specialty qualifications; it does not personally perform every department's daily FTO evaluation. The corrections pathway may produce a different credential and curriculum while remaining under the same SADLE/POST standards structure.

**Three connected but distinct records:**
1. **Person's permanent qualification and training history:** statewide academy completion, job-classification credentials, specialized endorsements and continuing education. Transfers must not erase it.
2. **Accredited employing agency:** agency-level credential/authorization, accredited programs and standards obligations, status/review/expiry and responsible training leadership. This is a distinct accreditable entity, not merely a QBCore job label.
3. **Agency-conducted field training:** FTO/DOR observations, instructors, phases, competency evaluations, sign-offs and annual/continuing training performed under delegated state standards. Supervisors manage their own agency's training records; authorized SADLE roles can inspect compliance and applicable underlying records. State oversight must be explicit and auditable, not universal boss access.

Reuse the original FTO, personnel roster, certifications, training and SOP code. The existing `agency_job` on FTO assignments identifies the **training provider/employer**, not the owner of a person's lifetime qualifications. Current domain/job-scoped DOR protections are transitional and must evolve to explicitly authorized accreditor review. Avoid equating statewide standards with one shared academy-only workflow or restricting the original employee's portable training transcript to the current employer.

Apply the corresponding model to SAFR: SAFR sets fire-rescue standards and accredits individual fire personnel *and local/county fire departments*, which then conduct their own supervised ongoing training. Keep each agency's operational records and local instruction separate from statewide accreditation policy.
