from std.memory import unsafe_memcpy
from std.pathlib import Path
from std.tempfile import TemporaryDirectory
from std.testing import assert_equal, assert_false, assert_true, assert_raises, TestSuite
from bio import BufferedReader, FastxReader, FastxRecord, GZFile, KRead


struct Chunked(KRead):
    var data: List[UInt8]
    var chunk: Int
    var position: Int

    def __init__(out self, var data: List[UInt8], chunk: Int):
        self.data = data^
        self.chunk = chunk
        self.position = 0

    def unbuffered_read(mut self, buffer: Span[mut=True, UInt8, _]) raises -> Int:
        var count = min(self.chunk, min(len(buffer), len(self.data) - self.position))
        if count:
            unsafe_memcpy(
                dest=buffer.unsafe_ptr(),
                src=self.data.unsafe_ptr().unsafe_offset(self.position),
                count=count,
            )
        self.position += count
        return count


def test_multiline_fasta_short_reads_crlf_and_owned_records() raises:
    for chunk in [1, 2, 7, 128]:
        var data = List("\n>chr1 first comment\r\nAcG\r\n\r\n\nTN\n>empty\n>last".as_bytes())
        var reader = FastxReader(BufferedReader(Chunked(data^, chunk), 9))
        assert_equal(reader.read(), 5)
        assert_equal(reader.name, List("chr1".as_bytes()))
        assert_equal(reader.comment, List("first comment".as_bytes()))
        assert_equal(reader.seq, List("AcGTN".as_bytes()))
        var saved = reader.to_var()
        var moved = reader^
        assert_equal(moved.read(), 0)
        assert_equal(moved.name, List("empty".as_bytes()))
        assert_equal(len(moved.comment), 0)
        assert_equal(moved.read(), 0)
        assert_equal(moved.name, List("last".as_bytes()))
        assert_equal(moved.read(), -1)
        assert_equal(moved.read(), -1)
        _ = moved^
        assert_equal(saved.seq, List("AcGTN".as_bytes()))
        assert_equal(saved.comment.value(), List("first comment".as_bytes()))
        assert_false(Bool(saved.qual))


def test_fastq_multiline_qualities_empty_records_and_final_line() raises:
    for chunk in [1, 3, 16, 128]:
        var data = List(
            "@q\tcomment\r\nAC\nG\r\n+q\r\n@\r\n+>\n@empty\n\n+\n\n@tail\nT\n+\n!".as_bytes()
        )
        var reader = FastxReader(BufferedReader(Chunked(data^, chunk), 11))
        assert_equal(reader.read(), 3)
        assert_equal(reader.name, List("q".as_bytes()))
        assert_equal(reader.comment, List("comment".as_bytes()))
        assert_equal(reader.seq, List("ACG".as_bytes()))
        assert_equal(reader.qual, List("@+>".as_bytes()))
        var saved = reader.to_var()
        assert_equal(reader.read(), 0)
        var empty = reader.to_var()
        assert_true(Bool(empty.qual))
        assert_equal(len(empty.qual.value()), 0)
        assert_equal(reader.read(), 1)
        assert_equal(reader.name, List("tail".as_bytes()))
        assert_equal(reader.qual, List("!".as_bytes()))
        assert_equal(reader.read(), -1)
        assert_equal(reader.read(), -1)
        assert_equal(saved.qual.value(), List("@+>".as_bytes()))


def test_unsplit_binary_header_and_large_record() raises:
    var data: List[UInt8] = [62, 255, 32, 99, 9, 100, 13, 10]
    var sequence = List[UInt8]()
    for i in range(131073):
        sequence.append("ACnTG".as_bytes()[i % 5])
    data.extend(Span(sequence))
    data.extend("\n>next\nG".as_bytes())
    var reader = FastxReader[read_comment=False](BufferedReader(Chunked(data^, 65537)))
    assert_equal(reader.read(), len(sequence))
    assert_equal(reader.name, [255, 32, 99, 9, 100])
    assert_equal(reader.seq, sequence)
    assert_equal(len(reader.comment), 0)
    var saved = reader.to_var()
    assert_false(Bool(saved.comment))
    assert_equal(reader.read(), 1)
    assert_equal(reader.seq, List("G".as_bytes()))
    assert_equal(reader.read(), -1)
    assert_equal(saved.seq, sequence)


def test_malformed_fastq_and_empty_input() raises:
    for text in [
        "@x\nAC\n+\n!",
        "@x\nAC\n+\n!!!\n",
        "@x\nAC\n+",
        "@x\nAC\n",
        "@x\nAC\n@y\nT\n+\n!\n",
        "@x\n\n+\n",
    ]:
        var reader = FastxReader(BufferedReader(Chunked(List(text.as_bytes()), 2), 5))
        assert_equal(reader.read(), -2)
    var empty = FastxReader(BufferedReader(Chunked(List[UInt8](), 1)))
    assert_equal(empty.read(), -1)
    assert_equal(empty.read(), -1)
    with assert_raises():
        _ = BufferedReader(Chunked(List[UInt8](), 1), 0)


@fieldwise_init
struct BrokenSource(KRead):
    def unbuffered_read(mut self, buffer: Span[mut=True, UInt8, _]) raises -> Int:
        raise Error("source failure")


def test_io_errors_propagate() raises:
    var reader = FastxReader(BufferedReader(BrokenSource()))
    with assert_raises():
        _ = reader.read()
    var directory = TemporaryDirectory()
    with assert_raises():
        _ = GZFile(String(Path(directory.name) / "missing"))


def test_plain_gzip_members_and_corruption() raises:
    var plain = "@read note\nAC\n+\n!#\n"
    # Python gzip.compress(plain.encode(), mtime=0), independent of the reader.
    var packed: List[UInt8] = [
        31,
        139,
        8,
        0,
        0,
        0,
        0,
        0,
        2,
        3,
        115,
        40,
        74,
        77,
        76,
        81,
        200,
        203,
        47,
        73,
        229,
        114,
        116,
        230,
        210,
        230,
        82,
        84,
        230,
        2,
        0,
        36,
        166,
        32,
        131,
        19,
        0,
        0,
        0,
    ]
    var directory = TemporaryDirectory()
    var path = String(Path(directory.name) / "input")  # No extension-based detection.
    for compressed in [False, True]:
        with open(path, "w") as file:
            if compressed:
                file.write_all(Span(packed))
                file.write_all(Span(packed))
            else:
                file.write_all(plain.as_bytes())
                file.write_all(plain.as_bytes())
        var source = GZFile(path)
        var reader = FastxReader(BufferedReader(source^, 3))
        for _ in range(2):
            assert_equal(reader.read(), 2)
            assert_equal(reader.name, List("read".as_bytes()))
            assert_equal(reader.comment, List("note".as_bytes()))
            assert_equal(reader.seq, List("AC".as_bytes()))
            assert_equal(reader.qual, List("!#".as_bytes()))
        assert_equal(reader.read(), -1)
    for truncate in [False, True]:
        var damaged = packed.copy()
        if truncate:
            damaged.resize(len(damaged) - 5, 0)
        else:
            damaged[len(damaged) - 8] ^= 1  # CRC mismatch, not a malformed FASTQ.
        with open(path, "w") as file:
            file.write_all(Span(damaged))
        var reader = FastxReader(BufferedReader(GZFile(path)))
        with assert_raises():
            while reader.read() >= 0:
                pass


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
