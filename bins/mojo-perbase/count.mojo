"""Native Mojo counting, ported from the MIT Goose/C Perbase algorithms.

Workers own their reader and reuse payload, cursor and sparse endpoint storage.
The sink must consume bytes synchronously; it must not retain the passed view.
"""

from std.collections import Array
from std.ffi import external_call
from std.bit import count_trailing_zeros
from mojo_seqair.bam import Bam, Reader, Record, Region, decode_sequence
from mojo_seqair.buffer import Buffer, BytePtr, le32
from options import Options
from names import Names
from text import literal, integer, quoted, base_counts, unsigned_integer_reserved
from fasta import Fasta


@fieldwise_init
struct Read(ImplicitlyCopyable):
    var pos: Int
    var end: Int
    var span: Int
    var refpos: Int
    var query: Int
    var segment_end: Int
    var group: Int
    var cigar: UInt32
    var seq: UInt32
    var qual: UInt32
    var nseq: UInt32
    var ncigar: UInt32
    var operation: UInt32
    var flags: UInt16
    var mapq: UInt8
    var code: UInt8
    var passed: Bool
    var admitted: Bool


@fieldwise_init
struct Entry(ImplicitlyCopyable):
    var read: Int
    var next: Int
    var qpos: Int
    var base: UInt8
    var quality: UInt8
    var op: UInt8
    var insertion: Bool


@fieldwise_init
struct Block(ImplicitlyCopyable):
    var begin: Int
    var end: Int
    var ordinal: Int
    var next: Int
    var no_stop: Bool


def block_less(a: Block, b: Block) -> Bool:
    if a.begin != b.begin:
        return a.begin < b.begin
    if a.end != b.end:
        return a.end < b.end
    return a.ordinal < b.ordinal


def int_less(a: Int, b: Int) -> Bool:
    return a < b


@always_inline
def passes(o: Options, r: Record) -> Bool:
    return (r.flags & o.include) == o.include and not (r.flags & o.exclude) and r.mapq >= o.mapq


def advance(mut s: Read, payload: BytePtr, pos: Int) raises:
    while s.operation < s.ncigar:
        var word = le32(payload.unsafe_offset(Int(s.cigar) + Int(s.operation) * 4))
        var op = word & 15
        var n = Int(word >> 4)
        var consumes_ref = op == 0 or op == 2 or op == 3 or op == 7 or op == 8
        var consumes_query = op == 0 or op == 1 or op == 4 or op == 7 or op == 8
        if consumes_ref and s.refpos + n > pos:
            s.segment_end = s.refpos + n
            s.code = UInt8(op)
            return
        if consumes_ref:
            s.refpos += n
        if consumes_query:
            s.query += n
        s.operation += 1
    raise Error("pileup cursor outside read")


@always_inline
def entry_at(mut s: Read, payload: BytePtr, id: Int, pos: Int) raises -> Entry:
    if pos >= s.segment_end:
        advance(s, payload, pos)
    var e = Entry(id, -1, -1, 78, 255, s.code, False)
    if s.code != 2 and s.code != 3:
        var q = s.query + pos - s.refpos
        if q >= 0 and q < Int(s.nseq):
            e.qpos = q
            e.base = payload[unsafe_offset=Int(s.seq) + q]
            e.quality = payload[unsafe_offset=Int(s.qual) + q]
        if pos + 1 == s.segment_end:
            for nxt in range(Int(s.operation) + 1, Int(s.ncigar)):
                var following = le32(payload.unsafe_offset(Int(s.cigar) + nxt * 4)) & 15
                if following == 6:
                    continue
                e.insertion = following == 1
                break
    return e


def canonical(b: UInt8) -> UInt8:
    return b if b == 65 or b == 67 or b == 71 or b == 84 else 78


struct Counter[send: def(Int, BytePtr, Int) raises thin -> None](Movable):
    var o: Options
    var context: Int
    var reader: Reader
    var fasta: Fasta
    var payload: Buffer
    var output: Buffer
    var reads: List[Read]
    var names: Names
    var active: List[Int]
    var entries: List[Entry]
    var touched: List[Int]
    var members: List[Int]
    var heap: List[Int]
    var delta: List[Int]
    var mask: List[UInt64]
    var words: List[Int]
    var blocks: List[Block]
    var sorted: List[Block]

    def __init__(out self, o: Options, context: Int) raises:
        self.o = o.copy()
        self.context = context
        self.reader = Reader(o.input)
        self.fasta = Fasta(o.reference, o.cache_size)
        self.payload = Buffer()
        self.output = Buffer(131072)
        self.reads = List[Read]()
        self.names = Names()
        self.active = List[Int]()
        self.entries = List[Entry]()
        self.touched = List[Int]()
        self.members = List[Int]()
        self.heap = List[Int]()
        self.delta = List[Int]()
        self.mask = List[UInt64]()
        self.words = List[Int]()
        self.blocks = List[Block]()
        self.sorted = List[Block]()

    def flush(mut self) raises:
        if self.output.length:
            Self.send(self.context, self.output.data, self.output.length)
            self.output.length = 0

    @always_inline
    def maybe_flush(mut self) raises:
        var sent = self.output.length // 65536 * 65536
        if sent:
            Self.send(self.context, self.output.data, sent)
            self.output.length -= sent
            _ = external_call["memmove", Int](
                self.output.data, self.output.data.unsafe_offset(sent), self.output.length
            )

    def load_base(mut self, bam: Bam, region: Region) raises:
        self.reads.clear()
        self.payload.length = 0
        self.names.clear()
        self.reader.fetch(bam, region)
        var logical = 0
        while self.reader.next():
            var r = self.reader.record.value()
            if r.flags & 4:
                continue
            logical += r.name_length + r.nseq * 2 + r.ncigar * 4
            if logical > self.o.max_bytes:
                raise Error("region payload exceeds --max-region-bytes")
            var cigar = self.payload.length
            self.payload.append(r.cigar, r.ncigar * 4)
            var seq = self.payload.length
            self.payload.reserve(seq + r.nseq)
            decode_sequence(r.sequence, self.payload.data.unsafe_offset(seq), r.nseq)
            self.payload.length += r.nseq
            var qual = self.payload.length
            self.payload.append(r.quality, r.nseq)
            var group = -1
            if self.o.mate:
                group = self.names.group(r.name, r.name_length)
                ref g = self.names.groups[group]
                if g.end >= r.pos:
                    g.overlaps = True
                g.end = max(g.end, r.end - 1)
            self.reads.append(
                Read(
                    r.pos,
                    r.end,
                    r.span,
                    r.pos,
                    0,
                    r.pos,
                    group,
                    UInt32(cigar),
                    UInt32(seq),
                    UInt32(qual),
                    UInt32(r.nseq),
                    UInt32(r.ncigar),
                    0,
                    UInt16(r.flags),
                    UInt8(r.mapq),
                    0,
                    passes(self.o, r),
                    True,
                )
            )
        self.heap.clear()
        self.heap.reserve(len(self.reads))
        var previous = -1
        var limit = min(self.o.max_depth, 2147483647)
        for i in range(len(self.reads)):
            ref s = self.reads[i]
            if s.group != -1 and not self.names.groups[s.group].overlaps:
                s.group = -1
            if limit > 0 and len(self.reads) <= limit:
                continue
            while len(self.heap) and self.heap[0] < s.pos:
                var last = self.heap.pop()
                var at = 0
                while at * 2 + 1 < len(self.heap):
                    var child = at * 2 + 1
                    if child + 1 < len(self.heap) and self.heap[child + 1] < self.heap[child]:
                        child += 1
                    if self.heap[child] >= last:
                        break
                    self.heap[at] = self.heap[child]
                    at = child
                if len(self.heap):
                    self.heap[at] = last
            var cursor = s.pos == previous or (previous < 0 and region.tid == 0 and s.pos == 0)
            if cursor and len(self.heap) >= limit:
                s.admitted = False
                continue
            if s.span or not cursor:
                var value = s.pos + s.span
                var at = len(self.heap)
                self.heap.append(value)
                while at and self.heap[(at - 1) // 2] > value:
                    self.heap[at] = self.heap[(at - 1) // 2]
                    at = (at - 1) // 2
                self.heap[at] = value
            previous = s.pos
        # One entry/index per retained read is the upper bound for a column.
        # These lists do not grow while their pointers are used below. Every
        # read/group/link index originates in this store, never in BAM bytes.
        self.active.resize(len(self.reads), 0)
        self.entries.resize(len(self.reads), Entry(0, -1, -1, 78, 255, 0, False))
        self.members.resize(len(self.reads), 0)
        self.touched.resize(len(self.reads), 0)

    @always_inline
    def choose(self, a: Entry, b: Entry) -> Tuple[Bool, UInt8]:
        var ar = self.reads.unsafe_ptr()[unsafe_offset=a.read]
        var br = self.reads.unsafe_ptr()[unsafe_offset=b.read]
        if ar.passed != br.passed:
            return (ar.passed, 0)
        if not ar.passed:
            return (True, 0)
        var mode = self.o.strategy
        var fallback = mode == 1 or a.qpos < 0 or b.qpos < 0
        if fallback:
            if ar.mapq != br.mapq:
                return (ar.mapq > br.mapq, 0)
        elif mode < 8:
            var aq = a.quality if mode <= 4 else ar.mapq
            var bq = b.quality if mode <= 4 else br.mapq
            if aq != bq:
                return (aq > bq, 0)
            aq = ar.mapq if mode <= 4 else a.quality
            bq = br.mapq if mode <= 4 else b.quality
            if aq != bq:
                return (aq > bq, 0)
        if fallback or mode == 2 or mode == 5:
            return (Bool(ar.flags & 64) or not Bool(br.flags & 64), 0)
        var ab = canonical(a.base)
        var bb = canonical(b.base)
        if ab == bb:
            return (True, ab)
        if mode == 4 or mode == 7 or mode == 9:
            return (True, 78)
        var lo = min(ab, bb)
        var hi = max(ab, bb)
        var recommended = UInt8(78)
        if lo == 65 and hi == 71:
            recommended = 82
        elif lo == 67 and hi == 84:
            recommended = 89
        elif lo == 67 and hi == 71:
            recommended = 83
        elif lo == 65 and hi == 84:
            recommended = 87
        elif lo == 71 and hi == 84:
            recommended = 75
        elif lo == 65 and hi == 67:
            recommended = 77
        return (True, recommended)

    @always_inline
    def add_entry(self, mut counts: Array[Int, 17], e: Entry, recommended: UInt8, resolved: Bool):
        if not self.reads.unsafe_ptr()[unsafe_offset=e.read].passed:
            counts[15] += 1
            return
        if resolved:
            counts[16] += 1
        if e.op == 3:
            counts[14] += 1
            return
        counts[0] += 1
        if e.op == 2:
            counts[13] += 1
            return
        var base = recommended if recommended else e.base
        if Int(e.quality) < self.o.baseq:
            base = 78
        # Inputs are the uppercase BAM alphabet (or the mate resolver's
        # uppercase IUPAC recommendation), so low five bits identify the base.
        comptime ordinary = "\x05\x01\x05\x02\x05\x05\x05\x03\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x04\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05"
        comptime resolved_base = "\x05\x01\x05\x02\x05\x05\x05\x03\x05\x05\x05\x0a\x05\x0b\x05\x05\x05\x05\x06\x08\x04\x05\x05\x09\x05\x07\x05\x05\x05\x05\x05\x05"
        var column = Int(ordinary.as_bytes()[Int(base & 31)])
        if recommended:
            column = Int(resolved_base.as_bytes()[Int(base & 31)])
        counts[column] += 1
        if e.insertion:
            counts[12] += 1

    def count_entries(mut self, nentries: Int, mut counts: Array[Int, 17]):
        var entries = self.entries.unsafe_ptr().unsafe_origin_cast[MutUntrackedOrigin]()
        var reads = self.reads.unsafe_ptr().unsafe_origin_cast[MutUntrackedOrigin]()
        var groups = self.names.groups.unsafe_ptr().unsafe_origin_cast[MutUntrackedOrigin]()
        var touched = self.touched.unsafe_ptr().unsafe_origin_cast[MutUntrackedOrigin]()
        var members = self.members.unsafe_ptr().unsafe_origin_cast[MutUntrackedOrigin]()
        var ntouched = 0
        for i in range(nentries):
            var e = entries[unsafe_offset=i]
            var id = reads[unsafe_offset=e.read].group
            if id == -1:
                self.add_entry(counts, e, 0, False)
                continue
            ref g = groups[unsafe_offset=id]
            if g.head == -1:
                touched[unsafe_offset=ntouched] = id
                ntouched += 1
            entries[unsafe_offset=i].next = g.head
            g.head = i
        for t in range(ntouched):
            var id = touched[unsafe_offset=t]
            var n = 0
            var i = groups[unsafe_offset=id].head
            while i != -1:
                members[unsafe_offset=n] = i
                n += 1
                i = entries[unsafe_offset=i].next
            groups[unsafe_offset=id].head = -1
            if n == 1:
                self.add_entry(counts, entries[unsafe_offset=members[unsafe_offset=0]], 0, False)
                continue
            if n == 2:
                var later = entries[unsafe_offset=members[unsafe_offset=0]]
                var earlier = entries[unsafe_offset=members[unsafe_offset=1]]
                var best = later
                var second = earlier
                if not self.choose(later, earlier)[0]:
                    best = earlier
                    second = later
                self.add_entry(counts, best, self.choose(best, second)[1], True)
                continue
            for j in range(n // 2):
                var tmp = members[unsafe_offset=j]
                members[unsafe_offset=j] = members[unsafe_offset=n - j - 1]
                members[unsafe_offset=n - j - 1] = tmp
            for j in range(1, n):
                var value = members[unsafe_offset=j]
                var at = j
                while (
                    at
                    and self.choose(
                        entries[unsafe_offset=value],
                        entries[unsafe_offset=members[unsafe_offset=at - 1]],
                    )[0]
                ):
                    members[unsafe_offset=at] = members[unsafe_offset=at - 1]
                    at -= 1
                members[unsafe_offset=at] = value
            var best = entries[unsafe_offset=members[unsafe_offset=0]]
            self.add_entry(
                counts,
                best,
                self.choose(best, entries[unsafe_offset=members[unsafe_offset=1]])[1],
                True,
            )

    def base_depth[mate: Bool](mut self, bam: Bam, region: Region) raises:
        self.load_base(bam, region)
        var prefix = Buffer()
        quoted(prefix, Span(bam.references[region.tid].name))
        prefix.push(9)
        var bases = self.payload.data
        if self.o.reference and (len(self.reads) or self.o.keep):
            bases = self.fasta.fetch(Span(bam.references[region.tid].name), region)
        var next = 0
        var expire = region.end
        var pos = region.begin
        var nactive = 0
        var active = self.active.unsafe_ptr().unsafe_origin_cast[MutUntrackedOrigin]()
        var reads = self.reads.unsafe_ptr().unsafe_origin_cast[MutUntrackedOrigin]()
        var entries = self.entries.unsafe_ptr().unsafe_origin_cast[MutUntrackedOrigin]()
        var nreads = len(self.reads)
        while pos < region.end:
            while next < nreads and reads[unsafe_offset=next].pos <= pos:
                var s = reads[unsafe_offset=next]
                if s.admitted and s.span and s.end > pos:
                    active[unsafe_offset=nactive] = next
                    nactive += 1
                    expire = min(expire, s.end)
                next += 1
            if pos >= expire:
                var kept = 0
                expire = region.end
                for i in range(nactive):
                    var id = active[unsafe_offset=i]
                    if reads[unsafe_offset=id].end > pos:
                        active[unsafe_offset=kept] = id
                        kept += 1
                        expire = min(expire, reads[unsafe_offset=id].end)
                nactive = kept
            if not nactive and not self.o.keep:
                if next == nreads:
                    break
                pos = max(pos + 1, reads[unsafe_offset=next].pos)
                continue
            var counts = Array[Int, 17](fill=0)
            var nentries = 0
            for i in range(nactive):
                var id = active[unsafe_offset=i]
                var e = entry_at(reads[unsafe_offset=id], self.payload.data, id, pos)
                # Without mate resolution there is no need to materialize
                # entries. Keep the separately measured grouped path for -m.
                comptime if not mate:
                    self.add_entry(counts, e, 0, False)
                else:
                    entries[unsafe_offset=nentries] = e
                    nentries += 1
            if nentries:
                self.count_entries(nentries, counts)
            self.output.append(prefix.data, prefix.length)
            integer(self.output, pos + Int(not self.o.zero))
            if self.o.reference:
                self.output.push(9)
                self.output.push(bases[unsafe_offset=pos - region.begin])
            var near = nactive > self.o.max_depth - self.o.max_depth // 100
            base_counts(self.output, counts, near)
            self.maybe_flush()
            pos += 1

    @always_inline
    def delta_change(mut self, pos: Int, value: Int):
        var word = pos // 64
        if not self.mask[word]:
            self.words.append(word)
        self.mask[word] |= UInt64(1) << UInt64(pos % 64)
        self.delta[pos] += value

    def delta_add(mut self, b: Block):
        self.delta_change(b.begin, 1)
        if not b.no_stop:
            self.delta_change(b.end, -1)

    def add_block(mut self, r: Region, begin: Int, end: Int, group: Int):
        if begin >= r.end or end <= r.begin:
            return
        var b = Block(
            max(begin, r.begin) - r.begin,
            min(end - r.begin, r.end - r.begin - 1),
            len(self.blocks),
            -1,
            end >= r.end,
        )
        if group == -1:
            self.delta_add(b)
            return
        b.next = self.names.groups[group].head
        self.names.groups[group].head = len(self.blocks)
        self.blocks.append(b)

    def depth_emit(mut self, prefix: Buffer, r: Region, begin: Int, end: Int, depth: Int) raises:
        if self.o.no_merge and not self.o.keep and not depth:
            return
        var pos = begin
        while pos < end:
            var stop = pos + 1 if self.o.no_merge else end
            self.output.append(prefix.data, prefix.length)
            # Three u64 fields plus up to three tabs and a newline fit in 64 bytes.
            self.output.reserve(self.output.length + 64)
            unsigned_integer_reserved(self.output, UInt64(r.begin + pos + Int(not self.o.zero)))
            self.output.data[unsafe_offset=self.output.length] = 9
            self.output.length += 1
            unsigned_integer_reserved(self.output, UInt64(r.begin + stop + Int(not self.o.zero)))
            self.output.data[unsafe_offset=self.output.length] = 9
            self.output.length += 1
            if self.o.bed_format:
                self.output.data[unsafe_offset=self.output.length] = 9
                self.output.length += 1
            unsigned_integer_reserved(self.output, UInt64(depth))
            self.output.data[unsafe_offset=self.output.length] = 10
            self.output.length += 1
            self.maybe_flush()
            pos = stop

    def only_depth(mut self, bam: Bam, r: Region) raises:
        for w in self.words:
            var bits = self.mask[w]
            while bits:
                var bit = Int(count_trailing_zeros(bits))
                self.delta[w * 64 + bit] = 0
                bits &= bits - 1
            self.mask[w] = 0
        self.words.clear()
        self.blocks.clear()
        self.names.clear()
        var length = r.end - r.begin
        if length > len(self.delta):
            self.delta.resize(length, 0)
        if (length + 63) // 64 > len(self.mask):
            self.mask.resize((length + 63) // 64, 0)
        self.reader.fetch(bam, r)
        while self.reader.next():
            var rec = self.reader.record.value()
            if not passes(self.o, rec):
                continue
            if self.o.fast:
                self.add_block(r, rec.pos, rec.end, -1)
                continue
            var eligible = (
                self.o.mate
                and Bool(rec.flags & 1)
                and rec.tid == rec.mate_tid
                and (
                    abs(rec.template_len) // 2 < rec.end - rec.pos
                    or abs(rec.mate_pos - rec.pos) < rec.end - rec.pos
                )
            )
            var id = -1
            if eligible:
                id = self.names.group(rec.name, rec.name_length)
            var pos = rec.pos
            for i in range(rec.ncigar):
                var word = rec.cigar_word(i)
                var op = word & 15
                var n = Int(word >> 4)
                if op == 0 or op == 2 or op == 7 or op == 8:
                    self.add_block(r, pos, pos + n, id)
                    pos += n
                elif op == 3:
                    pos += n
        for g in range(len(self.names.groups)):
            self.sorted.clear()
            var i = self.names.groups[g].head
            while i != -1:
                self.sorted.append(self.blocks[i])
                i = self.blocks[i].next
            sort(Span(self.sorted), block_less)
            i = 0
            while i < len(self.sorted):
                var b = self.sorted[i]
                i += 1
                while i < len(self.sorted) and self.sorted[i].begin <= b.end:
                    b.end = max(b.end, self.sorted[i].end)
                    i += 1
                self.delta_add(b)
        sort(Span(self.words), int_less)
        var prefix = Buffer()
        quoted(prefix, Span(bam.references[r.tid].name))
        prefix.push(9)
        var depth = 0
        var begin = 0
        for w in self.words:
            var bits = self.mask[w]
            while bits:
                var pos = w * 64 + Int(count_trailing_zeros(bits))
                var next = depth + self.delta[pos]
                if next != depth:
                    self.depth_emit(prefix, r, begin, pos, depth)
                    begin = pos
                    depth = next
                bits &= bits - 1
        self.depth_emit(prefix, r, begin, length, depth)

    def region(mut self, bam: Bam, r: Region) raises:
        if self.o.only:
            self.only_depth(bam, r)
        elif self.o.mate:
            self.base_depth[True](bam, r)
        else:
            self.base_depth[False](bam, r)
        self.flush()
