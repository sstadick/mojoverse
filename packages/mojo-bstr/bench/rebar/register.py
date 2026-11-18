#!/usr/bin/env python3
"""Register Mojo alongside memchr (and optionally goostr), changing engine lists only."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tomllib

MEMCHR = "5fdb40c054e1fff359a2f7bdf7f87a13b34b465d"
ENGINES = {"memchr/oneshot": "memchr-oneshot", "memrchr": "memrchr", "memchr2": "memchr2",
           "memchr3": "memchr3", "memrchr2": "memrchr2", "memrchr3": "memrchr3",
           "memmem/oneshot": "memmem-oneshot", "memmem/prebuilt": "memmem-prebuilt"}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--memchr-checkout", type=Path, required=True)
    p.add_argument("--mojo-exe", type=Path, required=True)
    p.add_argument("--verify-only", action="store_true", help="register runners that never read the clock")
    args = p.parse_args()
    checkout = args.memchr_checkout.resolve()
    revision = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
    if revision != MEMCHR:
        p.error(f"expected memchr {MEMCHR}")
    subprocess.run(["git", "-C", str(checkout), "diff", "--exit-code", "HEAD", "--", "benchmarks/haystacks"], check=True)
    root = checkout / "benchmarks"
    engine = root / "engines/mojo-bstr"
    if engine.exists() or 'name = "mojo/bstr/' in (root / "engines.toml").read_text():
        p.error("Mojo engine already registered; use a fresh checkout rather than overwrite it")
    changes = {}
    for path in sorted((root / "definitions").rglob("*.toml")):
        before = path.read_text()
        baseline = subprocess.check_output(["git", "-C", str(checkout), "show",
                                            "HEAD:" + str(path.relative_to(checkout))], text=True)

        def add(match):
            block = match[0]
            additions = [f'  "mojo/bstr/{name}",\n' for name in ENGINES if f'"rust/memchr/{name}"' in block]
            return block[:-1] + "".join(additions) + "]" if additions else block

        after = re.sub(r"engines\s*=\s*\[[^\]]*\]", add, before)
        clean = tomllib.loads(after)
        for case in clean["bench"]:
            case["engines"] = [e for e in case["engines"]
                               if not e.startswith(("mojo/bstr/", "goose/goostr/"))]
        if clean != tomllib.loads(baseline):
            raise ValueError(f"fixture changed beyond engine registration: {path}")
        if after != before:
            changes[path] = after
    config = (root / "engines.toml").read_text()
    for name, mode in ENGINES.items():
        config += f'''
[[engine]]
name = "mojo/bstr/{name}"
cwd = "./engines/mojo-bstr"
[engine.version]
bin = "cat"
args = ["version.txt"]
[engine.run]
bin = "./main"
args = {json.dumps([mode] + (["--verify"] if args.verify_only else []))}
'''
    tomllib.loads(config)
    binary_hash = hashlib.sha256(args.mojo_exe.read_bytes()).hexdigest()
    engine.mkdir()
    shutil.copy2(args.mojo_exe, engine / "main")
    (engine / "version.txt").write_text("0.1.0-" + binary_hash + "\n")
    (root / "engines.toml").write_text(config)
    for path, value in changes.items():
        path.write_text(value)
    source = Path(__file__).resolve().parents[2]
    metadata = dict(memchr=MEMCHR, binary_sha256=binary_hash, verify_only=args.verify_only,
                    compiler=subprocess.check_output(["mojo", "--version"], text=True).strip(),
                    sources={str(path.relative_to(source)): hashlib.sha256(path.read_bytes()).hexdigest()
                             for path in [*source.glob("bstr/*.mojo"), source / "bench/rebar/main.mojo"]},
                    fixtures={str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                              for folder in ["definitions", "haystacks"]
                              for path in sorted((root / folder).rglob("*")) if path.is_file()})
    (engine / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Registered {len(ENGINES)} engines in {len(changes)} definition files; fixtures unchanged")


if __name__ == "__main__":
    main()
