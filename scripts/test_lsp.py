"""Check the migrated LSP bridge and package its VS Code extension locally."""

from pathlib import Path
import os
import subprocess
import sys

root = Path(__file__).resolve().parents[1] / "bins/mojo-lsp-bridge"
if sys.argv[1:] == ["--integration"]:
    env = os.environ.copy()
    env["MOJO_LSP_SERVER"] = str(Path(env["CONDA_PREFIX"]) / "bin/mojo-lsp-server")
    env["PYTHONPATH"] = str(root / "tests")
    subprocess.run([sys.executable, "-m", "unittest",
                    "test_bridge.ZeroConfigurationIntegrationTests", "-v"], cwd=root, env=env, check=True)
    subprocess.run(["npm", "run", "test:integration"], cwd=root / "vscode", env=env, check=True)
    sys.exit(0)
commands = [
    ["cargo", "fmt", "--check"],
    ["cargo", "test", "--locked", "--lib"],
    [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v"],
    *[["bash", f"scripts/check-{name}.sh"] for name in
      ("snippets", "indents", "highlight-order", "runnables")],
]
for command in commands:
    subprocess.run(command, cwd=root, check=True)
for command in (["npm", "ci"], ["npm", "test"], ["npm", "run", "package"]):
    subprocess.run(command, cwd=root / "vscode", check=True)
