"""Run unchanged Goose Perbase BAM/merge assertions against an explicit oracle.

Requires the reference suite's Python dependencies (pysam). CRAM and its
benchmark driver are intentionally excluded; neither is claimed as validated.
"""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import subprocess
import sys


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", type=Path, required=True, help="goose-perbase checkout")
    p.add_argument("--oracle", type=Path, required=True)
    p.add_argument("--binary", type=Path, required=True)
    a = p.parse_args()
    source = a.source / "tests/run.py"
    print("Reference suite SHA256:", hashlib.sha256(source.read_bytes()).hexdigest(), flush=True)
    print("Oracle:", a.oracle.resolve(), flush=True)
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("reference_suite", source)
    suite = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(suite)
    suite.cram_tests = lambda *args: print("SKIP: CRAM is not implemented")
    suite.benchmark_tests = lambda *args: print("SKIP: reference benchmark driver")
    calls = 0
    original = subprocess.run

    def run(*args, **kwargs):
        nonlocal calls
        calls += 1
        result = original(*args, **kwargs)
        for stream in (result.stdout, result.stderr):
            data = stream.encode() if isinstance(stream, str) else (stream or b"")
            assert not any(marker in data for marker in (
                b"AddressSanitizer", b"LeakSanitizer", b"ThreadSanitizer", b"runtime error:")), (args, data)
        return result

    subprocess.run = run
    sys.argv = ["reference_suite", "--perbase", str(a.oracle.resolve()), "--goose", str(a.binary.resolve())]
    try:
        suite.main()
    finally:
        subprocess.run = original
    print(f"PASS {calls} subprocess invocations; oracle is the explicit binary above, not necessarily Rust")


if __name__ == "__main__":
    main()
