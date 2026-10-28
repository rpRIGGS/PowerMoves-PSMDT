<script lang="ts">
	import type { AuthService } from "../services/authService.svelte";
	let { authService }: { authService: AuthService } = $props();
	const jurisdictions: Record<string, string> = {
		state: "State of San Andreas",
		san_andreas: "State of San Andreas",
		blaine_county: "Blaine County",
		los_santos_county: "Los Santos County",
		los_santos_city: "City of Los Santos",
		city_of_los_santos: "City of Los Santos",
	};
	let jurisdiction = $derived(jurisdictions[authService.jurisdiction] || authService.jurisdiction || "Not assigned");
</script>

<section class="government-home">
	<div class="heading">
		<span class="material-icons">account_balance</span>
		<div><h1>SAGOV.net</h1><p>San Andreas Government</p></div>
	</div>
	<div class="office-card">
		<h2>Your office</h2>
		<dl>
			<div><dt>Department</dt><dd>{authService.playerInfo().department || authService.agency}</dd></div>
			<div><dt>Position</dt><dd>{authService.playerInfo().rank}</dd></div>
			<div><dt>Jurisdiction</dt><dd>{jurisdiction}</dd></div>
		</dl>
	</div>
	<p class="availability">Government services are being prepared. No applications or government transactions are available here yet.</p>
</section>

<style>
	.government-home { padding: 32px; color: var(--primary-text); }
	.heading { display: flex; align-items: center; gap: 16px; margin-bottom: 28px; }
	.heading > .material-icons { font-size: 36px; }
	h1 { font-size: 26px; margin: 0 0 5px; }
	p { margin: 0; opacity: 0.7; }
	.office-card { max-width: 700px; padding: 22px; border: 1px solid var(--border-primary); border-radius: 8px; background: var(--card-dark-bg); }
	h2 { margin: 0 0 18px; font-size: 17px; }
	dl { margin: 0; display: grid; gap: 18px; }
	dl > div { display: grid; grid-template-columns: 135px 1fr; gap: 16px; }
	dt { opacity: 0.6; } dd { margin: 0; }
	.availability { max-width: 700px; margin-top: 20px; line-height: 1.6; }
</style>
