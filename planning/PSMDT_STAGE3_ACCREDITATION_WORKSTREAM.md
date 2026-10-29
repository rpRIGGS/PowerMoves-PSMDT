# Stage 3 source workstream — statewide professional credentials

Stage 3 **source implementation** has begun; this does not certify Stage 2 completion on the user's live FiveM server. Stage 2 employer separation still needs two-employer runtime acceptance, calendar migration, legacy FTO record triage and authorized sharing tests.

## Existing engine and source work

- Keep the existing shared FTO engine: employer-specific phases, training, DORs and agency-job assigned FTO records. Do not clone separate scripts for fire, hospitals and law enforcement.
- Legacy FTO rows with NULL `agency_job` are withheld from employer manager list, detail and mutations. Historical data is **not** deleted or guessed. A read-only audit exists in `sql/migrations/2026-10-28-fto-owner-audit.sql`.
- `mdt_personal_accreditations` is the existing permanent credential ledger, separate from employer-private DOR records. The subject can access their permanent credentials after a transfer.
- A POST or authorized SADLE issuer may issue LEO-family credentials; SAFR may issue fire-family credentials; SAMS may issue EMS/medical-family credentials. All require the actual designated issuer job, an authorized session, and an explicit `roster_manage_certifications` grant. Employment alone is **not** a grant.
- The issue path rechecks permission after its citizen lookup to avoid stale duty/role authorizations.

## Remaining Stage 3 gates

1. Exact approved supervisor/accreditor grades and rights in `mdt_permission_roles`; do not assume boss = authority across agencies.
2. Actual medical, fire, corrections, and academy credential definitions and validity/revocation/renewal policy.
3. Agency-specific training results and inspections, audit logs, accreditation overview UI, DOJ legal mentorship paths, and government vocational pathways.
4. Runtime FiveM and SQL validation, including off-duty and employer-transfer checks.

**No schema migration, runtime testing or issuance has been executed against the user's server.**
