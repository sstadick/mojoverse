# Mojo LSP Bridge for VS Code

Runs [Mojo LSP Bridge](https://github.com/sstadick/mojo-lsp-bridge) around your project's native Mojo language server. Adds matching stdlib source discovery/downloads, missing-import quick fixes, and crash recovery. Completion, diagnostics, hover, navigation, and semantic highlighting come from the native server. Formatting uses the matching environment's `mblack`.

## Install

1. Have Mojo, Python 3.10+, and Git installed on the development machine. Run `pixi install` for an existing Pixi project.
2. **Disable the official Mojo (and Mojo Nightly, if installed) extension for this workspace**, then reload VS Code. The bridge extension refuses to start alongside those extensions to avoid duplicate servers. It does not provide their debugger, SDK management, or run commands. The official extension already provides formatting; that is not a new VS Code feature here.
3. Run **Extensions: Install from VSIX…** and select `mojo-lsp-bridge-0.1.0.vsix`.
4. Open your project folder and a `.mojo` or `.🔥` file.

For Remote-SSH, WSL, or dev containers, install the VSIX in the remote workspace, not just locally. Python, Mojo, Git, and the source cache live on that remote machine. Native Windows Mojo is not supported; use WSL. Untrusted and virtual workspaces are unsupported because the extension executes project-installed tools.

One server runs per workspace folder. Each folder searches itself and its ancestors for `.pixi/envs/default/bin/mojo-lsp-server` or `.venv/bin/mojo-lsp-server`, then falls back to `PATH`. For monorepos with separate environments, open each project as its own workspace folder; overlapping workspace folders (a parent and its child) are unsupported. No environment activation is needed. With no folder open, standalone files search from their containing directory. Unsaved, untitled files need to be saved first.

Sources download on first use and are cached in VS Code's extension global storage. Published nightlies use their exact release-pinning commit. Offline first use or custom compilers need explicit matching sources.

## Settings

Normal Pixi projects need no settings. Optional workspace/folder settings:

```json
{
  "mojoBridge.serverPath": "/absolute/path/to/mojo-lsp-server",
  "mojoBridge.pythonPath": "python3",
  "mojoBridge.options": {
    "stdlib_path": "/path/to/modular/Mojo/stdlib",
    "download_stdlib": false,
    "import_paths": ["packages"],
    "restart_limit": 2
  }
}
```

Relative source/import paths resolve against the workspace folder. Settings changes restart the servers. Use **Mojo LSP Bridge: Restart Language Servers** after changing project dependencies. Startup and compiler messages appear in **Output → Mojo LSP Bridge**.

Use **Go to Definition**, **Quick Fix…**, and **Format Document** as usual. To format on save:

```json
{
  "[mojo]": {
    "editor.defaultFormatter": "sstadick.mojo-lsp-bridge",
    "editor.formatOnSave": true
  }
}
```

## Build from source

From this repository's `vscode/` directory, with Node.js 22+:

```sh
npm ci
npm test
npm run package
```

The VSIX bundles the JavaScript client and canonical `../server/mojo_lsp.py`; users do not need Node.js, npm, Rust, or a checkout of this repository. No Marketplace publication is required.

Run the real VS Code extension-host test with an installed compiler. Sources download automatically; optionally set `MOJO_STDLIB_PATH` to a matching checkout to avoid the download:

```sh
MOJO_LSP_SERVER=/path/to/project/.pixi/envs/default/bin/mojo-lsp-server \
npm run test:integration
```

On headless Linux, prefix the command with `xvfb-run -a env`. This downloads VS Code and uses a disposable profile and two temporary project folders, without modifying your editor or project settings. It checks project/stdlib navigation, diagnostics, import edits, formatting unsaved buffers without touching disk, and restart with unsaved documents. Set `VSCODE_VERSION` to test a particular VS Code release instead of current stable.
