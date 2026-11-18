"""Install through pixi-build-mojo in a fresh consumer, never adding source to -I."""
from pathlib import Path
import json
import os
import platform
import shutil
import subprocess
import tempfile
import tomllib

root = Path(__file__).resolve().parents[1]
manifest = tomllib.loads((root / "pixi.toml").read_text())
target = {("Linux", "x86_64"): "linux-64", ("Linux", "aarch64"): "linux-aarch64",
          ("Darwin", "arm64"): "osx-arm64"}[(platform.system(), platform.machine())]
with tempfile.TemporaryDirectory(prefix="mojo-bstr-consumer-") as directory:
    consumer = Path(directory)
    (consumer / "pixi.toml").write_text(f'''[workspace]
name = "bstr-consumer"
channels = {json.dumps(manifest['workspace']['channels'])}
platforms = ["{target}"]
preview = ["pixi-build"]
[dependencies]
mojo = {json.dumps(manifest['dependencies']['mojo'])}
mojo-bstr = {{ path = {json.dumps(str(root))} }}
[tasks]
check = "mojo run main.mojo"
''')
    shutil.copyfile(root / "examples/bytes.mojo", consumer / "main.mojo")
    env = os.environ.copy()
    for name in ("MOJO_PATH", "MOJO_INCLUDE_PATH", "MODULAR_MOJO_IMPORT_PATH",
                 "PIXI_PROJECT_MANIFEST", "PIXI_WORKSPACE_MANIFEST"):
        env.pop(name, None)
    subprocess.run(["pixi", "run", "--manifest-path", str(consumer / "pixi.toml"), "check"],
                   cwd=consumer, env=env, check=True)
    installed = list((consumer / ".pixi/envs/default/lib/mojo").glob("bstr.*"))
    assert installed, "built module missing from consumer prefix"
    print("Clean consumer installed", installed[0].name, "and passed the executable example")
