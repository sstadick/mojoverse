# Mojo libdeflate

Thin, inlined Mojo 1.2.0 bindings to libdeflate **1.26**. The codec is unchanged
C, not a Mojo reimplementation. There are no extra copies, intermediary buffers,
callbacks or dynamic symbol lookups. This is an experimental source package,
not a package-index release.

Start with `Compressor`, `Decompressor` and byte spans. Handles are freed
automatically, buffers are caller-owned, and codec instances can be reused.
The API covers raw DEFLATE/gzip compression, gzip member decompression and
incremental CRC32. It does not implement BGZF framing or every libdeflate API.

## Compress and decompress

```mojo {doctest="gzip" global=true}
from mojo_libdeflate import Compressor, Decompressor, crc32
from std.testing import assert_equal

def main() raises:
    var text = String("hello, compressed world")
    var compressor = Compressor(level=2)
    var packed = List[UInt8](length=compressor.gzip_bound(text.byte_length()), fill=0)
    var size = compressor.compress_gzip(text.as_bytes(), Span(packed))

    var decoder = Decompressor()
    var output = List[UInt8](length=text.byte_length(), fill=0)
    var result = decoder.decompress_gzip(Span(packed)[:size], Span(output))
    assert_equal(result.consumed, size)
    assert_equal(String(from_utf8=Span(output)[:result.written]), text)
    assert_equal(crc32("123456789".as_bytes()), UInt32(0xCBF43926))
```

Reuse the codecs and buffers across calls; there are no intermediate copies.
Compression levels range from 0 to 12. Methods raise on bad input, invalid
levels, overlapping buffers or insufficient output space. Only the returned
output prefix is initialized. A decoder processes **one member**: use
`result.consumed` to locate trailing input, rather than silently ignoring it.
The caller must know or bound the uncompressed size. Do not concurrently use
the same codec; give each worker its own instance.

`compress_deflate` emits raw DEFLATE rather than a complete gzip member.
For direct FFI and status-code handling, the original pointer functions remain
available in `mojo_libdeflate.codec` and at the package root.

## Build and test

```sh
git clone https://github.com/sstadick/mojoverse.git
cd mojoverse/packages/mojo-libdeflate
pixi install --locked
pixi run t
pixi run docs
```

Import from `mojo_libdeflate`. Link consumers with
`-Xlinker -L$CONDA_PREFIX/lib -Xlinker -ldeflate` using `mojo build`.
For Git consumers use [Mojoverse dependency setup](https://github.com/sstadick/mojoverse#use-a-dependency)
with `subdirectory = "packages/mojo-libdeflate"`.
The `mojo-libdeflate-native` dependency installs the static archive, C header,
and upstream license. No reader/application dependency is needed.

Linux x86-64/AArch64 and Apple Silicon macOS 15+ are source targets. macOS
requires Xcode command-line tools. Native code uses Clang 18.1.8 on Linux and
Apple Clang on macOS with actual `-O3 -march=native`. These host-tuned builds
are not portable binary releases; libdeflate retains its own CPU dispatch.

Native and isolated installed-consumer tests pass on Linux x86-64 and Apple
Silicon macOS. Linux AArch64 is declared but has not been native-tested.
Build backends and the Mojo compiler are pinned; the same lockfile installs
with `--locked` on both tested platforms.

## Unsafe FFI contract

Handles are opaque `Int` addresses. Allocation returns 0 on failure. Free a
successful allocation exactly once after its last use; do not concurrently use
one codec handle. Input/output buffers must be valid for the supplied byte
lengths, must not overlap, and must remain allocated during the call. Lengths
must be nonnegative. These functions do not own the caller's buffers.

`deflate_compress` returns bytes written, or 0 when the destination is too small.
`gzip_decompress` returns the native status: 0 success, 1 bad data, 2 short
output, 3 insufficient space. Read consumed/written only on success. It decodes
one gzip member and checks its CRC and size; callers decide whether to reject
trailing input. `crc32` starts with checksum 0 and can extend an earlier result.

Tests use an independent gzip fixture containing NUL/non-UTF-8 bytes, a known
CRC32 vector, incremental checksums, a compression roundtrip, insufficient
space, trailing bytes and CRC corruption.

## Provenance

`native/vendor/libdeflate` is the unmodified 1.26 source snapshot at upstream
commit `8fcf5832a3fa680f4c6a5332e2436f8a6dd5c299`, moved from Mojo Seqair's native
dependency. Its MIT license is in `native/vendor/libdeflate/COPYING`.
