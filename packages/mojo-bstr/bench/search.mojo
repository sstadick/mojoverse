"""Goostr bench/search.goose protocol: haystack path, needle path, mode, iterations."""
from std.benchmark import black_box
from std.sys import argv
from std.time import perf_counter_ns
from bstr import finder, finder_reverse
from operations import operation


def measure[
    mode: Int
](s: Span[mut=False, UInt8, _], n: Span[mut=False, UInt8, _], iterations: Int, verify: Bool):
    var forward = finder(n)
    var backward = finder_reverse(n)
    if verify:
        print(0, operation[mode](s, n, forward, backward) + 1)
        return
    var checksum = 0
    var elapsed = 0
    for _ in range(2):
        checksum = 0
        var start = perf_counter_ns()
        for _ in range(iterations):
            checksum += operation[mode](black_box(s), black_box(n), forward, backward) + 1
        elapsed = perf_counter_ns() - start
    print(elapsed, checksum)


def main() raises:
    var args = argv()
    if len(args) != 5 and len(args) != 6:
        raise Error("expected haystack needle mode iterations [--verify]")
    var verify = len(args) == 6 and args[5] == "--verify"
    if len(args) == 6 and not verify:
        raise Error("unknown option")
    var haystack = open(args[1], "r").read_bytes()
    var needle = open(args[2], "r").read_bytes()
    var iterations = Int(args[4])
    if iterations <= 0:
        raise Error("iterations must be positive")
    comptime names = (
        "find",
        "rfind",
        "prepared-find",
        "prepared-rfind",
        "find-set",
        "rfind-set",
        "find-not-set",
        "rfind-not-set",
        "count",
        "rcount",
        "records",
    )
    comptime for mode in range(11):
        if args[3] == names[mode]:
            measure[mode](Span(haystack), Span(needle), iterations, verify)
            return
    raise Error("unknown benchmark mode")
