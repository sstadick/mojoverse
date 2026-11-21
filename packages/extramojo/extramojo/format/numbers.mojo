# Float layout adapted from Modular's builtin/_format_float.mojo at
# 5f6e78dac83e12e4b310ba940a71cfe37a494135, Copyright (c) 2026 Modular Inc.
# That implementation derives from Dragonbox, Copyright 2020-2024 Junekey Jeon.
# Licensed under Apache-2.0 WITH LLVM-exception; see the package LICENSE.
# Changes: batch ASCII output through Writer; retain stdlib decimal conversion.
# Integer digit pairs adapt the MIT-licensed Mojoverse bedcov formatter,
# Copyright (c) 2025 Seth Stadick; see the package LICENSE.

"""Format decimal integers and floats using stack buffers and batched writes."""

from std.builtin._format_float import _to_decimal
from std.collections import Array
from std.sys import bit_width_of, is_gpu
from std.utils.numerics import FPUtils, isinf, isnan


@always_inline
def write_int[dtype: DType, W: Writer, //](mut writer: W, value: Scalar[dtype]):
    """Append a decimal integer to a Writer, processing two digits at a time.

    Supports signed and unsigned integer scalars up to 64 bits on the CPU,
    including `Int`. Writes no prefix, padding, or trailing separator. Uses a
    stack buffer, without allocating an intermediate String.

    Parameters:
        dtype: The integer dtype, inferred from `value`.
        W: The destination Writer type.

    Args:
        writer: The destination to append to.
        value: The integer to format.

    Constraints:
        The target must be a CPU and `dtype` must be integral, at most 64 bits.

    Examples:
        ```mojo {doctest="write_int" global=true}
        from extramojo.format import write_int
        from std.testing import assert_equal

        def main() raises:
            var text = String("count=")
            write_int(text, Int64(-12345))
            assert_equal(text, "count=-12345")
        ```
    """
    comptime assert not is_gpu(), "write_int supports CPU targets only"
    comptime assert (
        dtype.is_integral() and bit_width_of[dtype]() <= 64
    ), "write_int requires an integer of at most 64 bits"
    comptime PAIRS: StaticString = (
        "0001020304050607080910111213141516171819202122232425262728293031323334353637383940414243444546474849"
        "5051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899"
    )
    var n = UInt64(value)
    # Nonnegative one- and two-digit values need no scratch buffer. Casting
    # before the comparison leaves negative values on the signed path below.
    if n < 10:
        var start = Int(n) * 2 + 1
        writer.write_string(
            StringSpan(unsafe_from_utf8=PAIRS.as_bytes()[start : start + 1])
        )
        return
    if n < 100:
        var start = Int(n) * 2
        writer.write_string(
            StringSpan(unsafe_from_utf8=PAIRS.as_bytes()[start : start + 2])
        )
        return
    var digits = Array[UInt8, 21](uninitialized=True)
    # A u64 needs at most 20 decimal digits, plus room for a sign. Each /100
    # iteration consumes exactly two positions, so no store precedes the buffer.
    var data = digits.unsafe_ptr()
    var cursor = 21
    if value < 0:
        # Negate after widening to unsigned, including the signed minimum.
        n = UInt64(0) - n
    while n >= 100:
        var index = Int(n % 100) * 2
        cursor -= 2
        data[unsafe_offset=cursor] = PAIRS.as_bytes()[index]
        data[unsafe_offset=cursor + 1] = PAIRS.as_bytes()[index + 1]
        n //= 100
    if n >= 10:
        cursor -= 2
        data[unsafe_offset=cursor] = PAIRS.as_bytes()[Int(n) * 2]
        data[unsafe_offset=cursor + 1] = PAIRS.as_bytes()[Int(n) * 2 + 1]
    else:
        cursor -= 1
        data[unsafe_offset=cursor] = UInt8(n) + 48
    if value < 0:
        cursor -= 1
        data[unsafe_offset=cursor] = 45
    writer.write_string(
        StringSpan(
            unsafe_from_utf8=Span(
                unsafe_ptr=data.unsafe_offset(cursor),
                length=21 - cursor,
            )
        )
    )


def write_float[
    dtype: DType, W: Writer, //
](mut writer: W, value: Scalar[dtype]):
    """Append a Float32 or Float64 to a Writer with batched ASCII output.

    Matches the pinned Mojo stdlib's shortest round-trip text, including
    scientific notation, signed zero, infinities and NaN. Decimal conversion
    uses the stdlib's private `_to_decimal` function; compiler upgrades require
    revalidation. Supports CPU targets only. No intermediate String is allocated.

    Parameters:
        dtype: Either `DType.float32` or `DType.float64`.
        W: The destination Writer type.

    Args:
        writer: The destination to append to.
        value: The float to format.

    Constraints:
        The target must be a CPU and `dtype` must be Float32 or Float64.

    Examples:
        ```mojo {doctest="write_float" global=true}
        from extramojo.format import write_float
        from std.testing import assert_equal

        def main() raises:
            var text = String("value=")
            write_float(text, Float64(-1.25))
            assert_equal(text, "value=-1.25")
        ```
    """
    comptime assert not is_gpu(), "write_float supports CPU targets only"
    comptime assert (
        dtype == .float32 or dtype == .float64
    ), "write_float requires Float32 or Float64"
    # Keep special-value spelling and the sign of zero in the stdlib path.
    if isinf(value) or isnan(value) or value == 0:
        writer.write(value)
        return

    var sig = FPUtils.get_mantissa_uint(value)
    var exp = FPUtils.get_exponent_biased(value)
    var sign = FPUtils.get_sign(value)
    _to_decimal[dtype](sig, exp)

    # Float64 needs at most 17 significant digits. Fixed notation has at most
    # four leading fractional zeros; scientific notation needs sign, point,
    # 'e', exponent sign and three exponent digits. Both fit within 32 bytes.
    var text = Array[UInt8, 32](uninitialized=True)
    var used = 0

    def put(byte: UInt8) {mut}:
        text[used] = byte
        used += 1

    if sign:
        put(45)
    var abs_exp = abs(exp)
    var digits = Array[UInt8, 17](uninitialized=True)
    var count = 0
    while sig > 0:
        digits[count] = UInt8(sig % 10) + 48
        sig //= 10
        count += 1
        if sig > 0:
            exp += 1
    var leading_zeroes = abs_exp - count

    if (exp < 0 and leading_zeroes > 3) or exp > 15:
        put(digits[count - 1])
        if count > 1:
            put(46)
        for i in reversed(range(count - 1)):
            put(digits[i])
        put(101)
        put(UInt8(45 if exp < 0 else 43))
        exp = abs(exp)
        if exp >= 100:
            put(UInt8(exp // 100) + 48)
        put(UInt8((exp // 10) % 10) + 48)
        put(UInt8(exp % 10) + 48)
    elif exp < 0 and leading_zeroes > 0:
        put(48)
        put(46)
        for _ in range(leading_zeroes):
            put(48)
        for i in reversed(range(count)):
            put(digits[i])
    else:
        var point_written = False
        for i in reversed(range(count)):
            if leading_zeroes < 1 and exp == count - i - 2:
                if i == count - 1:
                    put(48)
                put(46)
                point_written = True
            put(digits[i])
        for _ in range(exp - count + 1):
            put(48)
        if not point_written:
            put(46)
            put(48)
    writer.write_string(
        StringSpan(
            unsafe_from_utf8=Span(unsafe_ptr=text.unsafe_ptr(), length=used)
        )
    )
