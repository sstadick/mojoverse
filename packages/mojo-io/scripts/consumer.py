"""Build both packages, then run all I/O tests from installed artifacts without -I."""
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import tomllib

root = Path(__file__).resolve().parents[1]
config = tomllib.loads((root / "pixi.toml").read_text())
channels = json.dumps(config["workspace"]["channels"])
target = {("Linux", "x86_64"): "linux-64", ("Linux", "aarch64"): "linux-aarch64",
          ("Darwin", "arm64"): "osx-arm64"}[(platform.system(), platform.machine())]
with tempfile.TemporaryDirectory(prefix="mojo-io-consumer-") as directory:
    work = Path(directory)
    output = work / "packages"
    output.mkdir()
    for name in ("mojo-bstr", "mojo-io"):
        subprocess.run(["pixi", "build", "--path", str(root.parent / name / "pixi.toml"),
                        "--output-dir", str(output)], cwd=work, check=True)
    dependencies = []
    for name in ("mojo-bstr", "mojo-io"):
        package, = output.glob(f"{name}-*.conda")
        digest = hashlib.sha256(package.read_bytes()).hexdigest()
        dependencies.append(
            f"{name} = {{ url = {json.dumps(package.as_uri())}, sha256 = \"{digest}\" }}"
        )
    consumer = work / "consumer"
    consumer.mkdir()
    (consumer / "pixi.toml").write_text(
        '[workspace]\nname = "io-consumer"\n'
        f'channels = {channels}\n'
        f'platforms = ["{target}"]\n[dependencies]\n' + "\n".join(dependencies) + "\n"
    )
    shutil.copyfile(root / "tests/test_buffered.mojo", consumer / "test.mojo")
    env = os.environ.copy()
    for key in ("MOJO_PATH", "MOJO_INCLUDE_PATH", "MODULAR_MOJO_IMPORT_PATH",
                "PIXI_WORKSPACE_MANIFEST", "PIXI_PROJECT_MANIFEST", "CONDA_PREFIX"):
        env.pop(key, None)
    env["PIXI_CACHE_DIR"] = str(work / "consumer-cache")
    subprocess.run(["pixi", "run", "--manifest-path", str(consumer / "pixi.toml"),
                    "mojo", "run", "-D", "ASSERT=all", "test.mojo"], cwd=consumer, env=env, check=True)
    for module in ("bstr", "io"):
        assert (consumer / f".pixi/envs/default/lib/mojo/{module}.mojoc").is_file()
    print("Clean artifact-only consumer passed all I/O tests with installed bstr and I/O modules")
