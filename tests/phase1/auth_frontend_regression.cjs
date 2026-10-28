// In-memory tests of the actual auth service using existing Svelte/TS tools.
// Usage: node tests/phase1/auth_frontend_regression.cjs <svelte/compiler> <typescript>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const [sveltePath, typescriptPath] = process.argv.slice(2);
if (!sveltePath || !typescriptPath) {
  console.error('Provide paths to an existing Svelte compiler and TypeScript installation.');
  process.exit(2);
}
const compiler = require(path.resolve(sveltePath));
const ts = require(path.resolve(typescriptPath));
const root = path.resolve(__dirname, '../..');
function transpile(source, module) {
  return ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module } }).outputText;
}
function constants(file) {
  const exports = {};
  new Function('exports', transpile(fs.readFileSync(path.join(root, file), 'utf8'), ts.ModuleKind.CommonJS))(exports);
  return exports;
}
async function main() {
  const svelteRoot = path.resolve(path.dirname(require.resolve(path.resolve(sveltePath))), '..');
  const runtime = await import(pathToFileURL(path.join(svelteRoot, 'src/internal/client/index.js')).href);
  const { NUI_EVENTS } = constants('web/src/constants/nuiEvents.ts');
  const pending = [];
  const requests = [];
  let browser = false;
  const imports = {
    'svelte/internal/client': runtime,
    '@/utils/fetchNui': { fetchNui: (event, data, fallback) => {
      requests.push({ event, data, fallback });
      const resolve = pending.shift();
      return resolve ? resolve(event, data, fallback) : Promise.resolve(fallback);
    } },
    '@/utils/debug': { debugError() {} },
    '@/constants/index': { TIMING: { offDutyLoadingDuration: 1 } },
    '@/constants/nuiEvents': { NUI_EVENTS },
    '@/utils/misc': { isEnvBrowser: () => browser },
    '@/constants/management': { ALL_PERMISSION_KEYS: ['citizens_search', 'warrants_issue'] },
  };
  const source = fs.readFileSync(path.join(root, 'web/src/services/authService.svelte.ts'), 'utf8');
  const compiled = compiler.compileModule(transpile(source, ts.ModuleKind.ESNext), { filename: 'authService.svelte.js', generate: 'client' });
  const exports = {};
  new Function('require', 'exports', transpile(compiled.js.code, ts.ModuleKind.CommonJS))(id => {
    assert.ok(Object.hasOwn(imports, id), `Unexpected import: ${id}`);
    return imports[id];
  }, exports);
  const make = exports.createAuthService;
  function data(overrides = {}) {
    return {
      authorized: true, eligible: true, onDuty: true, isLEO: true,
      isBoss: false, isCivilian: false, jobType: 'leo', interfaceId: 'sadle',
      allowedInterfaces: ['sadle'], agency: 'police', permissions: ['citizens_search'],
      playerData: { citizenid: 'TEST', job: { name: 'police', grade: { name: 'Officer', level: 1 }, onduty: true }, charinfo: { firstname: 'Test', lastname: 'Player' }, metadata: {} },
      ...overrides,
    };
  }
  let passed = 0;
  async function test(name, run) {
    await run();
    passed++;
    console.log(`PASS ${name}`);
  }
  await test('in-game failed auth cannot use browser mock boss permissions', async () => {
    const service = make();
    await service.checkAuth();
    assert.equal(service.isAuthorized, false);
    assert.equal(service.isBoss, false);
    assert.equal(service.permissions.length, 0);
  });
  await test('server-authorized off-duty DOJ remains visible', () => {
    const service = make();
    service.updateAuthState(data({ onDuty: false, jobType: 'doj', interfaceId: 'sadoj', allowedInterfaces: ['sadoj'], agency: 'sadoj' }));
    assert.equal(service.onDuty, false);
    assert.equal(service.showInterface, true);
    assert.equal(service.showLoadingScreen, false);
  });
  await test('server-authorized duty exception is honored for LEO too', () => {
    const service = make();
    service.updateAuthState(data({ onDuty: false }));
    assert.equal(service.showInterface, true);
  });
  await test('server-denied off-duty staff cannot see the interface', () => {
    const service = make();
    service.updateAuthState(data({ authorized: false, onDuty: false }));
    assert.equal(service.showInterface, false);
    service.updateAuthState(data({ isCivilian: true, jobType: 'civilian', interfaceId: undefined, allowedInterfaces: [] }));
    assert.equal(service.showInterface, true);
  });
  await test('government receives its shell without fetching operational permissions', () => {
    const service = make();
    const before = requests.length;
    service.updateAuthState(data({ jobType: 'gov', interfaceId: 'sagov', allowedInterfaces: ['sagov'], agency: 'bcgov', jurisdiction: 'blaine_county', permissions: [], isBoss: true }));
    assert.equal(service.showInterface, true);
    assert.equal(service.jurisdiction, 'blaine_county');
    assert.equal(service.hasPermission('citizens_search'), false);
    assert.equal(requests.length, before);
  });
  await test('boss metadata cannot bypass the returned permission list', () => {
    const service = make();
    service.updateAuthState(data({ isBoss: true }));
    assert.equal(service.hasPermission('warrants_issue'), false);
    assert.equal(service.hasAnyPermission('warrants_issue', 'judicial_authority'), false);
  });
  await test('late initial authentication cannot restore a previous job', async () => {
    const service = make();
    let reply;
    pending.push(() => new Promise(resolve => { reply = resolve; }));
    const initial = service.checkAuth();
    service.updateAuthState(data({ jobType: 'gov', interfaceId: 'sagov', allowedInterfaces: ['sagov'], agency: 'lsgov', permissions: [] }));
    reply(data({ isBoss: true }));
    await initial;
    assert.equal(service.interfaceId, 'sagov');
    assert.equal(service.agency, 'lsgov');
    assert.equal(service.isBoss, false);
  });
  await test('late permission fetch cannot overwrite a newer government identity', async () => {
    const service = make();
    let reply;
    pending.push(() => new Promise(resolve => { reply = resolve; }));
    service.updateAuthState(data({ permissions: [] }));
    service.updateAuthState(data({ jobType: 'gov', interfaceId: 'sagov', allowedInterfaces: ['sagov'], agency: 'sagov', permissions: [] }));
    reply(data({ isBoss: true }));
    await Promise.resolve();
    await Promise.resolve();
    assert.equal(service.interfaceId, 'sagov');
    assert.equal(service.permissions.length, 0);
  });
  await test('unlisted interface switch never reaches the client callback', async () => {
    const service = make();
    service.updateAuthState(data());
    const before = requests.length;
    await assert.rejects(service.selectInterface('sagov'), /denied/);
    assert.equal(requests.length, before);
  });
  await test('AG selection uses server context and preserves real agency', async () => {
    const service = make();
    service.updateAuthState(data({ agency: 'sadle', role: 'attorney_general', allowedInterfaces: ['sadle', 'sadoj'] }));
    pending.push(async event => {
      assert.equal(event, NUI_EVENTS.AUTH.SET_INTERFACE);
      return data({ success: true, agency: 'sadle', role: 'attorney_general', jobType: 'doj', interfaceId: 'sadoj', allowedInterfaces: ['sadle', 'sadoj'], permissions: ['court_view'] });
    });
    await service.selectInterface('sadoj');
    assert.equal(service.interfaceId, 'sadoj');
    assert.equal(service.agency, 'sadle');
    assert.equal(service.hasPermission('judicial_authority'), false);
  });
  await test('late switch response cannot restore AG access after a job change', async () => {
    const service = make();
    service.updateAuthState(data({ agency: 'sadle', allowedInterfaces: ['sadle', 'sadoj'] }));
    let reply;
    pending.push(() => new Promise(resolve => { reply = resolve; }));
    const switching = service.selectInterface('sadoj');
    service.updateAuthState(data({ agency: 'ambulance', jobType: 'ems', interfaceId: 'sams', allowedInterfaces: ['sams'] }));
    reply(data({ success: true, agency: 'sadle', jobType: 'doj', interfaceId: 'sadoj', allowedInterfaces: ['sadle', 'sadoj'] }));
    await switching;
    assert.equal(service.interfaceId, 'sams');
    assert.equal(service.agency, 'ambulance');
  });
  await test('browser preview keeps its explicit development mock', async () => {
    browser = true;
    const service = make();
    await service.checkAuth();
    assert.equal(service.interfaceId, 'sadle');
    assert.equal(service.isAuthorized, true);
  });
  console.log(`Phase 1 frontend auth: ${passed} passed; actual compiled auth service, mocked NUI, no files emitted.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
