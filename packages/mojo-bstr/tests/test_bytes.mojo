from std.testing import assert_equal, assert_true, assert_false, assert_raises, TestSuite
from bstr import *


def test_boundaries_and_ownership() raises:
    var s = String("ababa")
    var n = String("aba")
    assert_true(contains_str(s.as_bytes(), n.as_bytes()))
    assert_true(starts_with_str(s.as_bytes(), n.as_bytes()))
    assert_true(ends_with_str(s.as_bytes(), n.as_bytes()))
    assert_false(starts_with_str(n.as_bytes(), s.as_bytes()))
    assert_equal(finder_reverse(n.as_bytes()).rfind(s.as_bytes()), 2)
    var forward = List[Int]()
    for at in find_iter(s.as_bytes(), n.as_bytes()):
        forward.append(at)
    assert_equal(forward, [0])
    var backward = List[Int]()
    for at in rfind_iter(s.as_bytes(), n.as_bytes()):
        backward.append(at)
    assert_equal(backward, [2])
    var text = String("é")
    var offsets = List[Int]()
    for at in rfind_iter(text.as_bytes(), text.as_bytes()[:0]):
        offsets.append(at)
    assert_equal(offsets, [2, 1, 0])
    if case .Some((left, right)) = split_once_str(s.as_bytes(), n.as_bytes()):
        assert_equal(len(left), 0)
        assert_true(right == s.as_bytes()[3:])
    else:
        raise Error("missing first split")
    if case .Some((left, right)) = rsplit_once_str(s.as_bytes(), n.as_bytes()):
        assert_true(left == s.as_bytes()[:2])
        assert_equal(len(right), 0)
    else:
        raise Error("missing last split")
    assert_false(Bool(split_once_str(n.as_bytes(), s.as_bytes())))
    var output: List[UInt8] = [33]
    replace_into(text.as_bytes(), text.as_bytes()[:0], n.as_bytes()[:1], output)
    var expected: List[UInt8] = [33, 97, 195, 97, 169, 97]
    assert_equal(output, expected)
    var repeated = repeatn(text.as_bytes(), 2)
    var expected_repeat: List[UInt8] = [195, 169, 195, 169]
    assert_equal(repeated, expected_repeat)
    with assert_raises():
        _ = repeatn(text.as_bytes(), -1)
    with assert_raises():
        _ = splitn_str(text.as_bytes(), n.as_bytes(), -1)
    with assert_raises():
        _ = rsplitn_str(text.as_bytes(), n.as_bytes(), -1)
    with assert_raises():
        _ = replacen(text.as_bytes(), n.as_bytes(), n.as_bytes(), -1)


def test_mutation_guard_bands() raises:
    var data = List[UInt8]()
    data.append(65)
    for i in range(256):
        data.append(UInt8(i))
    data.append(90)
    make_ascii_lowercase(Span(data)[1:257])
    assert_equal(data[0], UInt8(65))
    assert_equal(data[257], UInt8(90))
    for i in range(256):
        assert_equal(data[i + 1], UInt8(i + 32 if 65 <= i <= 90 else i))
    make_ascii_uppercase(Span(data)[1:257])
    for i in range(256):
        assert_equal(data[i + 1], UInt8(i - 32 if 97 <= i <= 122 else i))
    reverse_bytes(Span(data)[1:257])
    assert_equal(data[1], UInt8(255))
    assert_equal(data[256], UInt8(0))
    assert_equal(data[0], UInt8(65))
    assert_equal(data[257], UInt8(90))


def test_utf8_predicates_and_errors() raises:
    var data: List[UInt8] = [0xE2, 0x98, 120, 0xFF]

    def malformed(cp: Int) -> Bool:
        return cp == 0xFFFD

    assert_true(trim_with(Span(data), malformed) == Span(data)[2:3])
    var pieces = List[Int]()
    for part in fields_with(Span(data), malformed):
        pieces.append(len(part))
        assert_true(part == Span(data)[2:3])
    assert_equal(pieces, [1])
    var points = List[Int]()
    for cp in chars(Span(data)):
        points.append(cp)
    assert_equal(points, [65533, 120, 65533])
    assert_equal(decode_utf8_lossy(Span(data)), (65533, 2))
    assert_equal(decode_last_utf8_lossy(Span(data)), (65533, 1))
    assert_false(is_utf8(Span(data)))
    assert_false(is_ascii(Span(data)))
    assert_equal(find_non_ascii_byte(Span(data)), 0)
    assert_true(is_whitespace(0xA0))
    assert_false(is_whitespace(0x200B))
    var output: List[UInt8] = [33]
    to_str_lossy_into(Span(data), output)
    var expected: List[UInt8] = [33, 239, 191, 189, 120, 239, 191, 189]
    assert_equal(output, expected)
    for invalid_cp in [-1, 0xD800, 0xDFFF, 0x110000]:
        with assert_raises():
            _ = find_char(Span(data), invalid_cp)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
