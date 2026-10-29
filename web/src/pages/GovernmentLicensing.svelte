<script lang="ts">
    import {onMount,untrack} from "svelte";
    import {fetchNui} from "../utils/fetchNui";
    import type {AuthService} from "../services/authService.svelte";
    let {authService}: {authService:AuthService}=$props();

    interface Authority {agency:string;jurisdiction:string;}
    interface Authorities {success:boolean;error?:string;authorities?:Authority[];agency?:string;}
    interface Application {
        id:number;agency:string;jurisdiction:string;owner_citizenid:string;
        business_name:string;business_type:string;description:string;
        property_reference:string|null;status:string;version:number;
        license_number:string|null;reviewer_citizenid:string|null;
        decision_reason:string|null;created_at:string;issued_at:string|null;
    }
    interface Queue {success:boolean;error?:string;applications?:Application[];
        hasMore?:boolean;page?:number;canReview?:boolean;canIssue?:boolean;agency?:string;}
    interface Result {success:boolean;error?:string;}
    let authorities=$state<Authority[]>([]);
    let chosenAgency=$state("");
    let applications=$state<Application[]>([]);
    let selected=$state<Application|null>(null);
    let page=$state(0);
    let hasMore=$state(false);
    let canReview=$state(false);
    let canIssue=$state(false);
    let loading=$state(false);
    let saving=$state(false);
    let error=$state("");
    let message=$state("");
    let decision=$state("under_review");
    let reason=$state("");
    let revision=0;

    function clear() {
        revision++;
        chosenAgency="";
        authorities=[];
        applications=[];
        selected=null;
        page=0;
        hasMore=false;
        canReview=false;
        canIssue=false;
        saving=false;
        loading=false;
        error="";
        message="";
    }
    async function initialize() {
        const token=++revision;
        loading=true;error="";
        try {
            const data=await fetchNui<Authorities>("getGovernmentBusinessLicenseAuthorities",{},
                {success:false});
            if (token!==revision) return;
            if (!data?.success || !Array.isArray(data.authorities)) {
                error=data?.error||"Licensing access unavailable";
                return;
            }
            authorities=data.authorities;
            chosenAgency=authorities.find(item=>item.agency===data.agency)?.agency
                ||authorities[0]?.agency||"";
            if (chosenAgency) await load();
        } catch {
            if(token===revision) error="Unable to access licensing department";
        } finally {
            if(token===revision) loading=false;
        }
    }
    async function load() {
        if (!chosenAgency) return;
        const token=++revision;
        loading=true;error="";
        try {
            const data=await fetchNui<Queue>("getGovernmentBusinessLicenses",
                {agency:chosenAgency,page},{success:false});
            if(token!==revision) return;
            if (!data?.success || !Array.isArray(data.applications)) {
                applications=[]; selected=null;
                error=data?.error||"Licensing queue unavailable";
                return;
            }
            applications=data.applications;
            hasMore=data.hasMore===true;
            canReview=data.canReview===true;
            canIssue=data.canIssue===true;
            selected=selected ? applications.find(row=>row.id===selected?.id)||null : null;
        } catch {
            if(token===revision) {error="Unable to load license applications";applications=[];}
        } finally {
            if(token===revision) loading=false;
        }
    }
    function select(item:Application) {
        selected=item;
        reason="";
        message="";
        decision=item.status==="submitted"?"under_review":
                 item.status==="under_review"?"denied":
                 item.status==="approved"?"suspended":"revoked";
    }
    function pageChange(next:number) {
        if(loading||saving||next<0||next>200||(next>page&&!hasMore))return;
        page=next;selected=null;void load();
    }
    function agencyChange(event:Event) {
        const value=(event.currentTarget as HTMLSelectElement).value;
        if(!authorities.some(item=>item.agency===value))return;
        chosenAgency=value;page=0;selected=null;void load();
    }
    async function submit() {
        if(!selected||saving||!reason.trim())return;
        const item=selected;
        const allowed=(item.status==="submitted"&&decision==="under_review"&&canReview)
          ||(item.status==="under_review"&&((decision==="denied"&&canReview)
              ||(decision==="approved"&&canIssue)))
          ||(item.status==="approved"&&decision==="suspended"&&canIssue)
          ||(item.status==="suspended"&&decision==="revoked"&&canIssue);
        if(!allowed)return;
        saving=true;error="";message="";
        try {
            const result=await fetchNui<Result>("decideGovernmentBusinessLicense",
                {id:item.id,version:item.version,action:decision,reason:reason.trim()},
                {success:false});
            if(!result?.success){error=result?.error||"Decision not saved";return;}
            selected=null;reason="";
            message="Licensing decision recorded. Other business and property systems were not changed.";
            await load();
        } catch {error="Unable to save licensing decision.";}
        finally {saving=false;}
    }
    onMount(()=>{void initialize();});
    $effect(()=>{
        authService.playerData?.citizenid;
        authService.agency;
        authService.jurisdiction;
        authService.playerData?.job?.grade?.level;
        authService.isAuthorized;
        untrack(()=>{clear();if(authService.isAuthorized&&authService.interfaceId==="sagov")void initialize();});
    });
</script>
<section class="licensing">
    <header>
        <div><h2>Local Business Licensing</h2>
            <p>Applications and government decisions. No automatic business creation or tax charge.</p></div>
        <button onclick={()=>void load()} disabled={loading||saving||!chosenAgency}>Refresh</button>
    </header>
    {#if error}<p role="alert" class="error">{error}</p>{/if}
    {#if message}<p role="status" class="success">{message}</p>{/if}
    {#if authorities.length>0}
        <label for="licensing-authority">Receiving licensing office</label>
        <select id="licensing-authority" value={chosenAgency} onchange={agencyChange} disabled={loading||saving}>
            {#each authorities as entry}<option value={entry.agency}>{entry.agency} · {entry.jurisdiction}</option>{/each}
        </select>
        <div class="workspace">
            <section class="queue">
                <h3>Applications</h3>
                {#if loading}<p>Loading…</p>{/if}
                {#each applications as entry (entry.id)}
                    <button class:selected={selected?.id===entry.id} onclick={()=>select(entry)}>
                        <strong>{entry.business_name}</strong>
                        <span>#{entry.id} · {entry.status} · {entry.agency}</span>
                    </button>
                {:else}<p>No applications on this page.</p>{/each}
                <div class="pagination">
                    <button onclick={()=>pageChange(page-1)} disabled={loading||saving||page===0}>Previous</button>
                    <span>Page {page+1}</span>
                    <button onclick={()=>pageChange(page+1)} disabled={loading||saving||!hasMore}>Next</button>
                </div>
            </section>
            <section class="detail">
                {#if selected}
                    <h3>{selected.business_name}</h3>
                    <p><strong>Applicant:</strong> {selected.owner_citizenid}</p>
                    <p><strong>Jurisdiction:</strong> {selected.jurisdiction}</p>
                    <p><strong>Business type:</strong> {selected.business_type}</p>
                    <p><strong>Proposal:</strong> {selected.description}</p>
                    <p><strong>Property reference (unverified):</strong> {selected.property_reference||"None supplied"}</p>
                    <p><strong>Status:</strong> {selected.status}</p>
                    <p><strong>License:</strong> {selected.license_number||"Not issued"}</p>
                    {#if selected.decision_reason}<p><strong>Previous decision:</strong> {selected.decision_reason}</p>{/if}
                    {#if (selected.status==="submitted"&&canReview)
                      ||(selected.status==="under_review"&&(canReview||canIssue))
                      ||(selected.status==="approved"&&canIssue)
                      ||(selected.status==="suspended"&&canIssue)}
                        <label for="license-action">Decision</label>
                        <select id="license-action" bind:value={decision} disabled={saving}>
                            {#if selected.status==="submitted"&&canReview}
                                <option value="under_review">Begin review</option>
                            {:else if selected.status==="under_review"}
                                {#if canReview}<option value="denied">Deny</option>{/if}
                                {#if canIssue}<option value="approved">Issue local license</option>{/if}
                            {:else if selected.status==="approved"&&canIssue}
                                <option value="suspended">Suspend</option>
                            {:else if selected.status==="suspended"&&canIssue}
                                <option value="revoked">Revoke</option>
                            {/if}
                        </select>
                        <label for="license-reason">Decision reason (audited)</label>
                        <textarea id="license-reason" rows="5" maxlength="1000"
                            bind:value={reason} disabled={saving}></textarea>
                        <button onclick={()=>void submit()} disabled={saving||!reason.trim()}>
                            {saving?"Saving…":"Save licensing decision"}
                        </button>
                    {:else}
                        <p>This request has no permitted decision for your role.</p>
                    {/if}
                {:else}
                    <p>Select a business application to review it. State oversight is read-only.</p>
                {/if}
            </section>
        </div>
    {:else if !loading}
        <p>You have no authorized local licensing offices.</p>
    {/if}
</section>
<style>
    .licensing{padding:8px 0}.licensing header{display:flex;align-items:center;justify-content:space-between;gap:12px}
    .workspace{display:grid;grid-template-columns:minmax(220px,35%) minmax(0,1fr);gap:16px;margin-top:20px}
    .queue,.detail{padding:16px;border:1px solid var(--border-primary);border-radius:8px;min-width:0}
    .queue button{display:flex;flex-direction:column;align-items:start;gap:5px;width:100%;margin:7px 0}
    .queue button.selected{border-color:var(--primary-text)}
    .pagination{display:flex;justify-content:space-between;align-items:center;gap:8px;margin-top:14px}
    input,select,textarea,button{font:inherit;color:var(--primary-text);background:var(--card-dark-bg);
        border:1px solid var(--border-primary);padding:9px;border-radius:5px}
    textarea{width:100%;box-sizing:border-box}
    label{display:block;margin:14px 0 6px}
    p{white-space:pre-wrap;overflow-wrap:anywhere;line-height:1.5}
    button{cursor:pointer}button:disabled{cursor:not-allowed;opacity:.5}
    .error{color:#fca5a5}.success{color:#86efac}
    @media(max-width:700px){.workspace{grid-template-columns:1fr}}
</style>
