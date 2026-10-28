// Run from repository root with existing project dependencies:
// node tests/phase3/government_frontend_regression.cjs
// Production service is compiled in memory; NUI is the only mocked import.
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
  const events = NUI_EVENTS.ROSTER;
  const names = {
    roster: events.GET_GOVERNMENT_ROSTER,
    candidate: events.GET_GOVERNMENT_HIRE_CANDIDATE,
    hire: events.HIRE_GOVERNMENT_EMPLOYEE,
    grade: events.SET_GOVERNMENT_EMPLOYEE_GRADE,
    terminate: events.TERMINATE_GOVERNMENT_EMPLOYEE,
  };
  for (const [key, name] of Object.entries(names)) {
    assert.equal(typeof name, 'string', `Missing NUI event ${key}`);
    assert.ok(ALL_NUI_EVENTS.includes(name), `NUI event ${key} is not whitelisted`);
  }
  const pending = [];
  const requests = [];
  const imports = {
    'svelte/internal/client': runtime,
    '../constants/nuiEvents': { NUI_EVENTS },
    '../utils/fetchNui': { fetchNui: (name, data, fallback) => {
      assert.ok(Object.values(names).includes(name), `Unexpected operational callback ${name}`);
      requests.push({ name, data });
      const next = pending.shift();
      if (!next) return Promise.resolve(fallback);
      assert.equal(name, next.name, 'Unexpected request order');
      return next.run(data, fallback);
    } },
  };
  const source = fs.readFileSync(path.join(root, 'web/src/services/governmentPersonnelService.svelte.ts'), 'utf8');
  const compiled = compiler.compileModule(transpile(source, ts.ModuleKind.ESNext), { filename: 'governmentPersonnelService.svelte.js', generate: 'client' });
  const exports = {};
  new Function('require', 'exports', transpile(compiled.js.code, ts.ModuleKind.CommonJS))(id => {
    assert.ok(Object.hasOwn(imports, id), `Unexpected import ${id}`);
    return imports[id];
  }, exports);
  const make = exports.createGovernmentPersonnelService;
  const candidate = { citizenid: 'UNEMPLOYED', serverId: 27, firstName: 'New', lastName: 'Applicant' };
  function response({ job = 'bcgov', manage = true, oversight = false, employees = ['EMPLOYEE'] } = {}) {
    return {
      success: true,
      roster: employees.map(citizenid => ({ citizenid, firstName: 'Test', lastName: citizenid, rank: 'County Clerk', grade: 6, department: job, departmentLabel: job, jurisdiction: job })),
      departments: [{ job, label: job, jurisdiction: job, jurisdictionLabel: job, grades: [{ grade: 0, name: 'Awaiting Appointment' }, { grade: 6, name: 'County Clerk' }, { grade: 12, name: 'County Commissioner' }] }],
      selectedDepartment: job, hasOversight: oversight, canManagePersonnel: manage,
    };
  }
  function reply(name, value) { pending.push({ name, run: async () => value }); }
  function delay(name) {
    let resolve, reject;
    pending.push({ name, run: () => new Promise((ok, fail) => { resolve = ok; reject = fail; }) });
    return { resolve: value => resolve(value), reject: value => reject(value) };
  }
  async function loaded(options) {
    const service = make();
    reply(names.roster, response(options));
    await service.loadRoster();
    assert.equal(service.error, '');
    return service;
  }
  async function found(service) {
    reply(names.candidate, { success: true, candidate });
    assert.equal(await service.findHireCandidate(27), true);
  }
  let passed = 0;
  async function test(name, run) {
    assert.equal(pending.length, 0, 'Prior test left an expected response unused');
    await run();
    assert.equal(pending.length, 0, 'Expected NUI response was unused');
    passed++;
    console.log(`PASS ${name}`);
  }
  await test('server management capability is separate from roster oversight', async () => {
    const service = await loaded({ manage: false, oversight: true });
    assert.equal(service.hasOversight, true);
    assert.equal(service.canManagePersonnel, false);
    const count = requests.length;
    assert.equal(await service.findHireCandidate(27), false);
    assert.equal(await service.hireEmployee(0), false);
    assert.equal(await service.changeGrade('EMPLOYEE', 0), false);
    assert.equal(await service.terminateEmployee('EMPLOYEE'), false);
    assert.equal(requests.length, count, 'Read-only users must not issue management requests');
    assert.ok(service.actionError);
  });
  await test('only strict server true enables management controls', async () => {
    for (const value of [undefined, false, 'true', 1]) {
      const service = make();
      const data = response();
      data.canManagePersonnel = value;
      reply(names.roster, data);
      await service.loadRoster();
      assert.equal(service.canManagePersonnel, false);
    }
  });
  await test('candidate lookup sends the selected department and numeric online ID only', async () => {
    const service = await loaded();
    await found(service);
    assert.deepEqual(requests.at(-1), { name: names.candidate, data: { department: 'bcgov', serverId: 27 } });
    assert.equal(service.hireCandidate.citizenid, 'UNEMPLOYED');
    assert.equal(service.hireCandidate.serverId, 27);
    assert.equal(service.isFindingCandidate, false);
  });
  await test('invalid online IDs are rejected before transport', async () => {
    const service = await loaded();
    const count = requests.length;
    for (const id of [0, -1, 1.5, NaN, Infinity, '27']) assert.equal(await service.findHireCandidate(id), false);
    assert.equal(requests.length, count);
    assert.equal(service.hireCandidate, null);
  });
  await test('candidate denial removes a previously selected applicant', async () => {
    const service = await loaded();
    await found(service);
    reply(names.candidate, { success: false, error: 'Player is already employed' });
    assert.equal(await service.findHireCandidate(27), false);
    assert.equal(service.hireCandidate, null);
    assert.match(service.actionError, /employed/);
  });
  await test('a candidate response with a different server ID is rejected', async () => {
    const service = await loaded();
    reply(names.candidate, { success: true, candidate: { ...candidate, serverId: 99 } });
    assert.equal(await service.findHireCandidate(27), false);
    assert.equal(service.hireCandidate, null);
  });
  await test('hiring requires a freshly selected candidate', async () => {
    const service = await loaded();
    const count = requests.length;
    assert.equal(await service.hireEmployee(0), false);
    assert.equal(requests.length, count);
    assert.ok(service.actionError);
  });
  await test('hiring binds candidate citizen ID and server ID and supports valid grade zero', async () => {
    const service = await loaded();
    await found(service);
    reply(names.hire, { success: true, message: 'Employee hired' });
    reply(names.roster, response({ employees: ['EMPLOYEE', 'UNEMPLOYED'] }));
    assert.equal(await service.hireEmployee(0), true);
    assert.deepEqual(requests.at(-2), { name: names.hire, data: { department: 'bcgov', citizenid: 'UNEMPLOYED', serverId: 27, grade: 0 } });
    assert.equal(service.hireCandidate, null);
    assert.equal(service.roster.length, 2);
    assert.equal(service.isSaving, false);
    assert.ok(service.actionMessage);
  });
  await test('grade changes send only the selected job target and existing grade', async () => {
    const service = await loaded();
    reply(names.grade, { success: true, message: 'Position changed' });
    reply(names.roster, response());
    assert.equal(await service.changeGrade('EMPLOYEE', 12), true);
    assert.deepEqual(requests.at(-2), { name: names.grade, data: { department: 'bcgov', citizenid: 'EMPLOYEE', grade: 12 } });
  });
  await test('unknown and malformed grades are rejected before any mutation', async () => {
    const service = await loaded();
    const count = requests.length;
    for (const grade of [999, -1, 1.5, NaN, Infinity, '6']) assert.equal(await service.changeGrade('EMPLOYEE', grade), false);
    assert.equal(requests.length, count);
  });
  await test('termination uses a government-only callback and refreshes the roster', async () => {
    const service = await loaded();
    reply(names.terminate, { success: true, message: 'Employment terminated' });
    reply(names.roster, response({ employees: [] }));
    assert.equal(await service.terminateEmployee('EMPLOYEE'), true);
    assert.deepEqual(requests.at(-2), { name: names.terminate, data: { department: 'bcgov', citizenid: 'EMPLOYEE' } });
    assert.equal(service.roster.length, 0);
  });
  await test('server-denied changes do not show success or discard the existing roster', async () => {
    const service = await loaded();
    reply(names.grade, { success: false, error: 'Target belongs to another jurisdiction' });
    const count = requests.length;
    assert.equal(await service.changeGrade('EMPLOYEE', 0), false);
    assert.equal(requests.length, count + 1, 'A denied mutation must not perform a success refresh');
    assert.equal(service.roster[0].citizenid, 'EMPLOYEE');
    assert.equal(service.actionMessage, '');
    assert.match(service.actionError, /jurisdiction/);
    assert.equal(service.isSaving, false);
  });
  await test('network failures resolve as errors and release the write guard', async () => {
    const service = await loaded();
    const request = delay(names.grade);
    const action = service.changeGrade('EMPLOYEE', 0);
    assert.equal(service.isSaving, true);
    request.reject(new Error('Connection failed'));
    assert.equal(await action, false);
    assert.match(service.actionError, /Connection failed/);
    assert.equal(service.isSaving, false);
  });
  await test('transport fallbacks cannot report a successful employment action', async () => {
    const service = await loaded();
    assert.equal(await service.terminateEmployee('EMPLOYEE'), false);
    assert.equal(service.actionMessage, '');
    assert.ok(service.actionError);
  });
  await test('an in-flight mutation prevents a duplicate write', async () => {
    const service = await loaded();
    const request = delay(names.grade);
    const first = service.changeGrade('EMPLOYEE', 0);
    const count = requests.length;
    assert.equal(await service.terminateEmployee('EMPLOYEE'), false);
    assert.equal(requests.length, count);
    reply(names.roster, response());
    request.resolve({ success: true, message: 'Position changed' });
    assert.equal(await first, true);
  });
  await test('pending roster loads disable mutation attempts', async () => {
    const service = await loaded();
    const request = delay(names.roster);
    const loading = service.loadRoster();
    const count = requests.length;
    assert.equal(await service.changeGrade('EMPLOYEE', 0), false);
    assert.equal(requests.length, count);
    request.resolve(response());
    await loading;
  });
  await test('identity reset cancels pending candidate lookup state', async () => {
    const service = await loaded();
    const request = delay(names.candidate);
    const finding = service.findHireCandidate(27);
    service.reset();
    request.resolve({ success: true, candidate });
    assert.equal(await finding, false);
    assert.equal(service.hireCandidate, null);
    assert.equal(service.isFindingCandidate, false);
    assert.equal(service.canManagePersonnel, false);
  });
  await test('a newer candidate lookup supersedes a delayed previous applicant', async () => {
    const service = await loaded();
    const first = delay(names.candidate);
    const earlier = service.findHireCandidate(27);
    const second = delay(names.candidate);
    const latest = service.findHireCandidate(28);
    second.resolve({ success: true, candidate: { ...candidate, citizenid: 'LATEST', serverId: 28 } });
    assert.equal(await latest, true);
    first.reject(new Error('Old candidate request failed'));
    assert.equal(await earlier, false);
    assert.equal(service.hireCandidate.citizenid, 'LATEST');
    assert.equal(service.hireCandidate.serverId, 28);
    assert.equal(service.actionError, '');
    assert.equal(service.isFindingCandidate, false);
  });
  await test('candidate lookup fallback clears an old candidate without reporting success', async () => {
    const service = await loaded();
    await found(service);
    assert.equal(await service.findHireCandidate(28), false);
    assert.equal(service.hireCandidate, null);
    assert.equal(service.isFindingCandidate, false);
    assert.ok(service.actionError);
    assert.equal(service.actionMessage, '');
  });
  await test('loading another roster invalidates the old hire candidate and management grant', async () => {
    const service = await loaded();
    await found(service);
    reply(names.roster, response({ job: 'lsgov', manage: false, oversight: true }));
    await service.loadRoster('lsgov');
    assert.equal(service.selectedDepartment, 'lsgov');
    assert.equal(service.hireCandidate, null);
    assert.equal(service.canManagePersonnel, false);
    const count = requests.length;
    assert.equal(await service.hireEmployee(0), false);
    assert.equal(requests.length, count);
  });
  await test('late mutation success cannot refresh or overwrite a newer identity', async () => {
    const service = await loaded();
    const request = delay(names.grade);
    const action = service.changeGrade('EMPLOYEE', 0);
    service.reset();
    reply(names.roster, response({ job: 'lsgov', manage: false, employees: ['NEW CHARACTER'] }));
    await service.loadRoster();
    const count = requests.length;
    request.resolve({ success: true, message: 'Old operation completed' });
    assert.equal(await action, false);
    assert.equal(requests.length, count);
    assert.equal(service.selectedDepartment, 'lsgov');
    assert.equal(service.roster[0].citizenid, 'NEW CHARACTER');
    assert.equal(service.actionMessage, '');
    assert.equal(service.actionError, '');
    assert.equal(service.isSaving, false);
  });
  await test('a successful write cannot retain management after the server revokes it', async () => {
    const service = await loaded();
    reply(names.grade, { success: true, message: 'Position changed' });
    reply(names.roster, response({ manage: false }));
    assert.equal(await service.changeGrade('EMPLOYEE', 0), true);
    assert.equal(service.canManagePersonnel, false);
  });
  console.log(`Phase 3 government frontend: ${passed} tests passed; production service compiled in memory, NUI mocked, no files emitted.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
