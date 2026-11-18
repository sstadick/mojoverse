"""Test installed raylib bindings without a display, then compile every example."""

import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
package = root / "packages/mojo-raylib"
output = root / "target/raylib-tests"
output.mkdir(parents=True, exist_ok=True)
prefix = Path(os.environ["CONDA_PREFIX"])
link = ["-Xlinker", f"-L{prefix}/lib", "-Xlinker", "-lmojo_raylib_shim", "-Xlinker", "-lraylib",
        "-Xlinker", "-rpath", "-Xlinker", str(prefix / "lib")]
for source in [package / "tests/test_headless.mojo", *sorted((package / "examples").glob("*/main.mojo"))]:
    binary = output / source.parent.name
    subprocess.run(["mojo", "build", "-O3", "-D", "ASSERT=all", *link, str(source), "-o", str(binary)],
                   cwd=root, check=True)
    if source.name == "test_headless.mojo":
        subprocess.run([str(binary)], cwd=root, check=True)
print("PASS: installed raylib native calls and example compilation (no GUI execution)")
