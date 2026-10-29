<script lang="ts">
    import { onMount } from "svelte";
    import { fetchNui } from "../utils/fetchNui";
    import { isEnvBrowser } from "../utils/misc";

    let { onClose }: { onClose: () => void } = $props();

    interface RequestItem {
        id: number;
        request_number: string | null;
        agency: string;
        subject: string;
        description: string;
        status: string;
        created_at: string;
    }
    interface QueueResult { success: boolean; error?: string; requests?: RequestItem[]; }
    interface DecisionResult { success: boolean; error?: string; }
    interface AuditEntry {
        action: string;
        reason: string;
        actor_citizenid: string;
        created_at: string;
    }
    interface AuditResult { success: boolean; entries?: AuditEntry[]; error?: string; }

    let items = $state<RequestItem[]>([]);
    let selected = $state<RequestItem | null>(null);
    let action = $state<"under_review" | "denied" | "approved">("under_review");
    let reason = $state("");
    let error = $state("");
    let info = $state("");
    let loading = $state(false);
    let saving = $state(false);
    let history = $state<AuditEntry[]>([]);
    let historyLoading = $state(false);

    async function loadHistory(id: number) {
        history = [];
        historyLoading = true;
        try {
            const result = await fetchNui<AuditResult>("getPublicRecordRequestAudit", { id }, {success:false});
            if (selected?.id === id) {
                history = result?.success && Array.isArray(result.entries) ? result.entries : [];
            }
        } catch {
            if (selected?.id === id) history = [];
        } finally {
            if (selected?.id === id) historyLoading = false;
        }
    }


    async function reload() {
        loading = true;
        error = "";
        try {
            const result = await fetchNui<QueueResult>("getPublicRecordsOfficeQueue", {}, { success: false });
            if (!result?.success) {
                items = [];
                selected = null;
                error = result?.error || "Records-office access denied.";
                return;
            }
            items = Array.isArray(result.requests) ? result.requests : [];
            if (selected) selected = items.find(item => item.id === selected?.id) ?? null;
        } catch {
            error = "Unable to load the records-office queue.";
            items = [];
            selected = null;
        } finally {
            loading = false;
        }
    }

    function choose(item: RequestItem) {
        selected = item;
        reason = "";
        info = "";
        error = "";
        action = item.status === "submitted" ? "under_review" : "denied";
        void loadHistory(item.id);
    }

    async function submit() {
        if (!selected || saving || reason.trim().length === 0) return;
        if (selected.status === "submitted" && action !== "under_review") return;
        if (selected.status === "under_review" && action === "under_review") return;
        const id = selected.id;
        saving = true;
        error = "";
        info = "";
        try {
            const eventName = action === "approved"
                ? "publishPublicRecordsResponse" : "reviewPublicRecordsRequest";
            const payload = action === "approved"
                ? { id, response: reason.trim() } : { id, action, reason: reason.trim() };
            const result = await fetchNui<DecisionResult>(eventName, payload, { success: false });
            if (!result?.success) {
                error = result?.error || "The request was not updated.";
                return;
            }
            selected = null;
            reason = "";
            info = "Decision saved.";
            await reload();
        } catch {
            error = "The request was not updated.";
        } finally {
            saving = false;
        }
    }

    onMount(() => {
        let active = true;
        void reload();
        if (isEnvBrowser()) return;
        // Clear cached confidential queue data when a player leaves the
        // configured counter or loses their job/duty/allowlist entitlement.
        const interval = setInterval(async () => {
            if (!active || loading || saving) return;
            try {
                const access = await fetchNui<{success:boolean}>(
                    "canUsePublicRecordsOffice", {}, {success:false}
                );
                if (active && !access?.success) {
                    items = [];
                    selected = null;
                    onClose();
                }
            } catch {
                if (active) {
                    items = [];
                    selected = null;
                    onClose();
                }
            }
        }, 2500);
        return () => { active = false; clearInterval(interval); };
    });
</script>

<section class="office">
    <header>
        <div>
            <h2>Records Office</h2>
            <p>Agency requests · Authorized employees only</p>
        </div>
        <div class="actions">
            <button onclick={() => void reload()} disabled={loading || saving}>Refresh</button>
            <button onclick={onClose}>Close</button>
        </div>
    </header>

    {#if error}<p class="error" role="alert">{error}</p>{/if}
    {#if info}<p class="info" role="status">{info}</p>{/if}

    <div class="workspace">
        <div class="queue">
            <h3>Requests</h3>
            {#if loading}<p>Loading requests…</p>
            {:else if items.length === 0}<p>No available requests.</p>{/if}
            {#each items as item (item.id)}
                <button class:selected={selected?.id === item.id} onclick={() => choose(item)}>
                    <strong>{item.request_number || `Request #${item.id}`}</strong>
                    <span>{item.subject}</span>
                    <small>{item.agency} · {item.status}</small>
                </button>
            {/each}
        </div>

        <div class="detail">
            {#if selected}
                <h3>{selected.request_number || `Request #${selected.id}`}</h3>
                <p><strong>{selected.subject}</strong></p>
                <p class="description">{selected.description}</p>
                <p>Agency: {selected.agency} · Status: {selected.status}</p>
                <section class="history">
                    <h3>Decision history</h3>
                    {#if historyLoading}<p>Loading history…</p>
                    {:else if history.length === 0}<p>No recorded decisions.</p>
                    {:else}
                        {#each history as entry}
                            <p><strong>{entry.action}</strong> · {entry.actor_citizenid} · {entry.created_at}</p>
                            <p class="description">{entry.reason}</p>
                        {/each}
                    {/if}
                </section>
                {#if selected.status === "submitted" || selected.status === "under_review"}
                    <label for="records-decision">Decision</label>
                    <select id="records-decision" bind:value={action} disabled={saving}>
                        {#if selected.status === "submitted"}
                            <option value="under_review">Mark under review</option>
                        {:else}
                            <option value="denied">Deny request</option>
                            <option value="approved">Approve and publish public response</option>
                        {/if}
                    </select>
                    <label for="records-reason">
                        {action === "approved" ? "Public response to the citizen" : action === "denied" ? "Public denial explanation to the citizen" : "Reason for review (agency audit)"}
                    </label>
                    <textarea id="records-reason" bind:value={reason}
                        maxlength={action === "approved" ? 12000 : 1000}
                        rows="7" disabled={saving}
                        placeholder={action === "approved" ? "Write only information approved for public release." : action === "denied" ? "Explain the denial in language suitable for the citizen." : "Explain why this request is under review."}
                    ></textarea>
                    {#if action === "approved"}
                        <p class="warning">Only the text written here is released. Restricted case, IA, medical, report, and evidence data are never attached automatically.</p>
                    {/if}
                    <button class="primary" onclick={() => void submit()} disabled={saving || reason.trim().length === 0}>
                        {saving ? "Saving…" : "Save decision"}
                    </button>
                {:else}
                    <p>This request has already been decided. It cannot be edited here.</p>
                {/if}
            {:else}
                <p>Select a request to review it. Decisions are checked and audited by the server.</p>
            {/if}
        </div>
    </div>
</section>

<style>
    .office { position: absolute; inset: 0; z-index: 5; background: var(--dark-bg); color: inherit; overflow: auto; padding: 24px; box-sizing: border-box; }
    header, .actions { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
    h2 { font-size: 22px; margin: 0 0 4px; }
    h3 { margin: 0 0 12px; font-size: 16px; }
    p { font-size: 13px; opacity: .85; white-space: pre-wrap; }
    header p { margin: 0; }
    .workspace { display: grid; grid-template-columns: minmax(220px, 34%) minmax(0, 1fr); gap: 18px; margin-top: 20px; }
    .queue, .detail { border: 1px solid rgba(255,255,255,.14); border-radius: 8px; padding: 16px; min-width: 0; }
    .queue button { text-align: left; width: 100%; display: flex; flex-direction: column; gap: 5px; margin: 6px 0; }
    .queue button.selected { border-color: var(--primary-text); }
    small { opacity: .65; }
    button, select, textarea { background: rgba(255,255,255,.06); color: inherit; border: 1px solid rgba(255,255,255,.2); padding: 8px 12px; border-radius: 5px; font: inherit; }
    button { cursor: pointer; }
    button:disabled { opacity: .5; cursor: not-allowed; }
    .primary { margin-top: 12px; }
    label { display: block; margin-top: 14px; font-size: 13px; }
    select, textarea { box-sizing: border-box; margin-top: 5px; width: 100%; }
    option { color: #111; }
    .description { line-height: 1.5; overflow-wrap: anywhere; }
    .history { margin: 18px 0; padding: 12px; border: 1px solid rgba(255,255,255,.12); border-radius: 6px; }
    .error { color: #fca5a5; }
    .info { color: #86efac; }
    .warning { border-left: 2px solid #d9b76e; padding-left: 10px; }
    @media (max-width: 700px) { .workspace { grid-template-columns: 1fr; } }
</style>
