# SPDX-License-Identifier: Apache-2.0 AND MIT
# Adapted from BioRadOpenSource/ish's ishlib/vendor/kseq.mojo and zlib.mojo
# at 304233bc80b14c18f6f1497d17116d2328d2474f. See LICENSE and NOTICE.md.
# Modified for Mojo 1.2: List-owned buffers, mojo-bstr search, direct zlib FFI,
# short-read handling, CRLF/EOF handling, and checked FASTQ completeness.
"""Streaming FASTA/FASTQ parsing with reusable byte buffers, derived from ish/kseq."""

from std.ffi import external_call
from bstr import memchr, memchr2


trait KRead(Deinitable, Movable):
    """A byte source: return bytes written, zero only at EOF, and raise on I/O errors.

    A positive short read is not EOF. Never write beyond the supplied span or
    retain it after returning. The caller supplies a nonempty buffer.
    """

    def unbuffered_read(mut self, buffer: Span[mut=True, UInt8, _]) raises -> Int:
        ...


struct GZFile(KRead):
    """Own a read-only plain/gzip file, auto-detected by zlib. Link with `-lz`.

    Concatenated gzip members are supported. Opening or reading a damaged gzip
    stream raises. This is sequential input, not indexed BGZF seeking.
    """

    var _handle: Int

    def __init__(out self, path: String) raises:
        var name = path.copy()
        var mode = String("rb")
        self._handle = external_call["gzopen", Int](
            name.as_c_string_span(), mode.as_c_string_span()
        )
        if not self._handle:
            raise Error("cannot open FASTX input: " + path)

    def __deinit__(deinit self):
        if self._handle:
            _ = external_call["gzclose", Int32](self._handle)

    def unbuffered_read(mut self, buffer: Span[mut=True, UInt8, _]) raises -> Int:
        """Fill up to the supplied buffer size, returning zero only at EOF."""
        var count = external_call["gzread", Int32](
            self._handle, buffer.unsafe_ptr(), UInt32(min(len(buffer), 2147483647))
        )
        var code = Int32(0)
        _ = external_call["gzerror", Int](self._handle, Pointer(to=code))
        if count < 0 or (code != 0 and code != 1):
            raise Error("error reading FASTX input (zlib code " + String(code) + ")")
        return Int(count)


struct BufferedReader[R: KRead](Movable):
    """Buffer a byte source for FASTX parsing; short reads do not terminate input."""

    var _buffer: List[UInt8]
    var _start: Int
    var _end: Int
    var _eof: Bool
    var _reader: Self.R

    def __init__(out self, var reader: Self.R, buffer_capacity: Int = 131072) raises:
        if buffer_capacity <= 0:
            raise Error("buffer capacity must be positive")
        self._buffer = List[UInt8](length=buffer_capacity, fill=0)
        self._start = 0
        self._end = 0
        self._eof = False
        self._reader = reader^

    def _fill(mut self) raises -> Bool:
        if self._start < self._end:
            return True
        if self._eof:
            return False
        self._start = 0
        self._end = self._reader.unbuffered_read(Span(self._buffer))
        if self._end < 0 or self._end > len(self._buffer):
            raise Error("invalid byte count from FASTX source")
        self._eof = self._end == 0
        return not self._eof

    def read_byte(mut self) raises -> Int:
        """Return the next byte, or -1 at EOF."""
        if not self._fill():
            return -1
        var value = self._buffer[self._start]
        self._start += 1
        return Int(value)

    def read_line(mut self, mut buffer: List[UInt8], append: Bool = False) raises -> Bool:
        """Read a line without LF/CRLF; return False only if no bytes remain.

        Append preserves existing bytes. An unterminated final line is valid.
        The destination must not alias the input source's storage.
        """
        if not append:
            buffer.clear()
        var offset = len(buffer)
        var got_any = False
        while self._fill():
            got_any = True
            var remaining = Span(self._buffer)[self._start : self._end]
            var stop = memchr(UInt8(10), remaining)
            if stop >= 0:
                buffer.extend(remaining[:stop])
                self._start += stop + 1
                break
            buffer.extend(remaining)
            self._start = self._end
        if len(buffer) > offset and buffer[len(buffer) - 1] == 13:
            buffer.resize(len(buffer) - 1, 0)
        return got_any


@fieldwise_init
struct FastxRecord(Copyable, Movable):
    """An owned FASTX snapshot. Qualities are ASCII, not decoded Phred scores.

    `qual` is None for FASTA and present for FASTQ, including empty records.
    `comment` is None when absent or when comment splitting is disabled.
    """

    var name: List[UInt8]
    var seq: List[UInt8]
    var qual: Optional[List[UInt8]]
    var comment: Optional[List[UInt8]]


struct FastxReader[R: KRead, read_comment: Bool = True](Movable):
    """Read FASTA/FASTQ into reusable name, seq, qual, and comment byte lists.

    `read()` returns the sequence length (including zero), -1 at EOF, or -2
    for malformed/truncated FASTQ. I/O errors raise. Stop after a parse error;
    partial fields are not a record. Copy fields or call `to_var()` to retain
    a record before the next read. No field is assumed to be UTF-8.

    With read_comment=True, split the header at its first space/tab. With
    False, retain the whole header in name, as in ish. Multiline sequences
    and qualities, blank sequence lines, and LF/CRLF input are supported.
    Sequence bytes are not alphabet-validated or case-normalized.
    """

    var name: List[UInt8]
    var seq: List[UInt8]
    var qual: List[UInt8]
    var comment: List[UInt8]
    var _reader: BufferedReader[Self.R]
    var _last_char: Int
    var _fastq: Bool

    def __init__(out self, var reader: BufferedReader[Self.R]):
        self._reader = reader^
        self.name = List[UInt8]()
        self.seq = List[UInt8](capacity=256)
        self.qual = List[UInt8]()
        self.comment = List[UInt8]()
        self._last_char = 0
        self._fastq = False

    def to_var(self) -> FastxRecord:
        """Copy the current successful record into independently owned storage."""
        var qual: Optional[List[UInt8]] = None
        var comment: Optional[List[UInt8]] = None
        if self._fastq:
            qual = self.qual.copy()
        if self.comment:
            comment = self.comment.copy()
        return FastxRecord(self.name.copy(), self.seq.copy(), qual^, comment^)

    def read(mut self) raises -> Int:
        """Return sequence length, -1 at EOF, or -2 for malformed FASTQ; I/O raises."""
        self.name.clear()
        self.seq.clear()
        self.qual.clear()
        self.comment.clear()
        var marker = self._last_char
        self._last_char = 0
        if marker == 0:
            marker = self._reader.read_byte()
            # Like kseq, skip input preceding the first record marker.
            while marker >= 0 and marker != 62 and marker != 64:
                marker = self._reader.read_byte()
            if marker < 0:
                return -1
        self._fastq = marker == 64
        _ = self._reader.read_line(self.name)
        comptime if Self.read_comment:
            var split = memchr2(UInt8(32), UInt8(9), Span(self.name))
            if split >= 0:
                self.comment.extend(Span(self.name)[split + 1 :])
                self.name.resize(split, 0)

        var c = self._reader.read_byte()
        while c >= 0 and c != 62 and c != 64 and c != 43:
            if c == 10:
                c = self._reader.read_byte()
                continue
            var offset = len(self.seq)
            self.seq.append(UInt8(c))
            _ = self._reader.read_line(self.seq, append=True)
            # A CRLF-only line has its CR before read_line's append offset.
            if len(self.seq) == offset + 1 and self.seq[offset] == 13:
                self.seq.resize(offset, 0)
            c = self._reader.read_byte()
        if c == 62 or c == 64:
            self._last_char = c
        if c != 43:
            return -2 if self._fastq else len(self.seq)
        if not self._fastq:
            return -2

        # Skip the optional repeated header on the '+' line.
        c = self._reader.read_byte()
        while c >= 0 and c != 10:
            c = self._reader.read_byte()
        if c < 0:
            return -2
        self.qual.reserve(len(self.seq))
        if not self._reader.read_line(self.qual):
            return -2
        while len(self.qual) < len(self.seq):
            if not self._reader.read_line(self.qual, append=True):
                return -2
        if len(self.qual) != len(self.seq):
            return -2
        return len(self.seq)
