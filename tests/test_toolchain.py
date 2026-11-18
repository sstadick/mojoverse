"""The workspace check must reject mismatched compilers and detached dependencies."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/toolchain.py"


class ToolchainTests(unittest.TestCase):
    def test_workspace_contract(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "pixi.toml").write_text('''[workspace]
channels = ["https://conda.modular.com/max", "conda-forge"]
[dependencies]
mojo = "=1.2.0"
max-core = "=26.7.0"
alpha = { path = "packages/alpha" }
''')
            package = root / "packages/alpha"
            package.mkdir(parents=True)
            good = '''[workspace]
channels = ["https://conda.modular.com/max", "conda-forge"]
[package]
name = "alpha"
[package.build]
backend = { name = "pixi-build-mojo" }
[package.build-dependencies]
mojo-compiler = "==1.2.0"
[package.host-dependencies]
mojo-compiler = "==1.2.0"
[package.run-dependencies]
mojo-compiler = "==1.2.0"
[dependencies]
alpha = { path = "." }
'''
            for change, expected in [
                (good, None),
                (good.replace("==1.2.0", "=1.1.0"), "disagrees with root"),
                (good.replace("/max\"", "/max-nightly\""), "mixed compiler channel"),
                (good.replace('{ path = "." }', '{ git = "https://example.com/old-alpha" }'), "relative path"),
                (good.replace('{ path = "." }', '{ path = "../../../../outside" }'), "escapes the checkout"),
                (good.replace('[package.run-dependencies]\nmojo-compiler = "==1.2.0"', ''), "missing run mojo-compiler pin"),
                (good.replace('name = "alpha"', 'name = "unlisted"'), "missing from the root environments"),
            ]:
                with self.subTest(expected=expected):
                    (package / "pixi.toml").write_text(change)
                    result = subprocess.run([sys.executable, str(SCRIPT), "--root", tmp,
                                             "check", "--lane", "stable"], capture_output=True, text=True)
                    if expected is None:
                        self.assertEqual(result.returncode, 0, result.stderr)
                    else:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn(expected, result.stderr)
