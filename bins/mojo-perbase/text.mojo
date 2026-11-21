"""Byte-oriented TSV formatting; no temporary strings in the column loop."""

from bio.buffer import Buffer, BytePtr
from std.collections import Array
from std.memory import unsafe_memcpy
from extramojo.format import write_int


@fieldwise_init
struct _ReservedWriter(Writer):
    """Write into the caller's already-reserved space for one UInt64."""

    var data: BytePtr
    var length: Int

    @always_inline
    def write_string(mut self, text: StringSpan):
        unsafe_memcpy(
            dest=self.data.unsafe_offset(self.length),
            src=text.as_bytes().unsafe_ptr(),
            count=text.byte_length(),
        )
        self.length += text.byte_length()


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
    var writer = _ReservedWriter(out.data.unsafe_offset(out.length), 0)
    write_int(writer, n)
    out.length += writer.length


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
