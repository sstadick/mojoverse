"""Deterministic CPU find/visit workloads, with construction timed separately.

Build in the root source environment with -O3 --march native and source
includes for packages/mojo-lapper and packages/mojo-bio/src.
Run on an idle pinned core; repeat the executable for independent samples.
No parsing or I/O is timed. Compare checksums across revisions; collecting
and streaming consume the same payloads, and a linear scan checks sample queries.
"""

from lapper.lapper import Interval, IntervalVisitor, Lapper
from std.time import perf_counter_ns
from std.testing import assert_equal


@fieldwise_init
struct Sum(IntervalVisitor):
    var matches: UInt64
    var checksum: UInt64

    @always_inline
    def visit(mut self, interval: Interval):
        self.matches += 1
        self.checksum += UInt64(interval.val)


def run(shape: String, n: Int, queries: Int) raises:
    var intervals = List[Interval](capacity=n)
    for i in range(n):
        var start = UInt32(i * 8)
        var stop = start + 3
        if shape == "span" and i == 0:
            stop = UInt32(n * 8)
        elif shape == "dense":
            stop += 4096
        elif shape == "mixed":
            stop += UInt32((i * 17) % 8192)
        intervals.append(Interval(start, stop, Int32(i)))

    var begin = perf_counter_ns()
    var index = Lapper(intervals^)
    var built = perf_counter_ns()
    var results = List[Interval]()
    var matches = UInt64(0)
    var checksum = UInt64(0)
    var expected_matches = UInt64(0)
    var expected_checksum = UInt64(0)
    # Compute the sparse oracle outside both timed regions.
    for q in range(queries):
        var i = (q * 7919) % n
        expected_matches += 1 + UInt64(shape == "span" and i != 0)
        expected_checksum += UInt64(i)
    var queried = perf_counter_ns()
    for q in range(queries):
        var start = UInt32(((q * 7919) % n) * 8 + 1)
        results.clear()
        index.find(start, start + 1, results)
        matches += UInt64(len(results))
        for iv in results:
            checksum += UInt64(iv.val)
    var end = perf_counter_ns()
    if shape == "plain" or shape == "span":
        assert_equal(matches, expected_matches)
        assert_equal(checksum, expected_checksum)
    var visitor = Sum(0, 0)
    var visited = perf_counter_ns()
    for q in range(queries):
        var start = UInt32(((q * 7919) % n) * 8 + 1)
        index.visit(start, start + 1, visitor)
    var finished = perf_counter_ns()
    assert_equal(visitor.matches, matches)
    assert_equal(visitor.checksum, checksum)
    # Independently check every shape, including dense/mixed output, outside timing.
    for q in range(0, queries, max(1, queries // 31)):
        var start = UInt32(((q * 7919) % n) * 8 + 1)
        var actual = Sum(0, 0)
        index.visit(start, start + 1, actual)
        var expected = Sum(0, 0)
        for i in range(n):
            var s = UInt32(i * 8)
            var e = s + 3
            if shape == "span" and i == 0:
                e = UInt32(n * 8)
            elif shape == "dense":
                e += 4096
            elif shape == "mixed":
                e += UInt32((i * 17) % 8192)
            if s < start + 1 and e > start:
                expected.matches += 1
                expected.checksum += UInt64(i)
        assert_equal(actual.matches, expected.matches)
        assert_equal(actual.checksum, expected.checksum)
    print(
        shape,
        n,
        queries,
        Float64(built - begin) / 1e6,
        Float64(end - queried) / 1e6,
        Float64(finished - visited) / 1e6,
        matches,
        checksum,
        sep=",",
    )


def main() raises:
    print("shape,n,queries,build_ms,find_ms,visit_ms,matches,checksum")
    run("plain", 100_000, 20_000)
    run("span", 100_000, 20_000)
    run("dense", 100_000, 20_000)
    run("mixed", 100_000, 20_000)
