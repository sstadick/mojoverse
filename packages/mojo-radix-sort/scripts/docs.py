"""Build API docs and execute examples using the shared Mojoverse tools."""
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
tools = Path(os.environ.get("MOJOVERSE", root.parent.parent))
if not (tools / "pixi.toml").is_file():
    raise SystemExit("Set MOJOVERSE to the Mojoverse repository root.")
subprocess.run(
    ["pixi", "run", "--locked", "-e", "docs", "--manifest-path", str(tools / "pixi.toml"),
     "docs", str(root), "radix_sort", "--site", "--readme", "README.md",
     "--include", "NOTICE.md", "--include", "LICENSE"],
    check=True,
)
