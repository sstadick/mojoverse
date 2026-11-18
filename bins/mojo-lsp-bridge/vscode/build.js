const { copyFileSync, existsSync, readFileSync, writeFileSync } = require('node:fs');
const path = require('node:path');

const result = require('esbuild').buildSync({
  entryPoints: [path.join(__dirname, 'extension.js')],
  outfile: path.join(__dirname, 'dist/extension.js'),
  bundle: true,
  metafile: true,
  platform: 'node',
  format: 'cjs',
  target: 'node18',
  external: ['vscode'],
});
copyFileSync(path.join(__dirname, '../server/mojo_lsp.py'), path.join(__dirname, 'dist/mojo_lsp.py'));
copyFileSync(path.join(__dirname, '../LICENSE'), path.join(__dirname, 'LICENSE'));
copyFileSync(path.join(__dirname, 'node_modules/vscode-languageclient/lib/node/terminateProcess.sh'), path.join(__dirname, 'dist/terminateProcess.sh'));

const packages = new Set(Object.keys(result.metafile.inputs)
  .map(input => input.match(/(?:^|\/)node_modules\/((?:@[^/]+\/)?[^/]+)/)?.[1]).filter(Boolean));
const notices = [...packages].sort().map(name => {
  const directory = path.join(__dirname, 'node_modules', name);
  const license = ['License.txt', 'LICENSE', 'LICENSE.md'].find(file => existsSync(path.join(directory, file)));
  if (!license) throw new Error(`Missing license for bundled dependency ${name}`);
  return `${name}\n\n${readFileSync(path.join(directory, license), 'utf8')}`;
});
writeFileSync(path.join(__dirname, 'dist/THIRD-PARTY-NOTICES.txt'), notices.join('\n\n---\n\n'));
