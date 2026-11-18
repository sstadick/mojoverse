"""Indexed BAM readers with borrowed records and checked long-CIGAR decoding.

The dictionary/index is immutable after loading and may be shared. Each worker
owns a Reader. A returned record's byte views expire at the next reader call.
Only auxiliary validation is performed; auxiliary bytes are not retained.
"""

from std.ffi import external_call
from std.memory import unsafe_memcpy
from std.sys import CompilationTarget
from std.sys.intrinsics import llvm_intrinsic
from .buffer import Buffer, BytePtr, le32
from .bgzf import Input


@fieldwise_init
struct Region(ImplicitlyCopyable):
    """Zero-based half-open reference interval: `begin <= pos < end`, identified by tid."""

    var tid: Int
    var begin: Int
    var end: Int


@fieldwise_init
struct Chunk(ImplicitlyCopyable):
    var begin: UInt64
    var end: UInt64


def _chunk_less(a: Chunk, b: Chunk) -> Bool:
    return a.begin < b.begin


@fieldwise_init
struct Bin(Movable):
    var id: UInt32
    var chunks: List[Chunk]


@fieldwise_init
struct IndexRef(Movable):
    var bins: List[Bin]
    var linear: List[UInt64]


@fieldwise_init
struct Reference(Movable):
    """Reference name as bytes and its length in bases."""

    var name: List[UInt8]
    var length: Int


def _exists(path: String) -> Bool:
    var c_path = path.copy()
    return external_call["access", Int32](c_path.as_c_string_span(), Int32(4)) == 0


struct Bam(Movable):
    """Own a BAM dictionary and BAI/CSI index, without retaining records."""

    var path: String
    var references: List[Reference]
    var index: List[IndexRef]
    var min_shift: Int
    var depth: Int

    def __init__(out self, path: String) raises:
        self.path = path.copy()
        self.references = List[Reference]()
        self.index = List[IndexRef]()
        self.min_shift = 14
        self.depth = 5
        var source = Input(path)
        if source.word() != UInt32(0x014D4142) or not source.compressed:
            raise Error("expected indexed BGZF BAM")
        source.skip(Int(source.word(2147483647)))
        var nref = Int(source.word(10000000))
        self.references.reserve(nref)
        var scratch = Buffer()
        for _ in range(nref):
            var n = Int(source.word(16777216))
            if not n:
                raise Error("empty BAM reference name")
            scratch.reserve(n)
            source.exact(scratch.data, n)
            if (
                scratch.data[unsafe_offset=n - 1] != 0
                or external_call["strlen", Int](scratch.data) != n - 1
            ):
                raise Error("invalid reference name")
            var name = List[UInt8](length=n - 1, fill=0)
            unsafe_memcpy(dest=name.unsafe_ptr(), src=scratch.data, count=n - 1)
            self.references.append(Reference(name^, Int(source.word(2147483647))))
        var index_path = path + ".bai"
        if not _exists(index_path):
            index_path = path + ".csi"
        if not _exists(index_path):
            var dot = path.rfind(".")
            if dot:
                index_path = String(from_utf8=path.as_bytes()[0:dot.value()]) + ".bai"
        if index_path == path or not _exists(index_path):
            raise Error("cannot find BAM index")
        var indexed = Input(index_path)
        var magic = indexed.word()
        var csi = magic == UInt32(0x01495343)
        if not csi and magic != UInt32(0x01494142):
            raise Error("invalid BAI/CSI magic")
        if csi:
            self.min_shift = Int(indexed.word(31))
            self.depth = Int(indexed.word(10))
            if self.min_shift + 3 * self.depth > 62:
                raise Error("unsupported CSI geometry")
            indexed.skip(Int(indexed.word(16777216)))
        if Int(indexed.word()) != nref:
            raise Error("BAM/index dictionary mismatch")
        self.index.reserve(nref)
        for _ in range(nref):
            var bins = List[Bin]()
            var nbin = Int(indexed.word(10000000))
            bins.reserve(nbin)
            for _ in range(nbin):
                var identifier = indexed.word()
                if csi:
                    _ = indexed.wide()
                var nchunk = Int(indexed.word(100000000))
                var chunks = List[Chunk](capacity=nchunk)
                for _ in range(nchunk):
                    var start = indexed.wide()
                    var stop = indexed.wide()
                    chunks.append(Chunk(start, stop))
                bins.append(Bin(identifier, chunks^))
            var linear = List[UInt64]()
            if not csi:
                var nlinear = Int(indexed.word(100000000))
                linear.reserve(nlinear)
                for _ in range(nlinear):
                    linear.append(indexed.wide())
            self.index.append(IndexRef(bins^, linear^))

    def region(self, reference: StringSlice, begin: Int, end: Int) raises -> Region:
        """Resolve a reference name and validate a zero-based half-open interval."""
        for tid in range(len(self.references)):
            if Span(self.references[tid].name) == reference.as_bytes():
                if begin < 0 or begin >= end or end > self.references[tid].length:
                    raise Error("region must be nonempty and within the reference")
                return Region(tid, begin, end)
        raise Error(String("unknown BAM reference: ", reference))

    def query(self, reference: StringSlice, begin: Int, end: Int) raises -> Reader:
        """Open an independent reader positioned at reads overlapping this interval.

        Use `while reader.next():` and `reader.record.value()` to access each
        borrowed record. For repeated queries, retain a Reader and call fetch
        with regions returned by `region`; this reuses its codec and buffers.
        """
        var selected = self.region(reference, begin, end)
        var reader = Reader(self.path)
        reader.fetch(self, selected)
        return reader^


@fieldwise_init
struct Record(ImplicitlyCopyable):
    """Borrowed BAM fields. Do not retain byte views across reader operations."""

    var tid: Int
    var pos: Int
    var end: Int
    var span: Int
    var flags: Int
    var mapq: Int
    var mate_tid: Int
    var mate_pos: Int
    var template_len: Int
    var nseq: Int
    var ncigar: Int
    var name_length: Int
    var name: BytePtr
    var cigar: BytePtr
    var sequence: BytePtr
    var quality: BytePtr

    def name_bytes(self) -> Span[UInt8, ImmUntrackedOrigin]:
        """Borrow the read name, excluding its NUL terminator; not necessarily UTF-8.

        Valid only until the next reader operation, move or destruction. The
        raw Record does not track its reader's origin. Copy with List(view)
        before advancing if the name must survive.
        """
        return Span(unsafe_ptr=self.name.unsafe_mut_cast[False](), length=self.name_length)

    def qualities(self) -> Span[UInt8, ImmUntrackedOrigin]:
        """Borrow numeric Phred qualities; 255 means absent. Same lifetime as name_bytes."""
        return Span(unsafe_ptr=self.quality.unsafe_mut_cast[False](), length=self.nseq)

    def decode_bases(self, dest: Span[mut=True, UInt8, _]) raises -> Int:
        """Decode into a reusable destination, returning the initialized prefix length.

        The destination needs at least nseq bytes and must not overlap the
        record. Decode before advancing the reader. Empty sequence writes zero
        bytes. Symbols follow BAM's full =ACMGRSVTWYHKDBN alphabet.
        """
        if len(dest) < self.nseq:
            raise Error("sequence destination too small")
        decode_sequence(
            self.sequence, dest.unsafe_ptr().unsafe_origin_cast[MutUntrackedOrigin](), self.nseq
        )
        return self.nseq

    @always_inline
    def cigar_word(self, i: Int) -> UInt32:
        """Unchecked packed CIGAR operation; requires `0 <= i < ncigar`."""
        return le32(self.cigar.unsafe_offset(i * 4))


def decode_sequence(source: BytePtr, dest: BytePtr, n: Int):
    """Decode n BAM bases; caller supplies ceil(n/2) input and n output bytes.

    Buffers must not overlap. The vector loop never reads or writes the tail.
    This is an unchecked buffer primitive, not a BAM validation entry point.
    """
    comptime alphabet = "=ACMGRSVTWYHKDBN"
    var q = 0
    comptime if CompilationTarget.has_sse4():
        comptime V = SIMD[DType.uint8, 16]
        var table = V(61, 65, 67, 77, 71, 82, 83, 86, 84, 87, 89, 72, 75, 68, 66, 78)
        while q + 32 <= n:
            var packed = source.unsafe_offset(q // 2).unsafe_load[width=16, alignment=1]()
            var high = llvm_intrinsic["llvm.x86.ssse3.pshuf.b.128", V, has_side_effect=False](
                table, packed >> 4
            )
            var low = llvm_intrinsic["llvm.x86.ssse3.pshuf.b.128", V, has_side_effect=False](
                table, packed & 15
            )
            dest.unsafe_offset(q).unsafe_store[alignment=1](
                high.shuffle[0, 16, 1, 17, 2, 18, 3, 19, 4, 20, 5, 21, 6, 22, 7, 23](low)
            )
            dest.unsafe_offset(q + 16).unsafe_store[alignment=1](
                high.shuffle[8, 24, 9, 25, 10, 26, 11, 27, 12, 28, 13, 29, 14, 30, 15, 31](low)
            )
            q += 32
    while q < n:
        var code = Int((source[unsafe_offset=q // 2] >> UInt8(4 if q % 2 == 0 else 0)) & 15)
        dest[unsafe_offset=q] = alphabet.as_bytes()[code]
        q += 1


def parse_record(p: BytePtr, length: Int) raises -> Record:
    """Validate the record layout, aux fields and CIGAR before exposing views."""
    if length < 32:
        raise Error("short BAM record")
    var tid = Int(Int32(le32(p)))
    var pos = Int(Int32(le32(p.unsafe_offset(4))))
    var name_length = Int(p[unsafe_offset=8])
    var ncigar = Int(p[unsafe_offset=12]) | (Int(p[unsafe_offset=13]) << 8)
    var flags = Int(p[unsafe_offset=14]) | (Int(p[unsafe_offset=15]) << 8)
    var nseq = Int(le32(p.unsafe_offset(16)))
    var cigar_end = 32 + name_length + ncigar * 4
    var seq_end = cigar_end + (nseq + 1) // 2
    var aux = seq_end + nseq
    if not name_length or nseq > 2147483647 or aux > length:
        raise Error("invalid BAM layout")
    var name = p.unsafe_offset(32)
    if (
        name[unsafe_offset=name_length - 1] != 0
        or external_call["strlen", Int](name) != name_length - 1
    ):
        raise Error("invalid BAM QNAME")
    var cigar = p.unsafe_offset(32 + name_length)
    var placeholder = (
        ncigar == 2
        and (le32(cigar) & 15) == 4
        and Int(le32(cigar) >> 4) == nseq
        and (le32(cigar.unsafe_offset(4)) & 15) == 3
    )
    while aux < length:
        if length - aux < 3:
            raise Error("truncated auxiliary tag")
        var cg = p[unsafe_offset=aux] == 67 and p[unsafe_offset=aux + 1] == 71
        var kind = p[unsafe_offset=aux + 2]
        aux += 3
        var count: Int
        if kind == 65 or kind == 99 or kind == 67:
            count = 1
        elif kind == 115 or kind == 83:
            count = 2
        elif kind == 105 or kind == 73 or kind == 102:
            count = 4
        elif kind == 100:
            count = 8
        elif kind == 90 or kind == 72:
            var address = external_call["memchr", Int](p.unsafe_offset(aux), Int32(0), length - aux)
            if not address:
                raise Error("unterminated auxiliary string")
            count = address - Int(p) - aux + 1
        elif kind == 66:
            if length - aux < 5:
                raise Error("truncated auxiliary array")
            var subtype = p[unsafe_offset=aux]
            var width = 0
            if subtype == 99 or subtype == 67:
                width = 1
            elif subtype == 115 or subtype == 83:
                width = 2
            elif subtype == 105 or subtype == 73 or subtype == 102:
                width = 4
            if not width:
                raise Error("invalid auxiliary array type")
            var elements = Int(le32(p.unsafe_offset(aux + 1)))
            count = 5 + elements * width
            if count > length - aux:
                raise Error("truncated auxiliary array payload")
            if cg and placeholder and subtype == 73:
                ncigar = elements
                cigar = p.unsafe_offset(aux + 5)
        else:
            raise Error("invalid auxiliary type")
        if count > length - aux:
            raise Error("truncated auxiliary payload")
        aux += count
    var span = 0
    var query = 0
    for i in range(ncigar):
        var word = le32(cigar.unsafe_offset(i * 4))
        var op = word & 15
        var count = Int(word >> 4)
        if op > 8 or not count:
            raise Error("invalid CIGAR operation")
        if op == 0 or op == 2 or op == 3 or op == 7 or op == 8:
            span += count
        if op == 0 or op == 1 or op == 4 or op == 7 or op == 8:
            query += count
    if not flags & 4 and nseq and ncigar and query != nseq:
        raise Error("CIGAR/SEQ length mismatch")
    var end = pos + (1 if flags & 4 else max(span, 1))
    return Record(
        tid,
        pos,
        end,
        span,
        flags,
        Int(p[unsafe_offset=9]),
        Int(Int32(le32(p.unsafe_offset(20)))),
        Int(Int32(le32(p.unsafe_offset(24)))),
        Int(Int32(le32(p.unsafe_offset(28)))),
        nseq,
        ncigar,
        name_length - 1,
        name,
        cigar,
        p.unsafe_offset(cigar_end),
        p.unsafe_offset(seq_end),
    )


struct Reader(Movable):
    """Reusable indexed cursor. Call fetch before next, then read record.value().

    next returns False at the end of a query and raises on corrupt input. Every
    fetch/next invalidates previous records, including the call reaching EOF.
    Each thread needs its own Reader; Bam's immutable index may be shared.
    """

    var source: Input
    var raw: Buffer
    var chunks: List[Chunk]
    var current: Int
    var region: Region
    var previous: Int
    var record: Optional[Record]

    def __init__(out self, path: String) raises:
        self.source = Input(path)
        self.raw = Buffer()
        self.chunks = List[Chunk]()
        self.current = 0
        self.region = Region(0, 0, 0)
        self.previous = -1
        self.record = None

    def fetch(mut self, bam: Bam, region: Region) raises:
        if (
            region.tid < 0
            or region.tid >= len(bam.references)
            or region.begin < 0
            or region.begin >= region.end
        ):
            raise Error("invalid BAM region")
        self.chunks.clear()
        self.current = 0
        self.region = region
        self.previous = -1
        self.record = None
        var minimum = UInt64(0)
        var linear = region.begin >> bam.min_shift
        if linear < len(bam.index[region.tid].linear):
            minimum = bam.index[region.tid].linear[linear]
        for i in range(len(bam.index[region.tid].bins)):
            ref bin = bam.index[region.tid].bins[i]
            var overlap = False
            var offset = UInt64(0)
            for level in range(bam.depth + 1):
                var shift = bam.min_shift + 3 * (bam.depth - level)
                var low = offset + (UInt64(region.begin) >> UInt64(shift))
                var high = offset + (UInt64(region.end - 1) >> UInt64(shift))
                if UInt64(bin.id) >= low and UInt64(bin.id) <= high:
                    overlap = True
                offset += UInt64(1) << UInt64(3 * level)
            if not overlap:
                continue
            for chunk in bin.chunks:
                if chunk.end <= minimum:
                    continue
                var begin = max(chunk.begin, minimum)
                if begin >= chunk.end:
                    raise Error("invalid index chunk")
                self.chunks.append(Chunk(begin, chunk.end))
        sort(Span(self.chunks), _chunk_less)
        var kept = 0
        for i in range(len(self.chunks)):
            var chunk = self.chunks[i]
            if kept and chunk.begin <= self.chunks[kept - 1].end:
                self.chunks[kept - 1].end = max(self.chunks[kept - 1].end, chunk.end)
            else:
                self.chunks[kept] = chunk
                kept += 1
        self.chunks.resize(kept, Chunk(0, 0))
        if kept:
            self.source.seek(self.chunks[0].begin)

    def next(mut self) raises -> Bool:
        self.record = None
        while self.current < len(self.chunks):
            if self.source.tell() >= self.chunks[self.current].end:
                self.current += 1
                if self.current == len(self.chunks):
                    return False
                self.source.seek(self.chunks[self.current].begin)
            var size = Int(self.source.word(2147483647))
            if size < 32:
                raise Error("invalid BAM record length")
            var p: BytePtr
            if size <= self.source.data.length - self.source.position:
                p = self.source.data.data.unsafe_offset(self.source.position)
                self.source.position += size
            else:
                self.raw.reserve(size)
                self.source.exact(self.raw.data, size)
                self.raw.length = size
                p = self.raw.data
            var record = parse_record(p, size)
            if record.tid > self.region.tid or (
                record.tid == self.region.tid and record.pos >= self.region.end
            ):
                self.current = len(self.chunks)
                return False
            if record.tid != self.region.tid or record.pos < 0:
                continue
            if record.pos < self.previous:
                raise Error("BAM is not coordinate sorted")
            self.previous = record.pos
            if record.end > self.region.begin:
                self.record = record
                return True
        return False
