"""Integration tests: real compiler, Modo, example execution, and Zensical."""

from html import unescape
from html.parser import HTMLParser
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import tomllib
import unittest
from urllib.parse import urljoin

from mojoverse.site import build_site


class DocumentationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="mojoverse-docs-test-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.project = Path(cls.temp.name)
        cls.source = cls.project / "src/probe"
        config = tomllib.loads((Path(__file__).resolve().parents[1] / "pixi.toml").read_text())
        channel = next(c for c in config["workspace"]["channels"] if "conda.modular.com" in c)
        version = config["dependencies"]["mojo"].lstrip("=")
        (cls.project / "pixi.toml").write_text(
            '[workspace]\nname = "docs-fixture"\npreview = ["pixi-build"]\n'
            f'channels = ["{channel}", "conda-forge"]\n'
            'platforms = ["linux-64", "linux-aarch64", "osx-arm64"]\n'
            '[package]\nname = "docs-fixture"\nversion = "0.1.0"\n'
            '[package.build]\nbackend = { name = "pixi-build-mojo", version = "0.*", '
            'channels = ["https://prefix.dev/pixi-build-backends", "conda-forge"] }\n'
            '[package.build.config.pkg]\nname = "probe"\npath = "src/probe"\n'
            f'[dependencies]\nmojo = "={version}"\n'
        )
        subprocess.run(["pixi", "install", "--manifest-path", str(cls.project / "pixi.toml")], check=True)

    def setUp(self):
        shutil.rmtree(self.source, ignore_errors=True)
        shutil.copytree(Path(__file__).parent / "fixtures/probe", self.source)
        self.output = self.project / self._testMethodName

    def invoke(self, *args):
        return subprocess.run(
            ["mojoverse-docs", str(self.project), "probe", "--output", str(self.output), *args],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180,
        )

    def test_render_and_execute_examples(self):
        (self.project / "README.md").write_text(
            "# Fixture\n\n[Notice](NOTICE.md)\n\nUsage:\n"
            "    ```mojo\n    comptime SCALE = 2\n    var values = [3, 7]\n"
            "    if values[0] == 3:\n        print(values[1])\n    ```\n"
            f"\n[API](https://sstadick.github.io/mojoverse/{self.project.name}/probe/api/add.html)\n"
        )
        (self.project / "NOTICE.md").write_text("# Notice\n\nFixture attribution.\n")
        nested = self.source / "nested"
        nested.mkdir()
        (nested / "__init__.mojo").write_text('"""Nested package."""\n')
        (nested / "detail.mojo").write_text('"""Nested module."""\n')
        subprocess.run(["git", "init", str(self.project)], check=True, capture_output=True)
        self.addCleanup(shutil.rmtree, self.project / ".git")
        subprocess.run(["git", "-C", str(self.project), "add", "src", "README.md"], check=True)
        subprocess.run([
            "git", "-C", str(self.project), "-c", "user.name=Docs Fixture",
            "-c", "user.email=docs@example.invalid", "commit", "-m", "Fixture",
        ], check=True, capture_output=True)
        subprocess.run([
            "git", "-C", str(self.project), "remote", "add", "origin", "git@github.com:example/docs-fixture.git",
        ], check=True)
        revision = subprocess.check_output(["git", "-C", str(self.project), "rev-parse", "HEAD"], text=True).strip()
        source_base = f"https://github.com/example/docs-fixture/blob/{revision}/"
        includes = ("--readme", "README.md", "--include", "NOTICE.md")
        result = self.invoke(*includes)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("2 executable examples passed", result.stdout)
        api = (self.output / "probe/api/add.md").read_text()
        self.assertIn("def add(a: Int, b: Int) -> Int", api)
        self.assertIn("def add(a: Float64, b: Float64) -> Float64", api)
        self.assertNotIn("fn def", api)
        self.assertIn("Box.md", api)
        self.assertIn(source_base + "src/probe/api.mojo", api)
        self.assertIn(source_base + "src/probe/__init__.mojo", (self.output / "probe/_index.md").read_text())
        self.assertIn(source_base + "src/probe/nested/detail.mojo", (self.output / "probe/nested/detail/_index.md").read_text())
        self.assertIn(source_base + "src/probe/nested/__init__.mojo", (self.output / "probe/nested/_index.md").read_text())
        box = (self.output / "probe/api/Box.md").read_text()
        self.assertIn("struct Box[T: Copyable & Deinitable]", box)
        self.assertNotIn("@memory_only", box)
        result = self.invoke("--site", *includes)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue((self.output / "probe/api/add.html").is_file())
        self.assertTrue((self.output / "index.html").is_file())
        self.assertTrue((self.output / "probe.json").is_file())
        self.assertIn("Fixture attribution", (self.output / "NOTICE.html").read_text())
        html = (self.output / "probe/api/add.html").read_text()
        self.assertNotIn('doctest=', html)
        self.assertNotIn('```mojo', html)
        self.assertIn(f'href="{source_base}src/probe/api.mojo"', html)
        self.assertIn("View source", html)
        index = (self.output / "index.html").read_text()
        self.assertIn(f'href="{source_base}README.md"', index)
        text = unescape(re.sub(r"<[^>]+>", "", index))
        self.assertIn("var values = [3, 7]", text)
        self.assertIn("    print(values[1])", text)
        self.assertIn('<span class="k">comptime</span>', index)
        self.assertIn('<span class="k">var</span>', index)
        self.assertTrue((self.output / "markdown/probe/api/add.md").is_file())
        self.assertIn('href="probe/api/add.html"', index)
        self.assertNotIn('href="3, 7"', index)
        self.assertNotIn("```mojo", index)

        readme = self.project / "README.md"
        readme.write_text(readme.read_text().replace("(NOTICE.md)", "(missing.md)"))
        result = self.invoke("--site", *includes)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.output / "index.html").read_text(), index)

    def test_native_linked_example(self):
        native = self.project / "docs_probe.c"
        native.write_text("int docs_probe(int value) { return value + 17; }\n")
        obj = self.project / "docs_probe.o"
        archive = self.project / "libdocs_probe.a"
        subprocess.run(["clang", "-O3", "-march=native", "-c", str(native), "-o", str(obj)], check=True)
        subprocess.run(["ar", "rcs", str(archive), str(obj)], check=True)
        (self.project / "README.md").write_text(
            '```mojo {doctest="native" global=true}\n'
            'from std.ffi import external_call\n'
            'from std.testing import assert_equal\n'
            'def main() raises:\n'
            '    assert_equal(external_call["docs_probe", Int32](Int32(25)), Int32(42))\n'
            '```\n'
        )
        result = self.invoke("--readme", "README.md", "--link-library", str(archive))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("3 executable examples passed", result.stdout)
        self.assertNotIn("source_url:", (self.output / "probe/api/add.md").read_text())

    def test_sidebar_shows_only_current_library(self):
        class SidebarLinks(HTMLParser):
            def __init__(self, html):
                super().__init__()
                self.depth = 0
                self.links = []
                self.feed(html)

            def handle_starttag(self, tag, attrs):
                attrs = dict(attrs)
                if tag == "nav" and (self.depth or "md-nav--primary" in attrs.get("class", "")):
                    self.depth += 1
                if self.depth and tag == "a":
                    self.links.append(attrs["href"])

            def handle_endtag(self, tag):
                if tag == "nav" and self.depth:
                    self.depth -= 1

        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            source = work / "source"
            source.mkdir()
            (source / "index.md").write_text("# Libraries\n")
            nav = [{"Libraries": "index.md"}]
            for name in ("first", "second"):
                (source / name).mkdir()
                (source / name / "index.md").write_text(f"# {name}\n")
                (source / name / "symbol.md").write_text("# Symbol\n")
                nav.append({name: [{"Guide": f"{name}/index.md"}, {"Symbol": f"{name}/symbol.md"}]})
            build_site(source, work / "site", "Fixture", nav, catalog=True)
            home = SidebarLinks((work / "site/index.html").read_text()).links
            self.assertEqual(home, ["index.html"])
            for name in ("first", "second"):
                links = SidebarLinks((work / f"site/{name}/symbol.html").read_text()).links
                self.assertEqual(
                    {urljoin(f"https://docs.test/{name}/symbol.html", link) for link in links},
                    {"https://docs.test/index.html", f"https://docs.test/{name}/index.html", f"https://docs.test/{name}/symbol.html"},
                )

    def test_failed_assertion_preserves_previous_output(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stdout)
        previous = (self.output / "probe/api/add.md").read_text()
        source = self.source / "api.mojo"
        source.write_text(source.read_text().replace("assert_equal(add(7, -3), 4)", "assert_equal(add(7, -3), 999)"))
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.output / "probe/api/add.md").read_text(), previous)

    def test_missing_examples_and_broken_cross_reference_fail(self):
        source = self.source / "api.mojo"
        original = source.read_text()
        source.write_text(original.replace('doctest="', 'not_a_doctest="'))
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("No doctests found", result.stdout)
        source.write_text(original.replace("[probe.api.Box]", "[probe.api.Missing]"))
        # A valid Markdown doctest must not hide a later API rendering failure.
        (self.project / "README.md").write_text(
            '```mojo {doctest="valid" global=true}\n'
            'from std.testing import assert_equal\n'
            'def main() raises:\n    assert_equal(7 - 3, 4)\n```\n'
        )
        result = self.invoke("--readme", "README.md")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Can't resolve cross ref", result.stdout)
        self.assertFalse(self.output.exists())

    def test_root_declaration_is_not_silently_omitted(self):
        source = self.source / "__init__.mojo"
        source.write_text(source.read_text() + '\ndef root_api() -> Int:\n    """Root API."""\n    return 7\n')
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Modo omits declarations", result.stdout)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
