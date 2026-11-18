"""Deterministic interval selection and worker-sized fetch windows."""

from mojo_seqair.bam import Bam, Region
from mojo_seqair.bgzf import Input
from mojo_seqair.buffer import Buffer, le32
from options import Options, number


def read_text(path: String) raises -> String:
    var source = Input(path)
    var data = Buffer()
    while source.fill():
        data.append(
            source.data.data.unsafe_offset(source.position), source.data.length - source.position
        )
        source.position = source.data.length
    var result = String(from_utf8=Span(unsafe_ptr=data.data, length=data.length))
    _ = data^
    return result^


def region_less(a: Region, b: Region) -> Bool:
    if a.tid != b.tid:
        return a.tid < b.tid
    if a.begin != b.begin:
        return a.begin < b.begin
    return a.end < b.end


def read_bcf(mut intervals: List[Region], bam: Bam, mut source: Input) raises:
    var buffer = Buffer()
    source.exact(buffer.data, 9)
    if le32(buffer.data) != 0x02464342 or buffer.data[unsafe_offset=4] != 2:
        raise Error("expected BCF 2.2")
    var n = Int(le32(buffer.data.unsafe_offset(5)))
    if n < 1 or n > 16777216:
        raise Error("invalid BCF header length")
    buffer.reserve(n)
    source.exact(buffer.data, n)
    var header = String(from_utf8=Span(unsafe_ptr=buffer.data, length=n - 1))
    var tids = List[Int]()
    for line in header.split("\n"):
        if not line.startswith("##contig=<"):
            continue
        var id = String("")
        var idx = len(tids)
        var body = String(line.removeprefix("##contig=<").removesuffix(">"))
        for field in body.split(","):
            if field.startswith("ID="):
                id = String(field.removeprefix("ID="))
            if field.startswith("IDX="):
                idx = number(String(field.removeprefix("IDX=")), 1048576)
        if not id:
            raise Error("BCF contig without ID")
        if idx >= len(tids):
            tids.resize(idx + 1, -1)
        for i in range(len(bam.references)):
            if String(from_utf8=Span(bam.references[i].name)) == id:
                tids[idx] = i
    while source.read(buffer.data, 8):
        var shared = Int(le32(buffer.data))
        var individual = Int(le32(buffer.data.unsafe_offset(4)))
        if shared < 24:
            raise Error("short BCF record")
        source.exact(buffer.data, 8)
        var rid = Int(le32(buffer.data))
        var pos = Int(le32(buffer.data.unsafe_offset(4)))
        if rid >= len(tids) or tids[rid] < 0 or pos >= 2147483647:
            raise Error("invalid BCF position")
        if pos < bam.references[tids[rid]].length:
            intervals.append(Region(tids[rid], pos, pos + 1))
        source.skip(shared - 8 + individual)


def read_regions(mut intervals: List[Region], bam: Bam, path: String, variants: Bool) raises:
    if variants:
        var source = Input(path)
        if source.fill() and source.data.data[unsafe_offset=0] == 66:
            read_bcf(intervals, bam, source)
            return
    var text = read_text(path)
    for line in text.split("\n"):
        var s = String(line).strip()
        if not s or s.startswith("#") or s.startswith("track ") or s.startswith("browser "):
            continue
        var fields = s.split()
        if len(fields) < (8 if variants else 3):
            raise Error("too few interval fields")
        var begin = number(String(fields[1]), 4294967295)
        var end = begin
        if variants:
            if not begin:
                raise Error("VCF position must be positive")
            begin -= 1
        else:
            end = number(String(fields[2]), 4294967295)
        if begin > end:
            raise Error("reversed interval")
        var tid = -1
        for i in range(len(bam.references)):
            if String(from_utf8=Span(bam.references[i].name)) == fields[0]:
                tid = i
        if tid == -1:
            raise Error("unknown reference in interval file")
        end = min(end, bam.references[tid].length)
        if begin < end:
            intervals.append(Region(tid, begin, end))


def make_jobs(bam: Bam, o: Options) raises -> List[Region]:
    var intervals = List[Region]()
    if o.bed:
        read_regions(intervals, bam, o.bed, False)
    if o.variants:
        read_regions(intervals, bam, o.variants, True)
    if o.bed or o.variants:
        sort(Span(intervals), region_less)
        if not o.skip_merge:
            var kept = 0
            for i in range(len(intervals)):
                var r = intervals[i]
                if kept and intervals[kept - 1].tid == r.tid and intervals[kept - 1].end >= r.begin:
                    intervals[kept - 1].end = max(intervals[kept - 1].end, r.end)
                else:
                    intervals[kept] = r
                    kept += 1
            intervals.resize(kept, Region(0, 0, 0))
    else:
        for tid in range(len(bam.references)):
            var p = 0
            while p < bam.references[tid].length:
                intervals.append(Region(tid, p, min(p + o.chunk, bam.references[tid].length)))
                p += o.chunk
    var jobs = List[Region]()
    var width = min(4294967295, o.chunk * max(1, o.threads - 2))
    var first = 0
    for tid in range(len(bam.references)):
        var begin = 0
        while begin < bam.references[tid].length:
            var end = min(begin + width, bam.references[tid].length)
            while first < len(intervals) and (
                intervals[first].tid < tid
                or (intervals[first].tid == tid and intervals[first].end <= begin)
            ):
                first += 1
            var i = first
            while i < len(intervals) and intervals[i].tid == tid and intervals[i].begin < end:
                var r = intervals[i]
                if r.end > begin:
                    jobs.append(Region(tid, max(r.begin, begin), min(r.end, end)))
                i += 1
            begin = end
    return jobs^
