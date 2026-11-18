"""Borrowed byte views, streaming searches, and owned byte transformations."""

from std.math import max
from .search import find, rfind, find_byte

comptime UNLIMITED = Int.MAX


def contains_str(s: Span[mut=False, UInt8, _], needle: Span[mut=False, UInt8, _]) -> Bool:
    """Whether needle occurs; an empty needle always matches."""
    return find(s, needle) >= 0


def starts_with_str(s: Span[mut=False, UInt8, _], prefix: Span[mut=False, UInt8, _]) -> Bool:
    """Whether s begins with prefix, including an empty prefix."""
    return len(prefix) <= len(s) and s[: len(prefix)] == prefix


def ends_with_str(s: Span[mut=False, UInt8, _], suffix: Span[mut=False, UInt8, _]) -> Bool:
    """Whether s ends with suffix, including an empty suffix."""
    return len(suffix) <= len(s) and s[len(s) - len(suffix) :] == suffix


@fieldwise_init
struct Matches[reverse: Bool, origin: ImmOrigin, needle_origin: ImmOrigin](
    ImplicitlyCopyable, Iterator
):
    """Streaming non-overlapping offsets; empty needles visit every byte boundary."""

    var s: Span[UInt8, Self.origin]
    var needle: Span[UInt8, Self.needle_origin]
    var cursor: Int
    comptime Element = Int

    def __iter__(self) -> Self:
        return self

    def __next__(mut self) raises StopIteration -> Int:
        comptime if Self.reverse:
            if self.cursor < 0:
                raise StopIteration()
            var at = rfind(self.s[: self.cursor], self.needle)
            if at < 0:
                raise StopIteration()
            self.cursor = at - Int(len(self.needle) == 0)
            return at
        else:
            if self.cursor > len(self.s):
                raise StopIteration()
            var pos = find(self.s[self.cursor :], self.needle)
            if pos < 0:
                raise StopIteration()
            var at = self.cursor + pos
            self.cursor = at + max(1, len(self.needle))
            return at


def find_iter[
    o: ImmOrigin, n: ImmOrigin
](s: Span[UInt8, o], needle: Span[UInt8, n]) -> Matches[False, o, n]:
    """Iterate non-overlapping matches from left to right without allocating."""
    return Matches[False, o, n](s, needle, 0)


def rfind_iter[
    o: ImmOrigin, n: ImmOrigin
](s: Span[UInt8, o], needle: Span[UInt8, n]) -> Matches[True, o, n]:
    """Iterate non-overlapping matches from right to left without allocating."""
    return Matches[True, o, n](s, needle, len(s))


@fieldwise_init
struct Splits[reverse: Bool, origin: ImmOrigin, needle_origin: ImmOrigin](
    ImplicitlyCopyable, Iterator
):
    """Streaming borrowed pieces, retaining empty pieces but omitting separators."""

    var matches: Matches[Self.reverse, Self.origin, Self.needle_origin]
    var boundary: Int
    var remaining: Int
    comptime Element = Span[UInt8, Self.origin]

    def __iter__(self) -> Self:
        return self

    def __next__(mut self) raises StopIteration -> Self.Element:
        if self.remaining == 0:
            raise StopIteration()
        self.remaining -= 1
        if self.remaining > 0:
            try:
                var at = self.matches.__next__()
                comptime if Self.reverse:
                    var piece = self.matches.s[at + len(self.matches.needle) : self.boundary]
                    self.boundary = at
                    return piece
                else:
                    var piece = self.matches.s[self.boundary : at]
                    self.boundary = at + len(self.matches.needle)
                    return piece
            except:
                pass
        self.remaining = 0
        comptime if Self.reverse:
            return self.matches.s[: self.boundary]
        else:
            return self.matches.s[self.boundary :]


def splitn_str[
    o: ImmOrigin, p: ImmOrigin
](s: Span[UInt8, o], needle: Span[UInt8, p], n: Int) raises -> Splits[False, o, p]:
    """At most n pieces; last contains remainder. Negative n raises Error."""
    if n < 0:
        raise Error("split limit must be nonnegative")
    return Splits[False, o, p](find_iter(s, needle), 0, n)


def rsplitn_str[
    o: ImmOrigin, p: ImmOrigin
](s: Span[UInt8, o], needle: Span[UInt8, p], n: Int) raises -> Splits[True, o, p]:
    """At most n pieces from the right; negative n raises Error."""
    if n < 0:
        raise Error("split limit must be nonnegative")
    return Splits[True, o, p](rfind_iter(s, needle), len(s), n)


def split_str[
    o: ImmOrigin, p: ImmOrigin
](s: Span[UInt8, o], needle: Span[UInt8, p]) -> Splits[False, o, p]:
    """All forward pieces; empty needle splits at both ends and between bytes."""
    return Splits[False, o, p](find_iter(s, needle), 0, UNLIMITED)


def rsplit_str[
    o: ImmOrigin, p: ImmOrigin
](s: Span[UInt8, o], needle: Span[UInt8, p]) -> Splits[True, o, p]:
    """All reverse pieces; reverse matches can differ from forward matches."""
    return Splits[True, o, p](rfind_iter(s, needle), len(s), UNLIMITED)


def split_once_str[
    o: ImmOrigin
](s: Span[UInt8, o], needle: Span[mut=False, UInt8, _]) -> Optional[
    Tuple[Span[UInt8, o], Span[UInt8, o]]
]:
    """First split as two borrowed views; None if absent."""
    var at = find(s, needle)
    if at < 0:
        return None
    return (s[:at], s[at + len(needle) :])


def rsplit_once_str[
    o: ImmOrigin
](s: Span[UInt8, o], needle: Span[mut=False, UInt8, _]) -> Optional[
    Tuple[Span[UInt8, o], Span[UInt8, o]]
]:
    """Last split as two borrowed views; None if absent."""
    var at = rfind(s, needle)
    if at < 0:
        return None
    return (s[:at], s[at + len(needle) :])


def replacen_into(
    s: Span[mut=False, UInt8, _],
    needle: Span[mut=False, UInt8, _],
    replacement: Span[mut=False, UInt8, _],
    n: Int,
    mut output: List[UInt8],
) raises:
    """Append at most n replacements; never clear output. Negative n raises Error."""
    if n < 0:
        raise Error("replacement limit must be nonnegative")
    var start = 0
    var count = 0
    for at in find_iter(s, needle):
        if count == n:
            break
        output.extend(s[start:at])
        output.extend(replacement)
        start = at + len(needle)
        count += 1
    output.extend(s[start:])


def replace_into(
    s: Span[mut=False, UInt8, _],
    needle: Span[mut=False, UInt8, _],
    replacement: Span[mut=False, UInt8, _],
    mut output: List[UInt8],
) raises:
    """Append all non-overlapping replacements, including empty-needle boundaries."""
    replacen_into(s, needle, replacement, UNLIMITED, output)


def replacen(
    s: Span[mut=False, UInt8, _],
    needle: Span[mut=False, UInt8, _],
    replacement: Span[mut=False, UInt8, _],
    n: Int,
) raises -> List[UInt8]:
    """Own a copy with at most n replacements. Zero copies s unchanged."""
    var output = List[UInt8]()
    replacen_into(s, needle, replacement, n, output)
    return output^


def replace(
    s: Span[mut=False, UInt8, _],
    needle: Span[mut=False, UInt8, _],
    replacement: Span[mut=False, UInt8, _],
) raises -> List[UInt8]:
    """Own a copy with all non-overlapping matches replaced."""
    return replacen(s, needle, replacement, UNLIMITED)


def repeatn(s: Span[mut=False, UInt8, _], n: Int) raises -> List[UInt8]:
    """Own n concatenated copies. Negative n raises Error; empty input is empty."""
    if n < 0:
        raise Error("repeat count must be nonnegative")
    var output = List[UInt8]()
    if len(s) != 0:
        for _ in range(n):
            output.extend(s)
    return output^


@fieldwise_init
struct Lines[keep_terminator: Bool, origin: ImmOrigin](ImplicitlyCopyable, Iterator):
    """Borrowed LF-delimited lines; CR is stripped only immediately before LF."""

    var s: Span[UInt8, Self.origin]
    var start: Int
    comptime Element = Span[UInt8, Self.origin]

    def __iter__(self) -> Self:
        return self

    def __next__(mut self) raises StopIteration -> Self.Element:
        if self.start == len(self.s):
            raise StopIteration()
        var start = self.start
        var pos = find_byte(self.s[start:], 10)
        var end = len(self.s) if pos < 0 else start + pos + 1
        self.start = end
        comptime if not Self.keep_terminator:
            if pos >= 0:
                end -= 1
                if end > start and self.s[end - 1] == 13:
                    end -= 1
        return self.s[start:end]


def lines[o: ImmOrigin](s: Span[UInt8, o]) -> Lines[False, o]:
    """Lines without LF/CRLF. No extra empty line after a final LF."""
    return Lines[False, o](s, 0)


def lines_with_terminator[o: ImmOrigin](s: Span[UInt8, o]) -> Lines[True, o]:
    """Lines retaining LF/CRLF and any final unterminated line."""
    return Lines[True, o](s, 0)


def find_non_ascii_byte(s: Span[mut=False, UInt8, _]) -> Int:
    """First byte at least 128, or -1."""
    for i in range(len(s)):
        if s[i] >= 128:
            return i
    return -1


def is_ascii(s: Span[mut=False, UInt8, _]) -> Bool:
    """Whether every byte is below 128. Empty input is ASCII."""
    return find_non_ascii_byte(s) < 0


def make_ascii_lowercase(s: Span[mut=True, UInt8, _]):
    """Mutate ASCII A..Z only, preserving arbitrary non-ASCII bytes."""
    for i in range(len(s)):
        if s[i] >= 65 and s[i] <= 90:
            s[i] += 32


def make_ascii_uppercase(s: Span[mut=True, UInt8, _]):
    """Mutate ASCII a..z only."""
    for i in range(len(s)):
        if s[i] >= 97 and s[i] <= 122:
            s[i] -= 32


def to_ascii_lowercase(s: Span[mut=False, UInt8, _]) -> List[UInt8]:
    """Owned ASCII-lowercased bytes; not Unicode case conversion."""
    var output = List[UInt8]()
    output.extend(s)
    make_ascii_lowercase(Span(output))
    return output^


def to_ascii_uppercase(s: Span[mut=False, UInt8, _]) -> List[UInt8]:
    """Owned ASCII-uppercased bytes; not Unicode case conversion."""
    var output = List[UInt8]()
    output.extend(s)
    make_ascii_uppercase(Span(output))
    return output^


def reverse_bytes(s: Span[mut=True, UInt8, _]):
    """Reverse in place without interpreting UTF-8."""
    for i in range(len(s) // 2):
        var byte = s[i]
        s[i] = s[len(s) - 1 - i]
        s[len(s) - 1 - i] = byte
