"""Memchr/rebar KLV input and duration,count output; all setup is outside timing."""
from std.benchmark import black_box
from std.sys import argv
from std.time import perf_counter_ns
from std.math import max
from bstr import *


@fieldwise_init
struct Benchmark(Movable):
    var model: String
    var haystack: List[UInt8]
    var needles: List[List[UInt8]]
    var max_iters: Int
    var max_warmup_iters: Int
    var max_time: Int
    var max_warmup_time: Int


def text(s: Span[mut=False, UInt8, _]) -> String:
    var output = String()
    for b in s:
        output += String(chr(Int(b)))
    return output^


def parse(s: Span[mut=False, UInt8, _]) raises -> Benchmark:
    var b = Benchmark("", List[UInt8](), List[List[UInt8]](), 0, 0, 0, 0)
    var pos = 0
    while pos < len(s):
        var colon = find_byte(s[pos:], 58)
        if colon < 0:
            raise Error("missing KLV key colon")
        var key = text(s[pos : pos + colon])
        pos += colon + 1
        colon = find_byte(s[pos:], 58)
        if colon < 0:
            raise Error("missing KLV length colon")
        var size = Int(text(s[pos : pos + colon]))
        pos += colon + 1
        if size < 0 or size >= len(s) - pos or s[pos + size] != 10:
            raise Error("invalid KLV length or terminator")
        var value = s[pos : pos + size]
        pos += size + 1
        if key == "model":
            b.model = text(value)
        elif key == "haystack":
            b.haystack.extend(value)
        elif key == "pattern":
            b.needles.append(unescape_bytes(value))
        elif key == "max-iters":
            b.max_iters = Int(text(value))
        elif key == "max-warmup-iters":
            b.max_warmup_iters = Int(text(value))
        elif key == "max-time":
            b.max_time = Int(text(value))
        elif key == "max-warmup-time":
            b.max_warmup_time = Int(text(value))
    return b^


def count[
    mode: Int, model: Int, origin: ImmOrigin
](b: Benchmark, searchers: List[Finder[origin]]) -> Int:
    var s = Span(b.haystack)
    comptime if model == 0:
        var n = Span(b.needles[0])
        var total = 0
        var cursor = 0
        while cursor <= len(s):
            var at: Int
            comptime if mode == 1:
                at = searchers[0].find(s[cursor:])
            else:
                at = find(s[cursor:], n)
            if at < 0:
                break
            total += 1
            cursor += at + max(1, len(n))
        return total
    elif model == 1:
        var total = 0
        var cursor = len(s) if mode >= 5 else 0
        var a = b.needles[0][0]
        var second = b.needles[1][0] if len(b.needles) >= 2 else a
        var third = b.needles[2][0] if len(b.needles) >= 3 else a
        while cursor >= 0 if mode >= 5 else cursor <= len(s):
            var at: Int
            comptime if mode == 2:
                at = memchr(a, s[cursor:])
            elif mode == 3:
                at = memchr2(a, second, s[cursor:])
            elif mode == 4:
                at = memchr3(a, second, third, s[cursor:])
            elif mode == 5:
                at = memrchr(a, s[:cursor])
            elif mode == 6:
                at = memrchr2(a, second, s[:cursor])
            else:
                at = memrchr3(a, second, third, s[:cursor])
            if at < 0:
                break
            total += 1
            comptime if mode >= 5:
                cursor = at
            else:
                cursor += at + 1
        return total
    elif model == 2:
        var total = 0
        for i in range(len(b.needles)):
            for j in range(i, len(b.needles)):
                total += Int(searchers[i].find(Span(b.needles[j])) >= 0)
        return total
    else:
        var total = 0
        for searcher in searchers:
            total += Int(searcher.find(s) >= 0)
        return total


def measure[mode: Int, model: Int](b: Benchmark, verify: Bool):
    var searchers = List[Finder[ImmOrigin(origin_of(b.needles))]]()
    for n in b.needles:
        searchers.append(finder(Span(n)))
    if verify:
        print("0," + String(count[mode, model](b, searchers)))
        return
    var samples = List[Tuple[Int, Int]]()
    var warmup = perf_counter_ns()
    for _ in range(b.max_warmup_iters):
        var result = count[mode, model](b, searchers)
        _ = black_box(result)
        if perf_counter_ns() - warmup >= b.max_warmup_time:
            break
    var start = perf_counter_ns()
    for _ in range(b.max_iters):
        var before = perf_counter_ns()
        var result = count[mode, model](b, searchers)
        var duration = perf_counter_ns() - before
        samples.append((duration, result))
        if perf_counter_ns() - start >= b.max_time:
            break
    for duration, result in samples:
        print(String(duration) + "," + String(result))


def main() raises:
    var args = argv()
    if len(args) != 2 and len(args) != 3:
        raise Error("expected engine mode [--verify]")
    var verify = len(args) == 3 and args[2] == "--verify"
    if len(args) == 3 and not verify:
        raise Error("unknown option")
    var raw = open("/dev/stdin", "r").read_bytes()
    var b = parse(Span(raw))
    if len(b.needles) == 0:
        raise Error("missing patterns")
    comptime names = (
        "memmem-oneshot",
        "memmem-prebuilt",
        "memchr-oneshot",
        "memchr2",
        "memchr3",
        "memrchr",
        "memrchr2",
        "memrchr3",
    )
    comptime for mode in range(8):
        if args[1] == names[mode]:
            comptime if mode < 2:
                if b.model == "count" and len(b.needles) == 1 and len(b.needles[0]) > 0:
                    measure[mode, 0](b, verify)
                    return
                comptime if mode == 1:
                    if b.model == "needles-in-needles":
                        measure[mode, 2](b, verify)
                        return
                    if b.model == "needles-in-haystack":
                        measure[mode, 3](b, verify)
                        return
            else:
                var wanted = (mode - 2) % 3 + 1
                if b.model != "count-bytes" or len(b.needles) != wanted:
                    raise Error("invalid byte count model")
                for n in b.needles:
                    if len(n) != 1:
                        raise Error("byte pattern must have length 1")
                measure[mode, 1](b, verify)
                return
    raise Error("unsupported engine/model combination")
