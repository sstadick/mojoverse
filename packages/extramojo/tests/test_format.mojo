from std.memory import bitcast
from std.testing import assert_equal, TestSuite

from extramojo.format import write_float, write_int


struct ByteWriter(Writer):
    var data: List[UInt8]

    def __init__(out self):
        self.data = List[UInt8]()

    def write_string(mut self, text: StringSpan):
        self.data.extend(text.as_bytes())

    def text(self) -> String:
        return String(unsafe_from_utf8=Span(self.data))


def check_int[dtype: DType](value: Scalar[dtype], expected: String) raises:
    var text = String("before:")
    write_int(text, value)
    text += ":after"
    assert_equal(text, "before:" + expected + ":after")
    var bytes = ByteWriter()
    bytes.write_string("before:")
    write_int(bytes, value)
    bytes.write_string(":after")
    assert_equal(bytes.text(), text)


def test_integer_boundaries() raises:
    check_int(Int(0), "0")
    check_int(Int64.MIN, "-9223372036854775808")
    check_int(Int64.MAX, "9223372036854775807")
    check_int(UInt64.MAX, "18446744073709551615")
    check_int(Int8.MIN, "-128")
    check_int(Int16.MIN, "-32768")
    check_int(Int32.MIN, "-2147483648")
    # Odd/even digit counts and zero pairs catch reversed or dropped digits.
    var values: List[Int] = [1, 9, 10, 99, 100, 101, 999, 1000, 10001, 1000001]
    for value in values:
        check_int(value, String(value))
        check_int(-value, String(-value))
    var power = UInt64(1)
    for _ in range(20):
        check_int(power - 1, String(power - 1))
        check_int(power, String(power))
        check_int(power + 1, String(power + 1))
        power *= 10


def test_integer_widths() raises:
    comptime types = [
        DType.int8,
        DType.uint8,
        DType.int16,
        DType.uint16,
        DType.int32,
        DType.uint32,
        DType.int64,
        DType.uint64,
        DType.int,
    ]
    comptime for dtype in types:
        check_int(Scalar[dtype].MIN, String(Scalar[dtype].MIN))
        check_int(Scalar[dtype].MAX, String(Scalar[dtype].MAX))
        check_int(Scalar[dtype](0), "0")
        check_int(Scalar[dtype](42), "42")


def check_float[dtype: DType](value: Scalar[dtype], expected: String) raises:
    var text = String("before:")
    write_float(text, value)
    text += ":after"
    assert_equal(text, "before:" + expected + ":after")
    var bytes = ByteWriter()
    bytes.write_string("before:")
    write_float(bytes, value)
    bytes.write_string(":after")
    assert_equal(bytes.text(), text)


def test_float_layout() raises:
    check_float(Float64(0.0), "0.0")
    check_float(Float64(-0.0), "-0.0")
    check_float(Float64(1.0), "1.0")
    check_float(Float64(-12.5), "-12.5")
    check_float(Float64(0.0001), "0.0001")
    check_float(Float64(0.00001), "1e-05")
    check_float(Float64(1e15), "1000000000000000.0")
    check_float(Float64(1e16), "1e+16")
    check_float(Float64(-1.2345678901234567), "-1.2345678901234567")
    check_float(Float64(1e100), "1e+100")
    check_float(Float64(-1e-100), "-1e-100")
    check_float(bitcast[DType.float64](UInt64(1)), "5e-324")
    check_float(
        bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF)),
        "1.7976931348623157e+308",
    )
    check_float(bitcast[DType.float64](UInt64(0x7FF0000000000000)), "inf")
    check_float(bitcast[DType.float64](UInt64(0xFFF0000000000000)), "-inf")
    check_float(bitcast[DType.float64](UInt64(0xFFF8000000000001)), "nan")
    check_float(Float32(-0.0), "-0.0")
    check_float(Float32(1.25), "1.25")
    check_float(bitcast[DType.float32](UInt32(1)), "1e-45")
    check_float(bitcast[DType.float32](UInt32(0x7F7FFFFF)), "3.4028235e+38")
    check_float(bitcast[DType.float32](UInt32(0x7F800000)), "inf")
    check_float(bitcast[DType.float32](UInt32(0xFF800000)), "-inf")
    check_float(bitcast[DType.float32](UInt32(0x7FC00001)), "nan")


def test_float_matches_stdlib() raises:
    # Neighbors on both sides of notation boundaries and decimal powers.
    for value in List[Float64](
        [0.00001, 0.0001, 0.1, 1.0, 10.0, 1e15, 1e16, 1e100]
    ):
        var bits = bitcast[DType.uint64](value)
        for offset in range(-1, 2):
            var neighbor = bitcast[DType.float64](bits + UInt64(offset))
            check_float(neighbor, String(neighbor))
            check_float(-neighbor, String(-neighbor))
    # Seeded bit patterns exercise both signs, exponent ranges and subnormals.
    var state = UInt64(0x98D734A7B19C0625)
    for _ in range(1024):
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        var f64 = bitcast[DType.float64](state)
        var f32 = bitcast[DType.float32](UInt32(state))
        check_float(f64, String(f64))
        check_float(f32, String(f32))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
