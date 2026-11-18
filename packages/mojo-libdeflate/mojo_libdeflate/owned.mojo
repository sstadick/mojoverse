"""Reusable codecs with automatic ownership and caller-provided byte buffers."""

from std.ffi import external_call
from .codec import (
    alloc_compressor,
    free_compressor,
    alloc_decompressor,
    free_decompressor,
    deflate_compress,
    gzip_decompress,
)


@always_inline
def _check_buffers(source: Span[mut=False, UInt8, _], dest: Span[mut=True, UInt8, _]) raises:
    if len(source) and len(dest):
        var start = Int(source.unsafe_ptr())
        var target = Int(dest.unsafe_ptr())
        if start < target + len(dest) and target < start + len(source):
            raise Error("codec input and output must not overlap")


@fieldwise_init
struct Decompressed(ImplicitlyCopyable):
    """Byte counts for one decoded member; input may contain trailing bytes."""

    var consumed: Int
    """Compressed input bytes used; advance the input by this many bytes."""
    var written: Int
    """Decoded output bytes; only this prefix of the destination is valid."""


struct Compressor(Movable):
    """Own and reuse a libdeflate compressor. Do not use it concurrently.

    Methods write directly into the destination and return the byte count.
    No intermediate allocation or copy is made. Too-small output raises;
    its contents are unspecified after failure. The raw codec module retains
    status-returning pointer calls for pipelines that handle overflow themselves.

    Allocate the destination with `length`, not just `capacity`, so its span
    covers writable bytes. Reuse both codec instances and storage across calls:

    ```mojo {doctest="compressor-reuse" global=true}
    from mojo_libdeflate import Compressor, Decompressor
    from std.testing import assert_equal

    def main() raises:
        var compressor = Compressor(level=2)
        var decoder = Decompressor()
        var packed = List[UInt8](length=compressor.gzip_bound(64), fill=0)
        var output = List[UInt8](length=64, fill=0)
        for text in [String("alpha"), String("a longer second record")]:
            var size = compressor.compress_gzip(text.as_bytes(), Span(packed))
            var result = decoder.decompress_gzip(Span(packed)[:size], Span(output))
            assert_equal(String(from_utf8=Span(output)[:result.written]), text)
    ```
    """

    var _handle: Int

    def __init__(out self, level: Int = 6) raises:
        """Create a compressor at level 0 (uncompressed) through 12."""
        self._handle = 0
        if level < 0 or level > 12:
            raise Error("compression level must be between 0 and 12")
        self._handle = alloc_compressor(level)
        if not self._handle:
            raise Error("cannot allocate compressor")

    def __deinit__(deinit self):
        free_compressor(self._handle)

    @always_inline
    def gzip_bound(self, size: Int) raises -> Int:
        """Return a sufficient gzip destination size for this input length."""
        if size < 0:
            raise Error("input size must be nonnegative")
        return external_call["libdeflate_gzip_compress_bound", Int](self._handle, size)

    @always_inline
    def compress_deflate(
        mut self, source: Span[mut=False, UInt8, _], dest: Span[mut=True, UInt8, _]
    ) raises -> Int:
        """Write raw DEFLATE, without a gzip/zlib header or checksum."""
        _check_buffers(source, dest)
        var written = deflate_compress(
            self._handle, source.unsafe_ptr(), len(source), dest.unsafe_ptr(), len(dest)
        )
        if not written:
            raise Error("compressed output buffer too small")
        return written

    @always_inline
    def compress_gzip(
        mut self, source: Span[mut=False, UInt8, _], dest: Span[mut=True, UInt8, _]
    ) raises -> Int:
        """Write one complete gzip member, including its CRC32 and size."""
        _check_buffers(source, dest)
        var written = external_call["libdeflate_gzip_compress", Int](
            self._handle, source.unsafe_ptr(), len(source), dest.unsafe_ptr(), len(dest)
        )
        if not written:
            raise Error("compressed output buffer too small")
        return written


struct Decompressor(Movable):
    """Own and reuse a libdeflate decoder. Do not use it concurrently.

    Supply an output buffer large enough for the decoded data. The returned
    `consumed` counts compressed input, while `written` counts decoded output.
    Trailing bytes are left for the caller, not silently decoded or rejected:

    ```mojo {doctest="decoder-lengths" global=true}
    from mojo_libdeflate import Compressor, Decompressor
    from std.testing import assert_equal, assert_raises

    def main() raises:
        var compressor = Compressor()
        var packed = List[UInt8](length=compressor.gzip_bound(5), fill=0)
        var size = compressor.compress_gzip("hello".as_bytes(), Span(packed))
        var input = List(Span(packed)[:size])
        input.extend("trailer".as_bytes())

        var decoder = Decompressor()
        var output = List[UInt8](length=32, fill=0)
        var result = decoder.decompress_gzip(Span(input), Span(output))
        assert_equal(result.consumed, size)
        assert_equal(result.written, 5)
        assert_equal(String(from_utf8=Span(output)[:result.written]), "hello")
        assert_equal(String(from_utf8=Span(input)[result.consumed:]), "trailer")

        # Too-small output and truncated input both raise Error.
        with assert_raises():
            _ = decoder.decompress_gzip(Span(input), Span(output)[:2])
        with assert_raises():
            _ = decoder.decompress_gzip(Span(input)[:5], Span(output))
    ```
    """

    var _handle: Int

    def __init__(out self) raises:
        """Allocate a decoder; destruction frees it automatically."""
        self._handle = alloc_decompressor()
        if not self._handle:
            raise Error("cannot allocate decompressor")

    def __deinit__(deinit self):
        free_decompressor(self._handle)

    @always_inline
    def decompress_gzip(
        mut self, source: Span[mut=False, UInt8, _], dest: Span[mut=True, UInt8, _]
    ) raises -> Decompressed:
        """Decode one member, checking CRC/size; return consumed/written lengths.

        Trailing bytes (including further members) are not decoded. Only the
        returned written prefix is valid. Malformed/truncated input and small
        output raise Error; the destination is unspecified on failure.
        """
        _check_buffers(source, dest)
        var consumed = 0
        var written = 0
        var status = gzip_decompress(
            self._handle,
            source.unsafe_ptr(),
            len(source),
            dest.unsafe_ptr(),
            len(dest),
            consumed,
            written,
        )
        if status == 3:
            raise Error("decompressed output buffer too small")
        if status:
            raise Error("invalid gzip data or checksum")
        return Decompressed(consumed, written)
