<script lang="ts">
    import { onMount, untrack } from "svelte";
    import { fetchNui } from "../utils/fetchNui";
    import type { AuthService } from "../services/authService.svelte";
    let { authService }: { authService: AuthService } = $props();

    interface Notice {
        id: number;
        agency: string;
        jurisdiction: string;
        title: string;
        body: string;
        status: "draft" | "published";
        version: number;
        created_by_citizenid: string;
        published_by_citizenid?: string | null;
        updated_at: string;
    }
    interface NoticeList {
        success: boolean;
        error?: string;
        notices?: Notice[];
        page?: number;
        hasMore?: boolean;
        agency?: string;
        jurisdiction?: string;
        canManage?: boolean;
        canPublish?: boolean;
    }
    interface NoticeAction { success: boolean; error?: string; }

    let page = $state(0);
    let hasMore = $state(false);
    let notices = $state<Notice[]>([]);
    let agency = $state("");
    let jurisdiction = $state("");
    let canManage = $state(false);
    let canPublish = $state(false);
    let loading = $state(false);
    let saving = $state(false);
    let error = $state("");
    let message = $state("");
    let selected = $state<Notice | null>(null);
    let creating = $state(false);
    let title = $state("");
    let body = $state("");
    let revision = 0;

    function clear() {
        revision++;
        notices = [];
        selected = null;
        canManage = false;
        canPublish = false;
        agency = "";
        jurisdiction = "";
        hasMore = false;
        page = 0;
        creating = false;
        title = "";
        body = "";
    }

    async function load() {
        const token = ++revision;
        loading = true;
        error = "";
        try {
            const result = await fetchNui<NoticeList>("getGovernmentNotices", {page}, {success:false});
            if (token !== revision) return;
            if (!result?.success || !Array.isArray(result.notices)) {
                notices = [];
                selected = null;
                canManage = false;
                canPublish = false;
                error = result?.error || "Notices unavailable.";
                return;
            }
            notices = result.notices;
            hasMore = result.hasMore === true;
            agency = result.agency || "";
            jurisdiction = result.jurisdiction || "";
            canManage = result.canManage === true;
            canPublish = result.canPublish === true;
            if (selected) selected = notices.find(item => item.id === selected?.id) ?? null;
        } catch {
            if (token === revision) { error = "Unable to load government notices."; notices = []; }
        } finally {
            if (token === revision) loading = false;
        }
    }

    function select(item: Notice) {
        creating = false;
        selected = item;
        title = item.title;
        body = item.body;
        message = "";
        error = "";
    }
    function newDraft() {
        if (!canManage) return;
        selected = null;
        creating = true;
        title = "";
        body = "";
        error = "";
        message = "";
    }
    function switchPage(next: number) {
        if (loading || saving || next < 0 || next > 200 || (next > page && !hasMore)) return;
        page = next;
        selected = null;
        creating = false;
        void load();
    }

    async function saveDraft() {
        if (!canManage || saving || !title.trim() || !body.trim()) return;
        if (selected && (selected.status !== "draft" || selected.agency !== agency)) return;
        saving = true;
        error = "";
        try {
            const editing = selected !== null && !creating;
            const response = await fetchNui<NoticeAction>(
                editing ? "editGovernmentNotice" : "createGovernmentNotice",
                editing
                    ? {id:selected!.id, version:selected!.version, title:title.trim(), body:body.trim()}
                    : {title:title.trim(), body:body.trim()},
                {success:false}
            );
            if (!response?.success) { error = response?.error || "Draft not saved."; return; }
            message = editing ? "Draft updated." : "Government draft created.";
            creating = false;
            selected = null;
            page = 0;
            await load();
        } catch {
            error = "Draft could not be saved.";
        } finally { saving = false; }
    }

    async function publish() {
        if (!selected || selected.status !== "draft" || selected.agency !== agency
            || !canPublish || saving) return;
        const item = selected;
        saving = true;
        error = "";
        try {
            const response = await fetchNui<NoticeAction>(
                "publishGovernmentNotice", {id:item.id,version:item.version}, {success:false}
            );
            if (!response?.success) { error = response?.error || "Publication denied."; return; }
            selected = null;
            message = "Notice published. This is not enactment of a law.";
            await load();
        } catch {
            error = "Notice was not published.";
        } finally { saving = false; }
    }

    onMount(() => { void load(); });
    $effect(() => {
        authService.playerData?.citizenid;
        authService.agency;
        authService.jurisdiction;
        authService.playerData?.job?.grade?.level;
        authService.isAuthorized;
        untrack(() => {
            clear();
            if (authService.isAuthorized && authService.interfaceId === "sagov") void load();
        });
    });
</script>

<section class="notices">
    <header>
        <div>
            <h2>Government Public Notices</h2>
            <p>Jurisdiction-owned notices, not ordinances, statutes or election results.</p>
            {#if agency}<p>Your department: {agency} · {jurisdiction}</p>{/if}
        </div>
        <div class="actions">
            <button onclick={() => void load()} disabled={loading || saving}>Refresh</button>
            {#if canManage}<button onclick={newDraft} disabled={loading || saving}>New draft</button>{/if}
        </div>
    </header>
    {#if error}<p class="error" role="alert">{error}</p>{/if}
    {#if message}<p class="success" role="status">{message}</p>{/if}
    <div class="workspace">
        <div class="notice-list">
            <h3>Department drafts and published notices</h3>
            {#if loading}<p>Loading…</p>
            {:else if notices.length === 0}<p>No available notices.</p>{/if}
            {#each notices as item (item.id)}
                <button class:selected={selected?.id === item.id} onclick={() => select(item)}>
                    <strong>{item.title}</strong>
                    <span>{item.agency} · {item.jurisdiction} · {item.status}</span>
                </button>
            {/each}
            <div class="pagination">
                <button onclick={() => switchPage(page - 1)} disabled={loading || saving || page === 0}>Previous</button>
                <span>Page {page + 1}</span>
                <button onclick={() => switchPage(page + 1)} disabled={loading || saving || !hasMore}>Next</button>
            </div>
        </div>
        <div class="notice-detail">
            {#if creating || selected}
                <h3>{creating ? "New notice draft" : selected?.title}</h3>
                <p>{creating ? "This draft belongs to your current government department." : selected?.jurisdiction + " · " + selected?.status}</p>
                {#if creating || (selected?.status === "draft" && selected?.agency === agency && canManage)}
                    <label for="notice-title">Title</label>
                    <input id="notice-title" maxlength="160" bind:value={title} disabled={saving} />
                    <label for="notice-body">Content</label>
                    <textarea id="notice-body" rows="10" maxlength="6000" bind:value={body} disabled={saving}></textarea>
                    <button class="primary" onclick={() => void saveDraft()} disabled={saving || !title.trim() || !body.trim()}>
                        {saving ? "Saving…" : "Save draft"}
                    </button>
                {:else}
                    <p class="notice-body">{selected?.body}</p>
                {/if}
                {#if selected?.status === "draft" && selected?.agency === agency && canPublish}
                    <p class="warning">Publishing makes this notice visible to other jurisdictions. It does not enact legislation.</p>
                    <button class="primary" onclick={() => void publish()} disabled={saving}>Publish this notice</button>
                {/if}
            {:else}
                <p>Select a notice, or start a draft if your role is authorized.</p>
            {/if}
        </div>
    </div>
</section>
<style>
    .notices { padding: 8px 0; }
    header,.actions,.pagination { display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap; }
    .workspace { display:grid;grid-template-columns:minmax(220px,35%) minmax(0,1fr);gap:16px;margin-top:20px; }
    .notice-list,.notice-detail { padding:16px;border:1px solid var(--border-primary);border-radius:8px;min-width:0; }
    .notice-list button { display:flex;flex-direction:column;gap:5px;text-align:left;width:100%;margin-bottom:8px; }
    .notice-list button.selected { border-color:var(--primary-text); }
    .pagination button { width:auto; }
    h2,h3 { margin:0 0 12px; }
    p { margin:8px 0;line-height:1.5;white-space:pre-wrap;overflow-wrap:anywhere; }
    label { display:block;margin-top:12px; }
    input,textarea,button { font:inherit;color:var(--primary-text);background:var(--card-dark-bg);border:1px solid var(--border-primary);border-radius:5px;padding:10px 12px; }
    input,textarea { width:100%;box-sizing:border-box;margin-top:6px; }
    button { cursor:pointer; }
    button:disabled { opacity:.5;cursor:not-allowed; }
    .notice-body { white-space:pre-wrap; }
    .error { color:#fca5a5; } .success { color:#86efac; }
    .warning { border-left:2px solid #d9b76e;padding-left:10px; }
    @media(max-width:700px) { .workspace { grid-template-columns:1fr; } }
</style>
