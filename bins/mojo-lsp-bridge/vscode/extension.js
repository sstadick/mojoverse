const vscode = require('vscode');
const path = require('node:path');
const { LanguageClient } = require('vscode-languageclient/node');
const { findServer } = require('./discovery');

const clients = new Map();
let pending = Promise.resolve();

async function stopClients() {
  await Promise.all([...clients.values()].map(client => client.stop()));
  clients.clear();
}

function activate(context) {
  const output = vscode.window.createOutputChannel('Mojo LSP Bridge');
  context.subscriptions.push(output);

  async function start(document) {
    if (document.languageId !== 'mojo' || document.uri.scheme !== 'file') return;
    for (const id of ['modular-mojotools.vscode-mojo', 'modular-mojotools.vscode-mojo-nightly']) {
      if (vscode.extensions.getExtension(id)) {
        throw new Error(`Disable ${id} for this workspace and reload to avoid running two Mojo servers. This extension does not replace its debugger or run commands.`);
      }
    }
    const folder = vscode.workspace.getWorkspaceFolder(document.uri);
    // Navigating into downloaded stdlib sources must not start another compiler.
    if (!folder && vscode.workspace.workspaceFolders?.length) return;
    if (folder && vscode.workspace.workspaceFolders.some(other => other !== folder && (
      other.uri.fsPath.startsWith(path.join(folder.uri.fsPath, path.sep)) ||
      folder.uri.fsPath.startsWith(path.join(other.uri.fsPath, path.sep))
    ))) {
      throw new Error('Use non-overlapping workspace folders: add the Mojo projects, not both a project and its parent folder.');
    }
    const root = folder ? folder.uri : vscode.Uri.file(path.dirname(document.uri.fsPath));
    const key = root.toString();
    if (clients.has(key)) return;
    const config = vscode.workspace.getConfiguration('mojoBridge', document.uri);
    const server = findServer(root.fsPath, config.get('serverPath'));
    const client = new LanguageClient('mojoBridge', `Mojo (${folder?.name || root.fsPath})`, {
      command: config.get('pythonPath'),
      args: [context.asAbsolutePath('dist/mojo_lsp.py'), '--server', server,
        '--workspace', root.fsPath, '--cache', context.globalStorageUri.fsPath],
      options: { cwd: root.fsPath },
    }, {
      documentSelector: [{ language: 'mojo', scheme: 'file', pattern: new vscode.RelativePattern(root, '**/*') }],
      workspaceFolder: folder,
      initializationOptions: { zed_mojo: config.get('options') },
      outputChannel: output,
    });
    output.appendLine(`Workspace: ${root.fsPath}\nNative server: ${server}`);
    try {
      await client.start();
      clients.set(key, client);
    } catch (error) {
      await client.dispose();
      throw error;
    }
  }

  function report(error) {
    output.appendLine(String(error));
    void vscode.window.showErrorMessage(`Mojo LSP Bridge: ${error.message}`);
  }
  // Serialize starts and restarts so rapid document opens cannot spawn duplicates.
  function enqueue(operation) {
    pending = pending.then(operation).catch(report);
    return pending;
  }
  async function startOpenDocuments() {
    for (const document of vscode.workspace.textDocuments) await start(document).catch(report);
  }
  const restart = () => enqueue(async () => {
    await stopClients();
    await startOpenDocuments();
  });
  context.subscriptions.push(
    vscode.commands.registerCommand('mojoBridge.restart', restart),
    vscode.workspace.onDidOpenTextDocument(document => enqueue(() => start(document))),
    vscode.workspace.onDidChangeWorkspaceFolders(restart),
    vscode.workspace.onDidChangeConfiguration(event => {
      if (event.affectsConfiguration('mojoBridge')) void restart();
    }),
  );
  return enqueue(startOpenDocuments);
}

async function deactivate() {
  await pending;
  await stopClients();
}

module.exports = { activate, deactivate };
