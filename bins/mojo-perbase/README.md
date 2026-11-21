# Mojo Perbase

Experimental, native Mojo port of Perbase's indexed **BAM** workloads. This is
an independent project following Mojoverse's package conventions, not a wrapper
around the C, Rust or Goose executable. It is not the official Perbase release.

The BAM decoder is in [`mojo-bio`](../../packages/mojo-bio). Counting, mate selection,
sparse depth traversal, interval/reference parsing, formatting and scheduling
are Mojo. `mojo-libdeflate` packages the unchanged libdeflate 1.26 codec and
inlined bindings. `mojo-threads` supplies reusable pthread workers/monitors;
Perbase retains scheduling, byte-bounded mailboxes and ordered output. The
small C library under `native/` now contains only application-specific
stat/write/SIGPIPE glue. CLI parsing uses mojopt from the same monorepo;
strict numeric ranges and command restrictions are validated before opening output.

## Install

With [Pixi](https://pixi.prefix.dev/) 0.80 or newer, install directly from Git.
Replace `<full-commit>` with a Mojoverse commit:

```sh
pixi global install --git https://github.com/sstadick/mojoverse.git \
  --rev '<full-commit>' --subdirectory bins/mojo-perbase \
  -c https://conda.modular.com/max -c conda-forge
mojo-perbase --help
```

Dependencies resolve from the same Git revision; no local checkout is required.
For a project dependency, use [Mojoverse dependency setup](../../README.md#use-a-dependency)
with `subdirectory = "bins/mojo-perbase"`.

## Usage

```sh
mojo-perbase base-depth reads.bam -t 32 -c 1000000 -o counts.tsv
mojo-perbase only-depth reads.bam -m -o depth.tsv
```

## Build and test

For local development, clone Mojoverse and run from `bins/mojo-perbase`:

```sh
pixi install --locked
pixi run t
pixi run consumer
```

Stable Mojo 1.2.0 is pinned across development, host, build and runtime.
Local Mojo/CMake build backends are pinned too, avoiding different dependency
metadata from an old backend cache versus a fresh machine. The same lockfiles
install with `--locked` on both tested platforms.
`pixi-build-mojo` packages the application and libraries; nested CMake packages
build the static codec and POSIX glue with Clang 18.1.8 on Linux or Apple Clang
on macOS, with `-O3 -march=native`.
Mojo uses `-O3` and its default host CPU/features. These experimental artifacts
are **host-specific**, not portable release binaries. Linux x86-64 and Apple
Silicon macOS have native build and installed-consumer checks. Linux AArch64
is declared as a source target but has not been run on an AArch64 Linux host.
macOS requires Xcode command-line tools; Intel Macs and Windows are not targets.

`consumer` builds local conda artifacts, installs exact archive URLs/SHA-256s in
an isolated Pixi cache/prefix, and exercises the application and library APIs
without source-checkout include paths. Nothing is uploaded or published remotely.
The established benchmark driver uses Linux affinity and GNU time; it is not a
cross-platform timing harness.

## Supported behavior and limits

- `base-depth`, nine mate-resolution strategies, flag/mapq/base-quality filters,
  max-depth admission, missing sequence and long CIGARs.
- `only-depth`, sparse changed-word traversal, mate union, fast span mode,
  zero/one-based output and merged/unmerged/BED formats.
- BAI/CSI, BED/VCF/BCF intervals, indexed plain/BGZF FASTA.
- `merge-adjacent`, quoted/multiline TSV and stdin.
- Ordered plain/BGZF output; persistent counting and compression workers.
  `-T` controls BGZF compression concurrency, bounded by available CPUs.

**CRAM/CRAI is not implemented** and is rejected. This is not full format parity
with Goose or C Perbase. Inputs must be local, indexed and coordinate sorted.
Coordinates and region payloads follow the current Goose limits. Ambiguous mate
groups with more than two records retain the reference comparator caveat.
Worker failures terminate the CLI; partial output must be discarded.

## Performance and verification

`bench/run.py` runs explicit binaries serially with inherited CPU affinity,
32 requested threads, 1 Mb chunks, regular TSV output, one warmup and five
measured samples by default. Every output is hashed outside timing. Compare
whole applications; LLVM use alone does not establish a speed advantage.

```sh
taskset -c 0-31 python3 bench/run.py paper-chr20-full.bam \
  --program mojo=.pixi/envs/default/bin/mojo-perbase \
  --program c=../c-perbase/build/c-perbase --output results/comparison
```

`tests/smoke.py` uses independent stdlib-only BAM/count fixtures, including
compression-ring reuse, output errors and hardlink protection. To run the
existing Goose suite with its assertions unchanged, use Python with pysam:

```sh
python tests/compare.py --source ../goose-perbase \
  --oracle ../c-perbase/build/c-perbase \
  --binary .pixi/envs/default/bin/mojo-perbase
```

CRAM and the reference benchmark driver are explicitly skipped. See `NOTICE`
for algorithm provenance. Benchmark evidence records unsuccessful experiments
as well as retained optimizations; timings are not a language-wide ranking.

### Selected local results

HG00157 chr20 BAM with the original whole-genome header, Ryzen 9 3950X,
CPUs 0–31, `-t 32 -c 1000000`. Five-run medians after one warmup, rotating
serial order, warm cache, complete regular TSV files, no fsync. The preceding
Mojo executable is also a control: all 120 output length/SHA-256 checks matched.
No builds, tests or profiling overlapped timing.

| Workflow | C | Goose G3 | Mojo before | Mojo selected |
| --- | ---: | ---: | ---: | ---: |
| base-depth | 4.54 s | 4.76 s | 4.38 s | 4.40 s |
| base-depth -m | 4.99 s | 5.22 s | 4.88 s | 4.82 s |
| only-depth | 1.24 s | 1.06 s | 1.20 s | 0.94 s |
| only-depth -m | 1.23 s | 1.09 s | 1.18 s | 0.98 s |
| only-depth -x | 1.23 s | 1.04 s | 1.19 s | 0.91 s |

This third pass targets Mojo only-depth: 17–24% less elapsed time than its
preceding build, and 10–13% less than Goose in this cohort. Base-depth is
effectively unchanged (4.38 → 4.40 s, overlapping ranges); its mate-fixed
median improves slightly. These are implementation results on one BAM dataset,
not language-wide rankings. C and Goose are unchanged controls; the second-pass
cohort is preserved in `results/optimization-pass3.json`.

Only-depth now quotes its reference prefix once per region and reserves space
for all three numeric fields before writing them. The shared integer formatter
writes digit pairs backwards into a fixed 20-byte stack array, then copies the
initialized suffix; it no longer writes individual digits and reverses them.
All u64 decimal-width boundaries and embedded-zero pairs are covered through
the CLI. This leaves counting, parsing/validation, scheduling and output bytes
unchanged. It adds no stdlib replacement or new library dependency.

The three-run paired experiments were 1.21 → 1.01 s for prefix/reservation,
then 1.00 → 0.91 s for digit pairs (normal only-depth); these separate pairs
are not additive estimates. The five-run installed-build table above is the
selected result. Summed CPU improved much less than wall time: 8.49 → 8.25 s
for normal only-depth. The result is an elapsed-time improvement in this ordered
pipeline, not a 22% reduction in total CPU work.

The selected build keeps
inline reserve checks with cold growth, pre-sized scratch, SIMD nibble decoding,
base-counter lookup and fused non-mate contributions. The second pass adds
comptime mate/non-mate specialization, a comptime-unrolled 17-counter formatter
with one capacity reservation, short-decimal fast paths, and a reference prefix
quoted once per region. Additional unchecked counter indexing was unnecessary:
the original release assembly already had no bounds branch there.

The biggest elapsed-time correction was outside the Mojo hot loop. The POSIX
glue called `ftruncate(fd, 0)` even for a new empty file. On this ext4 filesystem,
that set up delayed-allocation work at close: syscall traces showed 1.30 seconds
in the final `close()`. Skipping the redundant truncate reduced paired medians
from 5.70/6.80 to 4.55/4.97 seconds. Existing nonempty files still get truncated,
and inode/hardlink protection remains. This matches the benchmark's intended
close-without-fsync behavior; it is not a durability guarantee.

With that confound removed, retesting libc-owned `malloc/realloc/free` byte
buffers reduced paired medians from 4.48/5.07 to 4.30/4.80 seconds and saved
about 13 summed CPU-seconds and 1 GiB RSS per base-depth run. It is now retained.
The earlier rejection remains in the experiment history; it was based on noisy
end-to-end results before identifying the close-time difference. Ordinary Mojo
lists still use the Mojo allocator. No custom MLIR was needed for these gains.
Forced major-function outlining and mate-path contribution fusion remain rejected.

In that optimization pass, release and assertion-enabled Mojo AddressSanitizer configurations each passed
the 930-invocation reference differential suite, 64 boundary/regional
invocations and 24 independent CLI checks. These counts include oracle calls.
Native codec/glue libraries were not sanitizer-instrumented in this Mojo
check. ThreadSanitizer historically could not start due to an unexpected memory
mapping; it was not retried in this pass. The new installed package also passed
the full 930-invocation suite and 24 CLI checks. Clean-prefix application and
installed-reader checks passed in the preceding pass without source include
paths. No general language-performance or memory-safety claim follows.

Raw selected samples, source/build identity and rejected experiments are kept
under `results/` and in the existing Perbase benchmark gist.

### Packaging acceptance

The mojopt/thread/codec extraction leaves counting and formatting unchanged.
The final installed build was compared with the pre-cleanup executable using
the same dataset, affinity, worker count and output protocol above. Five measured
runs per workflow followed one warmup. The runner now reverses after each full
rotation: reversing every round had accidentally canceled rotation for two
programs. No builds or tests overlapped timing. All 60 complete-output size and
SHA-256 checks matched.

| Workflow | Before cleanup | Packaged |
| --- | ---: | ---: |
| base-depth | 4.35 s | 4.32 s |
| base-depth -m | 4.78 s | 4.81 s |
| only-depth | 0.94 s | 0.95 s |
| only-depth -m | 0.95 s | 0.95 s |
| only-depth -x | 0.93 s | 0.92 s |

Medians stay within about 1.1%; sample ranges overlap in every workflow. This
supports retaining the packaging changes, not claiming a new speedup or exact
zero overhead. Raw samples and final binary hashes are in
`results/packaging-benchmarks.json`.

Linux release and assertion-enabled AddressSanitizer builds each passed 930
differential invocations, 64 boundary/real-region invocations and 48 independent
CLI checks. Unlike the preceding pass, this sanitizer build instruments the
pthread/output C glue and libdeflate too. No sanitizer findings were reported;
ThreadSanitizer was not rerun. Fresh-prefix consumer checks pass on Linux
x86-64 and Apple Silicon macOS, including allocating/restarting workers, codec
roundtrips, sequence decoding and the CLI. macOS runs 45 CLI checks, excluding
Linux `/dev/full` cases; it has not run the Linux full real-data suite.

`results/packaging-validation.json` records source identities, compiler-command
audits, unchanged algorithms, shared lockfile hashes and test evidence. Native
Linux AArch64 execution and publication remain outstanding. All packages are
local and unpublished; no release or language-performance claim follows.
