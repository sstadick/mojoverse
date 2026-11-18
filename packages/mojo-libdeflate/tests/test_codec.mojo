from std.testing import assert_equal, assert_true, assert_raises, TestSuite
from libdeflate import (
    Compressor,
    Decompressor,
    alloc_compressor,
    free_compressor,
    alloc_decompressor,
    free_decompressor,
    deflate_compress,
    gzip_decompress,
    crc32,
)


def test_gzip_and_checksums() raises:
    # Python gzip fixture for binary input, independent of these bindings.
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
        51,
        52,
        50,
        54,
        49,
        53,
        51,
        183,
        176,
        100,
        248,
        15,
        0,
        170,
        61,
        0,
        240,
        11,
        0,
        0,
        0,
        42,
    ]
    var plain: List[UInt8] = [49, 50, 51, 52, 53, 54, 55, 56, 57, 0, 255]
    var output = List[UInt8](length=32, fill=0)
    var owned = Decompressor()
    var decoded = owned.decompress_gzip(Span(packed), Span(output))
    assert_equal(decoded.consumed, 31)
    assert_equal(decoded.written, 11)
    assert_equal(List(Span(output)[:11]), plain)
    with assert_raises():
        _ = owned.decompress_gzip(Span(packed), Span(output)[:10])
    var decoder = alloc_decompressor()
    assert_true(decoder != 0)
    var consumed = 0
    var written = 0
    var status = gzip_decompress(
        decoder,
        packed.unsafe_ptr(),
        len(packed),
        output.unsafe_ptr(),
        len(output),
        consumed,
        written,
    )
    var correct = status == 0 and consumed == 31 and written == 11
    for i in range(len(plain)):
        correct &= output[i] == plain[i]
    var small = gzip_decompress(
        decoder, packed.unsafe_ptr(), 31, output.unsafe_ptr(), 10, consumed, written
    )
    packed[23] ^= 1  # Corrupt CRC, not the DEFLATE payload.
    with assert_raises():
        _ = owned.decompress_gzip(Span(packed), Span(output))
    var corrupt = gzip_decompress(
        decoder, packed.unsafe_ptr(), 31, output.unsafe_ptr(), len(output), consumed, written
    )
    free_decompressor(decoder)
    assert_true(correct)
    assert_equal(small, 3)
    assert_equal(corrupt, 1)
    assert_equal(crc32(0, plain.unsafe_ptr(), 9), UInt32(0xCBF43926))
    var prefix = crc32(0, plain.unsafe_ptr(), 4)
    assert_equal(crc32(prefix, plain.unsafe_ptr().unsafe_offset(4), 5), UInt32(0xCBF43926))
    assert_equal(crc32(Span(plain)[4:9], crc32(Span(plain)[:4])), UInt32(0xCBF43926))


def test_owned_codec_reuse() raises:
    var compressor = Compressor(level=2)
    var decoder = Decompressor()
    var source: List[UInt8] = [97, 0, 255, 13, 10]
    var packed = List[UInt8](length=compressor.gzip_bound(len(source)), fill=0)
    var output = List[UInt8](length=len(source), fill=0)
    for size in range(len(source) + 1):
        var written = compressor.compress_gzip(Span(source)[:size], Span(packed))
        var result = decoder.decompress_gzip(Span(packed)[:written], Span(output))
        assert_equal(result.consumed, written)
        assert_equal(result.written, size)
        assert_equal(List(Span(output)[:size]), List(Span(source)[:size]))
    with assert_raises():
        _ = compressor.compress_gzip(Span(source), Span(packed)[:1])
    with assert_raises():
        _ = compressor.compress_deflate(Span(source), Span(packed)[:1])
    # An FFI caller can supply untracked overlapping views; reject them too.
    var alias = Span(
        unsafe_ptr=packed.unsafe_ptr()
        .unsafe_mut_cast[False]()
        .unsafe_origin_cast[ImmUntrackedOrigin](),
        length=3,
    )
    with assert_raises():
        _ = compressor.compress_gzip(alias, Span(packed))
    with assert_raises():
        _ = Compressor(13)
    with assert_raises():
        _ = compressor.gzip_bound(-1)


def test_compression() raises:
    var source: List[UInt8] = [49, 50, 51, 52, 53, 54, 55, 56, 57]
    var gzip = List[UInt8](length=128, fill=0)
    gzip[0] = 31
    gzip[1] = 139
    gzip[2] = 8
    var compressor = alloc_compressor(2)
    assert_true(compressor != 0)
    var failed = deflate_compress(
        compressor, source.unsafe_ptr(), len(source), gzip.unsafe_ptr().unsafe_offset(10), 1
    )
    free_compressor(compressor)
    var owned = Compressor(level=2)
    var n = owned.compress_deflate(Span(source), Span(gzip)[10:110])
    assert_equal(failed, 0)
    assert_true(n > 0)
    # Known checksum, rather than computing expected data with the binding.
    for i in range(4):
        gzip[10 + n + i] = UInt8((UInt32(0xCBF43926) >> UInt32(8 * i)) & 255)
    gzip[14 + n] = 9
    var decoder = alloc_decompressor()
    assert_true(decoder != 0)
    var dest = List[UInt8](length=9, fill=0)
    var used = 0
    var written = 0
    var result = gzip_decompress(
        decoder, gzip.unsafe_ptr(), n + 18, dest.unsafe_ptr(), 9, used, written
    )
    free_decompressor(decoder)
    assert_equal(result, 0)
    assert_equal(used, n + 18)
    assert_equal(written, 9)
    assert_equal(dest, source)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
