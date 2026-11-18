"""UTF-8 maximal-subpart decoding, preserving arbitrary input bytes in views."""

from std.math import max
from .bytes import reverse_bytes
from .search import find, rfind


def decode_utf8(s: Span[mut=False, UInt8, _]) -> Tuple[Int, Int, Bool]:
    """(scalar, consumed, valid); malformed maximal subparts yield U+FFFD.

    Empty input returns (0xFFFD, 0, False). Surrogates and values above
    U+10FFFF are never accepted.
    """
    if len(s) == 0:
        return (0xFFFD, 0, False)
    var lead = Int(s[0])
    if lead < 0x80:
        return (lead, 1, True)
    if lead < 0xC2 or lead > 0xF4:
        return (0xFFFD, 1, False)
    var width = 2 if lead < 0xE0 else (3 if lead < 0xF0 else 4)
    var cp = lead & (0x7F >> width)
    for i in range(1, width):
        if i == len(s):
            return (0xFFFD, i, False)
        var b = Int(s[i])
        if b < 0x80 or b > 0xBF:
            return (0xFFFD, i, False)
        if i == 1 and (
            (lead == 0xE0 and b < 0xA0)
            or (lead == 0xED and b > 0x9F)
            or (lead == 0xF0 and b < 0x90)
            or (lead == 0xF4 and b > 0x8F)
        ):
            return (0xFFFD, 1, False)
        cp = (cp << 6) | (b & 0x3F)
    return (cp, width, True)


def decode_last_utf8(s: Span[mut=False, UInt8, _]) -> Tuple[Int, Int, Bool]:
    """Decode the final scalar or malformed subpart; empty consumes zero bytes."""
    if len(s) == 0:
        return (0xFFFD, 0, False)
    var start = len(s) - 1
    var limit = max(0, len(s) - 4)
    while start > limit and s[start] >= 0x80 and s[start] <= 0xBF:
        start -= 1
    var cp, size, valid = decode_utf8(s[start:])
    if start + size != len(s):
        return (0xFFFD, 1, False)
    return (cp, size, valid)


def decode_utf8_lossy(s: Span[mut=False, UInt8, _]) -> Tuple[Int, Int]:
    """First (scalar, consumed), with malformed subparts replaced by U+FFFD."""
    var cp, size, _ = decode_utf8(s)
    return (cp, size)


def decode_last_utf8_lossy(s: Span[mut=False, UInt8, _]) -> Tuple[Int, Int]:
    """Final (scalar, consumed), with malformed subparts replaced by U+FFFD."""
    var cp, size, _ = decode_last_utf8(s)
    return (cp, size)


def validate_utf8(s: Span[mut=False, UInt8, _]) -> Tuple[Int, Int]:
    """(valid_up_to, error_len): 0 success, -1 truncated, 1..3 malformed bytes."""
    var i = 0
    while i < len(s):
        var _, size, valid = decode_utf8(s[i:])
        if not valid:
            var incomplete = i + size == len(s) and s[i] >= 0xC2 and s[i] <= 0xF4
            return (i, -1 if incomplete else size)
        i += size
    return (len(s), 0)


def is_utf8(s: Span[mut=False, UInt8, _]) -> Bool:
    """Whether the whole input is valid UTF-8; empty input is valid."""
    return validate_utf8(s)[1] == 0


@fieldwise_init
struct CharIndices[origin: ImmOrigin](ImplicitlyCopyable, Iterator):
    """Streaming (start, exclusive end, scalar) in original byte coordinates."""

    var s: Span[UInt8, Self.origin]
    var cursor: Int
    comptime Element = Tuple[Int, Int, Int]

    def __iter__(self) -> Self:
        return self

    def __next__(mut self) raises StopIteration -> Self.Element:
        if self.cursor == len(self.s):
            raise StopIteration()
        var start = self.cursor
        var cp, size, _ = decode_utf8(self.s[start:])
        self.cursor += size
        return (start, self.cursor, cp)


def char_indices[o: ImmOrigin](s: Span[UInt8, o]) -> CharIndices[o]:
    """Iterate decoded scalars and malformed maximal subparts with byte offsets."""
    return CharIndices(s, 0)


@fieldwise_init
struct Chars[origin: ImmOrigin](ImplicitlyCopyable, Iterator):
    """Streaming decoded scalars, replacing malformed subparts with U+FFFD."""

    var indices: CharIndices[Self.origin]
    comptime Element = Int

    def __iter__(self) -> Self:
        return self

    def __next__(mut self) raises StopIteration -> Int:
        return self.indices.__next__()[2]


def chars[o: ImmOrigin](s: Span[UInt8, o]) -> Chars[o]:
    """Iterate decoded scalar values; this is not grapheme segmentation."""
    return Chars(char_indices(s))


@fieldwise_init
struct UTF8Chunks[origin: ImmOrigin](ImplicitlyCopyable, Iterator):
    """Streaming pairs of valid bytes and one malformed subpart, both borrowed."""

    var s: Span[UInt8, Self.origin]
    var cursor: Int
    comptime Element = Tuple[Span[UInt8, Self.origin], Span[UInt8, Self.origin]]

    def __iter__(self) -> Self:
        return self

    def __next__(mut self) raises StopIteration -> Self.Element:
        if self.cursor == len(self.s):
            raise StopIteration()
        var start = self.cursor
        while self.cursor < len(self.s):
            var at = self.cursor
            var _, size, valid = decode_utf8(self.s[at:])
            self.cursor += size
            if not valid:
                return (self.s[start:at], self.s[at : self.cursor])
        return (self.s[start:], self.s[len(self.s) :])


def utf8_chunks[o: ImmOrigin](s: Span[UInt8, o]) -> UTF8Chunks[o]:
    """Borrow valid/invalid pieces without loss; empty input yields no chunks."""
    return UTF8Chunks(s, 0)


def to_str_lossy_into(s: Span[mut=False, UInt8, _], mut output: List[UInt8]):
    """Append valid UTF-8 bytes; replace each malformed subpart with EF BF BD."""
    for valid, invalid in utf8_chunks(s):
        output.extend(valid)
        if len(invalid) != 0:
            output.append(0xEF)
            output.append(0xBF)
            output.append(0xBD)


def to_str_lossy(s: Span[mut=False, UInt8, _]) -> List[UInt8]:
    """Owned valid UTF-8 bytes, replacing malformed subparts with U+FFFD."""
    var output = List[UInt8]()
    to_str_lossy_into(s, output)
    return output^


def is_whitespace(cp: Int) -> Bool:
    """Unicode White_Space (not zero-width space or BOM)."""
    return (
        0x09 <= cp <= 0x0D
        or cp == 0x20
        or cp == 0x85
        or cp == 0xA0
        or cp == 0x1680
        or 0x2000 <= cp <= 0x200A
        or cp == 0x2028
        or cp == 0x2029
        or cp == 0x202F
        or cp == 0x205F
        or cp == 0x3000
    )


def trim_start_with[
    o: ImmOrigin, P: def(Int) -> Bool
](s: Span[UInt8, o], predicate: P) -> Span[UInt8, o]:
    """Borrow s without leading scalars accepted by predicate (invalid becomes U+FFFD)."""
    var start = 0
    while start < len(s):
        var cp, size, _ = decode_utf8(s[start:])
        if not predicate(cp):
            break
        start += size
    return s[start:]


def trim_end_with[
    o: ImmOrigin, P: def(Int) -> Bool
](s: Span[UInt8, o], predicate: P) -> Span[UInt8, o]:
    """Borrow s without trailing scalars accepted by predicate."""
    var end = len(s)
    while end > 0:
        var cp, size, _ = decode_last_utf8(s[:end])
        if not predicate(cp):
            break
        end -= size
    return s[:end]


def trim_with[o: ImmOrigin, P: def(Int) -> Bool](s: Span[UInt8, o], predicate: P) -> Span[UInt8, o]:
    """Borrow s with accepted scalars removed at both ends."""
    return trim_end_with(trim_start_with(s, predicate), predicate)


def trim_start[o: ImmOrigin](s: Span[UInt8, o]) -> Span[UInt8, o]:
    """Borrow s without leading Unicode White_Space."""
    return trim_start_with(s, is_whitespace)


def trim_end[o: ImmOrigin](s: Span[UInt8, o]) -> Span[UInt8, o]:
    """Borrow s without trailing Unicode White_Space."""
    return trim_end_with(s, is_whitespace)


def trim[o: ImmOrigin](s: Span[UInt8, o]) -> Span[UInt8, o]:
    """Borrow s without Unicode White_Space at either end."""
    return trim_with(s, is_whitespace)


@fieldwise_init
struct Fields[origin: ImmOrigin, P: (def(Int) -> Bool) & Copyable](Copyable):
    """Nonempty borrowed fields separated by decoded scalars accepted by predicate."""

    var s: Span[UInt8, Self.origin]
    var predicate: Self.P
    var cursor: Int
    comptime Element = Span[UInt8, Self.origin]

    def __iter__(self) -> Self:
        return self.copy()

    def __next__(mut self) raises StopIteration -> Self.Element:
        var start = self.cursor
        while self.cursor < len(self.s):
            var at = self.cursor
            var cp, size, _ = decode_utf8(self.s[at:])
            self.cursor += size
            if self.predicate(cp):
                if start < at:
                    return self.s[start:at]
                start = self.cursor
        if start < len(self.s):
            return self.s[start:]
        raise StopIteration()


def fields_with[
    o: ImmOrigin, P: (def(Int) -> Bool) & Copyable
](s: Span[UInt8, o], var predicate: P) -> Fields[o, P]:
    """Iterate nonempty fields; invalid subparts are U+FFFD to predicate."""
    return Fields(s, predicate^, 0)


def fields[o: ImmOrigin](s: Span[UInt8, o]) -> Fields[o, type_of(is_whitespace)]:
    """Iterate nonempty fields separated by Unicode White_Space."""
    return fields_with(s, is_whitespace)


def reverse_chars(s: Span[mut=True, UInt8, _]):
    """Reverse scalars and malformed subparts in place, retaining bytes within each."""
    var i = 0
    while i < len(s):
        var _, size, _ = decode_utf8(s[i:])
        reverse_bytes(s[i : i + size])
        i += size
    reverse_bytes(s)


def _char_bytes(cp: Int) raises -> List[UInt8]:
    if cp < 0 or cp > 0x10FFFF or 0xD800 <= cp <= 0xDFFF:
        raise Error("expected a Unicode scalar")
    var width = 1 if cp < 0x80 else (2 if cp < 0x800 else (3 if cp < 0x10000 else 4))
    var output = List[UInt8](length=width, fill=0)
    var rest = cp
    for i in range(width - 1, 0, -1):
        output[i] = UInt8(0x80 | (rest & 0x3F))
        rest >>= 6
    var prefix = 0 if width == 1 else (0xC0 if width == 2 else (0xE0 if width == 3 else 0xF0))
    output[0] = UInt8(prefix | rest)
    return output^


def find_char(s: Span[mut=False, UInt8, _], cp: Int) raises -> Int:
    """Find a scalar's UTF-8 encoding; malformed input never matches U+FFFD."""
    var encoded = _char_bytes(cp)
    return find(s, Span(encoded))


def rfind_char(s: Span[mut=False, UInt8, _], cp: Int) raises -> Int:
    """Find the final scalar encoding; invalid scalar arguments raise Error."""
    var encoded = _char_bytes(cp)
    return rfind(s, Span(encoded))


def escape_bytes(s: Span[mut=False, UInt8, _]) -> List[UInt8]:
    """Escape bytes as bstr: retain valid non-ASCII, escape space and invalid bytes."""
    var output = List[UInt8]()
    var hex_digits: List[UInt8] = [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 65, 66, 67, 68, 69, 70]
    var i = 0
    while i < len(s):
        var _, size, valid = decode_utf8(s[i:])
        if valid and size > 1:
            output.extend(s[i : i + size])
            i += size
            continue
        var b = s[i]
        i += 1
        if b >= 0x21 and b <= 0x7E and b != 92:
            output.append(b)
            continue
        output.append(92)
        match Int(b):
            case 0:
                output.append(48)
            case 10:
                output.append(110)
            case 13:
                output.append(114)
            case 9:
                output.append(116)
            case 92:
                output.append(92)
            case _:
                output.append(120)
                output.append(hex_digits[Int(b >> 4)])
                output.append(hex_digits[Int(b & 15)])
    return output^


def unescape_bytes(s: Span[mut=False, UInt8, _]) -> List[UInt8]:
    """Decode backslash 0/n/r/t/backslash/xHH; retain unknown/incomplete escapes.

    A malformed hex escape retains every consumed byte, even a backslash.
    Unicode escapes are not interpreted and input need not be UTF-8.
    """
    var output = List[UInt8]()
    var i = 0
    while i < len(s):
        var start = i
        var b = s[i]
        i += 1
        if b != 92 or i == len(s):
            output.append(b)
            continue
        var escaped = s[i]
        i += 1
        match Int(escaped):
            case 48:
                output.append(0)
            case 110:
                output.append(10)
            case 114:
                output.append(13)
            case 116:
                output.append(9)
            case 92:
                output.append(92)
            case 120:
                var value = 0
                var digits = 0
                while digits < 2 and i < len(s):
                    var ch = Int(s[i])
                    i += 1
                    var digit = (
                        ch - 48 if 48
                        <= ch
                        <= 57 else ((ch | 32) - 97 + 10 if 97 <= (ch | 32) <= 102 else -1)
                    )
                    if digit < 0:
                        break
                    value = value * 16 + digit
                    digits += 1
                if digits == 2:
                    output.append(UInt8(value))
                else:
                    output.extend(s[start:i])
            case _:
                output.extend(s[start:i])
    return output^
