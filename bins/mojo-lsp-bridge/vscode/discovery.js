const fs = require('node:fs');
const path = require('node:path');

function executable(file) {
  try {
    fs.accessSync(file, fs.constants.X_OK);
    return fs.statSync(file).isFile();
  } catch {
    return false;
  }
}

function findServer(root, override = '', searchPath = process.env.PATH || '') {
  if (override) {
    if (!path.isAbsolute(override) || !executable(override)) {
      throw new Error('mojoBridge.serverPath must be an absolute path to an executable mojo-lsp-server.');
    }
    return override;
  }
  for (let directory = root; ; directory = path.dirname(directory)) {
    for (const environment of ['.pixi/envs/default', '.venv']) {
      const candidate = path.join(directory, environment, 'bin/mojo-lsp-server');
      if (executable(candidate)) return candidate;
    }
    if (directory === path.dirname(directory)) break;
  }
  for (const directory of searchPath.split(path.delimiter).filter(Boolean)) {
    const candidate = path.resolve(root, directory, 'mojo-lsp-server');
    if (executable(candidate)) return candidate;
  }
  throw new Error('No mojo-lsp-server found. Run pixi install, add it to PATH, or set mojoBridge.serverPath.');
}

module.exports = { findServer };
