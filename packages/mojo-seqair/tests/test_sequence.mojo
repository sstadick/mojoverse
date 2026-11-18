from std.testing import assert_equal, TestSuite
from mojo_seqair.bam import decode_sequence
from mojo_seqair.buffer import Buffer


def test_sequence_alphabet_and_vector_tails() raises:
    # Grow repeatedly before decoding, also checking byte-buffer preservation.
    var source = Buffer(1)
    var result = Buffer(131)
    comptime alphabet = "=ACMGRSVTWYHKDBN"
    for i in range(65):
        source.push(UInt8((i * 37 + 9) % 256))
    for n in range(130):
        for i in range(131):
            result.data[unsafe_offset=i] = 255
        decode_sequence(source.data, result.data.unsafe_offset(1), n)
        assert_equal(result.data[unsafe_offset=0], UInt8(255))
        assert_equal(result.data[unsafe_offset=n + 1], UInt8(255))
        for i in range(n):
            var byte = (i // 2 * 37 + 9) % 256
            var index = byte // 16 if i % 2 == 0 else byte % 16
            assert_equal(result.data[unsafe_offset=i + 1], alphabet.as_bytes()[index])
    _ = source^
    _ = result^


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
