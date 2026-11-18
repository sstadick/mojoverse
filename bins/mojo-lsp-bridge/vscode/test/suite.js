const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vscode = require('vscode');

async function waitFor(description, operation) {
  const deadline = Date.now() + 60000;
  while (Date.now() < deadline) {
    const result = await operation();
    if (result) return result;
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  throw new Error(`Timed out waiting for ${description}`);
}

async function run() {
  const documents = await Promise.all(vscode.workspace.workspaceFolders.map(folder =>
    vscode.workspace.openTextDocument(vscode.Uri.joinPath(folder.uri, 'main.mojo'))));
  await vscode.extensions.getExtension('sstadick.mojo-lsp-bridge').activate();

  for (const document of documents) {
    assert.equal(document.languageId, 'mojo');
    await vscode.window.showTextDocument(document);
    for (const [line, column, expected] of [
      [0, 22, '/std/math/math.mojo'],
      [4, 21, path.join(path.dirname(document.uri.fsPath), 'helper.mojo')],
    ]) {
      const definitions = await waitFor(`definition ${expected}`, async () => {
        const locations = await vscode.commands.executeCommand('vscode.executeDefinitionProvider', document.uri, new vscode.Position(line, column));
        return locations?.length && locations;
      });
      assert.equal(definitions.length, 1, 'exactly one server should handle the document');
      const uri = definitions[0].targetUri || definitions[0].uri;
      assert.ok(uri.fsPath.endsWith(expected), uri.fsPath);
    }

    const original = fs.readFileSync(document.uri.fsPath, 'utf8');
    const replacement = new vscode.WorkspaceEdit();
    replacement.replace(document.uri, new vscode.Range(0, 0, document.lineCount, 0), 'def main():\n    print(  sqrt(4.0)  )\n');
    assert.ok(await vscode.workspace.applyEdit(replacement));
    await waitFor('unknown sqrt diagnostic', () => vscode.languages.getDiagnostics(document.uri).some(d => d.message.includes('sqrt')));
    const fixes = await waitFor('stdlib import quick fix', async () => {
      const actions = await vscode.commands.executeCommand('vscode.executeCodeActionProvider', document.uri, new vscode.Range(1, 12, 1, 16), vscode.CodeActionKind.QuickFix.value);
      const imports = actions?.filter(action => action.title === 'Import sqrt from std.math');
      return imports?.length && imports;
    });
    assert.equal(fixes.length, 1, 'duplicate servers must not offer duplicate fixes');
    assert.ok(await vscode.workspace.applyEdit(fixes[0].edit));
    assert.match(document.getText(), /^from std\.math import sqrt\n/);

    const edits = await vscode.commands.executeCommand('vscode.executeFormatDocumentProvider', document.uri, { tabSize: 4, insertSpaces: true });
    assert.ok(edits?.length, 'mblack must return edits for the unsaved buffer');
    const formatting = new vscode.WorkspaceEdit();
    formatting.set(document.uri, edits);
    assert.ok(await vscode.workspace.applyEdit(formatting));
    assert.match(document.getText(), /    print\(sqrt\(4\.0\)\)\n/);
    assert.ok(document.isDirty);
    assert.equal(fs.readFileSync(document.uri.fsPath, 'utf8'), original, 'formatting must not change the file on disk');
  }

  await vscode.commands.executeCommand('mojoBridge.restart');
  for (const document of documents) {
    const line = document.getText().split('\n').findIndex(value => value.includes('print(sqrt'));
    const definitions = await waitFor('definition after restart with unsaved edits', async () => {
      const locations = await vscode.commands.executeCommand('vscode.executeDefinitionProvider', document.uri, new vscode.Position(line, 11));
      return locations?.length && locations;
    });
    assert.equal(definitions.length, 1);
    assert.ok((definitions[0].targetUri || definitions[0].uri).fsPath.endsWith('/std/math/math.mojo'));
  }
  console.log('PASS: multi-root navigation, diagnostics, import fixes, unsaved formatting, and restart');
}

module.exports = { run };
