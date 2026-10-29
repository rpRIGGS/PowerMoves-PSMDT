<script lang="ts">
import {untrack} from "svelte";
import {fetchNui} from "../utils/fetchNui";
import type {AuthService} from "../services/authService.svelte";
let {authService}:{authService:AuthService}=$props();
interface Budget{id:number;agency:string;jurisdiction:string;department:string;
fiscal_year:number;revenue_estimate:number;expense_limit:number;notes:string;
status:string;version:number;approved_at:string|null}
interface Authority {job:string;jurisdiction:string}
interface Listing {success:boolean;error?:string;budgets?:Budget[];
authorities?:Authority[];agency?:string;hasMore?:boolean;canDraft?:boolean;canApprove?:boolean}
interface Result{success:boolean;error?:string}
let budgets=$state<Budget[]>([]);
let authorities=$state<Authority[]>([]);
let agency=$state("");
let selected=$state<Budget|null>(null);
let page=$state(0);
let hasMore=$state(false);
let canDraft=$state(false);
let canApprove=$state(false);
let loading=$state(false);
let saving=$state(false);
let error=$state("");
let info=$state("");
let department=$state("");
let fiscalYear=$state(new Date().getFullYear());
let revenue=$state(0);
let expense=$state(0);
let notes=$state("");
let reason=$state("");
let revision=0;
async function load(target?:string){
  const token=++revision;
  loading=true;error="";
  try{
    const answer=await fetchNui<Listing>("getGovernmentBudgets",
       {page,agency:target||agency||undefined},{success:false});
    if(token!==revision)return;
    if(!answer?.success || !Array.isArray(answer.budgets)){
      budgets=[];selected=null;canDraft=false;canApprove=false;
      error=answer?.error||"Budget access denied";return;
    }
    budgets=answer.budgets;
    authorities=Array.isArray(answer.authorities)?answer.authorities:[];
    agency=answer.agency||"";
    hasMore=answer.hasMore===true;
    canDraft=answer.canDraft===true;
    canApprove=answer.canApprove===true;
    if(selected)selected=budgets.find(x=>x.id===selected?.id)??null;
  }catch{if(token===revision){error="Budget office unavailable";budgets=[];}}
  finally{if(token===revision)loading=false;}
}
async function createBudget(){
  if(!canDraft||saving||!department.trim()||!notes.trim()
    ||!Number.isSafeInteger(fiscalYear)||fiscalYear<2020||fiscalYear>2100
    ||!Number.isSafeInteger(revenue)||revenue<0||revenue>1000000000000
    ||!Number.isSafeInteger(expense)||expense<0||expense>1000000000000)return;
  saving=true;error="";
  try{
    const result=await fetchNui<Result>("createGovernmentBudget",
      {department:department.trim(),fiscalYear,revenueEstimate:revenue,
       expenseLimit:expense,notes:notes.trim()},{success:false});
    if(!result?.success){error=result?.error||"Budget not saved";return;}
    department="";notes="";revenue=0;expense=0;info="Annual budget draft created.";
    page=0;await load();
  }catch{error="Budget draft failed";}
  finally{saving=false;}
}
async function approve(){
  if(!canApprove||!selected||selected.status!=="draft"||saving||!reason.trim())return;
  const item=selected;
  saving=true;error="";
  try{
    const result=await fetchNui<Result>("approveGovernmentBudget",
      {id:item.id,version:item.version,reason:reason.trim()},{success:false});
    if(!result?.success){error=result?.error||"Budget not adopted";return;}
    selected=null;reason="";info="Budget adopted and audited.";await load();
  }catch{error="Budget adoption failed";}
  finally{saving=false;}
}
function changePage(next:number){
  if(next<0||next>200||(next>page&&!hasMore)||loading||saving)return;
  page=next;selected=null;void load();
}
$effect(()=>{
  authService.playerData?.citizenid;authService.agency;authService.jurisdiction;
  authService.playerData?.job?.grade?.level;authService.isAuthorized;
  untrack(()=>{revision++;budgets=[];selected=null;authorities=[];agency="";page=0;
    canApprove=false;canDraft=false;
    if(authService.isAuthorized&&authService.interfaceId==="sagov")void load();});
});
</script>
<section class="budgets">
<header><div><h2>Government Budgets</h2>
<p>Annual jurisdiction and department operating proposals. No direct payment or taxation.</p></div>
<button onclick={()=>void load()} disabled={loading||saving}>Refresh</button></header>
{#if error}<p role="alert" class="error">{error}</p>{/if}
{#if info}<p role="status" class="success">{info}</p>{/if}
{#if authorities.length>1}<label>Government authority
<select value={agency} disabled={loading||saving} onchange={event=>{page=0;selected=null;void load((event.currentTarget as HTMLSelectElement).value);}}>
{#each authorities as authority}<option value={authority.job}>{authority.job} · {authority.jurisdiction}</option>{/each}
</select></label>{/if}
{#if canDraft}
<section class="draft"><h3>Draft annual department budget — {agency}</h3>
<div class="fields">
<label>Department<input bind:value={department} maxlength="100"/></label>
<label>Fiscal year<input type="number" bind:value={fiscalYear} min="2020" max="2100" step="1"/></label>
<label>Estimated revenue<input type="number" bind:value={revenue} min="0" step="1"/></label>
<label>Spending ceiling<input type="number" bind:value={expense} min="0" step="1"/></label>
</div>
<label>Budget rationale<textarea bind:value={notes} rows="3" maxlength="6000"></textarea></label>
<button onclick={()=>void createBudget()} disabled={saving||!department.trim()||!notes.trim()}>Save draft</button>
</section>{/if}
<div class="workspace">
<section class="queue"><h3>Annual budget records</h3>
{#if loading}<p>Loading…</p>{/if}
{#each budgets as item(item.id)}
<button class:selected={selected?.id===item.id} onclick={()=>{selected=item;reason="";}}>
<strong>{item.department} · {item.fiscal_year}</strong>
<span>{item.agency} · {item.status}</span>
</button>
{:else}{#if !loading}<p>No budgets for this authority.</p>{/if}{/each}
<div class="pages">
<button onclick={()=>changePage(page-1)} disabled={page===0||loading||saving}>Previous</button>
<span>Page {page+1}</span>
<button onclick={()=>changePage(page+1)} disabled={!hasMore||loading||saving}>Next</button>
</div></section>
<section class="detail">
{#if selected}
<h3>{selected.department} · FY {selected.fiscal_year}</h3>
<p>{selected.jurisdiction} · {selected.status}</p>
<p>Revenue estimate: {Number(selected.revenue_estimate).toLocaleString()}</p>
<p>Expense limit: {Number(selected.expense_limit).toLocaleString()}</p>
<p class="body">{selected.notes}</p>
{#if selected.status==="draft"&&canApprove}
<label>Approval justification<textarea bind:value={reason} rows="3" maxlength="1000"></textarea></label>
<button onclick={()=>void approve()} disabled={saving||!reason.trim()}>Adopt this budget</button>
{/if}
{:else}<p>Select an annual budget.</p>{/if}
</section>
</div>
</section>
<style>
.budgets{padding:8px 0}.budgets h2,.budgets h3{margin:0 0 12px}
.budgets p{white-space:pre-wrap;margin:10px 0;line-height:1.5}
.budgets header,.budgets .pages,.budgets .fields{display:flex;gap:12px;align-items:center;flex-wrap:wrap}
.budgets header,.budgets .pages{justify-content:space-between}
.budgets .workspace{display:grid;grid-template-columns:minmax(220px,35%) minmax(0,1fr);gap:16px;margin-top:16px}
.budgets .queue,.budgets .detail,.budgets .draft{border:1px solid var(--border-primary);padding:16px;border-radius:8px;min-width:0}
.budgets .draft{margin-top:18px}
.budgets .queue>button{display:flex;flex-direction:column;gap:5px;width:100%;text-align:left;margin:5px 0}
.budgets .queue>button.selected{border-color:var(--primary-text)}
.budgets label{display:grid;gap:6px;margin:10px 0}
.budgets input,.budgets textarea,.budgets select,.budgets button{font:inherit;color:var(--primary-text);background:var(--card-dark-bg);border:1px solid var(--border-primary);padding:9px;border-radius:5px}
.budgets input,.budgets textarea,.budgets select{max-width:100%;box-sizing:border-box}
.budgets button{cursor:pointer}.budgets button:disabled{opacity:.5}
.budgets .error{color:#fca5a5}.budgets .success{color:#86efac}
.budgets .body{white-space:pre-wrap}
@media(max-width:700px){.budgets .workspace{grid-template-columns:1fr}}
</style>
