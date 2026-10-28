<script lang="ts">
	import { untrack } from "svelte";
	import type { AuthService } from "../services/authService.svelte";
	import { createGovernmentPersonnelService } from "../services/governmentPersonnelService.svelte";
	import type { GovernmentEmployee } from "../interfaces/IGovernment";
	let { authService }: { authService: AuthService } = $props();
	const personnel = createGovernmentPersonnelService();
	let search = $state("");
	let showPositions = $state(false);
	let editor = $state<"hire" | "grade" | "terminate" | null>(null);
	let selectedEmployee = $state<GovernmentEmployee | null>(null);
	let selectedGrade = $state(0);
	let hireServerId = $state<number | undefined>();
	let busy = $derived(personnel.isLoading || personnel.isSaving);
	let department = $derived(personnel.departments.find(item => item.job === personnel.selectedDepartment));
	let employees = $derived.by(() => {
		const query = search.trim().toLowerCase();
		return personnel.roster.filter(employee => !query ||
			[`${employee.firstName} ${employee.lastName}`, employee.rank, employee.grade?.toString(), employee.departmentLabel]
				.some(value => value?.toLowerCase().includes(query)));
	});

	$effect(() => {
		// Refresh and discard prior responses on any government identity change,
		// including a transfer that leaves the active interface as SAGOV.net.
		authService.playerData?.citizenid;
		authService.playerData?.job?.grade?.level;
		authService.agency;
		authService.jurisdiction;
		const eligible = authService.isAuthorized && authService.interfaceId === "sagov";
		untrack(() => {
			personnel.reset();
			search = "";
			showPositions = false;
			editor = null;
			selectedEmployee = null;
			if (eligible) void personnel.loadRoster();
		});
		return () => personnel.reset();
	});

	$effect(() => {
		if (!personnel.canManagePersonnel && !personnel.isLoading) editor = null;
	});

	function openEditor(action: "hire" | "grade" | "terminate", employee?: GovernmentEmployee) {
		if (!personnel.canManagePersonnel || busy) return;
		personnel.clearActionStatus();
		personnel.clearHireCandidate();
		selectedEmployee = employee ?? null;
		selectedGrade = employee?.grade ?? department?.grades[0]?.grade ?? 0;
		hireServerId = undefined;
		editor = action;
	}

	function closeEditor() {
		if (personnel.isSaving) return;
		editor = null;
		selectedEmployee = null;
		personnel.clearHireCandidate();
	}

	async function submitEmployment() {
		let success = false;
		if (editor === "hire") success = await personnel.hireEmployee(selectedGrade);
		else if (selectedEmployee && editor === "grade") success = await personnel.changeGrade(selectedEmployee.citizenid, selectedGrade);
		else if (selectedEmployee && editor === "terminate") success = await personnel.terminateEmployee(selectedEmployee.citizenid);
		if (success) closeEditor();
	}

	function selectDepartment(event: Event) {
		const job = (event.currentTarget as HTMLSelectElement).value;
		if (personnel.departments.some(item => item.job === job)) void personnel.loadRoster(job);
	}
</script>

<section class="government-home">
	<div class="heading">
		<span class="material-icons">account_balance</span>
		<div><h1>SAGOV.net</h1><p>Government Personnel</p></div>
	</div>
	<div class="office-card">
		<h2>{authService.playerInfo().department || authService.agency}</h2>
		<dl>
			<div><dt>Your position</dt><dd>{authService.playerInfo().rank}</dd></div>
			<div><dt>Access</dt><dd>{personnel.canManagePersonnel ? "Your department · Personnel administration" : personnel.hasOversight ? "Authorized state personnel oversight · Read only" : "Your government department · Read only"}</dd></div>
		</dl>
	</div>
	<div class="roster-toolbar">
		<label class="search-field"><span>Search personnel</span><input type="search" bind:value={search} placeholder="Name, position, grade or department" /></label>
		{#if personnel.departments.length > 1}
			<label><span>Government department</span><select value={personnel.selectedDepartment} onchange={selectDepartment} disabled={busy}>
				{#each personnel.departments as item}<option value={item.job}>{item.label}</option>{/each}
			</select></label>
		{/if}
		<button onclick={() => personnel.loadRoster(personnel.selectedDepartment || undefined)} disabled={busy}>Refresh</button>
		{#if personnel.canManagePersonnel}<button onclick={() => openEditor("hire")} disabled={busy}>Hire employee</button>{/if}
	</div>
	{#if department}
		<div class="roster-heading"><div><h2>{department.label}</h2><p>{department.jurisdictionLabel}</p></div>
			<button onclick={() => showPositions = !showPositions} aria-expanded={showPositions}>{showPositions ? "Hide" : "View"} positions and grades</button>
		</div>
		{#if showPositions}
			<div class="positions"><table><caption>Positions and grades — {department.label}</caption><thead><tr><th scope="col">Grade</th><th scope="col">Position / rank</th></tr></thead>
				<tbody>{#each department.grades as position}<tr><td>{position.grade}</td><td>{position.name}</td></tr>{/each}</tbody>
			</table></div>
		{/if}
	{/if}
	{#if personnel.actionMessage}<p class="message success" role="status">{personnel.actionMessage}</p>{/if}
	{#if personnel.actionError && !editor}<p class="message error" role="alert">{personnel.actionError}</p>{/if}
	{#if personnel.error}
		<p class="message error" role="alert">{personnel.error}</p>
	{:else if personnel.isLoading}
		<p class="message" role="status">Loading government personnel…</p>
	{:else if personnel.departments.length > 0}
		<div class="roster-table"><table><caption>{employees.length} employee{employees.length === 1 ? "" : "s"}{search.trim() ? " matching your search" : ""}</caption>
			<thead><tr><th scope="col">Employee</th><th scope="col">Position / rank</th><th scope="col">Grade</th><th scope="col">Department</th>{#if personnel.canManagePersonnel}<th scope="col">Personnel actions</th>{/if}</tr></thead>
			<tbody>{#each employees as employee (employee.citizenid)}
				<tr><td>{employee.firstName} {employee.lastName}</td><td>{employee.rank || "Unknown position"}</td><td>{employee.grade ?? "Unknown"}</td><td>{employee.departmentLabel}</td>
					{#if personnel.canManagePersonnel}<td>{#if employee.citizenid !== authService.playerData?.citizenid}<div class="employee-actions"><button onclick={() => openEditor("grade", employee)} disabled={busy}>Change position</button><button class="danger" onclick={() => openEditor("terminate", employee)} disabled={busy}>Terminate</button></div>{:else}<span>Your position</span>{/if}</td>{/if}
				</tr>
			{:else}<tr><td colspan={personnel.canManagePersonnel ? 5 : 4} class="empty">{search.trim() ? "No employees match your search." : "No employees are currently assigned to this department."}</td></tr>{/each}</tbody>
		</table></div>
	{/if}
	<p class="availability">{personnel.canManagePersonnel ? "Personnel changes apply to your government department. Employees must be online." : "Personnel administration is available to department bosses within their own government job."}</p>
</section>

{#if editor && personnel.canManagePersonnel && department}
	<div class="editor-backdrop">
		<section class="personnel-editor" role="dialog" aria-modal="true" aria-labelledby="personnel-editor-title" tabindex="-1">
			<h2 id="personnel-editor-title">{editor === "hire" ? "Hire government employee" : editor === "grade" ? "Change employee position" : "Terminate employment"}</h2>
			<p>{department.label}</p>
			{#if editor === "hire"}
				<p>Find an online unemployed player by their server ID.</p>
				<div class="candidate-search"><label><span>Player server ID</span><input type="number" min="1" step="1" bind:value={hireServerId} oninput={() => personnel.clearHireCandidate()} disabled={personnel.isSaving} /></label>
					<button onclick={() => personnel.findHireCandidate(hireServerId ?? 0)} disabled={personnel.isFindingCandidate || personnel.isSaving}>{personnel.isFindingCandidate ? "Finding…" : "Find player"}</button></div>
				{#if personnel.hireCandidate}<p class="candidate-name">{personnel.hireCandidate.firstName} {personnel.hireCandidate.lastName} · Server ID {personnel.hireCandidate.serverId}</p>{/if}
			{:else if selectedEmployee}
				<p class="candidate-name">{selectedEmployee.firstName} {selectedEmployee.lastName}</p>
				<p>{editor === "terminate" ? "End this employee's employment with your department?" : "Choose a position from your department's existing grades."} The employee must be online.</p>
			{/if}
			{#if editor !== "terminate"}<label><span>{editor === "hire" ? "Initial position" : "New position"}</span><select bind:value={selectedGrade} disabled={personnel.isSaving}>{#each department.grades as position}<option value={position.grade}>{position.grade} — {position.name}</option>{/each}</select></label>{/if}
			{#if personnel.actionError}<p class="error" role="alert">{personnel.actionError}</p>{/if}
			<div class="editor-actions"><button onclick={closeEditor} disabled={personnel.isSaving}>Cancel</button><button class:danger={editor === "terminate"} onclick={submitEmployment} disabled={busy || (editor === "hire" && !personnel.hireCandidate)}>{personnel.isSaving ? "Saving…" : editor === "hire" ? "Hire employee" : editor === "grade" ? "Save position" : "Terminate employment"}</button></div>
		</section>
	</div>
{/if}

<style>
	.government-home { padding: 32px; color: var(--primary-text); }
	.heading { display: flex; align-items: center; gap: 16px; margin-bottom: 28px; }
	.heading > .material-icons { font-size: 36px; }
	h1 { font-size: 26px; margin: 0 0 5px; }
	p { margin: 0; opacity: 0.7; }
	.office-card { padding: 22px; border: 1px solid var(--border-primary); border-radius: 8px; background: var(--card-dark-bg); }
	h2 { margin: 0 0 18px; font-size: 17px; }
	dl { margin: 0; display: grid; gap: 18px; }
	dl > div { display: grid; grid-template-columns: 135px 1fr; gap: 16px; }
	dt { opacity: 0.6; } dd { margin: 0; }
	.availability { max-width: 700px; margin-top: 20px; line-height: 1.6; }
	.roster-toolbar, .roster-heading { display: flex; align-items: end; gap: 16px; margin: 24px 0 16px; flex-wrap: wrap; }
	.roster-heading { align-items: center; justify-content: space-between; }
	.roster-heading h2 { margin-bottom: 6px; }
	label { display: grid; gap: 7px; font-size: 13px; }
	.search-field { flex: 1; min-width: 220px; }
	input, select, button { font: inherit; color: var(--primary-text); background: var(--card-dark-bg); border: 1px solid var(--border-primary); border-radius: 5px; padding: 10px 12px; }
	button { cursor: pointer; }
	button:disabled { cursor: wait; opacity: 0.5; }
	input:focus-visible, select:focus-visible, button:focus-visible { outline: 2px solid var(--primary-text); outline-offset: 2px; }
	.roster-table, .positions { overflow-x: auto; border: 1px solid var(--border-primary); border-radius: 8px; }
	.positions { margin-bottom: 20px; }
	table { width: 100%; border-collapse: collapse; text-align: left; font-size: 14px; }
	caption { padding: 14px 16px; text-align: left; opacity: 0.7; }
	th, td { padding: 13px 16px; border-top: 1px solid var(--border-primary); overflow-wrap: anywhere; }
	th { font-size: 12px; }
	.empty, .message { padding: 28px 16px; text-align: center; }
	.error { color: #fca5a5; }
	.success { color: #86efac; }
	.employee-actions, .editor-actions, .candidate-search { display: flex; gap: 10px; align-items: end; flex-wrap: wrap; }
	.employee-actions button { padding: 7px 9px; font-size: 12px; }
	.danger { color: #fca5a5; border-color: #7f1d1d; }
	.editor-backdrop { position: fixed; inset: 0; background: rgba(0, 0, 0, 0.65); display: grid; place-items: center; z-index: 100; padding: 20px; }
	.personnel-editor { background: var(--card-dark-bg); color: var(--primary-text); border: 1px solid var(--border-primary); border-radius: 8px; padding: 24px; width: min(520px, 100%); display: grid; gap: 18px; max-height: 90vh; overflow-y: auto; }
	.personnel-editor h2 { margin: 0; }
	.candidate-name { opacity: 1; font-weight: 600; }
	.editor-actions { justify-content: end; }
</style>
