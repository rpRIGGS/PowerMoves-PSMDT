# PowerMoves-PSMDT — Stage 4 source closeout / runtime handoff

Updated: October 29, 2026
Status: **Stage 4 source implementation and automated CI baseline ready for user DEV acceptance; live Stage 4 not signed off.**

## Completed in repository

1. **Local/Internal Affairs → SADLE**: original-complaint employer isolation, reasoned local referral, SADLE restricted queue and pending→accepted transition, referring department status view, source authorization rechecks and audit.
2. **Case-specific legal discovery**: named recipient citizenid + original employer, purpose, grant/revoke, recipient inbox, source-owned management, read audit, revocation recheck during case detail loading. Existing case-owner write boundaries preserved.
3. **Report-specific legal discovery**: separate named grants without replacing `mdt_reports_restrictions`, original report owner management, recipient inbox, read-only detail access, revocation/audit and anti-transfer checks. Ownerless legacy reports cannot be newly granted via the scoped workflow.
4. **Evidence-specific discovery**: issuer restricted by `evidence_transfer` and actual case employer/collector; read-only metadata and custody history; named recipient inbox, grant and revoke. No stash ID, inventory, movement, image upload or independent case/report access is conferred by an evidence grant.
5. **NUI**: IA referral panels; case/report shared-with-me lists and grant managers; evidence disclosure and custody panel.
6. **SQL**: new additive tables only (IA referral, case disclosures, report disclosures, evidence disclosures), shipped in QBCore/QBX clean install schemas and separate migration files. Existing police, fire, medical, DOJ or government operational tables were not relabeled by these Stage 4 migrations.
7. **Source tests**: Lua callback/regression tests, Node source contracts, Svelte TypeScript/build, and MariaDB CI integration tests for migration, recipient job scope, expiry/revocation and atomic referral acceptance.

## Actual test-server requirements — NOT completed in chat

- Make a backup of database and resource before applying the four Stage 4 migrations in `sql/migrations/`.
- Deploy on DEV server and run `planning/PSMDT_STAGE4_ACCEPTANCE.md` with actual LSPD, BCSO, SADLE and SADOJ actors at configured grades, both on- and off-duty.
- Verify actual oxmysql + ps_lib + QBCore callback behavior and real NUI rendering; inspect F8/server logs.
- Demonstrate prosecutor and assigned defense attorney record sharing is legally/organizationally correct for the specific role matrix, including what should happen on counsel reassignment or departure.
- Confirm how broad pre-existing SADOJ `court_view` rights should behave. The existing court permissions are intentionally preserved, not silently reduced. This is an authorization-policy acceptance item, not something to guess.
- Confirm evidence grant expiration, retention/audit policies and external disclosure notices if desired. Current schema has revocation; evidence grants are not time-limited by default.
- Sign off Stage 4 only after those scenarios pass. Until then: no production deployment, no declaration of operational completion.

## Handoff

Use `planning/PSMDT_STAGE4_ACCEPTANCE.md` as the detailed test matrix. All code is in the same existing PSMDT resource. No FiveM test server or live database is connected to the GitHub Actions runner. Source validation cannot certify in-game behavior.
