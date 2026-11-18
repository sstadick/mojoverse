# mojo-lapper

Interval overlap queries for Mojo, with CPU queries and GPU batch counting.
Distribution: `mojo-lapper`; import: `lapper`.

[API reference](https://sstadick.github.io/mojoverse/mojo-lapper/lapper/_index.html)

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

`count` uses binary interval search (BITS). Construction uses `mojo-bio`'s
integer radix sort, preserving start/stop ordering and payload associations;
already-ordered intervals and ends skip sorting. Ordering among intervals
with identical start and stop coordinates is unspecified. The six-argument
pointer constructor borrows prebuilt index arrays. Do not mutate indexed
arrays after construction.

## Install

The stable toolchain is **Mojo 1.2.0** and **MAX core 26.7.0**.
For a consumer beside the Mojoverse checkout:

```toml
[workspace]
name = "interval-example"
channels = ["https://conda.modular.com/max", "conda-forge"]
platforms = ["linux-64"]
preview = ["pixi-build"]

[dependencies]
mojo = "=1.2.0"
mojo-lapper = { path = "../mojoverse/packages/mojo-lapper" }
```

Run `pixi run mojo run main.mojo`; no source include path is needed.
For pinned Git dependencies, use [Mojoverse dependency setup](https://github.com/sstadick/mojoverse#use-a-dependency)
with `subdirectory = "packages/mojo-lapper"`.

## GPU use

`Lapper.prep_for_gpu` requires mutable device buffers. The returned Lapper
borrows those buffers: keep them alive until all queued work finishes.
Kernel lengths are `UInt64`, including query and output lengths.
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

`main` targets stable Mojo; `nightly` tracks nightly compiler compatibility.
CPU targets are Linux x86-64, Linux ARM64, and Apple-silicon macOS.

The documentation task executes the marked example and builds `target/docs`.
CPU/GPU benchmark commands are `pixi run bc`, `pixi run bg`, and `pixi run bl`;
run the resulting `cpu_bench`, `gpu_bench`, or `lapper_bench` executable.

MIT licensed; see [LICENSE](LICENSE).
