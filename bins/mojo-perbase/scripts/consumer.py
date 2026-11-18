"""Build monorepo artifacts and test an installed, source-independent consumer."""
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import tomllib


def main():
    root = Path(__file__).resolve().parents[1]
    siblings = root.parents[1] / "packages"
    manifest = tomllib.loads((root / "pixi.toml").read_text())
    target = {
        ("Linux", "x86_64"): "linux-64",
        ("Linux", "aarch64"): "linux-aarch64",
        ("Darwin", "arm64"): "osx-arm64",
    }[(platform.system(), platform.machine())]
    env = os.environ.copy()
    for name in ("MOJO_PATH", "MOJO_INCLUDE_PATH", "MODULAR_MOJO_IMPORT_PATH",
                 "PIXI_PROJECT_MANIFEST", "PIXI_WORKSPACE_MANIFEST", "CONDA_PREFIX"):
        env.pop(name, None)
    packages = [siblings / "mojo-bstr", siblings / "mojo-libdeflate/native", siblings / "mojo-threads/native",
                siblings / "mojo-libdeflate", siblings / "mojo-threads",
                siblings / "mojo-bio", siblings / "mojopt", root / "native", root]
    with tempfile.TemporaryDirectory(prefix="perbase-consumer-") as tmp:
        consumer = Path(tmp)
        artifacts = consumer / "artifacts"
        artifacts.mkdir()
        for package in packages:
            subprocess.run(["pixi", "build", "--path", str(package / "pixi.toml"),
                            "--output-dir", str(artifacts)], cwd=consumer, env=env,
                           check=True, timeout=600)
        archives = sorted(artifacts.glob("*.conda"))
        assert len(archives) == len(packages), archives
        dependencies = {}
        for archive in archives:
            name = archive.name.rsplit("-", 2)[0]
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            dependencies[name] = {"url": archive.as_uri(), "sha256": digest}
        print(json.dumps({"platform": target, "artifacts": dependencies}, indent=2), flush=True)
        lines = ["[workspace]", 'name = "perbase-consumer"',
                 "channels = " + json.dumps(manifest["workspace"]["channels"]),
                 "platforms = " + json.dumps([target]), '[dependencies]',
                 "mojo = " + json.dumps(manifest["dependencies"]["mojo"])]
        for name, identity in dependencies.items():
            lines.append(f'{name} = {{ url = {json.dumps(identity["url"])}, '
                         f'sha256 = "{identity["sha256"]}" }}')
        (consumer / "pixi.toml").write_text("\n".join(lines) + "\n")
        # Same-version development artifacts must not come from the global cache.
        env["PIXI_CACHE_DIR"] = str(consumer / "cache")
        pixi = ["pixi", "run", "--manifest-path", str(consumer / "pixi.toml")]
        prefix = consumer / ".pixi/envs/default"
        features = []
        if target == "linux-64":
            features = ["--target-features=" + ",".join("-" + flag for flag in (
                "avx512f", "avx512bw", "avx512cd", "avx512dq", "avx512vl",
                "avx512ifma", "avx512vbmi", "avx512vbmi2", "avx512vnni",
                "avx512bitalg", "avx512vpopcntdq", "avx512fp16", "avx512bf16"))]
        tests = [(siblings / "mojo-threads/tests/test_worker.mojo", ["-lmojo_threads_native", "-lpthread"]),
                 (siblings / "mojo-libdeflate/tests/test_codec.mojo", ["-ldeflate"]),
                 (siblings / "mojo-bio/tests/test_sequence.mojo", ["-ldeflate"]),
                 (siblings / "mojo-bio/tests/test_fastx.mojo", ["-lz"])]
        for source, libraries in tests:
            shutil.copyfile(source, consumer / source.name)
            binary = consumer / source.stem
            link = ["-Xlinker", "-L" + str(prefix / "lib")]
            for library in libraries:
                link += ["-Xlinker", library]
            subprocess.run([*pixi, "mojo", "build", "-O3", "-D", "ASSERT=all",
                            *features, *link, source.name, "-o", str(binary)],
                           cwd=consumer, env=env, check=True, timeout=300)
            subprocess.run([*pixi, str(binary)], cwd=consumer, env=env, check=True, timeout=120)
        shutil.copyfile(root / "tests/smoke.py", consumer / "smoke.py")
        subprocess.run([*pixi, "python3", "smoke.py", "--binary", str(prefix / "bin/mojo-perbase")],
                       cwd=consumer, env=env, check=True, timeout=300)
        print("PASS installed application, reader, codec and workers without source include paths", flush=True)


if __name__ == "__main__":
    main()
