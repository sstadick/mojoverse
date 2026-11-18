"""Check dangling-view rejection; report the known Mojo 1.2 mutation-check gap."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
cases = {
    "valid": '''from mojo_bstr import trim, finder, finder_reverse
def main():
    var data: List[UInt8] = [32, 97]
    var view = trim(Span(data))
    print(view[0], finder(view).needle()[0], finder_reverse(view).needle()[0])
''',
    "dangling": '''from mojo_bstr import trim
def bad() -> Span[UInt8, ImmStaticOrigin]:
    var data: List[UInt8] = [32, 97]
    return trim(Span(data))
def main():
    print(bad()[0])
''',
    "mutation": '''from mojo_bstr import trim
def main():
    var data: List[UInt8] = [32, 97]
    var view = trim(Span(data))
    data.append(98)
    print(view[0])
''',
    "finder_assignment": '''from mojo_bstr import finder, finder_reverse
def main():
    var data: List[UInt8] = [32, 97]
    var searcher = finder(Span(data))
    searcher.needle = Span(data)[:1]
    print(searcher.find(Span(data)))
''',
}
with tempfile.TemporaryDirectory(prefix="bstr-origins-") as directory:
    for name, source in cases.items():
        path = Path(directory) / f"{name}.mojo"
        path.write_text(source)
        result = subprocess.run(["mojo", "build", "-I", str(root), str(path),
                                 "-o", str(Path(directory) / name)], capture_output=True, text=True)
        if name == "valid":
            assert result.returncode == 0, result.stderr
            print("valid borrowed-view control: compiled")
            continue
        if name == "mutation" and result.returncode == 0:
            print("LIMITATION: compiler accepts List growth while a view is live; do not execute it")
            continue
        assert result.returncode != 0, f"{name} unexpectedly compiled"
        assert "error:" in result.stderr, result.stderr
        if name == "dangling":
            assert "origin_of(data)" in result.stderr and "ImmStaticOrigin" in result.stderr, result.stderr
        print(result.stderr)
        print(f"{name}: rejected; inspect the diagnostic above")
