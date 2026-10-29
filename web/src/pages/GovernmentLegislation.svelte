<script lang="ts">
import { untrack } from "svelte";
import { fetchNui } from "../utils/fetchNui";
import type { AuthService } from "../services/authService.svelte";

let { authService }: { authService: AuthService } = $props();

type Status = "draft" | "voting" | "adopted" | "rejected" | "published";
type MeasureType = "state_law" | "county_ordinance" | "municipal_code";
interface Measure {
  id: number; agency: string; jurisdiction: string; measure_type: MeasureType;
  title: string; body: string; status: Status; version?: number;
  published_at?: string | null; certification_reason?: string | null;
}
interface Vote { voter_citizenid: string; vote: "yes" | "no" | "abstain"; cast_at: string; }
interface Listing {
  success: boolean; error?: string; measures?: Measure[]; hasMore?: boolean;
  agency?: string; canDraft?: boolean; canVote?: boolean;
  canCertify?: boolean; canPublish?: boolean;
}
interface Result { success: boolean; error?: string; votes?: Vote[]; }
type LegislativeAction =
  | "createGovernmentMeasure" | "editGovernmentMeasure"
  | "openGovernmentMeasureVote" | "castGovernmentOfficialVote"
  | "certifyGovernmentMeasure" | "publishGovernmentMeasure";

let page = $state(0), hasMore = $state(false);
let measures = $state<Measure[]>([]), selected = $state<Measure | null>(null);
let agency = $state("");
let canDraft = $state(false), canVote = $state(false);
let canCertify = $state(false), canPublish = $state(false);
let saving = $state(false), loading = $state(false);
let error = $state(""), notice = $state("");
let creating = $state(false), title = $state(""), body = $state("");
let measureType = $state<MeasureType>("county_ordinance");
let choice = $state<"yes" | "no" | "abstain">("yes");
let outcome = $state<"adopted" | "rejected">("adopted");
let certificationReason = $state("");
let votes = $state<Vote[]>([]), votesLoading = $state(false);
let revision = 0;

function reset() {
  revision++;
  measures = []; selected = null; agency = "";
  canDraft = false; canVote = false; canCertify = false; canPublish = false;
  page = 0; hasMore = false; votes = []; creating = false;
  title = ""; body = ""; error = ""; notice = "";
}
async function load() {
  const token = ++revision;
  loading = true; error = "";
  try {
    const response = await fetchNui<Listing>("getGovernmentLegislation", {page}, {success: false});
    if (token !== revision) return;
    if (!response?.success || !Array.isArray(response.measures)) {
      measures = []; selected = null;
      canDraft = false; canVote = false; canCertify = false; canPublish = false;
      error = response?.error || "Legislative docket unavailable.";
      return;
    }
    measures = response.measures;
    agency = response.agency || "";
    canDraft = response.canDraft === true;
    canVote = response.canVote === true;
    canCertify = response.canCertify === true;
    canPublish = response.canPublish === true;
    hasMore = response.hasMore === true;
    if (selected) selected = measures.find(item => item.id === selected?.id) ?? null;
  } catch {
    if (token === revision) { measures = []; error = "Cannot retrieve legislative docket."; }
  } finally { if (token === revision) loading = false; }
}
async function loadVotes(item: Measure) {
  votes = []; votesLoading = true;
  const token = revision;
  try {
    const response = await fetchNui<Result>("getGovernmentOfficialVotes", {id:item.id}, {success:false});
    if (token === revision && selected?.id === item.id) {
      votes = response.success && Array.isArray(response.votes) ? response.votes : [];
    }
  } catch { if (token === revision) votes = []; }
  finally { if (token === revision) votesLoading = false; }
}
function selectMeasure(item: Measure) {
  selected = item; creating = false; title = item.title; body = item.body;
  error = ""; notice = ""; votes = []; certificationReason = "";
  if (item.status !== "draft") void loadVotes(item);
}
function newDraft() {
  if (!canDraft || saving) return;
  creating = true; selected = null; title = ""; body = ""; error = "";
  const area = authService.jurisdiction || "";
  measureType = area === "state" ? "state_law"
    : area.includes("county") ? "county_ordinance" : "municipal_code";
}
function changePage(next: number) {
  if (loading || saving || next < 0 || next > 200 || (next > page && !hasMore)) return;
  page = next; selected = null; creating = false; votes = []; void load();
}
async function post(action: LegislativeAction, payload: Record<string, unknown>, successMessage: string) {
  if (saving) return;
  saving = true; error = "";
  try {
    const result = await fetchNui<Result>(action, payload, {success:false});
    if (!result?.success) { error = result?.error || "Legislative action denied."; return; }
    notice = successMessage; selected = null; creating = false; votes = [];
    page = 0; await load();
  } catch { error = "Legislative action failed."; }
  finally { saving = false; }
}
function saveDraft() {
  if (!canDraft || !title.trim() || !body.trim()) return;
  const item = selected;
  if (item && (item.status !== "draft" || item.agency !== agency || !item.version)) return;
  const action = item ? "editGovernmentMeasure" : "createGovernmentMeasure";
  const payload = item
    ? {id:item.id,version:item.version,title:title.trim(),body:body.trim()}
    : {measureType,title:title.trim(),body:body.trim()};
  void post(action,payload,item ? "Draft updated." : "Legislative draft created.");
}
function act(action: LegislativeAction, additional: Record<string, unknown> = {}) {
  const item = selected;
  if (!item || item.agency !== agency || !item.version) return;
  void post(action, {id:item.id,version:item.version,...additional}, "Official action recorded.");
}
$effect(() => {
  authService.playerData?.citizenid;
  authService.playerData?.job?.grade?.level;
  authService.agency;
  authService.jurisdiction;
  authService.isAuthorized;
  untrack(() => {
    reset();
    if (authService.isAuthorized && authService.interfaceId === "sagov") void load();
  });
});
</script>

<section class="legislation">
  <header>
    <div><h2>Legislative Docket</h2>
      <p>State laws, county ordinances and municipal codes · jurisdiction-specific official votes</p>
    </div>
    <div class="actions">
      <button onclick={() => void load()} disabled={loading || saving}>Refresh</button>
      {#if canDraft}<button onclick={newDraft} disabled={loading || saving}>New measure</button>{/if}
    </div>
  </header>
  {#if error}<p role="alert" class="error">{error}</p>{/if}
  {#if notice}<p role="status" class="success">{notice}</p>{/if}
  <div class="workspace">
    <div class="list">
      <h3>Measures</h3>
      {#if loading}<p>Loading…</p>{/if}
      {#each measures as item (item.id)}
        <button class:selected={selected?.id === item.id} onclick={() => selectMeasure(item)}>
          <strong>{item.title}</strong>
          <span>{item.agency} · {item.measure_type} · {item.status}</span>
        </button>
      {:else}{#if !loading}<p>No measures available.</p>{/if}{/each}
      <div class="pages">
        <button onclick={() => changePage(page-1)} disabled={page === 0 || loading || saving}>Previous</button>
        <span>Page {page+1}</span>
        <button onclick={() => changePage(page+1)} disabled={!hasMore || loading || saving}>Next</button>
      </div>
    </div>
    <div class="detail">
      {#if creating || selected}
        <h3>{creating ? "New legislative draft" : selected?.title}</h3>
        <p>{creating ? "Your jurisdiction" : selected?.jurisdiction} · {creating ? measureType : selected?.status}</p>
        {#if creating || (selected?.status === "draft" && selected?.agency === agency && canDraft)}
          {#if creating}
            <label for="measure-type">Measure type</label>
            <select id="measure-type" bind:value={measureType} disabled={saving}>
              <option value="state_law">State law</option>
              <option value="county_ordinance">County ordinance</option>
              <option value="municipal_code">Municipal code</option>
            </select>
          {/if}
          <label for="measure-title">Title</label>
          <input id="measure-title" bind:value={title} maxlength="180" disabled={saving}/>
          <label for="measure-body">Measure text</label>
          <textarea id="measure-body" bind:value={body} maxlength="10000" rows="9" disabled={saving}></textarea>
          <button onclick={saveDraft} disabled={saving || !title.trim() || !body.trim()}>Save draft</button>
        {:else}
          <p class="body">{selected?.body}</p>
        {/if}

        {#if selected && selected.agency === agency && selected.status === "draft" && canDraft}
          <button onclick={() => act("openGovernmentMeasureVote")} disabled={saving}>Open official voting</button>
        {/if}
        {#if selected && selected.agency === agency && selected.status === "voting"}
          {#if canVote}
            <label for="official-vote">Your official vote</label>
            <select id="official-vote" bind:value={choice} disabled={saving}>
              <option value="yes">Yes</option><option value="no">No</option><option value="abstain">Abstain</option>
            </select>
            <button onclick={() => act("castGovernmentOfficialVote",{choice})} disabled={saving}>Record my vote</button>
          {/if}
          {#if canCertify}
            <label for="certification-outcome">Certification outcome</label>
            <select id="certification-outcome" bind:value={outcome} disabled={saving}>
              <option value="adopted">Adopted</option><option value="rejected">Rejected</option>
            </select>
            <label for="certification-reason">Certification rationale</label>
            <textarea id="certification-reason" bind:value={certificationReason} maxlength="1000" rows="3" disabled={saving}></textarea>
            <p class="warning">Certification follows the jurisdiction's RP rules; the system does not calculate quorum or infer passage.</p>
            <button onclick={() => act("certifyGovernmentMeasure",{outcome,reason:certificationReason.trim()})}
              disabled={saving || !certificationReason.trim()}>Certify official result</button>
          {/if}
        {/if}
        {#if selected && selected.agency === agency && selected.status === "adopted" && canPublish}
          <button onclick={() => act("publishGovernmentMeasure")} disabled={saving}>Publish certified measure</button>
        {/if}
        {#if selected && (selected.status === "voting" || selected.status === "adopted" || selected.status === "rejected" || selected.status === "published")}
          <h3>Official votes</h3>
          {#if votesLoading}<p>Loading recorded votes…</p>{/if}
          {#each votes as vote}
            <p>{vote.voter_citizenid}: {vote.vote} · {vote.cast_at}</p>
          {:else}<p>No votes available to your role.</p>{/each}
        {/if}
      {:else}<p>Select a measure or start a draft if authorized.</p>{/if}
    </div>
  </div>
</section>

<style>
.legislation{padding:8px 0}.legislation h2,.legislation h3{margin:0 0 12px}
.legislation p{white-space:pre-wrap;margin:10px 0;line-height:1.5}
.legislation header,.legislation .actions,.legislation .pages{display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap}
.legislation .workspace{display:grid;grid-template-columns:minmax(220px,35%) minmax(0,1fr);gap:16px;margin-top:20px}
.legislation .list,.legislation .detail{border:1px solid var(--border-primary);border-radius:8px;padding:16px;min-width:0}
.legislation .list>button{width:100%;display:flex;flex-direction:column;gap:5px;text-align:left;margin:6px 0}
.legislation .list>button.selected{border-color:var(--primary-text)}
.legislation label{display:block;margin-top:12px}.legislation input,.legislation textarea,.legislation select,.legislation button{font:inherit;color:var(--primary-text);background:var(--card-dark-bg);border:1px solid var(--border-primary);padding:9px;border-radius:5px}
.legislation input,.legislation textarea,.legislation select{box-sizing:border-box;width:100%;margin-top:4px}
.legislation button{cursor:pointer}.legislation button:disabled{opacity:.5}
.legislation .body{white-space:pre-wrap;overflow-wrap:anywhere}.legislation .error{color:#fca5a5}.legislation .success{color:#86efac}
.legislation .warning{border-left:2px solid #c8b074;padding-left:10px}
@media(max-width:700px){.legislation .workspace{grid-template-columns:1fr}}
</style>
