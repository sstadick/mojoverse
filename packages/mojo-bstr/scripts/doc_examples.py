"""Execute the README's complete marked Mojo programs."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
examples = re.findall(r'```mojo \{doctest="([^"]+)" global=true\}\n(.*?)\n```',
                      (root / "README.md").read_text(), re.S)
assert examples, "no marked examples found"
with tempfile.TemporaryDirectory(prefix="bstr-docs-") as directory:
    for name, source in examples:
        path = Path(directory) / f"{name}.mojo"
        path.write_text(source)
        subprocess.run(["mojo", "run", "-I", str(root), str(path)], check=True)
        print(f"README example {name}: passed")
