"""The goostr Rust/bstr oracle protocol; Python is used only for test input."""
from std.python import Python
from mojo_bstr import *


def hex_bytes(mut output: String, s: Span[UInt8, _]):
    var digits = String("0123456789abcdef")
    output += "["
    for b in s:
        output += digits[byte=Int(b >> 4)]
        output += digits[byte=Int(b & 15)]
    output += "]"


def unhex(s: String) raises -> List[UInt8]:
    var result = List[UInt8]()
    var data = s.as_bytes()
    for i in range(0, len(data), 2):
        var a = Int(data[i])
        var b = Int(data[i + 1])
        result.append(UInt8((a - 48 if a <= 57 else a - 87) * 16 + (b - 48 if b <= 57 else b - 87)))
    return result^


def snapshot(s: Span[UInt8, _], needle: Span[UInt8, _], n: Int) raises -> String:
    var cp, size, valid = decode_utf8(s)
    var rcp, rsize, rvalid = decode_last_utf8(s)
    var end, error = validate_utf8(s)
    var output = String(cp) + "," + String(size) + "," + ("true" if valid else "false")
    output += "," + String(rcp) + "," + String(rsize) + "," + ("true" if rvalid else "false")
    output += "," + String(end) + "," + String(error) + "|"
    var lossy = to_str_lossy(s)
    var escaped = escape_bytes(s)
    var unescaped = unescape_bytes(Span(escaped))
    var unescaped_lossy = unescape_bytes(Span(lossy))
    hex_bytes(output, Span(lossy))
    hex_bytes(output, Span(escaped))
    hex_bytes(output, Span(unescaped))
    hex_bytes(output, Span(unescaped_lossy))
    var scalar, scalar_size, _ = decode_utf8(needle)
    if scalar_size == 0:
        scalar = 0
    output += String(find_char(s, scalar)) + "," + String(rfind_char(s, scalar)) + "|"
    hex_bytes(output, trim(s))
    hex_bytes(output, trim_start(s))
    hex_bytes(output, trim_end(s))
    var lower = to_ascii_lowercase(s)
    var upper = to_ascii_uppercase(s)
    var reversed = List[UInt8]()
    reversed.extend(s)
    reverse_chars(Span(reversed))
    hex_bytes(output, Span(lower))
    hex_bytes(output, Span(upper))
    hex_bytes(output, Span(reversed))
    output += "|"
    for a, b, point in char_indices(s):
        output += String(a) + "," + String(b) + "," + String(point) + ";"
    output += "|"
    for good, bad in utf8_chunks(s):
        hex_bytes(output, good)
        hex_bytes(output, bad)
    output += "|"
    for part in fields(s):
        hex_bytes(output, part)
    output += "|"
    for part in lines(s):
        hex_bytes(output, part)
    output += "|"
    for part in lines_with_terminator(s):
        hex_bytes(output, part)
    output += "|" + String(find(s, needle)) + "," + String(rfind(s, needle)) + ","
    output += String(find_byteset(s, needle)) + "," + String(rfind_byteset(s, needle)) + ","
    output += String(find_not_byteset(s, needle)) + "," + String(rfind_not_byteset(s, needle)) + "|"
    for at in find_iter(s, needle):
        output += String(at) + ","
    output += "|"
    for at in rfind_iter(s, needle):
        output += String(at) + ","
    output += "|"
    for part in split_str(s, needle):
        hex_bytes(output, part)
    output += "|"
    for part in rsplit_str(s, needle):
        hex_bytes(output, part)
    output += "|"
    for part in splitn_str(s, needle, n):
        hex_bytes(output, part)
    output += "|"
    for part in rsplitn_str(s, needle, n):
        hex_bytes(output, part)
    output += "|"
    var replacement: List[UInt8] = [255, 33]
    var replaced = replace(s, needle, Span(replacement))
    var limited = replacen(s, needle, Span(replacement), n)
    hex_bytes(output, Span(replaced))
    hex_bytes(output, Span(limited))
    return output^


def main() raises:
    var sys = Python.import_module("sys")
    var rows = sys.stdin.read().splitlines()
    for i in range(Int(len(rows))):
        var parts = rows[i].split("|")
        var data = unhex(String(parts[0]))
        var needle = unhex(String(parts[1]))
        print(snapshot(Span(data), Span(needle), Int(String(parts[2]))))
