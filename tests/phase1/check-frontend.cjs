// Syntax validation with existing local tools; does not install packages or emit files.
// Usage: node tests/phase1/check-frontend.cjs <svelte/compiler> <typescript> [git executable]
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const [sveltePath, typescriptPath, gitExecutable = 'git'] = process.argv.slice(2);
if (!sveltePath || !typescriptPath) {
  console.error('Provide paths to an existing Svelte compiler and TypeScript installation.');
  process.exit(2);
}
const compiler = require(path.resolve(sveltePath));
const ts = require(path.resolve(typescriptPath));
const root = path.resolve(__dirname, '../..');
function gitFiles(args) {
  return execFileSync(gitExecutable, args, { cwd: root, encoding: 'utf8', windowsHide: true })
    .split(/\r?\n/).filter(Boolean);
}
const files = [...new Set([
  ...gitFiles(['diff', '--name-only', '--diff-filter=ACMR', '--', 'web/src']),
  ...gitFiles(['ls-files', '--others', '--exclude-standard', '--', 'web/src']),
])].filter(file => /\.(svelte|ts)$/.test(file));
let failures = 0;
for (const file of files) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  try {
    if (file.endsWith('.svelte')) {
      compiler.compile(source, { filename: file, generate: 'client' });
    } else {
      const result = ts.transpileModule(source, {
        fileName: file,
        reportDiagnostics: true,
        compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext },
      });
      const errors = (result.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error);
      if (errors.length) throw new Error(errors.map(item => ts.flattenDiagnosticMessageText(item.messageText, '\n')).join('\n'));
      if (file.endsWith('.svelte.ts')) {
        compiler.compileModule(result.outputText, { filename: file.replace(/\.ts$/, '.js'), generate: 'client' });
      }
    }
    console.log(`PASS ${file}`);
  } catch (error) {
    failures++;
    console.error(`FAIL ${file}: ${error.message}`);
  }
}
console.log(`Validated ${files.length} changed frontend files; ${failures} syntax failures. Full dependency-aware type/build checks remain separate.`);
process.exitCode = failures ? 1 : 0;
