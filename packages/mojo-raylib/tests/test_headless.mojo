"""Exercise installed scalar and struct-by-value C calls without a display."""

from mojo_raylib import (
    Vector2, Rectangle, Color, vector2_add, vector2_length, matrix_identity,
    check_collision_recs, get_collision_rec, color_to_int,
)
from std.testing import assert_equal, assert_false, assert_true


def main() raises:
    var v = vector2_add(Vector2(3, -7), Vector2(-5, 11))
    assert_equal(v.x, Float32(-2))
    assert_equal(v.y, Float32(4))
    assert_equal(vector2_length(Vector2(3, 4)), Float32(5))
    var identity = matrix_identity()
    assert_equal(identity.m0, Float32(1))
    assert_equal(identity.m5, Float32(1))
    assert_equal(identity.m1, Float32(0))
    var a = Rectangle(2, 3, 8, 9)
    var b = Rectangle(7, 8, 10, 11)
    assert_true(check_collision_recs(a, b))
    assert_false(check_collision_recs(a, Rectangle(20, 30, 1, 2)))
    var overlap = get_collision_rec(a, b)
    assert_equal(overlap.x, Float32(7))
    assert_equal(overlap.y, Float32(8))
    assert_equal(overlap.width, Float32(3))
    assert_equal(overlap.height, Float32(4))
    assert_equal(color_to_int(Color(0x12, 0x34, 0x56, 0x78)), 0x12345678)
    print("PASS: headless raylib scalar, aggregate, and native-shim calls")
