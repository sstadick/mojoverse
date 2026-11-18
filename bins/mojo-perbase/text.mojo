"""Byte-oriented TSV formatting; no temporary strings in the column loop."""

from mojo_seqair.buffer import Buffer, BytePtr
from std.collections import Array
from std.memory import unsafe_memcpy


@always_inline
def literal(mut out: Buffer, s: StringSlice) raises:
    out.append(s.as_bytes().unsafe_ptr(), s.byte_length())


@always_inline
def integer(mut out: Buffer, n: Int) raises:
    unsigned_integer(out, UInt64(n))


@always_inline
def unsigned_integer(mut out: Buffer, n: UInt64) raises:
    out.reserve(out.length + 20)
    unsigned_integer_reserved(out, n)


@always_inline
def unsigned_integer_reserved(mut out: Buffer, n: UInt64):
    """Append a u64; caller must reserve 20 writable bytes first."""
    if n < 10:
        out.data[unsafe_offset=out.length] = UInt8(n) + 48
        out.length += 1
        return
    if n < 100:
        out.data[unsafe_offset=out.length] = UInt8(n // 10) + 48
        out.data[unsafe_offset=out.length + 1] = UInt8(n % 10) + 48
        out.length += 2
        return
    # A u64 has at most 20 digits. Pair indices stay in [0, 198]; writing
    # backwards preserves zeroes within each pair without a reversal pass.
    comptime pairs = (
        "0001020304050607080910111213141516171819202122232425262728293031323334353637383940414243444546474849"
        "5051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899"
    )
    var digits = Array[UInt8, 20](fill=0)
    var data = digits.unsafe_ptr()
    var table = pairs.as_bytes().unsafe_ptr()
    var value = n
    var start = 20
    while value >= 100:
        var pair = Int(value % 100) * 2
        value //= 100
        start -= 2
        data[unsafe_offset=start] = table[unsafe_offset=pair]
        data[unsafe_offset=start + 1] = table[unsafe_offset=pair + 1]
    if value < 10:
        start -= 1
        data[unsafe_offset=start] = UInt8(value) + 48
    else:
        start -= 2
        data[unsafe_offset=start] = table[unsafe_offset=Int(value) * 2]
        data[unsafe_offset=start + 1] = table[unsafe_offset=Int(value) * 2 + 1]
    unsafe_memcpy(
        dest=out.data.unsafe_offset(out.length), src=data.unsafe_offset(start), count=20 - start
    )
    out.length += 20 - start


@no_inline
def base_counts(mut out: Buffer, counts: Array[Int, 17], near: Bool) raises:
    # Each nonnegative counter fits in 20 decimal bytes, plus its tab.
    # Keep the unrolled formatter outside the cursor loop's machine code.
    out.reserve(out.length + 17 * 21 + 7)
    comptime for j in range(17):
        out.data[unsafe_offset=out.length] = 9
        out.length += 1
        unsigned_integer_reserved(out, UInt64(counts[j]))
    if near:
        literal(out, "\ttrue\n")
    else:
        literal(out, "\tfalse\n")


def quoted(mut out: Buffer, name: Span[UInt8, _]) raises:
    var quote = False
    for b in name:
        if b == 9 or b == 10 or b == 13 or b == 34:
            quote = True
    if not quote:
        out.append(name.unsafe_ptr(), len(name))
        return
    out.push(34)
    for b in name:
        out.push(b)
        if b == 34:
            out.push(34)
    out.push(34)
