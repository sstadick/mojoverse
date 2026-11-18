"""Build and test Modo documentation with the package's own locked compiler."""

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import textwrap
import tomllib

import yaml
from pymodo.modo import get_executable_path

from .site import build_site


def run(command, cwd):
    subprocess.run(command, cwd=cwd, check=True)


def check_init_declarations(decl):
    # Modo 0.11.13 ignores declarations in __init__, even in strict mode.
    for module in decl.get("modules", []):
        if module["name"] == "__init__" and any(
            module.get(key) for key in ("functions", "structs", "traits", "aliases")
        ):
            raise ValueError(
                "Modo omits declarations defined in __init__.mojo. "
                "Define APIs in modules and re-export them from __init__.mojo."
            )
    for package in decl.get("packages", []):
        check_init_declarations(package)


def build(project, package, output, site, readme, includes, libraries=()):
    project = project.resolve()
    output = output.resolve()
    if output.exists() and not (output / ".mojoverse-generated").is_file():
        raise ValueError(f"Refusing to replace non-generated directory: {output}")
    manifest = tomllib.loads((project / "pixi.toml").read_text())
    pkg = manifest.get("package", {}).get("build", {}).get("config", {}).get("pkg", {})
    package_path = project / (pkg.get("path", package) if pkg.get("name", package) == package else package)
    pixi = ["pixi", "run", "--locked", "--manifest-path", str(project / "pixi.toml")]
    mojo = [*pixi, "mojo"]
    link = []
    if libraries:
        prefix = subprocess.check_output([*pixi, "printenv", "CONDA_PREFIX"], cwd=project, text=True).strip()
        link = ["-Xlinker", f"-L{prefix}/lib"]
        for library in libraries:
            link += ["-Xlinker", library if Path(library).is_absolute() else f"-l{library}"]
    with tempfile.TemporaryDirectory(prefix="mojoverse-docs-") as directory:
        work = Path(directory)
        source = work / "source"
        source.mkdir()
        json_path = source / f"{package}.json"
        run([*mojo, "doc", str(package_path), "-o", str(json_path)], project)
        data = json.loads(json_path.read_text())
        check_init_declarations(data["decl"])
        if readme:
            # README links must work on GitHub; inside the site, keep readers
            # on the current build instead of sending them to published docs.
            text = re.sub(
                rf"\(https://sstadick\.github\.io/mojoverse/{re.escape(project.name)}/([^)]+)\.html\)",
                r"(\1.md)", (project / readme).read_text(),
            )
            (source / "index.md").write_text(text)
        for include in includes:
            relative = Path(include)
            if relative.is_absolute() or ".." in relative.parts:
                raise ValueError("Included documentation must be relative to the project")
            destination = source / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(project / relative, destination)
        templates = Path(__file__).with_name("templates")
        config = {
            "input": [str(source)],
            "output": str(work / "markdown"),
            "tests": str(work / "doctests"),
            "format": "plain",
            "exports": False,
            "strict": True,
            "templates": [str(templates)],
        }
        (work / "modo.yaml").write_text(yaml.safe_dump(config))
        # pymodo's CLI launcher discards the native program's exit status.
        run([get_executable_path(), "build"], work)
        tests = sorted((work / "doctests").rglob("*.mojo"))
        if not tests:
            raise ValueError("No doctests found. Mark executable examples with {doctest=\"name\"}.")
        for test in tests:
            binary = test.with_suffix("")
            run([*mojo, "build", "-O3", "-I", str(package_path.parent), "-D", "ASSERT=all",
                 *link, str(test), "-o", str(binary)], work)
            run([str(binary)], work)
        markdown = work / "markdown"
        # Modo's plain output retains Hugo-style fence attributes, which
        # CommonMark/MkDocs otherwise display as literal backticks.
        for page in markdown.rglob("*.md"):
            # Module docstrings also preserve indented fenced examples. Stock
            # MkDocs treats their brackets as links unless the fences start at
            # column zero; preserve indentation within the example itself.
            text = re.sub(
                r"(?m)^([ \t]+)```[^\n]*\n[\s\S]*?^\1```[ \t]*$",
                lambda match: "\n" + textwrap.dedent(match[0]) + "\n",
                page.read_text(),
            )
            page.write_text(re.sub(
                r"^```mojo\s+\{[^}\n]*\}\s*$", "```mojo", text, flags=re.MULTILINE
            ))
        if not (markdown / "index.md").exists():
            (markdown / "index.md").write_text(
                f"# {package}\n\n[API reference]({package}/_index.md)\n"
            )
        result = markdown
        if site:
            build_site(markdown, work / "site", package)
            result = work / "site"
        (result / ".mojoverse-generated").write_text("Generated by mojoverse-docs.\n")
        output.parent.mkdir(parents=True, exist_ok=True)
        if output.exists():
            shutil.rmtree(output)
        shutil.copytree(result, output)
        if site:
            # The hub renders these together, with one navigation/search index.
            shutil.copytree(markdown, output / "markdown")
        shutil.copyfile(json_path, output / f"{package}.json")
        print(f"Built {package} docs; {len(tests)} executable examples passed; output: {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path, help="Package checkout containing pixi.toml")
    parser.add_argument("package", help="Importable Mojo package directory")
    parser.add_argument("--output", type=Path, help="Generated output (default: PROJECT/target/docs)")
    parser.add_argument("--site", action="store_true", help="Render a GitHub Pages-ready HTML site")
    parser.add_argument("--readme", help="Also render a Markdown file relative to the package checkout")
    parser.add_argument("--include", action="append", default=[], help="Include a linked file relative to the checkout (repeatable)")
    parser.add_argument("--link-library", action="append", default=[], help="Link examples with a library from the package prefix, or an absolute archive path (repeatable)")
    args = parser.parse_args()
    try:
        build(args.project, args.package, args.output or args.project / "target/docs", args.site, args.readme, args.include, args.link_library)
    except (ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Documentation build failed: {error}\n")


if __name__ == "__main__":
    main()
