from std.testing import assert_equal

from extramojo.utils import (
    include_bytes_requires_cache_clear_on_edit,
    include_string_requires_cache_clear_on_edit,
)


def main() raises:
    comptime text = include_string_requires_cache_clear_on_edit[
        "tests/fixtures/embedded.txt"
    ]()
    comptime assert text == "Mojo 🔥\n"
    comptime data = include_bytes_requires_cache_clear_on_edit[
        "tests/fixtures/embedded.bin"
    ]()
    comptime assert len(data) == 4
    comptime assert (
        data[0] == 0 and data[1] == 255 and data[2] == 128 and data[3] == 10
    )
    comptime empty = "tests/fixtures/empty.bin"
    comptime assert (
        len(include_bytes_requires_cache_clear_on_edit[empty]()) == 0
    )
    comptime assert include_string_requires_cache_clear_on_edit[empty]() == ""

    assert_equal(String(text), "Mojo 🔥\n")
    assert_equal(data[1], UInt8(255))
