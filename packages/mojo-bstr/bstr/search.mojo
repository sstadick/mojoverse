"""Binary-safe searches returning byte offsets, or -1 for absence."""

from std.bit import count_leading_zeros, count_trailing_zeros
from std.memory import pack_bits
from std.sys import simd_width_of
from std.math import min, max
from std.collections import Array

comptime _WIDTH = min(32, simd_width_of[UInt8]())

# memchr's background byte-frequency ranks (MIT, Andrew Gallant), as used by goostr.
comptime _RANK = SIMD[DType.uint8, 256](
    55,
    52,
    51,
    50,
    49,
    48,
    47,
    46,
    45,
    103,
    242,
    66,
    67,
    229,
    44,
    43,
    42,
    41,
    40,
    39,
    38,
    37,
    36,
    35,
    34,
    33,
    56,
    32,
    31,
    30,
    29,
    28,
    255,
    148,
    164,
    149,
    136,
    160,
    155,
    173,
    221,
    222,
    134,
    122,
    232,
    202,
    215,
    224,
    208,
    220,
    204,
    187,
    183,
    179,
    177,
    168,
    178,
    200,
    226,
    195,
    154,
    184,
    174,
    126,
    120,
    191,
    157,
    194,
    170,
    189,
    162,
    161,
    150,
    193,
    142,
    137,
    171,
    176,
    185,
    167,
    186,
    112,
    175,
    192,
    188,
    156,
    140,
    143,
    123,
    133,
    128,
    147,
    138,
    146,
    114,
    223,
    151,
    249,
    216,
    238,
    236,
    253,
    227,
    218,
    230,
    247,
    135,
    180,
    241,
    233,
    246,
    244,
    231,
    139,
    245,
    243,
    251,
    235,
    201,
    196,
    240,
    214,
    152,
    182,
    205,
    181,
    127,
    27,
    212,
    211,
    210,
    213,
    228,
    197,
    169,
    159,
    131,
    172,
    105,
    80,
    98,
    96,
    97,
    81,
    207,
    145,
    116,
    115,
    144,
    130,
    153,
    121,
    107,
    132,
    109,
    110,
    124,
    111,
    82,
    108,
    118,
    141,
    113,
    129,
    119,
    125,
    165,
    117,
    92,
    106,
    83,
    72,
    99,
    93,
    65,
    79,
    166,
    237,
    163,
    199,
    190,
    225,
    209,
    203,
    198,
    217,
    219,
    206,
    234,
    248,
    158,
    239,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
)


def _pair(needle: Span[mut=False, UInt8, _]) -> Tuple[Int, Int]:
    if len(needle) < 2:
        return 0, 0
    var a = 0
    var b = len(needle) - 1
    if _RANK[Int(needle[b])] < _RANK[Int(needle[a])]:
        a, b = b, a
    for i in range(1, min(len(needle) - 1, 256)):
        if _RANK[Int(needle[i])] < _RANK[Int(needle[a])]:
            b, a = a, i
        elif needle[i] != needle[a] and (
            needle[b] == needle[a] or _RANK[Int(needle[i])] < _RANK[Int(needle[b])]
        ):
            b = i
    return a, b


@always_inline
def _equal(a: Span[mut=False, UInt8, _], b: Span[mut=False, UInt8, _]) -> Bool:
    if len(b) <= 32:
        comptime for shift in range(4):
            comptime width = 16 >> shift
            if len(b) >= width:
                var first = a.unsafe_ptr().unsafe_load[width=width, alignment=1]()
                var expected_first = b.unsafe_ptr().unsafe_load[width=width, alignment=1]()
                var last = a.unsafe_ptr().unsafe_load[width=width, alignment=1](len(b) - width)
                var expected_last = b.unsafe_ptr().unsafe_load[width=width, alignment=1](
                    len(b) - width
                )
                return first == expected_first and last == expected_last
        return len(b) == 0 or a[0] == b[0]
    var i = 0
    while len(b) - i >= _WIDTH:
        var x = a.unsafe_ptr().unsafe_load[width=_WIDTH, alignment=1](i)
        var y = b.unsafe_ptr().unsafe_load[width=_WIDTH, alignment=1](i)
        if x != y:
            return False
        i += _WIDTH
    while i < len(b):
        if a[i] != b[i]:
            return False
        i += 1
    return True


def find_byte(s: Span[mut=False, UInt8, _], byte: UInt8) -> Int:
    """Return the first matching byte offset, or -1."""
    return _small_set[False, 1](s, byte, byte, byte)


def rfind_byte(s: Span[mut=False, UInt8, _], byte: UInt8) -> Int:
    """Return the last matching byte offset, or -1."""
    return _small_set[True, 1](s, byte, byte, byte)


def memchr(byte: UInt8, s: Span[mut=False, UInt8, _]) -> Int:
    """Needle-first spelling of find_byte."""
    return find_byte(s, byte)


def memrchr(byte: UInt8, s: Span[mut=False, UInt8, _]) -> Int:
    """Needle-first spelling of rfind_byte."""
    return rfind_byte(s, byte)


def _small_set[
    reverse: Bool, count: Int, invert: Bool = False
](s: Span[mut=False, UInt8, _], a: UInt8, b: UInt8, c: UInt8) -> Int:
    var consumed = 0
    while len(s) - consumed >= _WIDTH:
        var base = len(s) - consumed - _WIDTH if reverse else consumed
        # The span need not be aligned. Every vector load stays within its bounds.
        var v = s.unsafe_ptr().unsafe_load[width=_WIDTH, alignment=1](base)
        var mask = v.eq(a)
        comptime if count >= 2:
            mask |= v.eq(b)
        comptime if count >= 3:
            mask |= v.eq(c)
        comptime if invert:
            mask = ~mask
        var bits = UInt64(pack_bits(mask))
        if bits != 0:
            comptime if reverse:
                return base + 63 - Int(count_leading_zeros(bits))
            else:
                return base + Int(count_trailing_zeros(bits))
        consumed += _WIDTH
    for step in range(consumed, len(s)):
        var i = len(s) - 1 - step if reverse else step
        if (s[i] == a or (count >= 2 and s[i] == b) or (count >= 3 and s[i] == c)) != invert:
            return i
    return -1


def memchr2(a: UInt8, b: UInt8, s: Span[mut=False, UInt8, _]) -> Int:
    """Return the first offset of either byte, or -1."""
    return _small_set[False, 2](s, a, b, b)


def memrchr2(a: UInt8, b: UInt8, s: Span[mut=False, UInt8, _]) -> Int:
    """Return the last offset of either byte, or -1."""
    return _small_set[True, 2](s, a, b, b)


def memchr3(a: UInt8, b: UInt8, c: UInt8, s: Span[mut=False, UInt8, _]) -> Int:
    """Return the first offset of any of three bytes, or -1."""
    return _small_set[False, 3](s, a, b, c)


def memrchr3(a: UInt8, b: UInt8, c: UInt8, s: Span[mut=False, UInt8, _]) -> Int:
    """Return the last offset of any of three bytes, or -1."""
    return _small_set[True, 3](s, a, b, c)


def _set_search[
    reverse: Bool, invert: Bool
](s: Span[mut=False, UInt8, _], byte_set: Span[mut=False, UInt8, _]) -> Int:
    if len(s) == 0:
        return -1
    if len(byte_set) == 0:
        return (len(s) - 1 if reverse else 0) if invert else -1
    if len(byte_set) == 1:
        return _small_set[reverse, 1, invert](s, byte_set[0], 0, 0)
    if len(byte_set) == 2:
        return _small_set[reverse, 2, invert](s, byte_set[0], byte_set[1], 0)
    if len(byte_set) == 3:
        return _small_set[reverse, 3, invert](s, byte_set[0], byte_set[1], byte_set[2])
    var members = Array[Bool, 256](fill=False)
    for byte in byte_set:
        members[Int(byte)] = True
    for step in range(len(s)):
        var i = len(s) - 1 - step if reverse else step
        if members[Int(s[i])] != invert:
            return i
    return -1


def find_byteset(s: Span[mut=False, UInt8, _], byte_set: Span[mut=False, UInt8, _]) -> Int:
    """First byte in the set; duplicates have no effect."""
    return _set_search[False, False](s, byte_set)


def rfind_byteset(s: Span[mut=False, UInt8, _], byte_set: Span[mut=False, UInt8, _]) -> Int:
    """Last byte in the set; an empty set never matches."""
    return _set_search[True, False](s, byte_set)


def find_not_byteset(s: Span[mut=False, UInt8, _], byte_set: Span[mut=False, UInt8, _]) -> Int:
    """First byte outside the set; an empty set matches every byte."""
    return _set_search[False, True](s, byte_set)


def rfind_not_byteset(s: Span[mut=False, UInt8, _], byte_set: Span[mut=False, UInt8, _]) -> Int:
    """Last byte outside the set."""
    return _set_search[True, True](s, byte_set)


def find(s: Span[mut=False, UInt8, _], needle: Span[mut=False, UInt8, _]) -> Int:
    """First substring offset; empty needle matches at zero."""
    if len(needle) > len(s):
        return -1
    if len(needle) <= 1 or len(s) < 64:
        return _packed_search[False, False](s, needle, 0, max(0, len(needle) - 1))
    if _equal(s, needle):
        return 0
    if len(needle) > 32:
        # Try one filtered candidate before paying for critical factorization.
        var a, b = _pair(needle)
        var at = _packed_search[False, True](s, needle, a, b)
        if at < 0 or _equal(s[at:], needle):
            return at
    return finder(needle).find(s)


@always_inline
def rfind(s: Span[mut=False, UInt8, _], needle: Span[mut=False, UInt8, _]) -> Int:
    """Last substring offset; empty needle matches at len(s)."""
    if len(needle) > len(s):
        return -1
    if len(needle) <= 1 or len(s) < 64:
        return _packed_search[True, False](s, needle, 0, max(0, len(needle) - 1))
    if _equal(s[len(s) - len(needle) :], needle):
        return len(s) - len(needle)
    if len(needle) > 32:
        var base = max(0, len(s) - len(needle) - _WIDTH + 1)
        var tail = _packed_search[True, True](s[base:], needle, 0, len(needle) - 1)
        if tail >= 0 and _equal(s[base + tail :], needle):
            return base + tail
        var a, b = _pair(needle)
        var at = _packed_search[True, True](s, needle, a, b)
        if at < 0 or _equal(s[at:], needle):
            return at
    return finder_reverse(needle).rfind(s)


struct Finder[origin: ImmOrigin](ImplicitlyCopyable):
    """Reusable forward searcher borrowing an immutable needle.

    Offsets count bytes, even in UTF-8 text. Keep the needle alive and unchanged.

    ```mojo {doctest="finder-offsets" global=true}
    from bstr import finder
    from std.testing import assert_equal

    def main() raises:
        var needle = String("needle")
        var search = finder(needle.as_bytes())
        assert_equal(search.find("é:needle".as_bytes()), 3)
        assert_equal(search.find("missing".as_bytes()), -1)
    ```
    """

    var _needle: Span[UInt8, Self.origin]
    var _two: _TwoWay
    var _a: Int
    var _b: Int

    def __init__(out self, needle: Span[UInt8, Self.origin]):
        self._needle = needle
        self._a, self._b = _pair(needle)
        self._two = _prepare[False](needle) if len(needle) > 32 else _TwoWay(0, 1, 0)

    def needle(self) -> Span[UInt8, Self.origin]:
        """The borrowed needle; construct a new finder to change it."""
        return self._needle

    def find(self, s: Span[mut=False, UInt8, _]) -> Int:
        """First matching byte offset, or -1. No allocations."""
        if len(self._needle) > len(s):
            return -1
        if len(self._needle) <= 32:
            return _packed_search[False, False](s, self._needle, self._a, self._b)
        return _two_way[False](s, self._needle, self._two, self._a, self._b)


struct FinderReverse[origin: ImmOrigin](ImplicitlyCopyable):
    """Reusable borrowed reverse-search needle."""

    var _needle: Span[UInt8, Self.origin]
    var _two: _TwoWay
    var _a: Int
    var _b: Int

    def __init__(out self, needle: Span[UInt8, Self.origin]):
        self._needle = needle
        self._a, self._b = _pair(needle)
        self._two = _prepare[True](needle) if len(needle) > 32 else _TwoWay(0, 1, 0)

    def needle(self) -> Span[UInt8, Self.origin]:
        """The borrowed needle; construct a new finder to change it."""
        return self._needle

    @always_inline
    def rfind(self, s: Span[mut=False, UInt8, _]) -> Int:
        """Last matching byte offset, or -1. No allocations."""
        if len(self._needle) > len(s):
            return -1
        if _equal(s[len(s) - len(self._needle) :], self._needle):
            return len(s) - len(self._needle)
        if len(self._needle) <= 32:
            return _packed_search[True, False](s, self._needle, self._a, self._b)
        return _two_way[True](s, self._needle, self._two, self._a, self._b)


def finder[origin: ImmOrigin](needle: Span[UInt8, origin]) -> Finder[origin]:
    """Borrow a reusable forward needle."""
    return Finder(needle)


def finder_reverse[origin: ImmOrigin](needle: Span[UInt8, origin]) -> FinderReverse[origin]:
    """Borrow a reusable reverse needle."""
    return FinderReverse(needle)


def _packed_search[
    reverse: Bool, prefilter: Bool
](s: Span[mut=False, UInt8, _], needle: Span[mut=False, UInt8, _], a: Int, b: Int) -> Int:
    if len(needle) == 0:
        return len(s) if reverse else 0
    if len(needle) == 1:
        return _small_set[reverse, 1](s, needle[0], 0, 0)
    var count = len(s) - len(needle) + 1
    var consumed = 0
    var c = 0
    if len(needle) > 2:
        while c == a or c == b:
            c += 1
    while count - consumed >= _WIDTH:
        var base = count - consumed - _WIDTH if reverse else consumed
        var first = s.unsafe_ptr().unsafe_load[width=_WIDTH, alignment=1](base + a)
        var last = s.unsafe_ptr().unsafe_load[width=_WIDTH, alignment=1](base + b)
        var bits = UInt64(pack_bits(first.eq(needle[a]) & last.eq(needle[b])))
        comptime if not prefilter:
            if len(needle) > 2 and bits and (bits & (bits - 1)):
                var third = s.unsafe_ptr().unsafe_load[width=_WIDTH, alignment=1](base + c)
                bits &= UInt64(pack_bits(third.eq(needle[c])))
        while bits != 0:
            var lane = 63 - Int(count_leading_zeros(bits)) if reverse else Int(
                count_trailing_zeros(bits)
            )
            var at = base + lane
            if prefilter or _equal(s[at : at + len(needle)], needle):
                return at
            bits &= ~(UInt64(1) << UInt64(lane))
        consumed += _WIDTH
    for step in range(consumed, count):
        var at = count - 1 - step if reverse else step
        if (
            s[at + a] == needle[a]
            and s[at + b] == needle[b]
            and (prefilter or _equal(s[at : at + len(needle)], needle))
        ):
            return at
    return -1


@fieldwise_init
struct _TwoWay(ImplicitlyCopyable):
    var critical: Int
    var period: Int
    var memory: Int


@inline(.always)
def _at[reverse: Bool](s: Span[mut=False, UInt8, _], i: Int) -> UInt8:
    return s[len(s) - 1 - i if reverse else i]


def _suffix[reverse: Bool, maximal: Bool](s: Span[mut=False, UInt8, _]) -> Tuple[Int, Int]:
    var best = 0
    var period = 1
    var candidate = 1
    var offset = 0
    while candidate + offset < len(s):
        var x = _at[reverse](s, best + offset)
        var y = _at[reverse](s, candidate + offset)
        if x == y:
            if offset + 1 == period:
                candidate += period
                offset = 0
            else:
                offset += 1
        elif (maximal and y > x) or (not maximal and y < x):
            best = candidate
            candidate += 1
            period = 1
            offset = 0
        else:
            candidate += offset + 1
            offset = 0
            period = candidate - best
    return (best, period)


def _prepare[reverse: Bool](s: Span[mut=False, UInt8, _]) -> _TwoWay:
    # Crochemore-Perrin critical factorization, following goostr/memchr.
    var a, ap = _suffix[reverse, False](s)
    var b, bp = _suffix[reverse, True](s)
    var critical = max(a, b)
    var period = ap if a > b else bp
    var periodic = critical * 2 < len(s)
    if periodic:
        for i in range(critical):
            if _at[reverse](s, i) != _at[reverse](s, period + i):
                periodic = False
                break
    if not periodic:
        period = max(critical, len(s) - critical)
    return _TwoWay(critical, period, len(s) - period if periodic else 0)


def _two_way[
    reverse: Bool
](
    s: Span[mut=False, UInt8, _], needle: Span[mut=False, UInt8, _], two: _TwoWay, a: Int, b: Int
) -> Int:
    var pos = 0
    var memory = 0
    var skips = 0
    var skipped = 0
    var prefilter = True
    while pos <= len(s) - len(needle):
        if prefilter:
            if skips >= 50 and skipped < skips * 8:
                prefilter = False
            else:
                var jump: Int
                comptime if reverse:
                    var found = _packed_search[True, True](s[: len(s) - pos], needle, a, b)
                    if found < 0:
                        return -1
                    jump = len(s) - pos - len(needle) - found
                else:
                    jump = _packed_search[False, True](s[pos:], needle, a, b)
                    if jump < 0:
                        return -1
                pos += jump
                skipped += jump
                skips += 1
                memory = 0
        var i = max(two.critical, memory)
        while len(needle) - i >= _WIDTH:
            var nbase = len(needle) - i - _WIDTH if reverse else i
            var sbase = len(s) - pos - i - _WIDTH if reverse else pos + i
            var x = needle.unsafe_ptr().unsafe_load[width=_WIDTH, alignment=1](nbase)
            var y = s.unsafe_ptr().unsafe_load[width=_WIDTH, alignment=1](sbase)
            var bits = UInt64(pack_bits(x.ne(y)))
            if bits:
                i += (
                    _WIDTH
                    - 1
                    - (63 - Int(count_leading_zeros(bits))) if reverse else Int(
                        count_trailing_zeros(bits)
                    )
                )
                break
            i += _WIDTH
        while i < len(needle) and _at[reverse](needle, i) == _at[reverse](s, pos + i):
            i += 1
        if i < len(needle):
            pos += i - two.critical + 1
            memory = 0
            continue
        var j = two.critical
        while j - memory >= _WIDTH:
            var nbase = len(needle) - j if reverse else j - _WIDTH
            var sbase = len(s) - pos - j if reverse else pos + j - _WIDTH
            var x = needle.unsafe_ptr().unsafe_load[width=_WIDTH, alignment=1](nbase)
            var y = s.unsafe_ptr().unsafe_load[width=_WIDTH, alignment=1](sbase)
            if x != y:
                break
            j -= _WIDTH
        while j > memory and _at[reverse](needle, j - 1) == _at[reverse](s, pos + j - 1):
            j -= 1
        if j <= memory:
            return len(s) - pos - len(needle) if reverse else pos
        pos += two.period
        memory = two.memory
    return -1
