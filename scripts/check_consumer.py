"""Exercise pinned Git/subdirectory dependencies in an independent Pixi consumer."""

import argparse
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile
import tomllib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default="https://github.com/sstadick/mojoverse.git")
    parser.add_argument("--rev", required=True, help="Full committed revision, not a branch")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.rev):
        parser.error("--rev must be a full 40-character Git commit")
    target = {("Linux", "x86_64"): "linux-64", ("Linux", "aarch64"): "linux-aarch64",
              ("Darwin", "arm64"): "osx-arm64"}[(platform.system(), platform.machine())]
    env = os.environ.copy()
    for key in ("MOJO_PATH", "MOJO_INCLUDE_PATH", "MODULAR_MOJO_IMPORT_PATH", "MOJO_IMPORT_PATH",
                "MODULAR_HOME", "PIXI_WORKSPACE_MANIFEST", "PIXI_PROJECT_MANIFEST", "CONDA_PREFIX"):
        env.pop(key, None)
    with tempfile.TemporaryDirectory(prefix="mojoverse-consumer-") as tmp:
        work = Path(tmp)
        # Tests and package source must describe the same commit, including in CI.
        source = work / "source"
        subprocess.run(["git", "clone", "--quiet", "--no-checkout", args.repository, str(source)], check=True)
        subprocess.run(["git", "-C", str(source), "checkout", "--quiet", args.rev], check=True)
        consumer = work / "consumer"
        consumer.mkdir()
        config = tomllib.loads((source / "pixi.toml").read_text())
        lines = ['[workspace]', 'name = "mojoverse-consumer"',
                 'channels = ' + json.dumps(config["workspace"]["channels"]),
                 f'platforms = ["{target}"]', 'preview = ["pixi-build"]',
                 '[dependencies]', 'mojo = ' + json.dumps(config["dependencies"]["mojo"]),
                 'python = "3.12.*"']
        for name in ("mojo-io", "mojo-seqair", "mojo-threads", "mojo-perbase"):
            directory = "bins" if name == "mojo-perbase" else "packages"
            lines.append(f'{name} = {{ git = {json.dumps(args.repository)}, rev = "{args.rev}", '
                         f'subdirectory = "{directory}/{name}" }}')
        (consumer / "pixi.toml").write_text("\n".join(lines) + "\n")
        env["PIXI_CACHE_DIR"] = str(work / "cache")
        pixi = ["pixi", "run", "--manifest-path", str(consumer / "pixi.toml")]
        prefix = consumer / ".pixi/envs/default"
        tests = [("mojo-io", "test_buffered", []), ("mojo-seqair", "test_sequence", ["deflate"]),
                 ("mojo-libdeflate", "test_codec", ["deflate"]),
                 ("mojo-threads", "test_worker", ["mojo_threads_native", "pthread"])]
        for name, test, libraries in tests:
            shutil.copyfile(source / f"packages/{name}/tests/{test}.mojo", consumer / f"{test}.mojo")
            link = ["-Xlinker", f"-L{prefix}/lib"] if libraries else []
            for library in libraries:
                link += ["-Xlinker", f"-l{library}"]
            subprocess.run([*pixi, "mojo", "build", "-O3", "-D", "ASSERT=all", *link,
                            f"{test}.mojo", "-o", test], cwd=consumer, env=env, check=True)
            subprocess.run([*pixi, str(consumer / test)], cwd=consumer, env=env, check=True)
        shutil.copyfile(source / "bins/mojo-perbase/tests/smoke.py", consumer / "smoke.py")
        subprocess.run([*pixi, "python", "smoke.py", "--binary", str(prefix / "bin/mojo-perbase")],
                       cwd=consumer, env=env, check=True)
        # A frozen rerun must use the consumer's lock, with no local source paths.
        subprocess.run(["pixi", "install", "--locked", "--manifest-path", str(consumer / "pixi.toml")],
                       cwd=consumer, env=env, check=True)
        print(f"PASS: Git/subdirectory consumer at {args.rev}; sibling and native dependencies included")


if __name__ == "__main__":
    main()
