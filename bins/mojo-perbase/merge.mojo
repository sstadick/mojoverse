"""Streaming merge-adjacent with quoted TSV and unsigned 64-bit fields."""

from bio.bgzf import Input
from bio.buffer import Buffer
from options import Options
from output import Output
from text import literal, quoted, unsigned_integer


def get(mut source: Input) raises -> Int:
    if not source.fill():
        return -1
    var b = Int(source.data.data[unsafe_offset=source.position])
    source.position += 1
    return b


def field(mut fields: List[String], mut data: Buffer) raises:
    fields.append(String(from_utf8=Span(unsafe_ptr=data.data, length=data.length)))
    data.length = 0


def row(mut source: Input, mut fields: List[String], mut data: Buffer) raises -> Bool:
    fields.clear()
    data.length = 0
    var quoted_field = False
    var at_start = True
    var after_quote = False
    var any = False
    while True:
        var b = get(source)
        if b == -1:
            if quoted_field:
                raise Error("unterminated quoted TSV field")
            if not any:
                return False
            field(fields, data)
            return True
        any = True
        if quoted_field:
            if b == 34:
                quoted_field = False
                after_quote = True
            else:
                data.push(UInt8(b))
            continue
        if after_quote and b == 34:
            data.push(34)
            quoted_field = True
            after_quote = False
            continue
        if at_start and b == 34:
            quoted_field = True
            at_start = False
            continue
        if b == 9 or b == 10 or b == 13:
            field(fields, data)
            if b == 13:
                var next = get(source)
                if next != 10 and next != -1:
                    source.position -= 1
            if b != 9:
                return True
            at_start = True
            after_quote = False
            continue
        if after_quote:
            raise Error("unexpected data after TSV quote")
        data.push(UInt8(b))
        at_start = False


def unsigned(s: String) raises -> UInt64:
    var n = UInt64(0)
    var start = 1 if s.startswith("+") else 0
    if start == s.byte_length():
        raise Error("empty unsigned integer")
    for i in range(start, s.byte_length()):
        var b = s.as_bytes()[i]
        if b < 48 or b > 57:
            raise Error("invalid unsigned integer")
        var digit = UInt64(b - 48)
        if n > (UInt64.MAX - digit) // 10:
            raise Error("unsigned integer overflow")
        n = n * 10 + digit
    return n


def emit(
    mut out: Output, mut data: Buffer, name: String, begin: UInt64, end: UInt64, depth: UInt64
) raises:
    quoted(data, name.as_bytes())
    data.push(9)
    unsigned_integer(data, begin)
    data.push(9)
    unsigned_integer(data, end)
    data.push(9)
    unsigned_integer(data, depth)
    data.push(10)
    if data.length >= 65536:
        out.write(data)
        data.length = 0


def merge(o: Options) raises:
    var source = Input(o.input if o.input and o.input != "-" else String("/dev/stdin"))
    var first = get(source)
    if first == 239:
        if get(source) != 187 or get(source) != 191:
            raise Error("invalid UTF-8 BOM")
    elif first != -1:
        source.position -= 1
    var out = Output(o)
    var fields = List[String]()
    var data = Buffer()
    var output = Buffer()
    var reference = 0
    var pos_column = 1
    var end_column = 2
    var depth_column = 3
    var columns = 0
    if not o.no_header:
        while row(source, fields, data):
            if len(fields) == 1 and not fields[0]:
                continue
            columns = len(fields)
            reference = -1
            pos_column = -1
            end_column = -1
            depth_column = -1
            for i in range(len(fields)):
                if fields[i] == "REF" or fields[i] == "chrom":
                    if reference != -1:
                        raise Error("duplicate TSV header")
                    reference = i
                if fields[i] == "POS" or fields[i] == "chromStart":
                    if pos_column != -1:
                        raise Error("duplicate TSV header")
                    pos_column = i
                if fields[i] == "END" or fields[i] == "chromEnd":
                    if end_column != -1:
                        raise Error("duplicate TSV header")
                    end_column = i
                if fields[i] == "DEPTH" or fields[i] == "COV":
                    if depth_column != -1:
                        raise Error("duplicate TSV header")
                    depth_column = i
            if reference == -1 or pos_column == -1 or depth_column == -1:
                raise Error("missing required TSV header")
            break
    var name = String("")
    var have = False
    var begin = UInt64(0)
    var end = UInt64(0)
    var depth = UInt64(0)
    while row(source, fields, data):
        if len(fields) == 1 and not fields[0]:
            continue
        if not columns:
            columns = len(fields)
        if len(fields) != columns or max(
            reference, max(pos_column, max(end_column, depth_column))
        ) >= len(fields):
            raise Error("missing or inconsistent TSV fields")
        var next_begin = unsigned(fields[pos_column])
        var next_end = next_begin + 1
        if end_column != -1 and fields[end_column]:
            next_end = unsigned(fields[end_column])
        var next_depth = unsigned(fields[depth_column])
        if have and name == fields[reference] and depth == next_depth and next_begin <= end:
            end = next_end
        else:
            if have:
                emit(out, output, name, begin, end, depth)
            else:
                literal(output, "REF\tPOS\tEND\tDEPTH\n")
            name = fields[reference].copy()
            begin = next_begin
            end = next_end
            depth = next_depth
            have = True
    if have:
        emit(out, output, name, begin, end, depth)
    out.write(output)
    out.close()
