<script lang="ts">
	import { untrack } from "svelte";
	import type { AuthService } from "../services/authService.svelte";
	import { createGovernmentPersonnelService } from "../services/governmentPersonnelService.svelte";
	let { authService }: { authService: AuthService } = $props();
	const personnel = createGovernmentPersonnelService();
	let search = $state("");
	let showPositions = $state(false);
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
			if (eligible) void personnel.loadRoster();
		});
		return () => personnel.reset();
	});

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
			<div><dt>Access</dt><dd>{personnel.hasOversight ? "Authorized state personnel oversight" : "Your government department"} · Read only</dd></div>
		</dl>
	</div>
	<div class="roster-toolbar">
		<label class="search-field"><span>Search personnel</span><input type="search" bind:value={search} placeholder="Name, position, grade or department" /></label>
		{#if personnel.departments.length > 1}
			<label><span>Government department</span><select value={personnel.selectedDepartment} onchange={selectDepartment} disabled={personnel.isLoading}>
				{#each personnel.departments as item}<option value={item.job}>{item.label}</option>{/each}
			</select></label>
		{/if}
		<button onclick={() => personnel.loadRoster(personnel.selectedDepartment || undefined)} disabled={personnel.isLoading}>Refresh</button>
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
	{#if personnel.error}
		<p class="message error" role="alert">{personnel.error}</p>
	{:else if personnel.isLoading}
		<p class="message" role="status">Loading government personnel…</p>
	{:else if personnel.departments.length > 0}
		<div class="roster-table"><table><caption>{employees.length} employee{employees.length === 1 ? "" : "s"}{search.trim() ? " matching your search" : ""}</caption>
			<thead><tr><th scope="col">Employee</th><th scope="col">Position / rank</th><th scope="col">Grade</th><th scope="col">Department</th></tr></thead>
			<tbody>{#each employees as employee (employee.citizenid)}
				<tr><td>{employee.firstName} {employee.lastName}</td><td>{employee.rank || "Unknown position"}</td><td>{employee.grade ?? "Unknown"}</td><td>{employee.departmentLabel}</td></tr>
			{:else}<tr><td colspan="4" class="empty">{search.trim() ? "No employees match your search." : "No employees are currently assigned to this department."}</td></tr>{/each}</tbody>
		</table></div>
	{/if}
	<p class="availability">Personnel changes and appointments are not available here yet.</p>
</section>

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
</style>
