<script lang="ts">
 import {onMount} from "svelte";
 import {fetchNui} from "../utils/fetchNui";
 import {NUI_EVENTS} from "../constants/nuiEvents";
 let {onOpen}:{onOpen:(reportId:string)=>void}=$props();
 interface SharedReport {id:number;type:string;title:string;datecreated:string;purpose:string;granted_at:string;}
 let items=$state<SharedReport[]>([]);
 let loading=$state(false);
 async function reload(){
  if(loading)return;
  loading=true;
  try{
   const rows=await fetchNui<SharedReport[]>(NUI_EVENTS.REPORT.GET_DISCLOSED_REPORTS,{},[]);
   items=Array.isArray(rows)?rows:[];
  }catch{items=[];}finally{loading=false;}
 }
 onMount(()=>{void reload();});
</script>
<section class="disclosed-cases">
 <div class="heading"><strong>Shared with me — report discovery</strong><button disabled={loading} onclick={()=>void reload()}>Refresh</button></div>
 {#if items.length===0}<p>{loading?"Loading disclosed reports…":"No active report disclosures."}</p>{/if}
 {#each items as item (item.id)}
 <button class="case-row" onclick={()=>onOpen(String(item.id))}>
  <strong>{item.type} — {item.title}</strong>
  <span>Purpose: {item.purpose}</span>
 </button>
 {/each}
</section>
<style>
.disclosed-cases{padding:12px 18px;border-bottom:1px solid rgba(128,128,128,.24)}
.heading{display:flex;justify-content:space-between;align-items:center;gap:10px}
p,span{font-size:12px;opacity:.7}
button{background:transparent;color:inherit;border:1px solid rgba(128,128,128,.3);padding:7px 10px;border-radius:4px;cursor:pointer}
.case-row{width:100%;display:flex;flex-direction:column;align-items:flex-start;margin:6px 0;text-align:left;gap:4px}
button:disabled{opacity:.4}
</style>
