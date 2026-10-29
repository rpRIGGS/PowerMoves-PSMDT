<script lang="ts">
    import { onMount, untrack } from "svelte";
    import { fetchNui } from "../utils/fetchNui";
    import type { AuthService } from "../services/authService.svelte";
    let { authService }: { authService: AuthService } = $props();

    interface Application {
        id:number;
        applicant_citizenid:string;
        agency:string;
        jurisdiction:string;
        license_type:string;
        business_name:string;
        description:string;
        status:string;
        decision_reason:string|null;
        expires_at:string|null;
        created_at:string;
    }
    interface Queue {
        success:boolean;
        error?:string;
        applications?:Application[];
        agency?:string;
        hasMore?:boolean;
        canApprove?:boolean;
        canRevoke?:boolean;
    }
    interface Decision {success:boolean; error?:string;}
    let items=$state<Application[]>([]);
    let selected=$state<Application|null>(null);
    let page=$state(0);
    let hasMore=$state(false);
    let agency=$state("");
    let canApprove=$state(false);
    let canRevoke=$state(false);
    let loading=$state(false);
    let saving=$state(false);
    let reason=$state("");
    let action=$state<"under_review"|"approved"|"denied"|"revoked">("under_review");
    let error=$state("");
    let message=$state("");
    let requestRevision=0;

    async function refresh() {
        const revision=++requestRevision;
        loading=true;
        error="";
        try {
            const response=await fetchNui<Queue>("getGovernmentLicenseQueue",{page},{success:false});
            if (revision!==requestRevision) return;
            if (!response?.success || !Array.isArray(response.applications)) {
                items=[];selected=null;canApprove=false;canRevoke=false;hasMore=false;
                error=response?.error||"Licensing review is restricted to authorized staff.";
                return;
            }
            items=response.applications;
            agency=response.agency||"";
            canApprove=response.canApprove===true;
            canRevoke=response.canRevoke===true;
            hasMore=response.hasMore===true;
            if (selected) selected=items.find(item=>item.id===selected?.id)??null;
        } catch {
            if (revision===requestRevision) {items=[];selected=null;error="Licensing queue unavailable.";}
        } finally {
            if (revision===requestRevision) loading=false;
        }
    }
    function select(item:Application) {
        selected=item;reason="";error="";message="";
        action=item.status==="submitted"?"under_review":item.status==="approved"?"revoked":"denied";
    }
    function nextPage(next:number) {
        if (loading || saving || next<0 || next>200 || (next>page&&!hasMore)) return;
        page=next;selected=null;void refresh();
    }
    async function decide() {
        if (!selected || !reason.trim() || saving) return;
        if (action==="approved"&&!canApprove || action==="revoked"&&!canRevoke) return;
        if (selected.status==="submitted"&&action!=="under_review") return;
        if (selected.status==="under_review"&&action!=="approved"&&action!=="denied") return;
        if (selected.status==="approved"&&action!=="revoked") return;
        saving=true;error="";
        try {
            const result=await fetchNui<Decision>("decideGovernmentLicense",{
                id:selected.id,action,reason:reason.trim()
            },{success:false});
            if (!result?.success) {error=result?.error||"Decision was not saved.";return;}
            message="Decision saved and audited.";
            selected=null;reason="";
            await refresh();
        } catch {
            error="Licensing decision could not be saved.";
        } finally {saving=false;}
    }
    onMount(()=>{void refresh();});
    $effect(()=>{
        authService.playerData?.citizenid;
        authService.playerData?.job?.grade?.level;
        authService.agency;
        authService.jurisdiction;
        authService.isAuthorized;
        untrack(()=>{
            requestRevision++;items=[];selected=null;agency="";canApprove=false;canRevoke=false;
            if(authService.isAuthorized&&authService.interfaceId==="sagov")void refresh();
        });
    });
</script>
<section class="licenses">
    <header><div>
        <h2>Government Licensing</h2>
        <p>Business registrations and vending permits · actual employing agency only</p>
        {#if agency}<p>Reviewing authority: {agency}</p>{/if}
    </div><button onclick={()=>void refresh()} disabled={saving||loading}>Refresh queue</button></header>
    {#if error}<p class="error" role="alert">{error}</p>{/if}
    {#if message}<p class="success" role="status">{message}</p>{/if}
    <div class="workspace">
        <section class="queue">
            <h3>Applications</h3>
            {#if loading}<p>Loading…</p>
            {:else if items.length===0}<p>No accessible applications.</p>{/if}
            {#each items as item(item.id)}
                <button class:selected={selected?.id===item.id} onclick={()=>select(item)}>
                    <strong>#{item.id} · {item.business_name}</strong>
                    <span>{item.license_type} · {item.status} · {item.jurisdiction}</span>
                </button>
            {/each}
            <div class="pages">
                <button onclick={()=>nextPage(page-1)} disabled={loading||saving||page===0}>Previous</button>
                <span>Page {page+1}</span>
                <button onclick={()=>nextPage(page+1)} disabled={loading||saving||!hasMore}>Next</button>
            </div>
        </section>
        <section class="details">
            {#if selected}
                <h3>{selected.business_name}</h3>
                <p>Application #{selected.id} · {selected.license_type} · {selected.status}</p>
                <p>Applicant ID: {selected.applicant_citizenid}</p>
                <p>Jurisdiction: {selected.jurisdiction}</p>
                <p class="description">{selected.description}</p>
                {#if selected.expires_at}<p>Expiration: {selected.expires_at}</p>{/if}
                {#if selected.decision_reason}<p>Last decision: {selected.decision_reason}</p>{/if}
                {#if selected.status==="submitted"||selected.status==="under_review"||selected.status==="approved"}
                    {#if selected.status==="submitted"}
                        <p>Begin review before deciding.</p>
                    {:else if selected.status==="approved" && !canRevoke}
                        <p>Revocation requires an explicit licensing revocation permission.</p>
                    {/if}
                    <label for="license-decision">Action</label>
                    <select id="license-decision" bind:value={action} disabled={saving}>
                        {#if selected.status==="submitted"}<option value="under_review">Take under review</option>
                        {:else if selected.status==="under_review"}
                            <option value="denied">Deny</option>
                            {#if canApprove}<option value="approved">Approve for one year</option>{/if}
                        {:else if selected.status==="approved"&&canRevoke}
                            <option value="revoked">Revoke license</option>
                        {/if}
                    </select>
                    <label for="license-reason">Audited reason / applicant decision notice</label>
                    <textarea id="license-reason" rows="5" maxlength="1000" bind:value={reason} disabled={saving}></textarea>
                    <button onclick={()=>void decide()} disabled={saving||!reason.trim()
                        ||(action==="approved"&&!canApprove)||(action==="revoked"&&!canRevoke)}>
                        {saving?"Saving…":"Save decision"}
                    </button>
                {/if}
            {:else}<p>Select an application to review its jurisdiction and details.</p>{/if}
        </section>
    </div>
</section>
<style>
    .licenses{padding:8px 0}
    header,.pages{display:flex;gap:14px;justify-content:space-between;align-items:center;flex-wrap:wrap}
    .workspace{display:grid;grid-template-columns:minmax(230px,35%) minmax(0,1fr);gap:16px;margin-top:16px}
    .queue,.details{border:1px solid var(--border-primary);border-radius:8px;padding:16px;min-width:0}
    .queue>button{width:100%;text-align:left;display:flex;flex-direction:column;gap:6px;margin:6px 0}
    .queue>button.selected{border-color:var(--primary-text)}
    h2,h3{margin:0 0 12px}
    p{margin:8px 0;line-height:1.5;overflow-wrap:anywhere;white-space:pre-wrap}
    label{display:block;margin-top:14px;font-size:13px}
    select,textarea,button{font:inherit;color:var(--primary-text);background:var(--card-dark-bg);border:1px solid var(--border-primary);border-radius:5px;padding:9px}
    select,textarea{width:100%;box-sizing:border-box;margin-top:6px}
    button{cursor:pointer}button:disabled{opacity:.5;cursor:not-allowed}
    .error{color:#fca5a5}.success{color:#86efac}.description{white-space:pre-wrap}
    @media(max-width:700px){.workspace{grid-template-columns:1fr}}
</style>
