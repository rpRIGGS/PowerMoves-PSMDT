<script lang="ts">
    import { onMount } from "svelte";
    import { fetchNui } from "../utils/fetchNui";
    interface Grant { id:number; recipient_citizenid:string; purpose:string; granted_at:string; revoked_at?:string|null; expires_at?:string|null; }
    let { caseId }: { caseId: number } = $props();
    let grants = $state<Grant[]>([]);
    let recipient = $state("");
    let purpose = $state("");
    let busy = $state(false);
    let message = $state("");
    async function reload() {
        try {
            const result = await fetchNui<Grant[]>("getCaseDisclosures",{caseId},[]);
            grants = Array.isArray(result) ? result : [];
        } catch { grants = []; }
    }
    async function grant() {
        if(busy || !recipient.trim() || purpose.trim().length<10) return;
        busy=true;message="";
        try {
            const result=await fetchNui<{success:boolean;error?:string}>("grantCaseDisclosure",
              {caseId,recipientCitizenid:recipient.trim(),purpose:purpose.trim()},{success:false});
            message=result.success?"Case detail disclosure recorded.":result.error || "Disclosure denied.";
            if(result.success){recipient="";purpose="";await reload();}
        } finally {busy=false;}
    }
    async function revoke(id:number) {
        if(busy) return;
        busy=true;message="";
        try {
            const result=await fetchNui<{success:boolean;error?:string}>("revokeCaseDisclosure",{grantId:id},{success:false});
            message=result.success?"Disclosure revoked.":result.error || "Revocation denied.";
            await reload();
        } finally {busy=false;}
    }
    onMount(()=>{void reload();});
</script>
<section class="case-disclosure">
    <h3>Controlled case disclosure</h3>
    <p>Grant one character read-only access to this case. This does not disclose independent reports, medical charts, evidence stashes, or permit editing. Only the case-owning department can manage grants.</p>
    <form onsubmit={(e)=>{e.preventDefault();void grant();}}>
        <label>Recipient citizen ID<input bind:value={recipient} maxlength="64" required /></label>
        <label>Disclosure purpose<input bind:value={purpose} minlength="10" maxlength="255" required /></label>
        <button type="submit" disabled={busy || purpose.trim().length < 10}>Grant case view</button>
    </form>
    {#if message}<p aria-live="polite">{message}</p>{/if}
    <button disabled={busy} onclick={()=>void reload()}>Refresh grants</button>
    {#each grants as item (item.id)}
      <div class="grant">
        <span>{item.recipient_citizenid} · {item.purpose} — {item.revoked_at ? "Revoked" : "Active"}</span>
        {#if !item.revoked_at}<button disabled={busy} onclick={()=>void revoke(item.id)}>Revoke</button>{/if}
      </div>
    {/each}
</section>
<style>
.case-disclosure {padding:18px 20px;border-top:1px solid rgba(128,128,128,.25);}
h3 {margin:0 0 8px;}
p {opacity:.75;font-size:13px;}
form {display:flex;gap:10px;flex-wrap:wrap;align-items:flex-end;margin:12px 0;}
label {display:flex;flex-direction:column;gap:5px;font-size:12px;flex:1;min-width:175px;}
input {border:1px solid rgba(128,128,128,.45);background:transparent;color:inherit;border-radius:4px;padding:8px;}
button {border:1px solid rgba(128,128,128,.45);background:transparent;color:inherit;padding:7px 11px;border-radius:4px;cursor:pointer;}
button:disabled {opacity:.5;cursor:default;}
.grant {display:flex;justify-content:space-between;gap:12px;padding:10px 0;border-top:1px solid rgba(128,128,128,.2);}
</style>
