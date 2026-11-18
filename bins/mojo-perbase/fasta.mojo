"""Indexed plain/BGZF FASTA windows; each counting worker owns its decoder."""

from std.ffi import external_call
from bio.bgzf import Input
from bio.buffer import Buffer, BytePtr
from bio.bam import Region
from regions import read_text
from options import number


@fieldwise_init
struct Fai(Copyable, Movable):
    var name: String
    var length: Int
    var offset: Int
    var bases: Int
    var width: Int


@fieldwise_init
struct Window(Movable):
    var region: Region
    var data: Buffer


struct Fasta(Movable):
    var source: Optional[Input]
    var entries: List[Fai]
    var packed: List[UInt64]
    var plain: List[UInt64]
    var windows: List[Window]
    var next: Int
    var limit: Int

    def __init__(out self, path: String, limit: Int) raises:
        self.source = None
        self.entries = List[Fai]()
        self.packed = List[UInt64]()
        self.plain = List[UInt64]()
        self.windows = List[Window]()
        self.next = 0
        self.limit = max(limit, 1)
        if not path:
            return
        self.source = Input(path)
        var index = read_text(path + ".fai")
        for line in index.split("\n"):
            if not line:
                continue
            var fields = line.split("\t")
            if len(fields) < 5:
                raise Error("invalid FAI")
            var entry = Fai(
                String(fields[0]),
                number(String(fields[1]), 2147483647),
                number(String(fields[2]), Int.MAX),
                number(String(fields[3]), 2147483647),
                number(String(fields[4]), 2147483647),
            )
            if not entry.bases or entry.width < entry.bases:
                raise Error("invalid FAI geometry")
            self.entries.append(entry^)
        if self.source.value().compressed:
            var gzi = Input(path + ".gzi")
            var n = gzi.wide()
            if n > 100000000:
                raise Error("invalid GZI count")
            self.packed.append(0)
            self.plain.append(0)
            for i in range(Int(n)):
                var a = gzi.wide()
                var b = gzi.wide()
                if a <= self.packed[i] or b <= self.plain[i]:
                    raise Error("unsorted GZI")
                self.packed.append(a)
                self.plain.append(b)

    def fetch(mut self, name: Span[UInt8, _], region: Region) raises -> BytePtr:
        for i in range(len(self.windows)):
            ref w = self.windows[i]
            if (
                w.region.tid == region.tid
                and w.region.begin <= region.begin
                and w.region.end >= region.end
            ):
                return w.data.data.unsafe_offset(region.begin - w.region.begin)
        var id = -1
        for i in range(len(self.entries)):
            if self.entries[i].name == String(from_utf8=name):
                id = i
        if id == -1 or region.end > self.entries[id].length:
            raise Error("reference missing or too short")
        ref e = self.entries[id]
        var offset = e.offset + region.begin // e.bases * e.width + region.begin % e.bases
        ref source = self.source.value()
        if source.compressed:
            var low = 0
            var high = len(self.plain)
            while low + 1 < high:
                var mid = (low + high) // 2
                if self.plain[mid] <= UInt64(offset):
                    low = mid
                else:
                    high = mid
            source.seek(self.packed[low] << 16)
            source.skip(offset - Int(self.plain[low]))
        else:
            if external_call["fseeko", Int32](source.file, offset, Int32(0)):
                raise Error("FASTA seek failed")
            source.position = 0
            source.data.length = 0
            source.eof = False
        var slot = self.next
        if len(self.windows) < self.limit:
            slot = len(self.windows)
            self.windows.append(Window(region, Buffer(region.end - region.begin)))
        else:
            self.next = (self.next + 1) % self.limit
        ref window = self.windows[slot]
        window.region = region
        window.data.reserve(region.end - region.begin)
        window.data.length = region.end - region.begin
        var pos = region.begin
        while pos < region.end:
            var n = min(e.bases - pos % e.bases, region.end - pos)
            source.exact(window.data.data.unsafe_offset(pos - region.begin), n)
            pos += n
            if pos < region.end:
                source.skip(e.width - e.bases)
        return window.data.data
