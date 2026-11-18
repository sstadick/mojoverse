#!/usr/bin/env python3
"""Reuse the supplied goostr cases; verify untimed or compare serially on one host."""
import argparse
from datetime import datetime, timezone
import fnmatch
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile


def expected(data, pattern, mode):
    if "set" in mode:
        positions = range(len(data) - 1, -1, -1) if mode.startswith("rfind") else range(len(data))
        return next((i for i in positions if (data[i] in pattern) != ("-not-" in mode)), -1)
    if mode == "count":
        return data.count(pattern)
    if mode == "rcount":
        return data[::-1].count(pattern[::-1])
    if mode == "records":
        return sum(line.find(b"|") + 1 for line in data.split(b"\n"))
    return data.rfind(pattern) if mode.endswith("rfind") else data.find(pattern)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--goostr-source", type=Path, required=True)
    p.add_argument("--mojo-exe", type=Path, required=True)
    p.add_argument("--bstr-exe", type=Path)
    p.add_argument("--goose-exe", type=Path)
    p.add_argument("--suite", choices=["substring", "byteset", "boundary", "upstream", "records"], default="substring")
    p.add_argument("--memchr-checkout", type=Path)
    p.add_argument("--record-corpus", type=Path, help="uncompressed record corpus")
    p.add_argument("--case", action="append")
    p.add_argument("--measure", action="store_true", help="opt in to real timings; default is untimed Mojo verification")
    p.add_argument("--samples", type=int, default=5)
    p.add_argument("--sample-ms", type=int, default=50)
    p.add_argument("--output", type=Path)
    args = p.parse_args()
    if args.measure and (not args.output or not args.bstr_exe or not args.goose_exe):
        p.error("measurement requires --output, --bstr-exe, and --goose-exe")
    if args.measure and platform.system() != "Linux":
        p.error("use Linux for now: Mojo runner does not match Goose/Rust's macOS QoS setup")
    if args.samples < 3 or args.sample_ms < 1:
        p.error("at least 3 samples and positive sample-ms required")
    source = args.goostr_source.resolve() / "bench/compare.py"
    spec = importlib.util.spec_from_file_location("goostr_compare", source)
    upstream = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(upstream)
    provenance = None
    if args.suite == "upstream":
        if not args.memchr_checkout:
            p.error("upstream suite requires --memchr-checkout")
        cases, provenance = upstream.upstream_cases(args.memchr_checkout.resolve())
    elif args.suite == "records":
        if not args.record_corpus:
            p.error("records suite requires --record-corpus")
        cases = [("records", args.record_corpus.read_bytes(), b"|")]
    else:
        cases = list({"substring": upstream.cases, "byteset": upstream.byteset_cases,
                      "boundary": upstream.boundary_cases}[args.suite]())
    modes = upstream.BYTESET_MODES if args.suite == "byteset" else upstream.SUBSTRING_MODES + upstream.COUNT_MODES
    if args.suite == "records":
        modes = ["records"]
    if args.case:
        cases = [case for case in cases if any(fnmatch.fnmatchcase(case[0], pat) for pat in args.case)]
    if not cases:
        p.error("no cases selected")
    programs = [("mojo", args.mojo_exe.resolve())]
    if args.measure:
        programs += [("bstr", args.bstr_exe.resolve()), ("goose", args.goose_exe.resolve())]
    rows = []
    with tempfile.TemporaryDirectory(prefix="mojo-bstr-bench-") as tmp:
        h, n = Path(tmp) / "haystack", Path(tmp) / "needle"
        for name, data, pattern in cases:
            h.write_bytes(data)
            n.write_bytes(pattern)
            for mode in modes:
                want = expected(data, pattern, mode)

                def run(exe, iterations, verify=False):
                    command = [str(exe), str(h), str(n), mode, str(iterations)]
                    result = subprocess.check_output(command + (["--verify"] if verify else []), text=True)
                    elapsed, checksum = map(int, result.split())
                    assert checksum == (want + 1) * iterations, (name, mode, checksum, want)
                    if verify:
                        assert elapsed == 0
                    return elapsed

                run(programs[0][1], 1, verify=True)
                row = dict(case=name, mode=mode, expected=want,
                           haystack_sha256=hashlib.sha256(data).hexdigest(),
                           needle_hex=pattern.hex(), haystack_length=len(data))
                if args.measure:
                    target = args.sample_ms * 1_000_000
                    iterations, times = {}, {name: [] for name, _ in programs}
                    for label, exe in programs:
                        count = 1
                        while True:
                            elapsed = run(exe, count)
                            if elapsed >= target or count >= 100_000_000:
                                break
                            count = min(100_000_000, count * min(100, max(2, target // max(1, elapsed))))
                        iterations[label] = count
                    for sample in range(args.samples):
                        offset = sample % len(programs)
                        for label, exe in programs[offset:] + programs[:offset]:
                            count = iterations[label]
                            times[label].append(run(exe, count) / count)
                    row.update(iterations=iterations, samples_ns=times,
                               medians_ns={key: statistics.median(values) for key, values in times.items()})
                    print(name, mode, row["medians_ns"], flush=True)
                rows.append(row)
    if args.output:
        metadata = dict(platform=platform.platform(), cpu=platform.processor(),
                        cpuinfo=Path("/proc/cpuinfo").read_text() if Path("/proc/cpuinfo").exists() else None,
                        affinity=sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None,
                        timestamp_utc=datetime.now(timezone.utc).isoformat(), measured=args.measure,
                        versions={tool: subprocess.check_output([tool, "--version"], text=True).strip()
                                  for tool in (["mojo", "rustc"] if args.measure else ["mojo"])},
                        binaries={label: hashlib.sha256(exe.read_bytes()).hexdigest() for label, exe in programs},
                        cases_source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), upstream=provenance,
                        samples=args.samples, sample_ms=args.sample_ms)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(dict(environment=metadata, results=rows), indent=2) + "\n")
    print(f"{len(rows)} workloads verified" + (" and measured serially" if args.measure else "; no timers executed"))


if __name__ == "__main__":
    main()
