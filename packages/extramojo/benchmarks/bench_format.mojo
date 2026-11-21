"""Compare ExtraMojo and stdlib String output; verify all text before timing.

Arguments: corpus (int-small, int-mixed, uint-mixed, float-simple, float32,
float64), repetitions, implementation (0 for stdlib, 1 for ExtraMojo).
Compile with -O3 --march native. Use long batches and alternate implementations.
"""

from std.benchmark import black_box
from std.memory import bitcast
from std.sys import argv
from std.testing import assert_equal, assert_true
from std.time import perf_counter_ns
from extramojo.format import write_float, write_int


@inline(.never)
def format_one[fast: Bool, dtype: DType](value: Scalar[dtype]) -> String:
    var text = String()
    comptime if not fast:
        text.write(value)
    elif dtype.is_integral():
        write_int(text, value)
    else:
        write_float(text, value)
    return text^


def measure[
    fast: Bool, dtype: DType
](values: List[Scalar[dtype]], rounds: Int) raises:
    var expected = 0
    for value in values:
        var reference = String(value)
        assert_equal(format_one[True](value), reference)
        expected += reference.byte_length()
    var checksum = 0
    var start = perf_counter_ns()
    for _ in range(rounds):
        for value in values:
            var text = format_one[fast](black_box(value))
            checksum += black_box(text).byte_length()
    var elapsed = perf_counter_ns() - start
    assert_equal(checksum, expected * rounds)
    print(elapsed, rounds * len(values), checksum)


def run[
    dtype: DType
](values: List[Scalar[dtype]], rounds: Int, fast: Bool) raises:
    if fast:
        measure[True](values, rounds)
    else:
        measure[False](values, rounds)


def main() raises:
    var args = argv()
    var corpus = args[1]
    var rounds = Int(args[2])
    var fast = Bool(Int(args[3]))
    assert_true(rounds > 0)
    var seed = UInt64(0x98D734A7B19C0625)
    if corpus == "int-small":
        var values = List[Int64]()
        for i in range(-100, 101):
            values.append(Int64(i))
        run(values, rounds, fast)
    elif corpus == "int-mixed":
        var values: List[Int64] = [Int64.MIN, Int64.MAX]
        for i in range(2048):
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            var n = Int64(seed)
            values.append(n if i % 2 else n % 1_000_000_000)
        run(values, rounds, fast)
    elif corpus == "uint-mixed":
        var values: List[UInt64] = [0, UInt64.MAX]
        for _ in range(2048):
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            values.append(seed)
        run(values, rounds, fast)
    elif corpus == "float-simple":
        var values: List[Float64] = [
            0.0,
            -0.0,
            1.0,
            -1.0,
            0.5,
            1.25,
            10.0,
            1000.0,
        ]
        run(values, rounds, fast)
    elif corpus == "float32":
        var values = List[Float32]()
        for _ in range(2048):
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            values.append(bitcast[DType.float32](UInt32(seed)))
        run(values, rounds, fast)
    elif corpus == "float64":
        var values = List[Float64]()
        for _ in range(2048):
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            values.append(bitcast[DType.float64](seed))
        run(values, rounds, fast)
    else:
        raise Error("Unknown corpus")
