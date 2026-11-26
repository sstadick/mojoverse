"""Keep every Mojo package on one compiler and one local dependency graph."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tomllib

ROOT = Path(__file__).resolve().parents[1]
CHANNEL = "https://conda.modular.com/max"


def manifests(root):
    for directory, children, files in os.walk(root):
        children[:] = sorted(c for c in children if not c.startswith(".") and c not in
                             {"vendor", "target", "build", "dist", "node_modules"})
        if "pixi.toml" in files:
            path = Path(directory) / "pixi.toml"
            yield path, tomllib.loads(path.read_text())


def tables(value, trail=()):
    if isinstance(value, dict):
        yield trail, value
        for key, child in value.items():
            yield from tables(child, (*trail, key))


def pin(value):
    if not isinstance(value, str) or not re.fullmatch(r"={1,2}[0-9][\w.]*", value):
        raise ValueError(f"Expected an exact compiler pin, got {value!r}")
    return value.lstrip("=")


def check(root, lane=None):
    files = dict(manifests(root))
    config = files[root / "pixi.toml"]
    version = pin(config["dependencies"]["mojo"])
    max_version = pin(config["dependencies"]["max-core"])
    channel = CHANNEL + ("-nightly" if ".dev" in version else "")
    if lane and (lane == "nightly") != (".dev" in version):
        raise ValueError(f"{lane} requires its own compiler lane, found Mojo {version}")
    packages = {data["package"]["name"].replace("_", "-"): path.parent
                for path, data in files.items() if "package" in data}
    errors = []
    root_deps = {name.replace("_", "-") for trail, table in tables(config)
                 if trail and trail[-1] == "dependencies" for name in table}
    for name, directory in packages.items():
        if directory.parent in {root / "packages", root / "bins"} and name not in root_deps:
            errors.append(f"{directory.relative_to(root)} is missing from the root environments")
    for path, data in files.items():
        label = str(path.relative_to(root))
        package = data.get("package", {})
        if package.get("build", {}).get("backend", {}).get("name") == "pixi-build-mojo":
            for phase in ("build", "host", "run"):
                if "mojo-compiler" not in package.get(f"{phase}-dependencies", {}):
                    errors.append(f"{label}: missing {phase} mojo-compiler pin")
        for trail, table in tables(data):
            if "channels" in table:
                for item in table["channels"]:
                    if isinstance(item, str) and item.startswith(CHANNEL) and item.rstrip("/") != channel:
                        errors.append(f"{label}: mixed compiler channel {item}")
            if not trail or not trail[-1].endswith("dependencies") or trail[-1] == "pypi-dependencies":
                continue
            for name, dep in table.items():
                if name in {"mojo", "mojo-compiler", "max-core", "max"}:
                    expected = max_version if name in {"max-core", "max"} else version
                    if pin(dep) != expected:
                        errors.append(f"{label}: {name} {dep} disagrees with root ={expected}")
                local = packages.get(name.replace("_", "-"))
                if local and (not isinstance(dep, dict) or "path" not in dep or
                              (path.parent / dep["path"]).resolve() != local.resolve()):
                    errors.append(f"{label}: {name} must use a relative path to {local.relative_to(root)}")
                if isinstance(dep, dict) and "path" in dep:
                    target = (path.parent / dep["path"]).resolve()
                    if Path(dep["path"]).is_absolute() or not target.is_relative_to(root) or not target.exists():
                        errors.append(f"{label}: dependency path escapes the checkout or is missing: {dep['path']}")
    recipe = root / "packages/mojopt/recipe.yaml"
    if recipe.exists() and f'mojo_version: "={version}"' not in recipe.read_text():
        errors.append("packages/mojopt/recipe.yaml: compiler pin disagrees with root")
    if errors:
        raise ValueError("\n".join(errors))
    print(f"PASS: {len(files)} manifests; Mojo {version}, MAX core {max_version}; local dependency graph")


def lock(root, checking=False):
    for path, data in manifests(root):
        if path.with_name("pixi.lock").exists() or "dependencies" in data:
            command = ["pixi", "lock", "--manifest-path", str(path)]
            if checking:
                command += ["--check"]
            print("+", " ".join(command), flush=True)
            subprocess.run(command, cwd=root, check=True)


def published(root, lane, version=None):
    """Select a published Mojo/MAX pair available on every workspace platform."""
    channel = CHANNEL + ("-nightly" if lane == "nightly" else "")
    records = {}
    for name in ("mojo", "max-core"):
        command = ["pixi", "search", name, "--channel", channel, "--json",
                   "--manifest-path", str(root / "pixi.toml")]
        records[name] = json.loads(subprocess.check_output(command, text=True, cwd=root))
    platforms = tomllib.loads((root / "pixi.toml").read_text())["workspace"]["platforms"]
    common = None
    for platform in platforms:
        mojo = {p["version"] for p in records["mojo"].get(platform, [])
                if p["name"] == "mojo" and ((".dev" in p["version"]) == (lane == "nightly"))}
        pairs = set()
        for package in records["max-core"].get(platform, []):
            for dep in package.get("depends", []):
                match = re.fullmatch(r"mojo-compiler ==([\w.]+)", dep)
                if match and match[1] in mojo and (version is None or match[1] == version):
                    pairs.add((match[1], package["version"]))
        common = pairs if common is None else common & pairs
    if not common:
        raise ValueError(f"No matching {lane} Mojo/MAX release on all of {platforms}")
    return max(common, key=lambda pair: tuple(int(n) for n in re.findall(r"\d+", pair[0])))


def update(root, lane, version, max_version):
    channel = CHANNEL + ("-nightly" if lane == "nightly" else "")
    old = pin(tomllib.loads((root / "pixi.toml").read_text())["dependencies"]["mojo"])
    for path, _ in manifests(root):
        text = path.read_text()
        text = re.sub(r'https://conda\.modular\.com/max(?:-nightly)?/?(?=["\'])', channel, text)
        text = re.sub(r'(?m)^((?:mojo|mojo-compiler)\s*=\s*)["\'][^"\']+["\']',
                      lambda m: m[1] + f'"={version}"', text)
        text = re.sub(r'(?m)^((?:max-core|max)\s*=\s*)["\'][^"\']+["\']',
                      lambda m: m[1] + f'"={max_version}"', text)
        path.write_text(text)
    recipe = root / "packages/mojopt/recipe.yaml"
    if recipe.exists():
        recipe.write_text(re.sub(r'mojo_version: "[^"]+"', f'mojo_version: "={version}"', recipe.read_text()))
    # Keep the landing-page copy/paste example in the same lane, not historical results.
    readme = root / "README.md"
    if readme.exists():
        text = readme.read_text().replace(f"**Mojo {old}**", f"**Mojo {version}**")
        text = text.replace(f'mojo = "={old}"', f'mojo = "={version}"')
        text = re.sub(r'"https://conda\.modular\.com/max(?:-nightly)?"', f'"{channel}"', text)
        readme.write_text(text)
    check(root, lane)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    sub = parser.add_subparsers(dest="command", required=True)
    checker = sub.add_parser("check")
    checker.add_argument("--lane", choices=["stable", "nightly"])
    locker = sub.add_parser("lock")
    locker.add_argument("--check", action="store_true")
    updater = sub.add_parser("update")
    updater.add_argument("--channel", choices=["stable", "nightly"], required=True)
    updater.add_argument("--version", help="Published Mojo version; default latest common release")
    updater.add_argument("--no-lock", action="store_true", help="Update manifests only, for inspection")
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        if args.command == "check":
            check(root, args.lane)
        elif args.command == "lock":
            lock(root, args.check)
        else:
            version, max_version = published(root, args.channel, args.version)
            print(f"Selected {args.channel}: Mojo {version}, MAX core {max_version}", flush=True)
            update(root, args.channel, version, max_version)
            if not args.no_lock:
                lock(root)
    except ValueError as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
