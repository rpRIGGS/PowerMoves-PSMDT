// Run from the repository root: node tests/basics/navigation_regression.cjs
// Exercises production navigation constants and component policy declarations.
// Management rendering uses its actual compiled SSR component with child markers.
// No browser, FiveM, database, network or generated files are involved.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname, '../..');
const ts = require(path.join(root, 'web/node_modules/typescript'));
const compiler = require(path.join(root, 'web/node_modules/svelte/compiler'));
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
function transpile(source) {
  return ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText;
}
function constants(file) {
  const exports = {};
  new Function('exports', transpile(read(file)))(exports);
  return exports;
}
function script(file) {
  const found = read(file).match(/<script[^>]*>([\s\S]*?)<\/script>/);
  assert.ok(found, `Missing component script: ${file}`);
  return found[1];
}
// Extract declarations by AST name rather than reimplementing their behavior.
function extract(file, names) {
  const source = script(file);
  const ast = ts.createSourceFile(file + '.ts', source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
  const selected = ast.statements.filter(statement =>
    ts.isFunctionDeclaration(statement) && names.includes(statement.name?.text) ||
    ts.isVariableStatement(statement) && statement.declarationList.declarations.some(item => ts.isIdentifier(item.name) && names.includes(item.name.text)));
  assert.equal(selected.length, names.length, `Missing policy declaration in ${file}`);
  return selected.map(statement => statement.getText(ast)).join('\n');
}
const navigation = constants('web/src/constants/index.ts');
const { TAB_VISIBILITY_KEYS } = constants('web/src/constants/management.ts');
const pagePolicy = extract('web/src/components/ContentArea.svelte', ['PAGE_PERMISSIONS', 'DOJ_SHARED_PAGES', 'canAccessPage']);
const hiddenPolicy = extract('web/src/components/NavigationPills.svelte', ['isTabHidden']);
function auth(jobType = 'leo', permissions = [], extra = {}) {
  const granted = new Set(permissions);
  return { jobType, role: jobType, hasPermission: key => granted.has(key), hasAnyPermission: (...keys) => keys.some(key => granted.has(key)), hasRawPermission: key => granted.has(key), ...extra };
}
function canAccess(service, page) {
  return new Function('authService', transpile(pagePolicy) + ';return canAccessPage;')(service)(page);
}
function isHidden(service, tab) {
  return new Function('authService', 'TAB_VISIBILITY_KEYS', transpile(hiddenPolicy) + ';return isTabHidden;')(service, TAB_VISIBILITY_KEYS)(tab);
}
function managementPolicy(service, selected = null) {
  const file = 'web/src/pages/Management.svelte';
  const ast = ts.createSourceFile(file + '.ts', script(file), ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
  const printer = ts.createPrinter();
  const statements = ast.statements.filter(statement => ts.isTypeAliasDeclaration(statement) || ts.isFunctionDeclaration(statement) ||
    ts.isVariableStatement(statement) && statement.declarationList.declarations.every(item => ts.isIdentifier(item.name)));
  const source = statements.map(statement => {
    if (ts.isVariableStatement(statement)) {
      const declarations = statement.declarationList.declarations.map(item => {
        if (item.name.text !== 'view') return item;
        return ts.factory.updateVariableDeclaration(item, item.name, item.exclamationToken, item.type, ts.factory.createIdentifier('__selectedView'));
      });
      statement = ts.factory.updateVariableStatement(statement, statement.modifiers, ts.factory.updateVariableDeclarationList(statement.declarationList, declarations));
    }
    return printer.printNode(ts.EmitHint.Unspecified, statement, ast);
  }).join('\n');
  assert.ok(source.includes('permittedTabs') && source.includes('activeView'), 'Actual permitted selection policy must exist');
  const derived = value => value;
  derived.by = callback => callback();
  return new Function('authService', '__selectedView', '$derived', '$state', transpile(source) + ';return { permittedTabs, activeView };')(service, selected, derived, value => value);
}
let passed = 0;
async function test(name, run) {
  await run();
  passed++;
  console.log(`PASS ${name}`);
}
async function main() {
  await test('DOJ Preferences and Bulletin Board both have reachable sidebar groups', () => {
    const tabs = new Set(navigation.getTabsForJob('doj').map(item => item.name));
    const grouped = new Set(navigation.DOJ_NAV_GROUPS.flatMap(group => group.tabs));
    for (const tab of ['Preferences', 'Bulletin Board']) {
      assert.ok(tabs.has(tab));
      assert.ok(grouped.has(tab));
      assert.ok(navigation.TAB_TO_COMPONENT_MAP[tab]);
    }
  });
  await test('personal Preferences do not require department administration', () => {
    for (const job of ['leo', 'doj', 'ems']) assert.equal(canAccess(auth(job), 'settings'), true);
  });
  await test('removing Preferences restriction does not open operational record pages', () => {
    const service = auth('ems');
    for (const page of ['reports', 'citizens', 'cases', 'evidence', 'warrants', 'management', 'calendar']) assert.equal(canAccess(service, page), false, page);
  });
  await test('existing DOJ shared-record reads remain separate from the AG role', () => {
    assert.equal(canAccess(auth('doj'), 'reports'), true);
    assert.equal(canAccess(auth('doj', [], { role: 'attorney_general' }), 'reports'), false);
    assert.equal(canAccess(auth('doj', ['reports_view'], { role: 'attorney_general' }), 'reports'), true);
  });
  await test('newly connected management entries honor their existing single-role grants', () => {
    for (const permission of ['management_tags', 'sop_manage', 'fto_manage']) assert.equal(canAccess(auth('leo', [permission]), 'management'), true, permission);
    assert.equal(canAccess(auth('leo'), 'management'), false);
  });
  await test('bulletin visibility uses the persisted canonical underscore key', () => {
    assert.equal(isHidden(auth('leo', ['tab_hidden_bulletin_board']), 'Bulletin Board'), true);
    assert.equal(isHidden(auth('leo', ['tab_hidden_bulletin board']), 'Bulletin Board'), false);
    assert.equal(isHidden(auth('doj'), 'Bulletin Board'), false);
  });
  await test('all configured visibility keys match their actual navigation tabs', () => {
    for (const item of TAB_VISIBILITY_KEYS) {
      assert.equal(isHidden(auth('leo', [item.key]), item.tabName), true, item.tabName);
      assert.equal(isHidden(auth('leo', [item.key]), 'Preferences'), false);
    }
  });
  await test('unlisted multiword visibility keys normalize spaces consistently', () => {
    assert.equal(isHidden(auth('leo', ['tab_hidden_legal_documents']), 'Legal Documents'), true);
    assert.equal(isHidden(undefined, 'Reports'), false);
  });
  await test('government retains its isolated personnel home instead of operational tabs', () => {
    assert.deepEqual(navigation.getTabsForJob('gov').map(item => item.name), ['Dashboard']);
    const content = read('web/src/components/ContentArea.svelte');
    assert.match(content, /authService\.isAuthorized\s*&&\s*authService\.interfaceId\s*===\s*['"]sagov['"][\s\S]*?<Government\s/);
  });
  await test('fire and hospital interface identities remain distinct while sharing EMS pages', () => {
    assert.equal(navigation.INTERFACE_INFO.safr.name, 'SAFR.net');
    assert.equal(navigation.INTERFACE_INFO.sams.name, 'SAMS.net');
    assert.notEqual(navigation.INTERFACE_INFO.safr.icon, navigation.INTERFACE_INFO.sams.icon);
    const tabs = navigation.getTabsForJob('ems').map(item => item.name);
    for (const tab of ['Dashboard', 'Reports', 'Roster', 'Calendar', 'Preferences']) assert.ok(tabs.includes(tab));
    // Hospital training inherits the shared FTO workflow; judicial and LEO-only tabs remain excluded.
    assert.ok(tabs.includes('FTO'));
    for (const tab of ['Court Orders', 'Warrant Review', 'PPR']) assert.ok(!tabs.includes(tab));
  });
  await test('management opens the first actually permitted section rather than Bulletins', () => {
    for (const [permission, expected] of [['management_activity', 'activity'], ['management_permissions', 'permissions'], ['management_tags', 'tags'], ['sop_manage', 'sop'], ['fto_manage', 'fto']]) {
      const policy = managementPolicy(auth('leo', [permission]));
      assert.equal(policy.activeView, expected);
      assert.ok(policy.permittedTabs.every(tab => tab.permission === permission));
    }
  });
  await test('permitted user selections survive while revoked selections are replaced', () => {
    const service = auth('leo', ['management_activity', 'management_tags']);
    assert.equal(managementPolicy(service, 'tags').activeView, 'tags');
    assert.equal(managementPolicy(auth('leo', ['management_activity']), 'tags').activeView, 'activity');
  });
  await test('no management permissions produces no mounted section', () => {
    const policy = managementPolicy(auth('leo'), 'bulletins');
    assert.equal(policy.activeView, null);
    assert.deepEqual(policy.permittedTabs, []);
  });
  await test('management keeps existing EMS and DOJ hidden sections unavailable', () => {
    assert.equal(managementPolicy(auth('ems', ['management_settings']), 'jailfines').permittedTabs.some(tab => tab.key === 'jailfines'), false);
    assert.equal(managementPolicy(auth('doj', ['fto_manage', 'sop_manage']), 'fto').activeView, null);
    assert.equal(managementPolicy(auth('doj', ['management_permissions'])).activeView, 'permissions');
  });

  const runtime = await import(pathToFileURL(path.join(root, 'web/node_modules/svelte/src/internal/server/index.js')).href);
  const { render } = await import(pathToFileURL(path.join(root, 'web/node_modules/svelte/src/server/index.js')).href);
  const compiled = compiler.compile(read('web/src/pages/Management.svelte'), { filename: 'web/src/pages/Management.svelte', generate: 'server' });
  const exports = {};
  new Function('require', 'exports', transpile(compiled.js.code))(id => {
    if (id === 'svelte/internal/server') return runtime;
    if (/\/Management\w+\.svelte$/.test(id)) {
      const name = path.basename(id, '.svelte');
      return { default: payload => { payload.out += `<div data-management-section="${name}"></div>`; } };
    }
    throw new Error(`Unexpected compiled management import ${id}`);
  }, exports);
  function rendered(service) { return render(exports.default, { props: { authService: service } }).body; }
  await test('actual Management component renders an allowed activity panel without denied Bulletins', () => {
    const html = rendered(auth('leo', ['management_activity']));
    assert.match(html, /data-management-section="ManagementActivity"/);
    assert.doesNotMatch(html, /data-management-section="ManagementBulletins"/);
  });
  await test('actual Management component renders no unauthorized section without grants', () => {
    const html = rendered(auth('leo'));
    assert.doesNotMatch(html, /data-management-section=/);
    assert.match(html, /No management sections/);
  });
  await test('actual Management component does not expose EMS or DOJ hidden sections', () => {
    assert.doesNotMatch(rendered(auth('ems', ['management_settings'])), /data-management-section="ManagementJailFines"/);
    assert.doesNotMatch(rendered(auth('doj', ['sop_manage', 'fto_manage'])), /data-management-section=/);
  });
  await test('missing authentication cannot select an administrative component', () => {
    const html = rendered(undefined);
    assert.doesNotMatch(html, /data-management-section=/);
  });
  console.log(`Basic interface navigation: ${passed} tests passed; production constants/policies and compiled Management component, no files emitted.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
