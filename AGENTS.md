# PowerMoves PSMDT — Codex Working Rules

Read `POWERMOVES_PSMDT_PROJECT_CONTEXT.md` before proposing or making any change. This is an extension of the existing QBCore PS-MDT, not a rewrite.

1. Treat the project context as design intent, **not** proof of implemented functionality. Verify the real repository, `planning-reference/jobs.lua`, configs, SQL and client/server/web code.
2. Do not invent agency ranks, grant cross-agency authority from `isboss` alone, or equate the Governor, Attorney General, and judiciary.
3. Preserve existing police, DOJ, EMS and civilian workflows unless a specifically approved change requires otherwise. No destructive edits, database migrations, or live-server operations without explicit approval.
4. The five `.net` names identify interfaces of ONE tablet/resource/shared backend, not five independent apps.
5. Work incrementally. Before changing code, explain in plain English what the player will experience and which files you intend to change. After changes, state precisely what changed, what was tested, and what remains unverified. Never claim a FiveM runtime test without one.
6. The development server does not exist yet. Do not describe installation/testing there as already possible. Code checks and in-game verification are separate milestones.
7. The prior interrupted Phase 1 work reportedly modified nine Lua files. Inspect the current working tree and diff before adding or reverting anything; do not assume those edits are committed, correct, complete, or reflected in web/NUI code.
8. Do not make unresolved design decisions on the owner's behalf. Flag them, and avoid expanding scope while finishing a bounded task.
