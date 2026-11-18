"""Run the existing stable tests from source or installed Pixi packages."""

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tomllib


def run(command, cwd):
    print("+", " ".join(map(str, command)), flush=True)
    subprocess.run(command, cwd=cwd, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--installed", action="store_true", help="Import only installed libraries")
    modes.add_argument("--bins", action="store_true", help="Test Hat and the installed Perbase CLI")
    parser.add_argument("names", nargs="*", help="Limit library tests to these distribution names")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    config = tomllib.loads((root / "pixi.toml").read_text())
    libraries = {
        name: root / dep["path"] for name, dep in config["dependencies"].items()
        if isinstance(dep, dict) and dep.get("path", "").startswith("packages/")
    }
    if unknown := set(args.names) - libraries.keys():
        parser.error(f"Unknown stable libraries: {', '.join(sorted(unknown))}")
    if args.bins and args.names:
        parser.error("--bins does not take library names")
    source_roots = []
    module_names = []
    for package in libraries.values():
        manifest = tomllib.loads((package / "pixi.toml").read_text())
        module = manifest["package"].get("build", {}).get("config", {}).get("pkg", {})
        source_roots.append((package / module.get("path", ".")).parent if module else package)
        module_names.append(module.get("name") or Path(module.get("path", manifest["package"]["name"].replace("-", "_"))).name)
    if not args.installed and not args.bins:
        # Installed .mojoc files take precedence over -I source directories.
        # Source tests use a compiler/native-only environment, never the combined one.
        compiled = Path(os.environ["CONDA_PREFIX"]) / "lib/mojo"
        if any((compiled / f"{name}.mojoc").exists() for name in module_names):
            raise SystemExit("Source tests require the source environment: pixi run -e source test-packages")
    projects = {"hat": root / "bins/hat"} if args.bins else {
        name: path for name, path in libraries.items() if not args.names or name in args.names
    }
    output = root / "target" / ("installed-tests" if args.installed else "source-tests")
    output.mkdir(parents=True, exist_ok=True)
    # These tests exercise APIs requiring native link dependencies.
    links = {"mojo-libdeflate": ["deflate"], "mojo-seqair": ["deflate"],
             "mojo-threads": ["mojo_threads_native", "pthread"]}
    count = 0
    for name, package in projects.items():
        manifest = tomllib.loads((package / "pixi.toml").read_text())
        module = manifest["package"].get("build", {}).get("config", {}).get("pkg", {})
        source_root = (package / module.get("path", ".")).parent if module else package
        tests = sorted({p for directory in ("tests", "test")
                        for p in (package / directory).rglob("test_*.mojo")})
        if not tests:
            raise SystemExit(f"No Mojo tests found in {package}")
        for test in tests:
            binary = output / (name + "-" + "-".join(test.relative_to(package).with_suffix("").parts))
            # Mojo 1.2 defaults to host CPU/features. Do not use --target-cpu=native.
            command = ["mojo", "build", "-O3", "-D", "ASSERT=all"]
            if not args.installed:
                for include in ([source_root] if args.bins else source_roots):
                    command += ["-I", str(include)]
            if name in links:
                command += ["-Xlinker", f"-L{os.environ['CONDA_PREFIX']}/lib"]
                for library in links[name]:
                    command += ["-Xlinker", f"-l{library}"]
            run([*command, str(test), "-o", str(binary)], package)
            run([str(binary)], package)
            count += 1
    if args.bins:
        run(["hat", "--help"], root)
        run([sys.executable, "tests/smoke.py", "--binary",
             str(Path(os.environ["CONDA_PREFIX"]) / "bin/mojo-perbase")], root / "bins/mojo-perbase")
    print(f"PASS: {count} Mojo test programs" + (" and bin checks" if args.bins else ""), flush=True)


if __name__ == "__main__":
    main()
