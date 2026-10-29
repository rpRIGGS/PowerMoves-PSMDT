<script lang="ts">
 import {onMount} from "svelte";
 import {fetchNui} from "../utils/fetchNui";
 import {NUI_EVENTS} from "../constants/nuiEvents";
 interface Item {id:number;title:string;type:string;serial?:string;notes?:string;case_id?:number;purpose?:string;created_at?:string;}
 interface Custody {id:number;action:string;from_citizenid?:string;to_citizenid?:string;notes?:string;created_at:string;}
 interface Grant {id:number;recipient_citizenid:string;recipient_job:string;purpose:string;revoked_at?:string|null;}
 let disclosed=$state<Item[]>([]);
 let detail=$state<{item:Item;custody:Custody[]}|null>(null);
 let grants=$state<Grant[]>([]);
 let evidenceId=$state("");
 let recipient=$state("");
 let purpose=$state("");
 let message=$state("");
 let busy=$state(false);
 async function reload(){
   try{
     const results=await fetchNui<Item[]>(NUI_EVENTS.EVIDENCE.GET_DISCLOSED_EVIDENCE,{},[]);
     disclosed=Array.isArray(results)?results:[];
   }catch{disclosed=[];}
 }
 async function view(id:number){
   const response=await fetchNui<{success:boolean;data?:{item:Item;custody:Custody[]}}>(
     NUI_EVENTS.EVIDENCE.GET_DISCLOSED_EVIDENCE_DETAIL,{evidenceId:id},{success:false});
   if(response.success && response.data)detail=response.data;
   else {detail=null;message="Evidence disclosure is unavailable or revoked.";}
 }
 async function loadGrants(){
   const id=Number(evidenceId);
   if(!id) return;
   const results=await fetchNui<Grant[]>(NUI_EVENTS.EVIDENCE.GET_EVIDENCE_DISCLOSURES,{evidenceId:id},[]);
   grants=Array.isArray(results)?results:[];
 }
 async function grant(){
   if(busy || !Number(evidenceId) || !recipient.trim() || purpose.trim().length<10)return;
   busy=true;
   try{
     const response=await fetchNui<{success:boolean;error?:string}>(NUI_EVENTS.EVIDENCE.GRANT_EVIDENCE_DISCLOSURE,
        {evidenceId:Number(evidenceId),recipientCitizenid:recipient.trim(),purpose:purpose.trim()},{success:false});
     message=response.success?"Evidence metadata disclosure recorded.":response.error||"Disclosure denied.";
     if(response.success){recipient="";purpose="";await loadGrants();}
   } finally {busy=false;}
 }
 async function revoke(id:number){
   if(busy)return;
   busy=true;
   try{
     const response=await fetchNui<{success:boolean;error?:string}>(NUI_EVENTS.EVIDENCE.REVOKE_EVIDENCE_DISCLOSURE,{grantId:id},{success:false});
     message=response.success?"Disclosure revoked.":response.error||"Revocation denied.";
     await loadGrants();
   } finally {busy=false;}
 }
 onMount(()=>{void reload();});
</script>
<section class="discovery">
 <h3>Controlled evidence discovery</h3>
 <p>Read-only metadata and custody history. Disclosures do not provide stash, inventory, transfer, or image-upload access.</p>
 <div class="split">
   <div>
     <h4>Shared with me</h4><button onclick={()=>void reload()}>Refresh</button>
     {#if disclosed.length===0}<p>No active evidence disclosures.</p>{/if}
     {#each disclosed as entry (entry.id)}
       <button class="row-button" onclick={()=>void view(entry.id)}>{entry.id} · {entry.title} ({entry.type})</button>
     {/each}
     {#if detail}
       <h4>{detail.item.title}</h4>
       <p>Type: {detail.item.type} · Serial: {detail.item.serial||"Not recorded"}</p>
       <p>{detail.item.notes||""}</p>
       <h4>Chain of custody</h4>
       {#each detail.custody as record (record.id)}
         <p>{record.action} — {record.created_at} · {record.notes||""}</p>
       {/each}
     {/if}
   </div>
   <div>
     <h4>Manage one evidence disclosure</h4>
     <form onsubmit={(event)=>{event.preventDefault();void grant();}}>
       <label>Evidence ID<input type="number" min="1" bind:value={evidenceId} required /></label>
       <label>Recipient citizen ID<input maxlength="64" bind:value={recipient} required /></label>
       <label>Purpose<input minlength="10" maxlength="255" bind:value={purpose} required /></label>
       <button disabled={busy} type="submit">Grant read-only discovery</button>
     </form>
     <button onclick={()=>void loadGrants()}>View existing grants</button>
     {#each grants as entry (entry.id)}
       <div class="grant"><span>{entry.recipient_citizenid} · {entry.recipient_job} — {entry.revoked_at?"Revoked":"Active"}</span>
       {#if !entry.revoked_at}<button disabled={busy} onclick={()=>void revoke(entry.id)}>Revoke</button>{/if}</div>
     {/each}
     {#if message}<p aria-live="polite">{message}</p>{/if}
   </div>
 </div>
</section>
<style>
.discovery{padding:12px 20px;border-bottom:1px solid rgba(128,128,128,.25)}
.split{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:18px}
p{font-size:12px;opacity:.75}
form,label{display:flex;flex-direction:column;gap:6px}
form{margin-bottom:8px}
input,button{border:1px solid rgba(128,128,128,.35);background:transparent;color:inherit;padding:7px;border-radius:4px}
button{cursor:pointer}
button:disabled{opacity:.4}
.row-button{display:block;width:100%;text-align:left;margin:4px 0}
.grant{display:flex;align-items:center;gap:8px;justify-content:space-between;margin:6px 0}
</style>
