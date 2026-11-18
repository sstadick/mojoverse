const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { runTests } = require('@vscode/test-electron');

async function main() {
  const server = process.env.MOJO_LSP_SERVER;
  const stdlib = process.env.MOJO_STDLIB_PATH;
  if (!server || !path.isAbsolute(server)) throw new Error('Set MOJO_LSP_SERVER to the absolute path of an installed mojo-lsp-server.');
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'mojo-vscode-'));
  try {
    const folders = ['project one', 'project two'].map((name, index) => {
      const root = path.join(temporary, name);
      fs.mkdirSync(path.join(root, '.pixi/envs'), { recursive: true });
      fs.symlinkSync(path.dirname(path.dirname(server)), path.join(root, '.pixi/envs/default'), 'dir');
      fs.writeFileSync(path.join(root, 'helper.mojo'), `def helper() -> Int:\n    return ${index + 11}\n`);
      fs.writeFileSync(path.join(root, 'main.mojo'), 'from std.math import sin\nfrom helper import helper\n\ndef main():\n    print(sin(1.0), helper())\n');
      return { path: root };
    });
    const workspace = path.join(temporary, 'test.code-workspace');
    fs.writeFileSync(workspace, JSON.stringify({ folders, settings: {
      'mojoBridge.options': stdlib ? { stdlib_path: stdlib, download_stdlib: false } : {},
      'telemetry.telemetryLevel': 'off',
      'workbench.startupEditor': 'none',
    } }));
    await runTests({
      version: process.env.VSCODE_VERSION || 'stable',
      extensionDevelopmentPath: path.resolve(__dirname, '..'),
      extensionTestsPath: path.join(__dirname, 'suite.js'),
      launchArgs: [workspace, '--disable-extensions', '--disable-workspace-trust', '--skip-welcome',
        '--skip-release-notes', '--no-sandbox', '--disable-gpu',
        '--user-data-dir', path.join(temporary, 'user'),
        '--extensions-dir', path.join(temporary, 'extensions')],
    });
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
