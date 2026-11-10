"""Integration tests: real compiler, Modo, example execution, and MkDocs."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class DocumentationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="mojoverse-docs-test-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.project = Path(cls.temp.name)
        cls.source = cls.project / "src/probe"
        channel = os.environ.get("MOJO_CHANNEL", "https://conda.modular.com/max")
        version = os.environ.get("MOJO_VERSION", "1.2.0")
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
            "    ```mojo\n    var values = List[Int](3, 7)\n"
            "    if values[0] == 3:\n        print(values[1])\n    ```\n"
        )
        (self.project / "NOTICE.md").write_text("# Notice\n\nFixture attribution.\n")
        includes = ("--readme", "README.md", "--include", "NOTICE.md")
        result = self.invoke(*includes)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("2 executable examples passed", result.stdout)
        api = (self.output / "probe/api/add.md").read_text()
        self.assertIn("def add(a: Int, b: Int) -> Int", api)
        self.assertIn("def add(a: Float64, b: Float64) -> Float64", api)
        self.assertNotIn("fn def", api)
        self.assertIn("Box.md", api)
        box = (self.output / "probe/api/Box.md").read_text()
        self.assertIn("struct Box[T: Copyable & Deinitable]", box)
        self.assertNotIn("@memory_only", box)
        result = self.invoke("--site", *includes)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue((self.output / "probe/api/add.html").is_file())
        self.assertTrue((self.output / "index.html").is_file())
        self.assertIn("Fixture attribution", (self.output / "NOTICE.html").read_text())
        html = (self.output / "probe/api/add.html").read_text()
        self.assertNotIn('doctest=', html)
        self.assertNotIn('```mojo', html)
        index = (self.output / "index.html").read_text()
        self.assertIn("List[Int](3, 7)", index)
        self.assertIn("    print(values[1])", index)
        self.assertNotIn('href="3, 7"', index)
        self.assertNotIn("```mojo", index)

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
