"""Installed CLI checks with independent, stdlib-only BAM/depth fixtures."""
import argparse
import gzip
from pathlib import Path
import struct
import subprocess
import tempfile
import zlib


def bgzf(data):
    compressor = zlib.compressobj(wbits=-15)
    payload = compressor.compress(data) + compressor.flush()
    return (bytes.fromhex("1f8b08040000000000ff060042430200")
            + struct.pack("<H", len(payload) + 25) + payload
            + struct.pack("<II", zlib.crc32(data), len(data)))


def fixture(path):
    header = b"BAM\1" + struct.pack("<iii", 0, 1, 4) + b"chr\0" + struct.pack("<i", 20)
    records = []
    for pos, flag, seq in ((1, 65, bytes.fromhex("1248")), (3, 129, bytes.fromhex("8811"))):
        core = struct.pack("<iiIIiiii", 0, pos, (4681 << 16) | (60 << 8) | 5,
                           (flag << 16) | 1, 4, 0, 3 if pos == 1 else 1, 6)
        record = core + b"pair\0" + struct.pack("<I", 4 << 4) + seq + bytes([30] * 4)
        records.append(struct.pack("<i", len(record)) + record)
    packed = bgzf(header + b"".join(records))
    path.write_bytes(packed + bgzf(b""))
    Path(str(path) + ".bai").write_bytes(
        b"BAI\1" + struct.pack("<iiiiQQiQ", 1, 1, 4681, 1, len(header), len(packed) << 16, 1, len(header)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    args = parser.parse_args()
    binary = str(args.binary.resolve(strict=True))
    calls = 0

    def run(command, path, *flags, ok=True):
        nonlocal calls
        calls += 1
        result = subprocess.run([binary, command, str(path), *map(str, flags)],
                                capture_output=True, timeout=30)
        assert not any(marker in result.stderr for marker in (
            b"AddressSanitizer", b"LeakSanitizer", b"ThreadSanitizer", b"runtime error:")), result.stderr
        assert (result.returncode == 0) == ok, (result.args, result.returncode, result.stderr)
        return result.stdout

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        bam = root / "test.bam"
        fixture(bam)
        base_header = ("REF\tPOS\tDEPTH\tA\tC\tG\tT\tN\tR\tY\tS\tW\tK\tM\tINS\tDEL\tREF_SKIP"
                       "\tFAIL\tCOUNT_OF_MATE_RESOLUTIONS\tNEAR_MAX_DEPTH\n")
        for mates in (False, True):
            flags = ["-m"] if mates else []
            depth = "REF\tPOS\tEND\tDEPTH\n"
            base = base_header
            for pos in range(20):
                bases = [seq[pos - start] for start, seq in ((1, "ACGT"), (3, "TTAA"))
                         if start <= pos < start + len(seq)]
                resolved = int(mates and len(bases) == 2)
                if mates: bases = bases[:1]
                depth += f"chr\t{pos}\t{pos + 1}\t{len(bases)}\n"
                counts = [len(bases), *(bases.count(b) for b in "ACGT"), *([0] * 11), resolved]
                base += f"chr\t{pos}\t" + "\t".join(map(str, counts)) + "\tfalse\n"
            for threads, chunk in ((1, 1), (4, 5), (4, 1000)):
                common = ["-k", "-z", "-t", threads, "-c", chunk, *flags]
                assert run("only-depth", bam, "-n", *common) == depth.encode()
                assert run("base-depth", bam, *common) == base.encode()
        # Enough output to wrap the compression ring repeatedly, including a
        # partial final block. Serial and threaded BGZF must preserve all bytes.
        tsv = root / "rows.tsv"
        rows = "REF\tPOS\tEND\tDEPTH\n" + "".join(f"chr\t{i}\t{i+1}\t{i%2}\n" for i in range(50000))
        tsv.write_text(rows)
        assert run("merge-adjacent", tsv) == rows.encode()
        for threads in (1, 2, 4):
            packed = run("merge-adjacent", tsv, "-Z", "-T", threads)
            assert gzip.decompress(packed) == rows.encode()
            if Path("/dev/full").exists():
                run("merge-adjacent", tsv, "-Z", "-T", threads, "-o", "/dev/full", ok=False)
        # Decimal-width boundaries and full u64 values must survive formatting.
        # New, empty and nonempty output files must produce exactly the same
        # bytes; overwriting a longer file must not leave its old tail behind.
        values = sorted({0, 100200300, 2**63, 2**64 - 1} | {
            10**width + offset for width in range(1, 20) for offset in (-1, 0, 1)
        })
        rows = "REF\tPOS\tEND\tDEPTH\n" + "".join(
            f"chr\t{i}\t{i+1}\t{value}\n" for i, value in enumerate(values))
        tsv.write_text(rows)
        target = root / "output.tsv"
        for previous in (None, b"", b"old data\n" * 1000):
            if previous is not None:
                target.write_bytes(previous)
            run("merge-adjacent", tsv, "-o", target)
            assert target.read_bytes() == rows.encode()
        alias = root / "alias.bam"
        alias.hardlink_to(bam)
        before = bam.read_bytes()
        run("base-depth", bam, "-o", alias, ok=False)
        assert bam.read_bytes() == before
        run("only-depth", bam, "-m", "-x", ok=False)
        # mojopt's attached values, bundles and -- retain the same CLI meaning.
        expected = "REF\tPOS\tEND\tDEPTH\n" + "".join(
            f"chr\t{i}\t{i+1}\t{int(1 <= i < 5) + int(3 <= i < 7)}\n"
            for i in range(20))
        assert run("only-depth", bam, "-nkzt4", "--chunksize=5") == expected.encode()
        assert run("only-depth", bam, "--no-merge", "--keep-zeros", "--zero-base",
                   "--threads=4", "--chunksize=5", "--mate-fix=false") == expected.encode()
        assert run("only-depth", "-nkz", "--", bam) == expected.encode()
        for command in ("base-depth", "only-depth", "merge-adjacent"):
            assert b"--output" in run(command, "--help")
        for command, flags in (
            ("only-depth", ["--max-depth=0"]),
            ("only-depth", ["-Q0"]),
            ("base-depth", ["--fast-mode=false"]),
            ("merge-adjacent", ["--no-merge"]),
            ("base-depth", ["--no-header"]),
            ("base-depth", ["-q256"]),
            ("base-depth", ["-F65536"]),
            ("base-depth", ["--threads=-1"]),
            ("base-depth", ["--threads=2147483648"]),
            ("base-depth", ["--threads=18446744073709551616"]),
            ("base-depth", ["--chunksize=0"]),
            ("base-depth", ["--channel-size-modifier=nan"]),
            ("base-depth", ["--channel-size-modifier=inf"]),
            ("base-depth", ["--compression-level=10"]),
            ("base-depth", ["--min-mapq="]),
            ("base-depth", ["--mate-resolution-strategy=unknown"]),
            ("base-depth", ["--unknown"]),
            ("base-depth", [str(bam)]),
        ):
            target.write_bytes(b"must survive rejected CLI\n")
            run(command, bam, "-o", target, *flags, ok=False)
            assert target.read_bytes() == b"must survive rejected CLI\n"
    print(f"PASS {calls} CLI checks: independent counts, workers, BGZF ring, errors and hardlinks")


if __name__ == "__main__":
    main()
