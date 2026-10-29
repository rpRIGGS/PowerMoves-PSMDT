<script lang="ts">
    import {untrack} from "svelte";
    import {fetchNui} from "../utils/fetchNui";
    import type {AuthService} from "../services/authService.svelte";
    let {authService}: {authService:AuthService}=$props();

    interface Area {id:string;label:string;}
    interface Assessment {
        property_id:number;jurisdiction:string;property_type:string;
        assessed_value:number|null;government_owned:number|boolean;tax_exempt:number|boolean;
        status:string;version:number;reviewed_by_citizenid:string|null;
        decision_reason:string|null;street:string;region:string;for_sale:number|boolean;
    }
    interface Queue {success:boolean;error?:string;assessments?:Assessment[];
        jurisdictions?:Area[];page?:number;hasMore?:boolean;canAssess?:boolean;}
    interface Result {success:boolean;error?:string;}
    const types=["residential","commercial","agricultural","industrial"];
    let jurisdictions=$state<Area[]>([]);
    let assessments=$state<Assessment[]>([]);
    let selected=$state<Assessment|null>(null);
    let page=$state(0);
    let hasMore=$state(false);
    let canAssess=$state(false);
    let loading=$state(false);
    let saving=$state(false);
    let error=$state("");
    let message=$state("");
    let entryPropertyId=$state<number|undefined>();
    let entryJurisdiction=$state("");
    let entryType=$state("residential");
    let assessValue=$state<number|undefined>();
    let assessJurisdiction=$state("");
    let assessType=$state("residential");
    let governmentOwned=$state(false);
    let exempt=$state(false);
    let reason=$state("");
    let decision=$state("approved");
    let revision=0;

    function clear(){
        revision++;
        assessments=[];jurisdictions=[];selected=null;page=0;hasMore=false;
        canAssess=false;loading=false;saving=false;error="";message="";
    }
    async function load(){
        const token=++revision;
        loading=true;error="";
        try{
            const result=await fetchNui<Queue>("getGovernmentPropertyAssessments",{page},{success:false});
            if(token!==revision)return;
            if(!result?.success||!Array.isArray(result.assessments)
                ||!Array.isArray(result.jurisdictions)){
                error=result?.error||"Assessment queue unavailable";
                assessments=[];selected=null;canAssess=false;
                return;
            }
            assessments=result.assessments;
            jurisdictions=result.jurisdictions;
            canAssess=result.canAssess===true;
            hasMore=result.hasMore===true;
            if(!entryJurisdiction)entryJurisdiction=jurisdictions[0]?.id||"";
            if(selected)selected=assessments.find(a=>a.property_id===selected?.property_id)||null;
        }catch{
            if(token===revision)error="Unable to load property assessments";
        }finally{
            if(token===revision)loading=false;
        }
    }
    function choose(item:Assessment){
        selected=item;reason="";error="";message="";
        decision=item.status==="pending"?"approved":"reopen";
        assessValue=item.assessed_value===null?undefined:Number(item.assessed_value);
        assessJurisdiction=item.jurisdiction;assessType=item.property_type;
        governmentOwned=item.government_owned===true||item.government_owned===1;
        exempt=item.tax_exempt===true||item.tax_exempt===1;
    }
    async function createQueue(){
        if(!canAssess||saving||!entryPropertyId||!Number.isInteger(entryPropertyId)
            ||entryPropertyId<1||!entryJurisdiction||!types.includes(entryType))return;
        saving=true;error="";
        try{
            const response=await fetchNui<Result>("queueGovernmentPropertyAssessment",{
                propertyId:entryPropertyId,jurisdiction:entryJurisdiction,propertyType:entryType
            },{success:false});
            if(!response?.success){error=response?.error||"Property was not queued";return;}
            entryPropertyId=undefined;message="Property placed in state assessment queue.";
            page=0;await load();
        }catch{error="Unable to queue property";}
        finally{saving=false;}
    }
    async function submitDecision(){
        if(!selected||saving||!canAssess||!reason.trim())return;
        if(decision==="approved"&&(assessValue===undefined||!Number.isSafeInteger(assessValue)
            ||assessValue<0||assessValue>100000000000
            ||!jurisdictions.some(a=>a.id===assessJurisdiction)
            ||!types.includes(assessType)))return;
        const row=selected;
        saving=true;error="";
        try{
            const response=await fetchNui<Result>("decideGovernmentPropertyAssessment",{
                propertyId:row.property_id,version:row.version,action:decision,
                reason:reason.trim(),assessedValue:assessValue,
                jurisdiction:assessJurisdiction,propertyType:assessType,
                governmentOwned,taxExempt:exempt,
            },{success:false});
            if(!response?.success){error=response?.error||"Assessment decision not saved";return;}
            message="Assessment decision audited. PS Housing sale status was not changed.";
            selected=null;reason="";await load();
        }catch{error="Assessment decision not saved";}
        finally{saving=false;}
    }
    function nextPage(n:number){
        if(loading||saving||n<0||n>200||(n>page&&!hasMore))return;
        page=n;selected=null;void load();
    }
    $effect(()=>{
        authService.playerData?.citizenid;
        authService.agency;
        authService.jurisdiction;
        authService.playerData?.job?.grade?.level;
        authService.isAuthorized;
        untrack(()=>{clear();if(authService.isAuthorized&&authService.interfaceId==="sagov")void load();});
    });
</script>

<section class="assessor">
    <header>
        <div>
            <h2>State Tax Assessor’s Office</h2>
            <p>Assessment decisions and auditable property classifications.</p>
        </div>
        <button onclick={()=>void load()} disabled={loading||saving}>Refresh</button>
    </header>
    {#if error}<p class="error" role="alert">{error}</p>{/if}
    {#if message}<p class="success" role="status">{message}</p>{/if}
    {#if canAssess}
        <section class="new">
            <h3>Add existing PS Housing property for assessment</h3>
            <p>The property must already exist. This does not make it available for sale.</p>
            <div class="fields">
                <label>PS Housing property ID<input type="number" min="1" step="1" bind:value={entryPropertyId}/></label>
                <label>Taxable jurisdiction
                    <select bind:value={entryJurisdiction}>
                        {#each jurisdictions as area}<option value={area.id}>{area.label}</option>{/each}
                    </select>
                </label>
                <label>Property classification
                    <select bind:value={entryType}>
                        {#each types as item}<option value={item}>{item}</option>{/each}
                    </select>
                </label>
            </div>
            <button onclick={()=>void createQueue()} disabled={loading||saving||!entryPropertyId||!entryJurisdiction}>
                Queue property for assessment
            </button>
        </section>
    {/if}
    <div class="workspace">
        <section class="queue">
            <h3>Property assessments</h3>
            {#if loading}<p>Loading assessments…</p>{/if}
            {#each assessments as row (row.property_id)}
                <button class:selected={selected?.property_id===row.property_id} onclick={()=>choose(row)}>
                    <strong>Property #{row.property_id} · {row.street||"Unknown street"}</strong>
                    <span>{row.jurisdiction} · {row.status}</span>
                </button>
            {:else}
                {#if !loading}<p>No property assessments on this page.</p>{/if}
            {/each}
            <div class="pages">
                <button onclick={()=>nextPage(page-1)} disabled={loading||saving||page===0}>Previous</button>
                <span>Page {page+1}</span>
                <button onclick={()=>nextPage(page+1)} disabled={loading||saving||!hasMore}>Next</button>
            </div>
        </section>
        <section class="detail">
            {#if selected}
                <h3>Property #{selected.property_id}</h3>
                <p>{selected.street} · {selected.region}</p>
                <p>Assessment: {selected.status} · Version {selected.version}</p>
                <p>Existing listing for_sale: {String(selected.for_sale)} (PS Housing controlled)</p>
                <p>Assessed value: {selected.assessed_value??"Not set"}</p>
                <p>Tax exempt: {selected.tax_exempt===1||selected.tax_exempt===true?"Yes":"No"}</p>
                {#if selected.decision_reason}<p>Last decision: {selected.decision_reason}</p>{/if}
                {#if canAssess}
                    <label>Assessment action
                        <select bind:value={decision} disabled={saving}>
                            {#if selected.status==="pending"}
                                <option value="approved">Approve assessment</option>
                                <option value="rejected">Reject assessment</option>
                            {:else}
                                <option value="reopen">Reopen for reassessment</option>
                            {/if}
                        </select>
                    </label>
                    {#if decision==="approved"}
                        <div class="fields">
                            <label>Assessed value<input type="number" min="0" step="1" bind:value={assessValue} disabled={saving}/></label>
                            <label>Jurisdiction
                                <select bind:value={assessJurisdiction} disabled={saving}>
                                    {#each jurisdictions as area}<option value={area.id}>{area.label}</option>{/each}
                                </select>
                            </label>
                            <label>Classification
                                <select bind:value={assessType} disabled={saving}>
                                    {#each types as item}<option value={item}>{item}</option>{/each}
                                </select>
                            </label>
                            <label class="checkbox"><input type="checkbox" bind:checked={governmentOwned} disabled={saving}/>Government-owned</label>
                            <label class="checkbox"><input type="checkbox" bind:checked={exempt} disabled={saving}/>Tax exemption approved</label>
                        </div>
                        <p class="warning">Government ownership does not automatically imply tax exemption. Exemption must be explicitly approved.</p>
                    {/if}
                    <label>Decision reason<textarea maxlength="1000" rows="3" bind:value={reason} disabled={saving}></textarea></label>
                    <button onclick={()=>void submitDecision()} disabled={saving||!reason.trim()}>Save audited decision</button>
                {/if}
            {:else}<p>Choose a property. Assessor authorization is required to make decisions.</p>{/if}
        </section>
    </div>
</section>
<style>
    .assessor{padding:8px 0}
    header,.pages,.fields{display:flex;align-items:center;gap:12px;flex-wrap:wrap}
    header,.pages{justify-content:space-between}
    .new{padding:16px;border:1px solid var(--border-primary);border-radius:8px;margin-top:16px}
    .workspace{display:grid;grid-template-columns:minmax(220px,35%) minmax(0,1fr);gap:16px;margin-top:18px}
    .queue,.detail{border:1px solid var(--border-primary);padding:16px;border-radius:8px;min-width:0}
    .queue button{display:flex;flex-direction:column;align-items:start;gap:4px;width:100%;margin:6px 0}
    .queue button.selected{border-color:var(--primary-text)}
    .fields label{min-width:160px;flex:1}
    label{display:block;margin:12px 0;font-size:13px}
    .checkbox{display:flex;align-items:center;gap:8px}
    input,select,textarea,button{font:inherit;color:var(--primary-text);
        background:var(--card-dark-bg);border:1px solid var(--border-primary);
        border-radius:5px;padding:9px}
    .detail textarea,.detail select{width:100%;box-sizing:border-box}
    .checkbox input{width:auto}
    button{cursor:pointer}button:disabled{opacity:.5;cursor:not-allowed}
    p{white-space:pre-wrap;overflow-wrap:anywhere}
    .warning{border-left:2px solid #d9b76e;padding-left:10px}
    .error{color:#fca5a5}.success{color:#86efac}
    @media(max-width:700px){.workspace{grid-template-columns:1fr}}
</style>
