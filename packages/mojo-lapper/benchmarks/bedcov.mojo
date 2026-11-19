"""Whole-program Biofast BED coverage using Lapper and binary buffered I/O.

Usage: bedcov <loaded.bed> <streamed.bed>. Emit each query's contig, signed
32-bit start/stop, overlap count and union coverage as TSV. Like Biofast,
skip incomplete records and reversed stored intervals, accept numeric suffixes,
and initialize covered endpoints to zero. Names are bytes, not validated UTF-8.
Build and comparison instructions are in docs/development.md at the repo root.
"""

from std.sys import argv
from std.sys.intrinsics import unlikely
from std.memory import unsafe_memcpy
from lapper.lapper import Interval, IntervalVisitor, Lapper
from io import BufferedReader, BufferedWriter


struct ByteOutput:
    """Reuse a byte batch; names must be separate from its storage."""

    var data: List[UInt8]

    def __init__(out self):
        self.data = List[UInt8](capacity=65536)

    def write_row(
        mut self, name: Span[UInt8, _], start: Int32, stop: Int32, count: Int, coverage: Int
    ):
        # Perbase's row-reservation pattern: four signed 64-bit values need
        # at most 20 bytes each, plus four tabs and a newline. Growth happens
        # once, before taking the pointer; shrink to initialized bytes after.
        var offset = len(self.data)
        self.data.resize(unsafe_uninit_length=offset + len(name) + 85)
        var output = self.data.unsafe_ptr()
        unsafe_memcpy(dest=output.unsafe_offset(offset), src=name.unsafe_ptr(), count=len(name))
        offset += len(name)
        output[unsafe_offset=offset] = 9
        offset += 1
        offset += write_int(output.unsafe_offset(offset), Int(start))
        output[unsafe_offset=offset] = 9
        offset += 1
        offset += write_int(output.unsafe_offset(offset), Int(stop))
        output[unsafe_offset=offset] = 9
        offset += 1
        offset += write_int(output.unsafe_offset(offset), count)
        output[unsafe_offset=offset] = 9
        offset += 1
        offset += write_int(output.unsafe_offset(offset), coverage)
        output[unsafe_offset=offset] = 10
        self.data.resize(unsafe_uninit_length=offset + 1)


def write_int(output: Pointer[mut=True, UInt8, _], value: Int) -> Int:
    """Write a signed decimal into 20 writable bytes; return initialized length."""
    comptime PAIRS: StaticString = (
        "0001020304050607080910111213141516171819202122232425262728293031323334353637383940414243444546474849"
        "5051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899"
    )
    var negative = value < 0
    var magnitude = UInt64(value)
    if negative:
        # Unsigned subtraction also handles Int.MIN, without signed overflow.
        magnitude = UInt64(0) - magnitude
        output[unsafe_offset=0] = 45
    if magnitude < 10:
        output[unsafe_offset=Int(negative)] = UInt8(magnitude) + 48
        return 1 + Int(negative)

    var digits = 1
    var remaining = magnitude
    while remaining >= 10000:
        digits += 4
        remaining //= 10000
    if remaining >= 1000:
        digits += 3
    elif remaining >= 100:
        digits += 2
    elif remaining >= 10:
        digits += 1

    var end = digits + Int(negative)
    var pairs = PAIRS.as_bytes().unsafe_ptr()
    var cursor = end
    while magnitude >= 100:
        var quotient = magnitude // 100
        var pair_offset = Int(magnitude - quotient * 100) * 2
        cursor -= 2
        # Remainder is 0..99: both reads lie within the 200-byte table.
        # Each iteration initializes two of the counted decimal digits.
        output[unsafe_offset=cursor] = pairs[unsafe_offset=pair_offset]
        output[unsafe_offset=cursor + 1] = pairs[unsafe_offset=pair_offset + 1]
        magnitude = quotient
    if magnitude < 10:
        output[unsafe_offset=cursor - 1] = UInt8(magnitude) + 48
    else:
        var pair_offset = Int(magnitude) * 2
        output[unsafe_offset=cursor - 2] = pairs[unsafe_offset=pair_offset]
        output[unsafe_offset=cursor - 1] = pairs[unsafe_offset=pair_offset + 1]
    return end


@fieldwise_init
struct Coverage(IntervalVisitor):
    """Accumulate ordered overlaps without storing and rereading each match."""

    var query_start: UInt32
    var query_stop: UInt32
    var count: Int
    var coverage: Int
    var covered_start: Int
    var covered_end: Int

    @always_inline
    def visit(mut self, interval: Interval):
        # Keep endpoints in index coordinates; differences cancel the bias.
        var start = Int(max(interval.start, self.query_start))
        var stop = Int(min(interval.stop, self.query_stop))
        if unlikely(start > self.covered_end):
            self.coverage += self.covered_end - self.covered_start
            self.covered_start = start
            self.covered_end = stop
        elif stop > self.covered_end:
            self.covered_end = stop
        self.count += 1


@always_inline
def atoi(text: Span[UInt8, _], mut offset: Int) -> Int32:
    var i = offset
    # Tabs delimit fields, including empty fields; never skip into the next one.
    while i < len(text) and (text[i] == 32 or (text[i] >= 10 and text[i] <= 13)):
        i += 1
    var negative = False
    if i < len(text) and (text[i] == 45 or text[i] == 43):
        negative = text[i] == 45
        i += 1
    var value = Int64(0)
    while i < len(text) and text[i] >= 48 and text[i] <= 57:
        value = value * 10 + Int64(text[i] - 48)
        i += 1
    offset = i
    return Int32(-value if negative else value)


def coordinate(value: Int32) -> UInt32:
    # Preserve signed BED coordinate order in mojo-lapper's unsigned index.
    return UInt32(value) ^ 0x80000000


@fieldwise_init
struct Record(Copyable):
    var contig_end: Int
    var start: Int32
    var stop: Int32


@always_inline
def parse_bed(line: Span[UInt8, _]) -> Optional[Record]:
    var first = 0
    while first < len(line) and line[first] != 9:
        first += 1
    var offset = first + 1
    var start = atoi(line, offset)
    # Usually atoi stops at the tab. Preserve atol's acceptance of suffixes
    # without rescanning every start coordinate to find its delimiter first.
    while offset < len(line) and line[offset] != 9:
        offset += 1
    if offset >= len(line):
        return None
    offset += 1
    var stop = atoi(line, offset)
    return Record(first, start, stop)


struct Contigs:
    """Own contig keys and cache the last lookup, without retaining reader views."""

    var ids: Dict[List[UInt8], Int]
    var name: List[UInt8]
    var id: Int

    def __init__(out self):
        self.ids = Dict[List[UInt8], Int]()
        self.name = List[UInt8]()
        self.id = -2  # Distinguish an uninitialized cache from a missing key.

    def resolve(mut self, name: Span[UInt8, _], create: Bool = False) raises -> Int:
        if self.id == -2 or name != Span(self.name):
            self.name.clear()
            self.name.extend(name)
            self.id = self.ids.get(self.name, -1)
        if create and self.id < 0:
            self.id = len(self.ids)
            self.ids[self.name.copy()] = self.id
        return self.id


def main() raises:
    var args = argv()
    if len(args) != 3:
        print("Usage: bedcov <loaded.bed> <streamed.bed>")
        return

    var contigs = Contigs()
    var intervals = List[List[Interval]]()
    var loaded = BufferedReader(open(args[1], "r"), buffer_capacity=65536)
    while True:
        var line = loaded.read_line()
        if not line:
            break
        var parsed = parse_bed(line.value())
        if not parsed:
            continue
        ref record = parsed.value()
        var id = contigs.resolve(line.value()[: record.contig_end], record.start <= record.stop)
        if record.start > record.stop:
            continue
        if id == len(intervals):
            intervals.append(List[Interval]())
        intervals[id].append(Interval(coordinate(record.start), coordinate(record.stop), 0))
    loaded.close()

    var lappers = List[Lapper[]]()
    while len(intervals):
        var index = Lapper(intervals.pop(0))
        lappers.append(index^)

    var text = ByteOutput()
    var queries = BufferedReader(open(args[2], "r"), buffer_capacity=65536)
    var output = BufferedWriter(open("/dev/stdout", "w"), buffer_capacity=65536)
    while True:
        var line = queries.read_line()
        if not line:
            break
        var parsed = parse_bed(line.value())
        if not parsed:
            continue
        ref record = parsed.value()
        var accumulator = Coverage(
            coordinate(record.start),
            coordinate(record.stop),
            0,
            0,
            0x80000000,
            0x80000000,
        )
        var id = contigs.resolve(line.value()[: record.contig_end])
        if id >= 0:
            lappers[id].visit(coordinate(record.start), coordinate(record.stop), accumulator)
        var coverage = accumulator.coverage + accumulator.covered_end - accumulator.covered_start
        text.write_row(Span(contigs.name), record.start, record.stop, accumulator.count, coverage)
        if len(text.data) >= 65536:
            output.write_bytes(Span(text.data))
            text.data.clear()
    output.write_bytes(Span(text.data))
    queries.close()
    output.close()
