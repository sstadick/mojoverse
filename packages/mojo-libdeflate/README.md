# Mojo libdeflate

Mojo 1.3.0.dev2026112605 bindings to libdeflate **1.26**, linked statically to the native
codec. Compression and decompression write directly into caller-owned buffers.

[API reference](https://sstadick.github.io/mojoverse/mojo-libdeflate/libdeflate/_index.html)

Start with `Compressor`, `Decompressor` and byte spans. Handles are freed
automatically, buffers are caller-owned, and codec instances can be reused.
The API covers raw DEFLATE/gzip compression, gzip member decompression and
incremental CRC32. It does not implement BGZF framing or every libdeflate API.

## Install

Choose a commit from `main` for nightly Mojo or `stable/1.2` for Mojo 1.2.0.
Match the compiler pin and channel to that revision: `max-nightly` for
nightly, `max` for stable. Use one revision for all Mojoverse dependencies.

Follow the [Mojoverse dependency setup](https://github.com/sstadick/mojoverse#use-a-dependency)
and add this Git dependency to your `pixi.toml`. Replace `<full-commit>` with a
Mojoverse commit and use the same revision for every Mojoverse dependency:

```toml
[dependencies]
mojo-libdeflate = { git = "https://github.com/sstadick/mojoverse.git", rev = "<full-commit>", subdirectory = "packages/mojo-libdeflate" }
```

Run `pixi install` and import from `libdeflate`. Link consumers with
`-Xlinker -L$CONDA_PREFIX/lib -Xlinker -ldeflate` using `mojo build`.
The `mojo-libdeflate-native` dependency installs the static archive, C header,
and upstream license from the same Git revision. No source `-I` path is needed.

## Compress and decompress

```mojo {doctest="gzip" global=true}
from libdeflate import Compressor, Decompressor, crc32
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
For direct FFI and status-code handling, use the pointer functions in
`libdeflate.codec`, also exported at the package root.

## Decode concatenated gzip members

Advance by `consumed`, not by the output size. The output buffer is reused;
consume its initialized prefix before decoding the next member. This example
creates two members so it can run without an external fixture.

```mojo {doctest="gzip-members" global=true}
from libdeflate import Compressor, Decompressor
from std.testing import assert_equal

def main() raises:
    var compressor = Compressor(level=2)
    var packed = List[UInt8](length=compressor.gzip_bound(32), fill=0)
    var stream = List[UInt8]()
    for text in [String("alpha"), String("beta!")]:
        var size = compressor.compress_gzip(text.as_bytes(), Span(packed))
        stream.extend(Span(packed)[:size])

    var decoder = Decompressor()
    var output = List[UInt8](length=32, fill=0)
    var decoded = String()
    var offset = 0
    while offset < len(stream):
        var member = decoder.decompress_gzip(Span(stream)[offset:], Span(output))
        decoded += String(from_utf8=Span(output)[:member.written])
        offset += member.consumed
    assert_equal(decoded, "alphabeta!")
    assert_equal(offset, len(stream))
```

## Update a checksum incrementally

Start at zero and feed the previous result into the next call. The input does
not have to be text.

```mojo {doctest="crc-parts" global=true}
from libdeflate import crc32
from std.testing import assert_equal

def main() raises:
    var checksum = crc32("1234".as_bytes())
    checksum = crc32("56789".as_bytes(), checksum)
    assert_equal(checksum, UInt32(0xCBF43926))
```

## Build and test

```sh
git clone https://github.com/sstadick/mojoverse.git
cd mojoverse/packages/mojo-libdeflate
pixi install --locked
pixi run t
pixi run docs
```

Linux x86-64/AArch64 and Apple Silicon macOS 15+ are source targets. macOS
requires Xcode command-line tools. Native code uses Clang 18.1.8 on Linux and
Apple Clang on macOS with actual `-O3 -march=native`. These host-tuned builds
are not portable binary releases; libdeflate retains its own CPU dispatch.

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

## Provenance

`native/vendor/libdeflate` is the unmodified 1.26 source snapshot at upstream
commit `8fcf5832a3fa680f4c6a5332e2436f8a6dd5c299`.
Its MIT license is in `native/vendor/libdeflate/COPYING`.
