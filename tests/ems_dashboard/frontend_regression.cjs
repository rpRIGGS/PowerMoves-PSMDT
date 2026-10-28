// Run from the repository root: node tests/ems_dashboard/frontend_regression.cjs
// Actual compiled dashboard service, mocked NUI transport/events, no browser or FiveM.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname, '../..');
const ts = require(path.join(root, 'web/node_modules/typescript'));
const compiler = require(path.join(root, 'web/node_modules/svelte/compiler'));
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
function transpile(source, module = ts.ModuleKind.CommonJS) {
  return ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module } }).outputText;
}
async function main() {
  const runtime = await import(pathToFileURL(path.join(root, 'web/node_modules/svelte/src/internal/client/index.js')).href);
  const constants = {};
  new Function('exports', transpile(read('web/src/constants/nuiEvents.ts')))(constants);
  const E = constants.NUI_EVENTS.DASHBOARD;
  let requests = [], listeners = new Map(), replies = [], browser = false, nextTimer = 0;
  const imports = {
    'svelte/internal/client': runtime,
    '../utils/useNuiEvent': { useNuiEvent: (event, handler) => listeners.set(event, handler) },
    '../utils/fetchNui': { fetchNui: (event, data, fallback) => {
      assert.ok([E.GET_DASHBOARD, E.GET_RECENT_REPORTS, E.GET_RECENT_DISPATCHES].includes(event), `Unexpected endpoint ${event}`);
      requests.push({ event, data });
      const index = replies.findIndex(reply => reply.event === event);
      return index < 0 ? Promise.resolve(fallback) : replies.splice(index, 1)[0].run(data);
    } },
    '../utils/debug': { debugError() {} },
    '../utils/misc': { isEnvBrowser: () => browser },
    '../constants/nuiEvents': { NUI_EVENTS: constants.NUI_EVENTS },
  };
  const compiled = compiler.compileModule(transpile(read('web/src/services/dashboardService.svelte.ts'), ts.ModuleKind.ESNext), { filename: 'dashboardService.svelte.js', generate: 'client' });
  const exports = {};
  new Function('require', 'exports', 'setInterval', 'clearInterval', transpile(compiled.js.code))(
    id => { assert.ok(Object.hasOwn(imports, id), `Unexpected import ${id}`); return imports[id]; }, exports,
    () => ++nextTimer, () => {},
  );
  function make(jobType = 'ems', inBrowser = false) {
    browser = inBrowser;
    let current = jobType;
    let contextKey = 'CID-A/HOSPITAL-A/0/on-duty';
    return {
      service: exports.createDashboardService(() => current, () => contextKey),
      setJobType: value => { current = value; },
      setContextKey: value => { contextKey = value; },
    };
  }
  function reply(event, value) { replies.push({ event, run: async () => value }); }
  function deferred(event) {
    let resolve, reject;
    replies.push({ event, run: () => new Promise((ok, fail) => { resolve = ok; reject = fail; }) });
    return { resolve: value => resolve(value), reject: error => reject(error) };
  }
  const event = (name, data) => { assert.ok(listeners.has(name), `Missing event handler ${name}`); listeners.get(name)(data); };
  const flush = async () => { for (let i = 0; i < 10; i++) await Promise.resolve(); };
  const emsReport = { id: 2, title: 'Authorized EMS report', type: 'Medical Report' };
  function payload(domain = 'ems') {
    return {
      dashboardDomain: domain, jobData: { rank: 'Paramedic', payRate: '$100/hr' },
      reportStatistics: { totalThisWeek: 6, changeFromLastWeek: 2 }, timeStatistics: [{ day: 'Mon', hours: 3 }],
      // Deliberately polluted fields prove the service never relies on UI hiding.
      activeWarrants: [{ reportid: 77, name: 'POLICE WARRANT' }], activeBolos: [{ id: 88, name: 'POLICE BOLO' }],
      openCases: [{ id: 99, title: 'POLICE INVESTIGATION' }], bulletins: [{ id: 3, content: 'Authorized EMS bulletin' }],
      upcomingHearings: [{ id: 4, title: 'EMS training', category: 'training' }], activeUnits: { count: 5 },
      recentDispatches: [{ id: 'EMS-CALL', jobs: ['ems'], message: 'Authorized EMS call' }],
      usageMetrics: { totals: { reports: 12, arrests: 987, activeWarrants: 876 }, windows: { reportsLast7: 6, reportsLast30: 12, arrestsLast7: 765, arrestsLast30: 654 }, impound: { held: 543, outstanding: 4321, oldestDays: 99, impoundedLast7: 321 } },
    };
  }
  function noPolice(service) {
    assert.equal(service.activeWarrants.length, 0);
    assert.equal(service.activeBolos.length, 0);
    assert.equal(service.openCases.length, 0);
    assert.equal(service.usageMetrics.totals.arrests, 0);
    assert.equal(service.usageMetrics.totals.activeWarrants, 0);
    assert.equal(service.usageMetrics.windows.arrestsLast7, 0);
    assert.equal(service.usageMetrics.windows.arrestsLast30, 0);
    assert.deepEqual(JSON.parse(JSON.stringify(service.usageMetrics.impound)), { held: 0, outstanding: 0, oldestDays: 0, impoundedLast7: 0 });
  }
  async function ready(jobType = 'ems') {
    const context = make(jobType);
    reply(E.GET_DASHBOARD, payload(jobType === 'ems' ? 'ems' : undefined));
    reply(E.GET_RECENT_REPORTS, [emsReport]);
    await context.service.initialize();
    return context;
  }
  let passed = 0;
  async function test(name, run) {
    requests = []; listeners = new Map(); replies = []; browser = false;
    await run();
    assert.equal(replies.length, 0, 'Test left unused response fixtures');
    passed++;
    console.log(`PASS ${name}`);
  }
  await test('EMS keeps authorized personal, report, calendar, bulletin, personnel and dispatch fields', async () => {
    const { service } = await ready();
    assert.equal(service.jobInfo.rank, 'Paramedic');
    assert.equal(service.reportsInfo.totalThisWeek, 6);
    assert.equal(service.weeklyTimeData[0].hours, 3);
    assert.equal(service.recentReports[0].title, emsReport.title);
    assert.equal(service.bulletins[0].content, 'Authorized EMS bulletin');
    assert.equal(service.upcomingHearings[0].title, 'EMS training');
    assert.equal(service.activeUnits.count, 5);
    assert.equal(service.recentDispatches[0].id, 'EMS-CALL');
    assert.equal(service.usageMetrics.totals.reports, 12);
    noPolice(service);
    service.destroy();
  });
  await test('EMS refuses an aggregate without the server EMS domain marker', async () => {
    const { service } = make();
    const data = payload(); delete data.dashboardDomain;
    reply(E.GET_DASHBOARD, data); reply(E.GET_RECENT_REPORTS, [emsReport]);
    await service.initialize();
    assert.equal(service.jobInfo.rank, 'Loading...');
    assert.equal(service.bulletins.length, 0);
    assert.equal(service.activeUnits.count, 0);
    assert.equal(service.recentReports[0].id, emsReport.id, 'Separately authorized report callback remains available');
    noPolice(service); service.destroy();
  });
  await test('empty Lua arrays clear previous collections rather than retaining stale records', async () => {
    const { service } = await ready();
    const data = payload();
    for (const key of ['activeWarrants', 'activeBolos', 'openCases', 'bulletins', 'upcomingHearings', 'recentDispatches']) data[key] = {};
    reply(E.GET_DASHBOARD, data); reply(E.GET_RECENT_REPORTS, {});
    await service.loadInitialData();
    assert.equal(service.bulletins.length, 0); assert.equal(service.upcomingHearings.length, 0);
    assert.equal(service.recentReports.length, 0); assert.equal(service.recentDispatches.length, 0);
    noPolice(service); service.destroy();
  });
  await test('raw warrant and BOLO updates never populate EMS or erase its authorized report totals', async () => {
    const { service } = await ready(); const before = requests.length;
    event(E.UPDATE_ACTIVE_WARRANTS, [{ name: 'SECRET' }]); event(E.UPDATE_ACTIVE_BOLOS, [{ name: 'SECRET' }]);
    assert.equal(requests.length, before);
    assert.equal(service.usageMetrics.totals.reports, 12);
    noPolice(service); service.destroy();
  });
  await test('EMS replaces unscoped shared updates through the authoritative aggregate', async () => {
    const { service } = await ready();
    for (const name of [E.UPDATE_JOB_DATA, E.UPDATE_REPORT_STATISTICS, E.UPDATE_TIME_STATISTICS, E.UPDATE_BULLETINS, E.UPDATE_ACTIVE_UNITS, E.UPDATE_USAGE_METRICS]) {
      reply(E.GET_DASHBOARD, payload());
      event(name, { rank: 'POLICE', count: 999, totalThisWeek: 999, content: 'SECRET' });
      await flush();
      assert.equal(service.jobInfo.rank, 'Paramedic'); assert.equal(service.activeUnits.count, 5);
      assert.equal(service.reportsInfo.totalThisWeek, 6); noPolice(service);
    }
    service.destroy();
  });
  await test('simultaneous unscoped EMS updates share one pending scoped refresh', async () => {
    const { service } = await ready(); const before = requests.length;
    const pending = deferred(E.GET_DASHBOARD);
    event(E.UPDATE_USAGE_METRICS, { totals: { arrests: 999 } }); event(E.UPDATE_ACTIVE_UNITS, { count: 999 });
    assert.equal(requests.length, before + 1);
    pending.resolve(payload()); await flush();
    assert.equal(service.activeUnits.count, 5); noPolice(service); service.destroy();
  });
  await test('EMS report pushes refetch scoped report data instead of storing their raw contents', async () => {
    const { service } = await ready();
    reply(E.GET_RECENT_REPORTS, [emsReport]); event(E.UPDATE_RECENT_REPORTS, [{ title: 'SECRET POLICE REPORT' }]);
    await flush(); assert.equal(service.recentReports[0].title, emsReport.title); service.destroy();
  });
  await test('EMS dispatch pushes and external setters refetch authorized calls', async () => {
    const { service } = await ready();
    reply(E.GET_RECENT_DISPATCHES, [{ id: 'EMS-NEW' }]); event(E.UPDATE_RECENT_DISPATCHES, [{ id: 'POLICE CALL' }]);
    await flush(); assert.equal(service.recentDispatches[0].id, 'EMS-NEW');
    reply(E.GET_RECENT_DISPATCHES, [{ id: 'EMS-SETTER' }]); service.setRecentDispatches([{ id: 'POLICE SETTER' }]);
    await flush(); assert.equal(service.recentDispatches[0].id, 'EMS-SETTER'); service.destroy();
  });
  await test('failed scoped EMS dispatch refresh clears stale calls', async () => {
    const { service } = await ready(); const pending = deferred(E.GET_RECENT_DISPATCHES);
    event(E.UPDATE_RECENT_DISPATCHES, [{ id: 'POLICE CALL' }]); pending.reject(new Error('Unavailable'));
    await flush(); assert.equal(service.recentDispatches.length, 0); service.destroy();
  });
  await test('a delayed police aggregate cannot populate a newly selected EMS context', async () => {
    const { service, setJobType } = make('leo'); const pending = deferred(E.GET_DASHBOARD);
    const loading = service.initialize(); setJobType('ems'); pending.resolve(payload()); await loading;
    assert.equal(service.jobInfo.rank, 'Loading...'); assert.equal(service.recentReports.length, 0);
    noPolice(service); service.destroy();
  });
  await test('a delayed police recent-report response is discarded after domain change', async () => {
    const { service, setJobType } = make('leo'); reply(E.GET_DASHBOARD, payload());
    const pending = deferred(E.GET_RECENT_REPORTS); const loading = service.initialize(); await flush();
    setJobType('ems'); pending.resolve([{ title: 'POLICE REPORT' }]); await loading;
    assert.equal(service.recentReports.length, 0); noPolice(service); service.destroy();
  });
  await test('same-interface EMS job changes immediately hide prior job records and refresh safely', async () => {
    const { service, setContextKey } = await ready();
    setContextKey('CID-A/HOSPITAL-B/0/on-duty');
    assert.equal(service.bulletins.length, 0); assert.equal(service.recentReports.length, 0);
    assert.equal(service.recentDispatches.length, 0); assert.equal(service.activeUnits.count, 0);
    assert.equal(service.upcomingHearings.length, 0); assert.equal(service.usageMetrics.totals.reports, 0);
    const next = payload(); next.bulletins = [{ id: 8, content: 'Hospital B bulletin' }];
    reply(E.GET_DASHBOARD, next); reply(E.GET_RECENT_REPORTS, [{ title: 'Hospital B report' }]);
    await service.initialize();
    assert.equal(service.bulletins[0].content, 'Hospital B bulletin');
    assert.equal(service.recentReports[0].title, 'Hospital B report'); noPolice(service); service.destroy();
  });
  await test('a delayed EMS aggregate cannot populate another character or job in the same interface', async () => {
    const { service, setContextKey } = make(); const pending = deferred(E.GET_DASHBOARD);
    const loading = service.initialize(); setContextKey('CID-B/HOSPITAL-B/0/on-duty');
    pending.resolve(payload()); await loading;
    assert.equal(service.bulletins.length, 0); assert.equal(service.jobInfo.rank, 'Loading...');
    assert.equal(service.recentReports.length, 0); noPolice(service); service.destroy();
  });
  await test('a delayed EMS report response cannot populate another character or job in the same interface', async () => {
    const { service, setContextKey } = make(); reply(E.GET_DASHBOARD, payload());
    const pending = deferred(E.GET_RECENT_REPORTS); const loading = service.initialize(); await flush();
    setContextKey('CID-B/HOSPITAL-B/0/on-duty'); pending.resolve([emsReport]); await loading;
    assert.equal(service.bulletins.length, 0); assert.equal(service.recentReports.length, 0);
    assert.equal(service.recentDispatches.length, 0); noPolice(service); service.destroy();
  });
  await test('destroyed dashboards ignore pending data and live events', async () => {
    const { service } = make(); const pending = deferred(E.GET_DASHBOARD); const loading = service.initialize();
    service.destroy(); pending.resolve(payload()); await loading;
    const before = requests.length; event(E.UPDATE_USAGE_METRICS, payload().usageMetrics);
    assert.equal(requests.length, before); assert.equal(service.recentReports.length, 0); noPolice(service);
  });
  await test('an older malformed response cannot clear a newer valid EMS snapshot', async () => {
    const { service } = await ready(); const first = deferred(E.GET_DASHBOARD); const older = service.loadInitialData();
    const second = deferred(E.GET_DASHBOARD); const latest = service.loadInitialData();
    reply(E.GET_RECENT_REPORTS, [emsReport]); second.resolve(payload()); await latest;
    reply(E.GET_RECENT_REPORTS, [emsReport]); first.resolve({ activeWarrants: [{ name: 'POLICE' }] }); await older;
    assert.equal(service.jobInfo.rank, 'Paramedic'); assert.equal(service.activeUnits.count, 5); noPolice(service); service.destroy();
  });
  await test('failed EMS aggregate refresh clears its previous authorized snapshot', async () => {
    const { service } = await ready(); const pending = deferred(E.GET_DASHBOARD);
    event(E.UPDATE_USAGE_METRICS, { totals: { arrests: 999 } }); pending.reject(new Error('Unavailable'));
    await flush(); assert.equal(service.activeUnits.count, 0); assert.equal(service.bulletins.length, 0); noPolice(service); service.destroy();
  });
  await test('LEO aggregate and raw live updates preserve existing dashboard behavior', async () => {
    const { service } = await ready('leo');
    assert.equal(service.activeWarrants[0].name, 'POLICE WARRANT'); assert.equal(service.activeBolos[0].name, 'POLICE BOLO');
    assert.equal(service.openCases[0].title, 'POLICE INVESTIGATION'); assert.equal(service.usageMetrics.impound.outstanding, 4321);
    const before = requests.length;
    event(E.UPDATE_ACTIVE_WARRANTS, [{ name: 'LEO UPDATE' }]); event(E.UPDATE_RECENT_REPORTS, [{ title: 'LEO REPORT' }]);
    event(E.UPDATE_USAGE_METRICS, payload().usageMetrics);
    assert.equal(service.activeWarrants[0].name, 'LEO UPDATE'); assert.equal(service.recentReports[0].title, 'LEO REPORT');
    assert.equal(requests.length, before); service.destroy();
  });
  await test('DOJ retains its existing non-EMS aggregate contract', async () => {
    const { service } = make('doj'); const data = payload(); delete data.dashboardDomain;
    reply(E.GET_DASHBOARD, data); reply(E.GET_RECENT_REPORTS, [{ title: 'Court filing' }]); await service.initialize();
    assert.equal(service.activeWarrants[0].name, 'POLICE WARRANT'); assert.equal(service.recentReports[0].title, 'Court filing');
    assert.equal(service.openCases[0].title, 'POLICE INVESTIGATION'); service.destroy();
  });
  await test('EMS browser preview contains no fictional police or impound data', async () => {
    const { service } = make('ems', true); await service.initialize();
    assert.equal(requests.length, 0); assert.equal(service.recentReports.length, 0); assert.equal(service.recentDispatches.length, 0);
    assert.equal(service.jobInfo.rank, 'EMS Personnel'); noPolice(service); service.destroy();
  });
  await test('LEO browser preview keeps its established sample dashboard', async () => {
    const { service } = make('leo', true); await service.initialize();
    assert.equal(service.activeWarrants.length, 2); assert.match(service.recentReports[0].title, /Armed Robbery/);
    assert.equal(service.usageMetrics.impound.held, 6); service.destroy();
  });
  await test('Dashboard supplies live job context and excludes the EMS impound widget', () => {
    const page = read('web/src/pages/Dashboard.svelte');
    assert.match(page, /createDashboardService\(\(\) => jobType, \(\) => dashboardContext\)/);
    assert.match(page, /playerData\?\.citizenid/); assert.match(page, /playerData\?\.job\?\.name/);
    assert.match(page, /context === initializedDashboardContext/);
    assert.match(page, /\{#if jobType !== 'ems' && \(impound\.held/);
    assert.match(page, /jobType === 'ems' \? 'Upcoming Appointments' : 'Upcoming Hearings'/);
    compiler.compile(page, { filename: 'web/src/pages/Dashboard.svelte', generate: 'client' });
  });
  console.log(`EMS dashboard frontend: ${passed} tests passed; production service, transport/events mocked, no files emitted.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
