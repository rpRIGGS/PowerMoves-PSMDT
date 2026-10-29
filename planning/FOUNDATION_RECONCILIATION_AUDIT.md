# Foundation reconciliation — original PS-MDT to PowerMoves interfaces

Status: initial verified inventory; **not** a claim of implemented or tested interface parity.
Reference: `Project-Sloth/ps-mdt` `config.lua` and `rpRIGGS/PowerMoves-PSMDT` `config.lua`, `server/auth.lua`, `fxmanifest.lua`, `planning-reference/jobs.lua` as inspected 2026-10-29.

## Baseline and invariant

- Keep one QBCore PS-MDT resource, existing SQL and original features; do not replace or erase the upstream police, DOJ, or EMS flows.
- The six UI/domain interfaces are SADLE (leo), SADOJ (doj), SAFR (fire), SAMS (ems), SAGOV (gov), SADOT (dot; disabled).
- Agency job names, QBCore job types, ranks and grades come from `planning-reference/jobs.lua`; do not invent grades.
- Interface entry permission, employer-scoped records, oversight visibility and inter-interface sharing are four separate decisions.
- Default deny confidential cross-agency and cross-domain access; sealed court records, patient charts and unpublished government records require explicit server checks.
- Do not mark a feature implemented without tracing the config through its server callback/query and web/client entry points.

## Original config inventory and disposition

| Original config keys | Reconciliation |
| --- | --- |
| `Debug`, `DateTime`, `Uploads`, `Pagination`, `CacheTTL`, `Animation` | Shared infrastructure; retain original unless a concrete interface requirement demands otherwise. |
| `OnlyShowOnDuty`, `CivilianAccess`, `Keys`, `Commands` | Shared entry mechanism, with interface-specific authorization and kiosk/public-service rules; no new slash-command kiosks. |
| `Sharing` | Original law-enforcement Mutual/OneWay contract. New `Sharingleo`, `Sharingdoj`, `Sharingems`, `Sharingfire`, `Sharinggov`, `Sharingdot` exist; `Sharing` aliases `Sharingleo`. **Must verify actual data readers before considering the others operational.** |
| `PoliceJobType`, `PoliceJobs`, `DojJobType`, `DojJobs`, `MedicalJobType`, `MedicalJobs` | Preserve existing LEO/DOJ/EMS mappings. Fork adds `FireJobType`, `FireJobs`, `MdtAccess` for fire, government and oversight; reconcile with real jobs.lua. |
| `ManagementPermissions`, `PermissionDefaults`, `PersonnelCleanup`, `OfficerStatus` | Audit original personnel/roster/certification/FTO functions per job and interface; scope every management action to authorized employer/oversight. |
| `Court`, `Warrants`, `Fines`, `AuditTracking` | Preserve original court/judicial and police functionality; enforce DOJ sealed-case permissions and durable history separately. |
| `Dispatch`, `DispatchCodes`, `Radio`, `Phone` | Shared integrations with job-family visibility/authorization; avoid cloning a dispatch service per interface. |
| `IA` | Preserve original complaint/IA handling; configure authorized SADLE oversight and qb-target kiosk submission. |
| `Housing`, `VehiclePoints`, `VehicleInsurance`, `VehicleRegistration`, `Impound`, `Fuel` | Preserve existing LEO vehicle/property flows; integrate GOV property assessment and DOT later through scoped APIs, not blanket access. |
| `UseWolfknightRadar`, `WolfknightNotifyTime`, `PlateScanForDriversLicense`, `FingerprintAutoFilled`, `FingerprintScan`, `RegisterWeaponsAutomatically`, `RegisterCreatedWeapons`, `WeaponImagePath`, `Weapons` | Police operational settings; do not duplicate into unrelated interfaces. |
| `MugshotCamera`, `CameraViewer`, `Dashcam`, `Bodycam`, `CameraModels`, `CameraPlacer` | Shared camera integrations; per-interface permissions and record ownership, not six independent camera systems. |

## Confirmed current implementation boundaries

- `fxmanifest.lua` still loads one `config.lua`, all `client/**.lua` and `server/**.lua`, and one `web/dist/index.html`. Config sections alone do **not** create or duplicate NUI interfaces.
- `server/auth.lua` contains `GetMdtAccess`, `CheckMdtInterfaceAccess`, and dedicated government/service access helpers; it does **not** reference any `Config.Sharing*` policy in the inspected file. Search all server consumers before changing legacy sharing behavior.
- Current `Config.MdtAccess.PermissionSets` has separate leo/ems/fire/doj ceilings and an empty gov ceiling. This is not evidence that all upstream features are wired per interface.
- Current sharing policies for DOJ and GOV are empty, and DOT is disabled. Empty policies are placeholders, **not** complete functional designs.
- Existing `Config.MdtAccess.GovernmentJobs` maps `sagov`, `bcgov`, `lscgov`, `lsgov` to state/Blaine County/Los Santos County/City of Los Santos. Government internal records must respect those jurisdictions.
- `planning-reference/jobs.lua` contains government job definitions; it is the authority for mapping, not a file to rewrite to fit guessed config values.

## Execution order and acceptance gates

1. Inventory **all** server/client/web source and SQL schemas, compare with upstream, trace original police/DOJ/EMS entry points and their config consumers. Record each feature as retained, adapted, missing, or broken.
2. Fix config organization only where an actual consumer needs a per-interface policy. Use original Project Sloth formatting and comments. No duplicate configuration that has no functional consumer.
3. Adapt existing LEO, DOJ and EMS entry points; build FIRE and GOV from reused original components with independent domain identity and job mapping. Keep DOT disabled until authorized design is implemented.
4. Wire each interface to its server-side authorization, employer/oversight scope, data queries, UI routes and existing report/roster/court workflows. Reject access on the server; client UI is not security.
5. Add explicitly authorized cross-interface sharing only after base interface isolation works. Test sealed, medical and unpublished government records as negative cases.
6. Validate syntax and diffs, document what can be statically checked, then hand off to an actual FiveM/QBCore test server for runtime tests.

**No stage is complete on the strength of this audit document alone.** Each gate needs code changes and verifiable checks.
