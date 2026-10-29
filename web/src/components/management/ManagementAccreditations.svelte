<script lang="ts">
    import { onMount } from "svelte";
    import { fetchNui } from "../../utils/fetchNui";
    import { NUI_EVENTS } from "../../constants/nuiEvents";
    import type { AuthService } from "../../services/authService.svelte";

    let { authService }: { authService?: AuthService } = $props();
    interface IssuedCredential {
        id: number;
        citizenid: string;
        credential_code: string;
        credential_name: string;
        credential_family: string;
        specialization?: string;
        issued_by_job: string;
        issued_at: string;
        expires_at?: string | null;
        source_reference?: string | null;
    }
    let records = $state<IssuedCredential[]>([]);
    let page = $state(1);
    let busy = $state(false);
    let error = $state("");
    let hasMore = $state(false);
    const issuerJobs = ["sadle", "post", "safr", "sams"];
    let authorized = $derived(
        !!authService?.hasPermission("roster_manage_certifications") &&
        issuerJobs.includes(authService?.agency ?? "")
    );

    async function load(nextPage = 1) {
        if (!authorized || busy) return;
        busy = true;
        error = "";
        try {
            const result = await fetchNui<IssuedCredential[]>(
                NUI_EVENTS.FTO.GET_ISSUED_ACCREDITATIONS, { page: nextPage }, []
            );
            records = Array.isArray(result) ? result : [];
            page = nextPage;
            hasMore = records.length === 50;
        } catch {
            records = [];
            error = "Could not load the issuing office's credential history.";
        } finally {
            busy = false;
        }
    }
    onMount(() => { void load(1); });
</script>

<section class="credential-audit">
    <h3>Issued credentials</h3>
    <p class="description">Read-only issuance history for your accredited state office. Credentials follow the individual; field-training evaluations remain with the employing department.</p>
    {#if !authorized}
        <p>State accreditation issuer authorization required.</p>
    {:else}
        <div class="toolbar"><span>{authService?.agency?.toUpperCase()} issuing office</span><button disabled={busy} onclick={() => void load(page)}>Refresh</button></div>
        {#if error}<p role="alert">{error}</p>{/if}
        {#if records.length === 0}
            <p>{busy ? "Loading…" : "No issued credentials on this page."}</p>
        {:else}
            <table>
                <thead><tr><th>Citizen ID</th><th>Credential</th><th>Family</th><th>Issued</th><th>Expires</th></tr></thead>
                <tbody>
                    {#each records as item (item.id)}
                        <tr><td>{item.citizenid}</td><td><strong>{item.credential_name}</strong><small>{item.credential_code}</small></td><td>{item.credential_family.toUpperCase()}</td><td>{item.issued_at}</td><td>{item.expires_at || "—"}</td></tr>
                    {/each}
                </tbody>
            </table>
        {/if}
        <nav aria-label="Credential audit pages"><button disabled={busy || page === 1} onclick={() => void load(page - 1)}>Previous</button><span>Page {page}</span><button disabled={busy || !hasMore} onclick={() => void load(page + 1)}>Next</button></nav>
    {/if}
</section>

<style>
    .credential-audit { padding: 18px 24px; color: var(--primary-text); }
    h3 { margin: 0 0 8px; }
    .description { opacity: .72; margin-bottom: 20px; max-width: 790px; }
    .toolbar, nav { display: flex; gap: 12px; align-items: center; justify-content: space-between; margin: 12px 0; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    th, td { padding: 10px 9px; border-bottom: 1px solid rgba(128,128,128,.2); text-align: left; }
    th { opacity: .7; }
    small { display: block; opacity: .65; margin-top: 3px; }
    button { padding: 7px 12px; border: 1px solid rgba(128,128,128,.35); border-radius: 5px; background: transparent; color: inherit; cursor: pointer; }
    button:disabled { opacity: .35; cursor: default; }
</style>
