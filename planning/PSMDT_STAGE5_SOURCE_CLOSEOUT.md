# Stage 5 source closeout — October 29, 2026

**Status:** SOURCE DEVELOPMENT CLOSED FOR THIS CHECKPOINT. DEV FiveM acceptance and
production deployment are **NOT** complete. Do not claim this has been tested in
FiveM, or that real public counters are configured.

## Verified automated checks
GitHub Actions run **40902235390** (commit `96a248c240ac906de999ff7dba73adbc409f9b92`)
completed successfully in all three jobs:
- `lua-regressions`: syntax and Stage 5 citizen, records-officer,
  transaction rollback, coordinate/poly-zone, release-copy and NUI-open mocks.
- `frontend-validation`: Svelte/TypeScript check, compiled NUI and static source
  regressions; CI also provides the `psmdt-nui-dist` artifact for DEV tests.
- `stage4-mariadb`: includes Stage 5 additive migrations and SQL cases for
  recipient scoping, duplicate release prevention, expiration, revocation,
  assignment and transaction rollback.

This is automated source/temporary-database validation only.

## Implemented boundary
- One PSMDT resource; no second framework, no records-office slash command.
- Civilian service counters use configured `qb-target` vector3 circles or
  polygon zones; target restarts are handled. Disabled/missing coordinates do
  not create active counters.
- IA complaint reuses the existing civilian complaint entry point.
- Public-records submission, applicant-owned tracking/history and status.
- Records-office queue, pagination, responsible reviewer assignment, per-job
  allowlist and live server-side location checks.
- Staff review, approval or written denial; each is audited and staff-only.
- Manually authored public release copies, recipient-citizen-ID grants, explicit
  1–365-day expiration and independently audited revocation.
- Applicant-only reads, with no implicit access to confidential case, medical,
  IA, report or evidence source tables.
- Checked oxmysql transactions require version 2.12.0+; incompatible installs
  fail closed and log a warning.

## DEV acceptance still required
1. Back up the development database; apply Stage 5 migrations on existing
   installations in this order:
   - `2026-10-29-public-records-intake.sql`
   - `2026-10-29-public-records-review.sql`
   - `2026-10-29-public-records-response.sql`
   - `2026-10-29-public-record-release-copies.sql`
   - `2026-10-29-public-records-assignment.sql`
   New installs use the updated `sql/qbcore.sql` or `sql/qbx.sql`.
2. Use real MLO counter vectors and vetted `Config.PublicServices.RecordsOfficers`
   assignments. Defaults intentionally enable **no actual counters**.
3. Build `web/dist` with `cd web && npm ci && npm run build`, or use the
   validated CI `psmdt-nui-dist` artifact and install contents under
   `web/dist/`. The directory is intentionally gitignored.
4. Run every case in `planning/PSMDT_STAGE5_ACCEPTANCE.md` with two civilian
   characters and two different employing agencies, including resource
   restarts, job/duty changes, expire/revoke tests and server/F8 logs.

## Exit gate for the complete live Stage 5
Only mark **runtime complete** when DEV validation is recorded. Beginning Stage 6
source work does not assert a completed FiveM deployment or waive that gate.
