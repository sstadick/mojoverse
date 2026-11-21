#!/usr/bin/env python3
"""Serial, matched-affinity whole-application comparisons with output hashing.

Uses the same workload, chunk/worker counts and rotating order as c-perbase's
benchmark. A named program is an explicit binary, never a changing cargo target.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess

WORKLOADS = {
    "base": ("base-depth", []),
    "base-mates": ("base-depth", ["-m"]),
    "depth": ("only-depth", []),
    "depth-mates": ("only-depth", ["-m"]),
    "depth-fast": ("only-depth", ["-x"]),
}


def digest(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("bam", type=Path)
    p.add_argument("--program", action="append", required=True, help="NAME=/absolute/binary")
    p.add_argument("--output", type=Path, required=True, help="new results directory")
    p.add_argument("--runs", type=int, default=5)
    p.add_argument("--warmups", type=int, default=1)
    p.add_argument("--workloads", nargs="+", choices=WORKLOADS, default=list(WORKLOADS))
    a = p.parse_args()
    if a.runs < 1 or a.warmups < 0:
        p.error("invalid run count")
    programs = {n: Path(v).resolve(strict=True) for n, v in (s.split("=", 1) for s in a.program)}
    if len(programs) != len(a.program): p.error("duplicate program name")
    bam = a.bam.resolve(strict=True)
    a.output.mkdir(parents=True, exist_ok=False)
    out = a.output.resolve()
    cpus = sorted(os.sched_getaffinity(0))
    env = {k: v for k, v in os.environ.items() if not k.startswith(("MALLOC_", "MIMALLOC_")) and k != "LD_PRELOAD"}
    root = Path(__file__).resolve().parents[1]
    packages = root.parents[1] / "packages"
    sources = [*root.glob("*.mojo"), root / "native/perbase.c", root / "pixi.toml"]
    sources.extend((packages / "mojo-bio/src/bio").rglob("*.mojo"))
    for name in ("extramojo", "mojo-libdeflate", "mojo-threads", "mojopt"):
        sources.extend((packages / name / name.removeprefix("mojo-")).rglob("*.mojo"))
    report = {
        "method": "Serial rotating/reversed order; warm cache; regular TSV; close, not fsync; SHA256 outside timing.",
        "input": str(bam), "input_sha256": digest(bam), "input_bytes": bam.stat().st_size,
        "cpus": cpus, "threads": 32, "chunksize": 1000000,
        "warmups": a.warmups, "measured_runs": a.runs,
        "programs": {n: {"path": str(v), "sha256": digest(v)} for n, v in programs.items()},
        "mojo_sources": {str(v): digest(v) for v in sorted(sources)},
        "runner_sha256": digest(Path(__file__)), "runs": [],
    }
    for workload in a.workloads:
        command, flags = WORKLOADS[workload]
        expected = None
        for round_ in range(a.warmups + a.runs):
            names = list(programs)
            pivot = round_ % len(names)
            names = names[pivot:] + names[:pivot]
            # Reverse after a full rotation; reversing every round cancels
            # rotation entirely in a two-program comparison.
            if (round_ // len(names)) % 2: names.reverse()
            for name in names:
                number = len(report["runs"]) + 1
                tsv = out / "output.tsv"
                timing = out / f"run-{number}.time"
                cmd = ["taskset", "-c", ",".join(map(str, cpus)), str(programs[name]), command,
                       str(bam), "-t", "32", "-c", "1000000", *flags, "-o", str(tsv)]
                with (out / f"run-{number}.log").open("w") as log:
                    subprocess.run(["/usr/bin/time", "-f", "%e %U %S %M", "-o", str(timing), *cmd],
                                   env=env, stdout=log, stderr=log, check=True)
                wall, user, system, rss = map(float, timing.read_text().split())
                observed = (tsv.stat().st_size, digest(tsv))
                if expected is None: expected = observed
                if expected != observed: raise RuntimeError((workload, name, observed, expected))
                report["runs"].append({"workload": workload, "program": name,
                    "warmup": round_ < a.warmups, "round": round_ - a.warmups, "command": cmd,
                    "wall_s": wall, "cpu_s": user + system, "peak_rss_kib": rss,
                    "output_bytes": observed[0], "output_sha256": observed[1]})
                tsv.unlink()
                (out / "results.json").write_text(json.dumps(report, indent=2) + "\n")
                print("PASS", workload, name, "warmup" if round_ < a.warmups else "measured", wall, flush=True)
    report["summary"] = {}
    for workload in a.workloads:
        report["summary"][workload] = {}
        for name in programs:
            runs = [r for r in report["runs"] if r["workload"] == workload and r["program"] == name and not r["warmup"]]
            summary = {"wall_runs_s": [r["wall_s"] for r in runs],
                       "median_wall_s": statistics.median(r["wall_s"] for r in runs),
                       "median_cpu_s": statistics.median(r["cpu_s"] for r in runs),
                       "median_rss_gib": statistics.median(r["peak_rss_kib"] for r in runs) / 1048576}
            report["summary"][workload][name] = summary
            print("SUMMARY", workload, name, summary, flush=True)
    (out / "results.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
