# Mojo libdeflate

Thin, inlined Mojo 1.2.0 bindings to libdeflate **1.26**. The codec is unchanged
C, not a Mojo reimplementation. There are no extra copies, intermediary buffers,
callbacks or dynamic symbol lookups. This is an experimental source package,
not a package-index release.

The current API covers the operations used by Mojo Seqair and Perbase:
raw DEFLATE compression, gzip member decompression with consumed/written byte
counts, incremental CRC32, and compressor/decompressor allocation and release.
It is not a binding to every libdeflate API and does not implement BGZF framing.

## Build and test

```sh
git clone https://github.com/sstadick/mojo-libdeflate
cd mojo-libdeflate
pixi install --locked
pixi run t
```

Import from `mojo_libdeflate`. Link consumers with
`-Xlinker -L$CONDA_PREFIX/lib -Xlinker -ldeflate` using `mojo build`.
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
