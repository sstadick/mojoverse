from std.testing import assert_equal, assert_true, assert_false, TestSuite
from bstr import *


def test_byte_equality() raises:
    for length in [0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129]:
        for padding in [0, 1, 7, 31]:
            var left = List[UInt8](length=length + padding, fill=55)
            var right = List[UInt8](length=length + padding + 1, fill=198)
            for i in range(length):
                left[padding + i] = UInt8(i * 73)
                right[padding + 1 + i] = UInt8(i * 73)
            assert_true(equal(Span(left)[padding:], Span(right)[padding + 1 :]))
            if length:
                # A matching prefix must not compare equal to a longer span.
                assert_false(equal(Span(left)[padding : len(left) - 1], Span(right)[padding + 1 :]))
                assert_false(equal(Span(right)[padding + 1 :], Span(left)[padding : len(left) - 1]))
            for mismatch in range(length):
                right[padding + 1 + mismatch] ^= 128
                assert_false(equal(Span(left)[padding:], Span(right)[padding + 1 :]))
                right[padding + 1 + mismatch] ^= 128


def test_binary_search() raises:
    var data: List[UInt8] = [0, 255, 13, 10, 255, 0]
    var needle: List[UInt8] = [255, 0]
    var s = Span(data)
    var n = Span(needle)
    assert_equal(memchr(255, s), 1)
    assert_equal(memrchr(255, s), 4)
    assert_equal(memchr2(10, 13, s), 2)
    assert_equal(memrchr3(10, 13, 255, s), 4)
    assert_equal(find(s, n), 4)
    assert_equal(finder(n).find(s), 4)
    assert_true(finder(n).needle() == n)
    assert_true(finder_reverse(n).needle() == n)
    assert_equal(rfind(s, n[:0]), 6)


def test_vector_boundaries() raises:
    for length in [0, 1, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129]:
        for padding in range(33):
            for hit in range(-1, length):
                var data = List[UInt8](length=length + padding + 1, fill=255)
                for i in range(length):
                    data[padding + i] = 65
                if hit >= 0:
                    data[padding + hit] = 255
                var s = Span(data)[padding : padding + length]
                assert_equal(memchr(255, s), hit)
                assert_equal(memrchr(255, s), hit)
                assert_equal(memchr2(0, 255, s), hit)
                assert_equal(memrchr2(0, 255, s), hit)
                assert_equal(memchr3(0, 13, 255, s), hit)
                assert_equal(memrchr3(0, 13, 255, s), hit)
                var member: List[UInt8] = [65]
                assert_equal(find_not_byteset(s, Span(member)), hit)
                assert_equal(rfind_not_byteset(s, Span(member)), hit)


def scalar_find[reverse: Bool](s: Span[mut=False, UInt8, _], n: Span[mut=False, UInt8, _]) -> Int:
    var count = len(s) - len(n) + 1
    for step in range(count):
        var at = count - 1 - step if reverse else step
        var equal = True
        for j in range(len(n)):
            if s[at + j] != n[j]:
                equal = False
                break
        if equal:
            return at
    return -1


def test_short_and_periodic_long_search() raises:
    var state = UInt64(0xB57)
    for trial in range(3000):
        var data = List[UInt8]()
        var needle = List[UInt8]()
        var length = trial % 257
        var nlength = trial % 139
        var alphabet = 2 if trial % 3 == 0 else (7 if trial % 3 == 1 else 256)
        for i in range(length + nlength):
            state = state * 6364136223846793005 + 1442695040888963407
            var byte = UInt8(Int(state >> 33) % alphabet)
            if i < length:
                data.append(byte)
            else:
                needle.append(byte)
        if trial % 2 == 0 and nlength <= length:
            for i in range(nlength):
                needle[i] = data[(length - nlength) // 2 + i]
        if trial % 5 == 0:
            for i in range(length):
                data[i] = UInt8(i % 7)
            for i in range(nlength):
                needle[i] = UInt8(i % 7)
            if nlength > 0 and trial % 10 == 0:
                needle[nlength // 2] = 255
        var s = Span(data)
        var n = Span(needle)
        var first = scalar_find[False](s, n)
        var last = scalar_find[True](s, n)
        assert_equal(find(s, n), first)
        assert_equal(rfind(s, n), last)
        assert_equal(finder(n).find(s), first)
        assert_equal(finder_reverse(n).rfind(s), last)

    # Dense candidates exercise filter retirement and both sides of the
    # preprocessing cutoff. Compare complete search results, not filter state.
    for size in [31, 32, 33, 255, 256, 257, 2048]:
        for mismatch in [0, size // 2, size - 1]:
            var data = List[UInt8](length=size * 2 + 139, fill=97)
            var needle = List[UInt8](length=size, fill=97)
            needle[mismatch] = 255
            for insert in [False, True]:
                if insert:
                    for i in range(size):
                        data[65 + i] = needle[i]
                        data[size + 73 + i] = needle[i]
                var s = Span(data)
                var n = Span(needle)
                var first = scalar_find[False](s, n)
                var last = scalar_find[True](s, n)
                assert_equal(find(s, n), first)
                assert_equal(rfind(s, n), last)
                assert_equal(finder(n).find(s), first)
                assert_equal(finder_reverse(n).rfind(s), last)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
