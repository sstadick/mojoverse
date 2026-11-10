"""Shared observable workloads for the bstr and rebar benchmark protocols."""
from std.math import max
from mojo_bstr import *


def count_matches[
    reverse: Bool, prepared: Bool
](
    s: Span[mut=False, UInt8, _],
    n: Span[mut=False, UInt8, _],
    forward: Finder[_],
    backward: FinderReverse[_],
) -> Int:
    var count = 0
    var cursor = len(s) if reverse else 0
    while cursor >= 0 if reverse else cursor <= len(s):
        var at: Int
        comptime if reverse:
            comptime if prepared:
                at = backward.rfind(s[:cursor])
            else:
                at = rfind(s[:cursor], n)
        else:
            comptime if prepared:
                at = forward.find(s[cursor:])
            else:
                at = find(s[cursor:], n)
        if at < 0:
            break
        count += 1
        comptime if reverse:
            cursor = at - Int(len(n) == 0)
        else:
            cursor += at + max(1, len(n))
    return count


def operation[
    mode: Int
](
    s: Span[mut=False, UInt8, _],
    n: Span[mut=False, UInt8, _],
    forward: Finder[_],
    backward: FinderReverse[_],
) -> Int:
    comptime if mode == 0:
        return find(s, n)
    elif mode == 1:
        return rfind(s, n)
    elif mode == 2:
        return forward.find(s)
    elif mode == 3:
        return backward.rfind(s)
    elif mode == 4:
        return find_byteset(s, n)
    elif mode == 5:
        return rfind_byteset(s, n)
    elif mode == 6:
        return find_not_byteset(s, n)
    elif mode == 7:
        return rfind_not_byteset(s, n)
    elif mode == 8:
        return count_matches[False, False](s, n, forward, backward)
    elif mode == 9:
        return count_matches[True, False](s, n, forward, backward)
    else:
        comptime assert mode == 10, "unknown mode"
        var checksum = 0
        var start = 0
        while start < len(s):
            var at = find_byte(s[start:], 10)
            var end = len(s) if at < 0 else start + at
            checksum += find_byte(s[start:end], 124) + 1
            start = end + 1
        return checksum
