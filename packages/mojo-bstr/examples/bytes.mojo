from std.testing import assert_equal, assert_true
from bstr import memchr, lines, trim, to_str_lossy, replace


def main() raises:
    var raw: List[UInt8] = [32, 97, 0, 255, 13, 10, 98]
    assert_equal(memchr(0, Span(raw)), 2)
    var sizes = List[Int]()
    for line in lines(Span(raw)):
        sizes.append(len(trim(line)))
    assert_equal(sizes, [3, 1])
    var valid = to_str_lossy(Span(raw))
    var expected = String(" a\0�\r\nb")
    assert_true(Span(valid) == expected.as_bytes())
    var needle: List[UInt8] = [255]
    var replacement: List[UInt8] = [33]
    var owned = replace(Span(raw), Span(needle), Span(replacement))
    assert_equal(owned[3], UInt8(33))
    assert_equal(raw[3], UInt8(255))
