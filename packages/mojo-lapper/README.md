# mojo-lapper

Interval overlap queries for Mojo, with CPU queries and GPU batch counting.
Distribution: `mojo-lapper`; import: `lapper`.

[API reference](https://sstadick.github.io/mojoverse/mojo-lapper/lapper/_index.html)

## Install

Choose a commit from `main` for nightly Mojo or `stable/1.2` for Mojo 1.2.0.
Match the compiler pin and channel to that revision: `max-nightly` for
nightly, `max` for stable. Use one revision for all Mojoverse dependencies.

The stable toolchain is **Mojo 1.2.0** and **MAX core 26.7.0**.
With Pixi 0.80 or newer, add to your `pixi.toml`. Replace `<full-commit>` with
a Mojoverse commit and use the same revision for every Mojoverse dependency:

```toml
[workspace]
name = "interval-example"
channels = ["https://conda.modular.com/max", "conda-forge"]
platforms = ["linux-64", "linux-aarch64", "osx-arm64"]
preview = ["pixi-build"]
requires-pixi = ">=0.80"

[dependencies]
mojo = "=1.2.0"
mojo-lapper = { git = "https://github.com/sstadick/mojoverse.git", rev = "<full-commit>", subdirectory = "packages/mojo-lapper" }
```

Run `pixi install`, then `pixi run mojo run main.mojo`; no source include path
is needed. The radix-sort dependency resolves from the same Git revision.

## Query intervals

```mojo {doctest="overlap" global=true}
from lapper import Interval, Lapper
from std.testing import assert_equal

def main() raises:
    var intervals: List[Interval] = [Interval(10, 20, 1), Interval(18, 30, 2)]
    var index = Lapper(intervals^)
    assert_equal(index.count(19, 21), UInt(2))
    assert_equal(index.count(30, 40), UInt(0))
    var matches = List[Interval]()
    index.find(5, 11, matches)
    assert_equal(len(matches), 1)
```

`Interval(start, stop, value)` represents a half-open range with `UInt32`
endpoints and an `Int32` payload. Overlap requires `a.start < b.stop` and
`a.stop > b.start`; touching boundaries do not overlap.

`Lapper(intervals^)` takes ownership of the list. Use `intervals.copy()` to
retain a separate copy. `count(start, stop)` returns the number of matches;
`find(start, stop, results)` appends matching intervals to the destination.

For a reduction, use `visit(start, stop, visitor)` to consume each match as
it is found. This avoids writing matches into a list and reading them again.
The visitor is specialized at compile time; calls are synchronous and ordered
by start, then stop. Its state is not reset between queries. Keep the index
unchanged during a visit. Borrowed indexes must refer to live host memory.

```mojo {doctest="visitor" global=true}
from lapper import Interval, IntervalVisitor, Lapper
from std.testing import assert_equal

@fieldwise_init
struct SumPayloads(IntervalVisitor):
    var total: Int

    def visit(mut self, interval: Interval):
        self.total += Int(interval.val)

def main() raises:
    var intervals: List[Interval] = [Interval(10, 20, 3), Interval(18, 30, 7)]
    var index = Lapper(intervals^)
    var visitor = SumPayloads(0)
    index.visit(19, 21, visitor)
    assert_equal(visitor.total, 10)
    index.visit(30, 40, visitor)
    assert_equal(visitor.total, 10)
```

`find` and `visit` use the same overlap predicate and ordering. Visitors cannot
raise or stop traversal early.

## CPU query index

Owning CPU indexes use 32-interval blocks, prefix maximum ends to locate the
first candidate, and a max tree to skip runs of blocks ending before the query.
Dense blocks emit a prefix of intervals; mixed blocks use native-width SIMD overlap masks, with a
bounded scalar tail. Results remain ordered by start, then stop.

`Lapper` only builds the overlap traversal index: it does not allocate or sort
an independent copy of the ends. Its `count` visits matches without collecting
them, so use `BITSLapper` instead when only counts are needed.

Construction uses `mojo-radix-sort`'s integer radix sort, preserving start/stop ordering
and payload associations; already-ordered intervals skip sorting. Ordering among
intervals with identical start and stop coordinates is unspecified.
`Lapper[owns_data=False](starts, stops, vals, length, max_len)` borrows prebuilt
arrays. Keep their owners alive and do not mutate indexed arrays after construction.

## Count-only BITS index

`BITSLapper` stores just independently sorted starts and ends, with no payloads
or traversal metadata. Each `count` uses two binary searches, independent of
the number of matches. Both endpoint arrays use the same radix sorter and
skip sorting when already ordered.

```mojo {doctest="bits" global=true}
from lapper import BITSLapper, Interval
from std.testing import assert_equal

def main() raises:
    var intervals: List[Interval] = [Interval(18, 30, 2), Interval(10, 20, 1)]
    var counts = BITSLapper(intervals^)
    assert_equal(counts.count(19, 21), UInt(2))
    assert_equal(counts.count(20, 30), UInt(1))
    assert_equal(counts.count(30, 40), UInt(0))
```

The list must be nonempty and each stored interval must have `start < stop`;
otherwise construction raises. Query endpoints must satisfy `start <= stop`.
As with `Lapper`'s strict overlap predicate, an empty query counts intervals
strictly spanning that position. `BITSLapper` has no `find` or `visit` method.
`BITSLapper[owns_data=False](starts, stops_sorted, length)` borrows independently
sorted endpoint arrays with the same interval requirements and lifetime rules.

## GPU use

`Lapper.prep_for_gpu` requires mutable device buffers. The returned Lapper
borrows starts, stops and values; no independently sorted ends are prepared.
For BITS counting, upload `BITSLapper`'s sorted endpoint arrays and use
`count_overlaps_kernel`, which takes only those two arrays, the interval count,
packed queries, query length, output and output length. Retain all backing
buffers until queued work finishes. Kernel lengths are `UInt64`, including
query and output lengths.
See [benchmarks/bench_lapper.mojo](benchmarks/bench_lapper.mojo) for a complete
GPU example with explicit buffer ownership and synchronization.

GPU execution requires compatible hardware. These commands check NVIDIA
compilation without executing a kernel:

```sh
pixi run bg --target-accelerator sm_80
pixi run bl --target-accelerator sm_80
```

Compile-only checks do not establish GPU correctness or performance.

## Develop

Install Pixi 0.80 or newer, then run:

```sh
pixi run t                 # CPU tests
pixi run test-consumer     # Build and test an isolated installed package
pixi run format
pixi run docs              # This monorepo's root documentation tools
pixi build --path . --output-dir dist  # Local archive only
```

`main` tracks nightly Mojo; `stable/1.2` supports Mojo 1.2.0.
CPU targets are Linux x86-64, Linux ARM64, and Apple-silicon macOS.

The documentation task executes the marked example and builds `target/docs`.
CPU/GPU benchmark commands are `pixi run bc`, `pixi run bg`, and `pixi run bl`;
run the resulting `cpu_bench`, `gpu_bench`, or `lapper_bench` executable.

MIT licensed; see [LICENSE](LICENSE).
