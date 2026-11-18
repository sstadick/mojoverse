from std.testing import assert_equal, assert_true, assert_false, assert_raises, TestSuite
from std.tempfile import TemporaryDirectory
from std.pathlib import Path
from bio import Bam, Buffer, decode_sequence


def test_named_query_and_record_views() raises:
    # Independent Python/zlib fixture: chr length 20, reads [1,5) ACGT and
    # [3,7) TTAA, QNAME "pair", four Phred-30 qualities each; one BAI chunk.
    var packed: List[UInt8] = [
        31,
        139,
        8,
        4,
        0,
        0,
        0,
        0,
        0,
        255,
        6,
        0,
        66,
        67,
        2,
        0,
        92,
        0,
        115,
        114,
        244,
        101,
        100,
        0,
        2,
        16,
        193,
        2,
        196,
        201,
        25,
        69,
        12,
        34,
        64,
        90,
        159,
        1,
        2,
        64,
        226,
        172,
        54,
        158,
        66,
        140,
        12,
        142,
        96,
        121,
        16,
        96,
        6,
        98,
        54,
        32,
        46,
        72,
        204,
        44,
        98,
        112,
        0,
        50,
        132,
        60,
        228,
        128,
        64,
        31,
        73,
        26,
        162,
        165,
        17,
        174,
        133,
        17,
        93,
        75,
        135,
        32,
        72,
        11,
        0,
        198,
        24,
        156,
        6,
        126,
        0,
        0,
        0,
        31,
        139,
        8,
        4,
        0,
        0,
        0,
        0,
        0,
        255,
        6,
        0,
        66,
        67,
        2,
        0,
        27,
        0,
        3,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
    ]
    var index: List[UInt8] = [
        66,
        65,
        73,
        1,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        73,
        18,
        0,
        0,
        1,
        0,
        0,
        0,
        24,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        93,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        24,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
    ]
    var directory = TemporaryDirectory()
    var path = String(Path(directory.name) / "tiny.bam")
    with open(path, "w") as file:
        file.write_all(Span(packed))
    with open(path + ".bai", "w") as file:
        file.write_all(Span(index))
    var bam = Bam(path)
    var reader = bam.query("chr", 5, 6)
    assert_true(reader.next())
    var record = reader.record.value()
    assert_equal(record.pos, 3)  # First read touches, but does not overlap [5,6).
    var saved_name = List(record.name_bytes())
    assert_equal(saved_name, List("pair".as_bytes()))
    assert_equal(List(record.qualities()), [30, 30, 30, 30])
    var bases = List[UInt8](length=6, fill=255)
    assert_equal(record.decode_bases(Span(bases)[1:5]), 4)
    assert_equal(bases, [255, 84, 84, 65, 65, 255])
    with assert_raises():
        _ = record.decode_bases(Span(bases)[:3])
    assert_false(reader.next())
    assert_false(Bool(reader.record))
    reader.fetch(bam, bam.region("chr", 0, 2))
    assert_true(reader.next())
    assert_equal(reader.record.value().pos, 1)
    assert_equal(saved_name, List("pair".as_bytes()))
    with assert_raises():
        _ = bam.query("missing", 1, 2)
    with assert_raises():
        _ = bam.region("chr", 2, 2)
    with assert_raises():
        _ = bam.region("chr", 0, 21)


def test_buffer_views_and_reuse() raises:
    var buffer = Buffer(1)
    buffer.append("abc".as_bytes())
    assert_equal(len(buffer), 3)
    assert_equal(List(buffer.as_bytes()), List("abc".as_bytes()))
    buffer.clear()
    buffer.append("xyz123".as_bytes())
    assert_equal(List(buffer.as_bytes()), List("xyz123".as_bytes()))


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
