// Run from the repository root: node tests/basics/dashboard_routes_regression.cjs
// Executes the actual Dashboard.svelte functions extracted through TypeScript's AST.
// Only transport, active-instance state and rune-backed row storage are mocked.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const ts = require(path.join(root, 'web/node_modules/typescript'));
const compiler = require(path.join(root, 'web/node_modules/svelte/compiler'));
const source = fs.readFileSync(path.join(root, 'web/src/pages/Dashboard.svelte'), 'utf8');
const script = source.slice(source.indexOf('>') + 1, source.indexOf('</script>'));
const ast = ts.createSourceFile('Dashboard.ts', script, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
const names = ['dojDashboardRows', 'navigateToTab', 'loadDojDashboard'];
const functions = ast.statements.filter(node => ts.isFunctionDeclaration(node) && names.includes(node.name?.text));
assert.equal(functions.length, names.length, 'Test must execute every actual dashboard function under review');
const compiledFunctions = ts.transpileModule(functions.map(node => node.getText(ast)).join('\n'), {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext },
}).outputText;
const eventExports = {};
new Function('exports', ts.transpileModule(fs.readFileSync(path.join(root, 'web/src/constants/nuiEvents.ts'), 'utf8'), {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
}).outputText)(eventExports);
const { NUI_EVENTS } = eventExports;

function dashboard(responses, activeInstance = { id: 'instance-1' }) {
  const requests = [], routes = [];
  const transport = async (event, data) => { requests.push({ event, data }); return responses[event]; };
  const tabs = {
    getActiveInstance: () => activeInstance,
    setInstanceTab: (id, tab) => routes.push({ id, tab }),
    setActiveTab: tab => routes.push({ tab }),
  };
  const instance = new Function('fetchNui', 'NUI_EVENTS', 'tabService', `
    let isDOJ = true;
    let dojWarrantReviews = [], dojCourtCases = [], dojCourtOrders = [];
    ${compiledFunctions}
    return {
      loadDojDashboard, navigateToTab,
      setDOJ(value) { isDOJ = value; },
      rows() { return { requests: dojWarrantReviews, cases: dojCourtCases, orders: dojCourtOrders }; }
    };
  `)(transport, NUI_EVENTS, tabs);
  return { ...instance, requests, routes };
}
function responses(requests, cases, orders) {
  return {
    [NUI_EVENTS.DOJ.GET_WARRANT_REQUESTS]: requests,
    [NUI_EVENTS.DOJ.GET_COURT_CASES]: cases,
    [NUI_EVENTS.DOJ.GET_COURT_ORDERS]: orders,
  };
}
let passed = 0;
async function test(name, run) { await run(); passed++; console.log(`PASS ${name}`); }
async function main() {
  await test('wrapped server records reach all three dashboard card collections', async () => {
    const request = { id: 1, citizen_name: 'Test Applicant' };
    const courtCase = { id: 2, title: 'Test Case' };
    const order = { id: 3, title: 'Test Order' };
    const ui = dashboard(responses({ requests: [request], total: 1 }, { cases: [courtCase], total: 1 }, { orders: [order], total: 1 }));
    await ui.loadDojDashboard();
    assert.deepEqual(ui.rows(), { requests: [request], cases: [courtCase], orders: [order] });
    for (const rows of ['dojWarrantReviews', 'dojCourtCases', 'dojCourtOrders']) {
      assert.ok(source.includes(`{#each ${rows} as `), `Loaded ${rows} must back the rendered cards`);
    }
    assert.equal(ui.requests.length, 3);
    assert.deepEqual(ui.requests[0].data, { status: 'pending', limit: 5 });
  });
  await test('legacy array responses remain compatible', async () => {
    const ui = dashboard(responses([{ id: 1 }], [{ id: 2 }], [{ id: 3 }]));
    await ui.loadDojDashboard();
    assert.deepEqual(ui.rows(), { requests: [{ id: 1 }], cases: [{ id: 2 }], orders: [{ id: 3 }] });
  });
  await test('dashboard collections remain limited to five records without mutating server data', async () => {
    const rows = Array.from({ length: 8 }, (_, id) => ({ id }));
    const ui = dashboard(responses({ requests: rows }, { cases: rows }, { orders: rows }));
    await ui.loadDojDashboard();
    for (const records of Object.values(ui.rows())) assert.deepEqual(records, rows.slice(0, 5));
    assert.equal(rows.length, 8);
  });
  await test('empty Lua tables, malformed wrappers and absent responses safely produce empty cards', async () => {
    for (const payload of [undefined, null, {}, { requests: {}, cases: 'invalid', orders: null }]) {
      const ui = dashboard(responses(payload, payload, payload));
      await ui.loadDojDashboard();
      assert.deepEqual(ui.rows(), { requests: [], cases: [], orders: [] });
    }
  });
  await test('non-DOJ dashboards do not fetch court card data', async () => {
    const ui = dashboard({});
    ui.setDOJ(false);
    await ui.loadDojDashboard();
    assert.equal(ui.requests.length, 0);
  });
  const cardTargets = [...source.matchAll(/onclick=\{\(\) => navigateToTab\('([^']+)'\)\}/g)].map(match => match[1]);
  await test('all actual court-card buttons use registered human-facing MDT tab keys', () => {
    assert.deepEqual(cardTargets, ['Warrant Review', 'Court Cases', 'Court Orders']);
    assert.equal(source.includes('tabService.openTab('), false);
  });
  await test('each court-card shortcut changes the active instance route', () => {
    const ui = dashboard({}, { id: 'active-legal-instance' });
    for (const target of cardTargets) ui.navigateToTab(target);
    assert.deepEqual(ui.routes, cardTargets.map(tab => ({ id: 'active-legal-instance', tab })));
  });
  await test('court-card shortcuts fall back to the global tab when no instance is active', () => {
    const ui = dashboard({}, undefined);
    // Explicit null avoids this harness's default active instance.
    const fallback = dashboard({}, null);
    for (const target of cardTargets) fallback.navigateToTab(target);
    assert.deepEqual(fallback.routes, cardTargets.map(tab => ({ tab })));
    assert.equal(ui.routes.length, 0);
  });
  await test('the updated Svelte component compiles with the installed project compiler', () => {
    compiler.compile(source, { filename: 'web/src/pages/Dashboard.svelte', generate: 'client' });
  });
  console.log(`Dashboard basic routing: ${passed} tests passed; actual component functions, mocked transport/navigation, no files emitted.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
