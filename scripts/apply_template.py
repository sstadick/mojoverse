"""Add the documentation overlay to a Hat-created library without overwrites."""
import argparse
from pathlib import Path
import subprocess
import tomllib

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("project", type=Path)
parser.add_argument("package", help="Importable Mojo package name, e.g. mojo_example")
args = parser.parse_args()
if not args.package.isidentifier():
    parser.error("package must be a Mojo identifier")
project = args.project.resolve()
manifest = project / "pixi.toml"
data = tomllib.loads(manifest.read_text())
if "docs" in data.get("tasks", {}):
    parser.error("project already has a docs task; integrate the template manually")
template = Path(__file__).resolve().parents[1] / "templates/library"
files = sorted(path for path in template.rglob("*") if path.is_file())
for source in files:
    target = project / source.relative_to(template)
    if target.exists():
        parser.error(f"refusing to overwrite {target}")
for source in files:
    target = project / source.relative_to(template)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(source.read_text().replace("__PACKAGE__", args.package))
subprocess.run(
    ["pixi", "task", "add", "--manifest-path", str(manifest), "docs", "python scripts/docs.py"],
    check=True,
)
print("Added executable docs and artifact-only CI. Review docs/index.md before running pixi run docs.")
