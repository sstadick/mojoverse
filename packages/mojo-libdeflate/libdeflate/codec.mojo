"""Inlining, allocation-free calls to libdeflate 1.26's C ABI.

These are deliberately low-level bindings: handle 0 means allocation failure;
free each successful allocation exactly once, after its last use. A codec
handle must not be used concurrently. Input/output buffers must not overlap,
and callers must provide valid byte extents and nonnegative lengths. No Mojo
allocation or copying is introduced. See libdeflate.h for the full contract.
"""

from std.ffi import external_call


@always_inline
def alloc_compressor(level: Int) -> Int:
    """Allocate a compressor at level 0..12; return 0 on failure."""
    return external_call["libdeflate_alloc_compressor", Int](Int32(level))


@always_inline
def free_compressor(handle: Int):
    external_call["libdeflate_free_compressor", NoneType](handle)


@always_inline
def alloc_decompressor() -> Int:
    return external_call["libdeflate_alloc_decompressor", Int]()


@always_inline
def free_decompressor(handle: Int):
    external_call["libdeflate_free_decompressor", NoneType](handle)


@always_inline
def deflate_compress(
    handle: Int, source: Pointer[UInt8, _], size: Int, dest: Pointer[UInt8, _], capacity: Int
) -> Int:
    """Write raw DEFLATE; return bytes written, or 0 if capacity is insufficient."""
    return external_call["libdeflate_deflate_compress", Int](handle, source, size, dest, capacity)


@always_inline
def gzip_decompress(
    handle: Int,
    source: Pointer[UInt8, _],
    size: Int,
    dest: Pointer[UInt8, _],
    capacity: Int,
    mut consumed: Int,
    mut written: Int,
) -> Int32:
    """Decode one gzip member, checking CRC/size. Return libdeflate_result.

    0 means success, 1 bad data, 2 short output, 3 insufficient space. Only
    read consumed/written on success; trailing input is reported, not rejected.
    """
    return external_call["libdeflate_gzip_decompress_ex", Int32](
        handle, source, size, dest, capacity, Pointer(to=consumed), Pointer(to=written)
    )


@always_inline
def crc32(initial: UInt32, source: Pointer[UInt8, _], size: Int) -> UInt32:
    """Extend an IEEE CRC32 (initial checksum 0)."""
    return external_call["libdeflate_crc32", UInt32](initial, source, size)


@always_inline
def crc32(source: Span[mut=False, UInt8, _], initial: UInt32 = 0) -> UInt32:
    """Checksum bytes, or extend an earlier checksum with another span.

    Start at zero; pass the preceding result when processing another chunk.
    This computes an IEEE CRC32, not a cryptographic hash.

    ```mojo {doctest="crc32-incremental" global=true}
    from libdeflate import crc32
    from std.testing import assert_equal

    def main() raises:
        var checksum = crc32("1234".as_bytes())
        checksum = crc32("56789".as_bytes(), checksum)
        assert_equal(checksum, UInt32(0xCBF43926))
        assert_equal(crc32("123456789".as_bytes()), checksum)
    ```
    """
    return crc32(initial, source.unsafe_ptr(), len(source))
