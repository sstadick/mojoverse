# Benchmark adapters

**Performance parity is not yet achieved.** Results below show measured gaps
and the workloads used to compare Mojo, Rust, and Goose.

## Local comparison, 10 November 2026

Linux x86-64, Ryzen 9 3950X, affinity CPU 0; Mojo 1.2.0 (2016d0cd), Rust
1.97.1/bstr 1.13.1, and Goose. Mojo used O3/host
features; Rust used its release build and runtime dispatch; Goose used O2
generation and Clang O3. The targets are not identical. Five rotated samples
per workload, calibrated to at least 10 ms, ran serially without concurrent
agent builds/tests. Checksums were checked before accepting every timing.

Ratios are Mojo time / the faster Rust-or-Goose median for each workload;
below 1 is faster. Aggregate medians are unweighted, not throughput totals.

| Suite | Workloads | Median ratio | At least as fast | Within 25% |
| --- | ---: | ---: | ---: | ---: |
| Substring/search/count | 186 | 1.328× | 74 | 92 |
| Byte-set search | 52 | 1.381× | 4 | 19 |

Important regressions remain: prepared reverse tail-miss search is 14.96×
slower; several long reverse/count cases are 13–14× slower. Inverted full-set
search is 3,329–3,799× slower than Goose, which detects the complete byte set
and skips scanning; Mojo and Rust scan the input. Small two-byte set misses
are up to 12.98× slower. These cases prevent a general near-parity claim.
An additional 804 boundary workloads pass untimed verification. Rebar and
UTF-8/operation timing coverage must not be inferred from these two suites.

Raw per-engine samples, fixture/binary hashes and host metadata are retained
in the local validation outputs `substring-final.json` and `byteset-final.json`.
Reproduce with the commands below, adding `--samples 5 --sample-ms 10`.

## Untimed validation

```sh
pixi run bench-verify
pixi run mojo build -I . bench/search.mojo -o /tmp/mojo-bstr-search
pixi run python bench/compare.py --goostr-source ../goostr \
  --mojo-exe /tmp/mojo-bstr-search --suite substring
```

`bench-verify` builds both runners and checks search/count/checksum semantics,
binary KLV input, escaped patterns, multi-needle models, and invalid protocol
input. `--verify` on either runner bypasses every clock read and emits a zero
duration. `compare.py` defaults to this mode; it measures only with `--measure`.
Its fixtures come from goostr's `bench/compare.py`. Additional suites are `byteset`,
`boundary`, `upstream` (requires `--memchr-checkout`), and `records` (requires
`--record-corpus`, an uncompressed newline/pipe corpus).

## Rust bstr / Goose / Mojo on one Linux host

Build all three on that host. Set `GOOSTR` to the current source checkout and
`OUT` to a scratch directory. The Goose compiler and its goosimd dependency must
already be installed as in goostr's benchmark setup.

```sh
mkdir -p "$OUT"
pixi run mojo build -O3 -I . bench/search.mojo -o "$OUT/mojo-search"
clang -O3 -c "$GOOSTR/bench/opaque.c" -o "$OUT/opaque.o"
cargo rustc --locked --release --manifest-path tests/oracle/Cargo.toml \
  --features bench --bin search-bench -- --check-cfg 'cfg(bench_external_barrier)' \
  -C "link-arg=$OUT/opaque.o"
goose --standalone -O2 -o "$OUT/goose-search.c" "$GOOSTR/bench/search.goose"
clang -O3 "$OUT/goose-search.c" "$OUT/opaque.o" -o "$OUT/goose-search" -lm -pthread -ldl
taskset -c "$CPU" pixi run python bench/compare.py \
  --goostr-source "$GOOSTR" --mojo-exe "$OUT/mojo-search" \
  --bstr-exe tests/oracle/target/release/search-bench --goose-exe "$OUT/goose-search" \
  --suite substring --measure --output bench/results/substring.json
```

Repeat for bytesets and boundaries. Set `CPU` to a permitted logical CPU. Keep
the build commands/tool versions with results. Mojo defaults to host CPU/features
and O3; upstream Rust uses its release profile and runtime memchr dispatch;
Goose uses O2 inlining then Clang O3 and runtime dispatch. These are not identical
code-generation targets. Report that distinction, or run an explicitly labeled
native-CPU configuration of **all** engines. Rebuild the binaries on the measured host.
The serial harness currently requires Linux: it does not match the other
runners' macOS foreground QoS initialization.

The file runner uses goostr's `haystack needle mode iterations` protocol,
discards one full warmup pass, and prints `elapsed_ns checksum`. Each loop uses
Mojo `black_box` on the spans, corresponding to Rust's inline black-box and
Goose's default inline assembly barrier; do not mix external-barrier binaries.
File I/O and prepared searcher construction are outside timing. Checksums are
validated against Python's independent byte operations. Calibration targets
50 ms by default, followed by five samples with rotated engine order. JSON
retains all samples, fixture/binary hashes, tool versions, CPU, and affinity.
Tiny-case clock/barrier overhead is part of the result, not subtracted.

## Pinned memchr / rebar suite

- memchr: `5fdb40c054e1fff359a2f7bdf7f87a13b34b465d` (2.8.3)
- rebar: `463d00f31887e84c38467805b9e3122c314b9521`
- bstr differential oracle: 1.13.1, pinned in `tests/oracle/Cargo.lock`

Set `MEMCHR` to a disposable checkout at that revision, and `REBAR` to the built
rebar executable at its revision. It can be the parent's goostr comparison
checkout: registration preserves existing Goose engines and verifies that
definitions differ from upstream only in engine lists. It refuses to overwrite
an existing Mojo registration. No fixtures or expected counts are rewritten.

```sh
pixi run mojo build -O3 -I . -I bench bench/rebar/main.mojo -o "$OUT/mojo-rebar"
pixi run python bench/rebar/register.py --memchr-checkout "$MEMCHR" \
  --mojo-exe "$OUT/mojo-rebar"
"$REBAR" build -d "$MEMCHR/benchmarks" -e '^mojo/bstr/' -e '^rust/memchr/'
taskset -c "$CPU" "$REBAR" measure -d "$MEMCHR/benchmarks" \
  -e '^mojo/bstr/' -e '^rust/memchr/' -e '^goose/goostr/' --verify
taskset -c "$CPU" "$REBAR" measure -d "$MEMCHR/benchmarks" \
  -e '^mojo/bstr/' -e '^rust/memchr/' -e '^goose/goostr/' \
  --max-time 100ms --max-warmup-time 50ms --max-iters 20000 --timeout 30s \
  > "$OUT/round-1.csv"
```

For **strictly untimed validation**, register with `--verify-only` in a separate
checkout, then run rebar `measure -e '^mojo/bstr/' --verify --verbose`. Every
engine receives `--verify`; no search timing is performed. Do not measure that
registration: its zero durations are placeholders, not performance data.

The eight modes cover forward/reverse 1/2/3-byte search, one-shot memmem and
prepared memmem. Models cover nonoverlapping count, byte count,
needles-in-needles and needles-in-haystack. Empty substring count is rejected,
matching goostr's guard against the upstream model's non-advancing empty needle.
Preparation/parsing/output are outside timing; one-shot search preparation is
inside each operation. Warmup consumes its result through a black box; measured
samples have no added barrier. Byte counts repeatedly call public search;
upstream reverse memchr uses iterators, so iteration/setup costs differ.

Registration records source/compiler/binary/fixture provenance in
`benchmarks/engines/mojo-bstr/provenance.json`. Save it with CSVs, CPU affinity,
build flags, other engine provenance and command lines. Run at least two rounds,
retain failures and every sample, compare common cases with rebar `cmp`, and
avoid calling one architecture or tuned corpus universal parity. The parent
owns combined report generation and common-host performance evaluation.
