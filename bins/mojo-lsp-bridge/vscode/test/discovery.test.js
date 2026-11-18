const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');
const { findServer } = require('../discovery');

test('selects nearest project environment, then PATH; explicit overrides win', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'mojo discovery '));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  function install(relative) {
    const server = path.join(root, relative, 'bin/mojo-lsp-server');
    fs.mkdirSync(path.dirname(server), { recursive: true });
    fs.writeFileSync(server, '#!/bin/sh\nexit 0\n', { mode: 0o755 });
    return server;
  }
  const global = install('global');
  const searchPath = path.dirname(global);
  assert.equal(findServer(root, '', searchPath), global);
  const parent = install('.pixi/envs/default');
  assert.equal(findServer(path.join(root, 'child/src'), '', searchPath), parent);
  const venv = install('child/.venv');
  assert.equal(findServer(path.join(root, 'child/src'), '', searchPath), venv);
  const pixi = install('child/.pixi/envs/default');
  assert.equal(findServer(path.join(root, 'child/src'), '', searchPath), pixi);
  assert.equal(findServer(path.join(root, 'child'), global, searchPath), global);
  fs.chmodSync(pixi, 0o644);
  assert.equal(findServer(path.join(root, 'child/src'), '', searchPath), venv);
  assert.throws(() => findServer(root, pixi, searchPath), /absolute path to an executable/);
  assert.throws(() => findServer(root, 'relative/server', searchPath), /absolute path/);
  fs.rmSync(parent);
  assert.throws(() => findServer(root, '', ''), /No mojo-lsp-server found/);
});
