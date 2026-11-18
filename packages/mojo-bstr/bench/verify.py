"""Untimed checks of both benchmark protocols, including binary KLV payloads."""
from pathlib import Path
import random
import subprocess
import tempfile
from compare import expected

root = Path(__file__).resolve().parents[1]


def klv(model, haystack, patterns):
    pairs = [("model", model.encode()), ("haystack", haystack)]
    pairs += [("pattern", pattern) for pattern in patterns]
    pairs += [("max-iters", b"3"), ("max-warmup-iters", b"1"),
              ("max-time", b"1000000"), ("max-warmup-time", b"1000000")]
    return b"".join(k.encode() + b":" + str(len(v)).encode() + b":" + v + b"\n" for k, v in pairs)


with tempfile.TemporaryDirectory(prefix="bstr-bench-verify-") as tmp:
    tmp = Path(tmp)
    search, rebar = tmp / "search", tmp / "rebar"
    for source, dest in [("bench/search.mojo", search), ("bench/rebar/main.mojo", rebar)]:
        subprocess.run(["mojo", "build", "-I", str(root), "-I", str(root / "bench"),
                        str(root / source), "-o", str(dest)], check=True)
    rng = random.Random(1839)
    cases = [(b"", b""), (b"abc", b""), (b"ababa", b"aba"),
             (b"\0a\xff\na|bc\r\n|tail", b"\xff\n"), (b"a" * 255, b"a" * 33)]
    cases += [(rng.randbytes(300), rng.randbytes(35)), (b"x" * 127 + b"\0\xff", b"\0\xff")]
    modes = ["find", "rfind", "prepared-find", "prepared-rfind", "count", "rcount",
             "find-set", "rfind-set", "find-not-set", "rfind-not-set", "records"]
    checks = 0
    for data, pattern in cases:
        h, n = tmp / "h", tmp / "n"
        h.write_bytes(data)
        n.write_bytes(pattern)
        for mode in modes:
            output = subprocess.check_output([str(search), str(h), str(n), mode, "1", "--verify"], text=True)
            elapsed, checksum = map(int, output.split())
            assert elapsed == 0 and checksum == expected(data, pattern, mode) + 1, (mode, output)
            checks += 1

    def check(mode, model, data, patterns, want):
        global checks
        output = subprocess.check_output([str(rebar), mode, "--verify"], input=klv(model, data, patterns))
        assert output == f"0,{want}\n".encode(), (mode, model, output, want)
        checks += 1

    for data in [b"", b"\0a\xffb\na\xffa", b"aba" * 70, b"x" * 257]:
        for mode in ["memmem-oneshot", "memmem-prebuilt"]:
            for pattern in [b"a", b"aba", b"x" * 33, b"\\xFF"]:
                decoded = b"\xff" if pattern == b"\\xFF" else pattern
                check(mode, "count", data, [pattern], data.count(decoded))
        for mode, count in [("memchr-oneshot", 1), ("memrchr", 1), ("memchr2", 2),
                            ("memrchr2", 2), ("memchr3", 3), ("memrchr3", 3)]:
            check(mode, "count-bytes", data, [b"a", b"\\xFF", b"\\x00"][:count],
                  sum(b in b"a\xff\0"[:count] for b in data))
        needles = [b"aba", b"a", b"xyz", b"a", b"baba"]
        check("memmem-prebuilt", "needles-in-haystack", data, needles, sum(n in data for n in needles))
        check("memmem-prebuilt", "needles-in-needles", data, needles,
              sum(n in h for i, n in enumerate(needles) for h in needles[i:]))
    for mode, payload in [("memmem-oneshot", klv("count", b"a", [b""])),
                          ("memchr2", klv("count-bytes", b"a", [b"a"])),
                          ("memmem-oneshot", b"haystack:99:short\n")]:
        result = subprocess.run([str(rebar), mode, "--verify"], input=payload, capture_output=True)
        assert result.returncode != 0, (mode, payload)
        checks += 1
    print(f"{checks} benchmark protocol checks passed; no timers executed")
