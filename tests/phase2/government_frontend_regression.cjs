// Uses installed project tools by default; optional args: <svelte/compiler> <typescript>.
// Compiles the actual service in memory and mocks only the NUI transport.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname, '../..');
const sveltePath = path.resolve(process.argv[2] || path.join(root, 'web/node_modules/svelte/compiler'));
const ts = require(path.resolve(process.argv[3] || path.join(root, 'web/node_modules/typescript')));
const compiler = require(sveltePath);
function transpile(source, module) {
  return ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module } }).outputText;
}
async function main() {
  const svelteRoot = path.resolve(path.dirname(require.resolve(sveltePath)), '..');
  const runtime = await import(pathToFileURL(path.join(svelteRoot, 'src/internal/client/index.js')).href);
  const eventExports = {};
  new Function('exports', transpile(fs.readFileSync(path.join(root, 'web/src/constants/nuiEvents.ts'), 'utf8'), ts.ModuleKind.CommonJS))(eventExports);
  const { NUI_EVENTS, ALL_NUI_EVENTS } = eventExports;
  const event = NUI_EVENTS.ROSTER.GET_GOVERNMENT_ROSTER;
  assert.ok(ALL_NUI_EVENTS.includes(event), 'Government callback must be whitelisted');
  const pending = [];
  const requests = [];
  const imports = {
    'svelte/internal/client': runtime,
    '../constants/nuiEvents': { NUI_EVENTS },
    '../utils/fetchNui': { fetchNui: (name, data, fallback) => {
      assert.equal(name, event, 'Government page must never request operational or write callbacks');
      requests.push({ name, data });
      const next = pending.shift();
      return next ? next(data, fallback) : Promise.resolve(fallback);
    } },
  };
  const source = fs.readFileSync(path.join(root, 'web/src/services/governmentPersonnelService.svelte.ts'), 'utf8');
  const compiled = compiler.compileModule(transpile(source, ts.ModuleKind.ESNext), { filename: 'governmentPersonnelService.svelte.js', generate: 'client' });
  const exports = {};
  new Function('require', 'exports', transpile(compiled.js.code, ts.ModuleKind.CommonJS))(id => {
    assert.ok(Object.hasOwn(imports, id), `Unexpected import: ${id}`);
    return imports[id];
  }, exports);
  const make = exports.createGovernmentPersonnelService;
  function response(job = 'bcgov', id = 'EMPLOYEE') {
    return {
      success: true, roster: [{ citizenid: id, firstName: 'Test', lastName: 'Employee', rank: 'County Clerk', grade: 6, department: job, departmentLabel: job, jurisdiction: job }],
      departments: [{ job, label: job, jurisdiction: job, jurisdictionLabel: job, grades: [{ grade: 6, name: 'County Clerk' }] }],
      selectedDepartment: job, hasOversight: false, canManagePersonnel: false,
    };
  }
  function reply(value) { pending.push(async () => value); }
  function delay() {
    let resolve, reject;
    pending.push(() => new Promise((ok, fail) => { resolve = ok; reject = fail; }));
    return { resolve: value => resolve(value), reject: error => reject(error) };
  }
  let passed = 0;
  async function test(name, run) {
    assert.equal(pending.length, 0, 'Previous test left a queued response');
    await run();
    passed++;
    console.log(`PASS ${name}`);
  }
  await test('loads server-returned personnel and exact runtime grade catalog', async () => {
    const service = make();
    reply(response());
    await service.loadRoster();
    assert.equal(service.roster[0].rank, 'County Clerk');
    assert.equal(service.departments[0].grades[0].grade, 6);
    assert.equal(service.selectedDepartment, 'bcgov');
    assert.deepEqual(requests.at(-1).data, {});
    assert.equal(service.hasOversight, false);
  });
  await test('selected department is the only request field; no client authority fields', async () => {
    const service = make();
    const data = response('lsgov');
    data.hasOversight = true;
    reply(data);
    await service.loadRoster('lsgov');
    assert.deepEqual(requests.at(-1).data, { department: 'lsgov' });
    assert.equal(service.hasOversight, true);
  });
  await test('late previous department response cannot overwrite the latest selection', async () => {
    const service = make();
    const first = delay();
    const earlier = service.loadRoster('bcgov');
    const second = delay();
    const latest = service.loadRoster('lsgov');
    second.resolve(response('lsgov', 'LATEST'));
    await latest;
    first.resolve(response('bcgov', 'OLD'));
    await earlier;
    assert.equal(service.roster[0].citizenid, 'LATEST');
    assert.equal(service.selectedDepartment, 'lsgov');
  });
  await test('identity reset clears personnel and ignores an old pending response', async () => {
    const service = make();
    reply(response());
    await service.loadRoster();
    const old = delay();
    const loading = service.loadRoster();
    service.reset();
    old.resolve(response('bcgov', 'OLD CHARACTER'));
    await loading;
    assert.equal(service.roster.length, 0);
    assert.equal(service.departments.length, 0);
    assert.equal(service.selectedDepartment, '');
    assert.equal(service.isLoading, false);
  });
  await test('server denial removes previously available oversight and records', async () => {
    const service = make();
    const initial = response('sagov');
    initial.hasOversight = true;
    reply(initial);
    await service.loadRoster();
    reply({ success: false, error: 'Department access denied', roster: {}, departments: {} });
    await service.loadRoster('bcgov');
    assert.equal(service.roster.length, 0);
    assert.equal(service.departments.length, 0);
    assert.equal(service.hasOversight, false);
    assert.match(service.error, /denied/);
  });
  await test('failed or timed-out NUI cannot fabricate a successful empty roster', async () => {
    const service = make();
    await service.loadRoster();
    assert.ok(service.error);
    assert.equal(service.departments.length, 0);
    const connection = delay();
    const loading = service.loadRoster();
    connection.reject(new Error('Disconnected'));
    await loading;
    assert.match(service.error, /Disconnected/);
  });
  await test('an empty Lua roster object is a valid empty department', async () => {
    const service = make();
    const data = response();
    data.roster = {};
    reply(data);
    await service.loadRoster();
    assert.equal(service.roster.length, 0);
    assert.equal(service.departments.length, 1);
    assert.equal(service.error, '');
  });
  await test('unexpected foreign-department rows fail closed', async () => {
    const service = make();
    const data = response();
    data.roster[0].department = 'lscgov';
    reply(data);
    await service.loadRoster();
    assert.equal(service.roster.length, 0);
    assert.ok(service.error);
  });
  await test('success without an authorized selected department is rejected', async () => {
    const service = make();
    reply({ success: true, roster: [], departments: {} });
    await service.loadRoster();
    assert.equal(service.departments.length, 0);
    assert.ok(service.error);
  });
  await test('old rejected requests do not clear a newly authorized response', async () => {
    const service = make();
    const old = delay();
    const earlier = service.loadRoster('bcgov');
    reply(response('sagov', 'CURRENT'));
    await service.loadRoster();
    old.reject(new Error('Old denied request'));
    await earlier;
    assert.equal(service.roster[0].citizenid, 'CURRENT');
    assert.equal(service.error, '');
  });
  console.log(`Phase 2 government frontend: ${passed} tests passed; actual compiled service, mocked NUI, no files emitted.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
