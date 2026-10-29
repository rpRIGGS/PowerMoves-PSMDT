# Stage 6 — SAGOV/SADOT implementation and acceptance

**Status:** Development in progress; source CI and live DEV acceptance are separate.
Do not mark Stage 6 deployed or operational until the complete checklist has
been run on a QBCore development server. Stage 7 is not in scope here.

## Source implementation checkpoints
- Single PSMDT resource. QBCore remains authoritative. SADOT disabled until
  vetted operator jobs, official tow permits, qualified drivers and authorized
  vehicles are provisioned.
- Government hierarchy: State, two peer counties, Los Santos City under Los
  Santos County. A future incorporated municipality can be configured without
  authorizing the parent county to see unpublished local records.
- SAGOV personnel, public administrative notices, local business licensing
  and separate vending permit applications. Publication and withdrawal are
  separately authorized and audited; a notice is not an enacted law.
- Public applications/notices use configured `qb-target` circle/polygon desks.
  No fictional counter coordinates or slash-command alternative.
- Local business licenses are owned by the actual applicant citizen ID and
  handled by their receiving government office. Review, issuance and state
  oversight have distinct permission grants. Issuance does **not** create a
  company in another script, assess a property, calculate tax or authorize 511.
- State Tax Assessor register uses PS Housing's actual
  `properties.property_id`; records are keyed by taxable jurisdiction and
  year. Reassessment/approval preserves audit snapshots and verifies the
  property's current owner. Government ownership and tax exemption are
  independent. No property tax is calculated yet.
- SADOT qualification gates require a qualifying local business license,
  independent current tow permit, driver qualification, vehicle registration,
  correct employer and on-duty status; all must pass server-side. An ordinary
  `mechanic` type is not sufficient.

## Required DEV validation
1. Back up the development database. Apply the Stage 6 additive SQL
   migrations in order, or use updated `sql/qbcore.sql` or `sql/qbx.sql`
   for a clean installation. Never import the latter over existing data.
2. Provide real `qb-target` vectors/polyzones and explicitly approved
   government staff permissions in `mdt_permission_roles`; defaults intentionally
   grant no business, publishing or assessor authority.
3. Test a civilian application and tracking at a public desk. Verify separate
   county/city routing and that a neighboring office cannot see or approve it.
4. Test state oversight separately from local action rights: state may read
   only when permitted, cannot silently issue licenses for another authority.
5. Test a public notice draft, edit, publish, withdraw, state read-only
   oversight and civilian published-only listing. Confirm no cross-agency draft
   leakage or employee metadata in unrelated public reads.
6. Test an assessment for each relevant taxable authority and year, including
   State's distinct authority. Change PS Housing owner mid-review, check
   rollback; validate explicit exemption reason and audit history.
7. SADOT: test wrong mechanic job, off-duty driver, expired permit, expired
   vehicle qualification, changed vehicle plate, and a cancelled 511 claim.
   Keep SADOT inactive if the actual dispatch fork has not been integrated.
8. Inspect F8 and server logs, resource restarts, NUI build, migration results
   and QBCore permissions; record observed outcomes before any production use.

## Unfinished integration / owner decisions (do not claim completion)
- **PS Realtor/PS Housing** currently create/manage listings without the
  assessment sale gate. The PSMDT assessor export is not called from those forks.
  Sale restrictions and real-estate approval remain unimplemented in-game.
- No authoritative server-approved tax-rate legislation, collection ledger,
  sales-tax location rules, budget disbursement, or finalized taxing-authority
  payment integration has been established. Do not charge players or assume
  all parent taxes apply to a property.
- Legislative enactment, official voting/ballots/elections, independent SADOJ
  challenges, and public FOIA publication have additional requirements beyond
  posting administrative notices; not complete.
- SADOT operator UI/report templates and full PS-Dispatch 511 exclusive claim
  integration require verification in both forks and the owner's test server.
  No mechanic job receives SADOT access simply by changing the config.
- Actual MLO vectors, specific assessor/issuer grades, fees and government
  tax policy have not been supplied; do not invent them.

## CI scope
The GitHub validation workflow runs Lua syntax and isolated runtime mocks,
frontend type checks/build, source contracts and MariaDB smoke tests.
Success is not evidence of full FiveM, PS Housing or PS Dispatch integration.
