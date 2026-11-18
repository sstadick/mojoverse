# Mojo Seqair

Native Mojo **BAM** reader. This is not an official Seqair release or a
complete port of its public API. BAM/BGZF parsing,
BAI/CSI lookup, auxiliary validation and CG long-CIGAR resolution are Mojo;
libdeflate 1.26 handles DEFLATE/CRC32 through direct static FFI calls.

[API reference](https://sstadick.github.io/mojoverse/mojo-seqair/mojo_seqair/_index.html)

## Query reads

Give an indexed, coordinate-sorted BAM and a **zero-based, half-open** region:

```mojo
from mojo_seqair import Bam

def main() raises:
    var bam = Bam("reads.bam")
    var reader = bam.query("chr20", 10000000, 10001000)
    while reader.next():
        var record = reader.record.value()
        print(record.pos, record.mapq, List(record.name_bytes()))
```

`query` returns overlapping reads, including reads beginning before the region.
Unknown names, empty intervals and coordinates outside the reference raise.
For many regions, keep a `Reader(bam.path)` and call
`reader.fetch(bam, bam.region("chr20", begin, end))` to reuse its buffers/codec.
`Bam` owns the dictionary/index; keep it immutable when sharing across threads.
Each thread needs its own reader.

**Consume records before the next reader operation.** Names and `qualities()`
are borrowed byte spans; use `List(view)` to retain them. Names are not assumed
UTF-8. Qualities are numeric Phred scores (255 means missing). `record.nseq`
is the sequence length: `record.decode_bases(Span(destination))` writes ASCII
bases into an existing buffer of at least that size and returns bytes written.
The raw `Record` does not statically track its reader's lifetime.

## Reuse a byte buffer

```mojo {doctest="buffer" global=true}
from mojo_seqair import Buffer
from std.testing import assert_equal

def main() raises:
    var buffer = Buffer(1024)
    buffer.append("ACGT".as_bytes())
    assert_equal(String(from_utf8=buffer.as_bytes()), "ACGT")
    buffer.clear()  # Retain capacity for the next record.
    buffer.append("NN".as_bytes())
    assert_equal(len(buffer), 2)
```

`Buffer` is the library's libc-owned scratch buffer. Views expire on growth,
move or destruction; append sources must not alias it. `Input` and the pointer
overload of `decode_sequence` are advanced APIs. The latter requires
non-overlapping buffers of at least ceil(n/2) source and n destination bytes.
The caller must validate these ranges before decoding.

## Build and documentation

Compile consumers with `-Xlinker -ldeflate` and their installed prefix's library
directory on the linker search path. `mojo-libdeflate` and its native dependency
install the bindings and static archive; no checkout-specific include path is
needed after package installation. Use [Mojoverse dependency setup](https://github.com/sstadick/mojoverse#use-a-dependency)
with `subdirectory = "packages/mojo-seqair"`; internal dependencies stay at the
same Git revision through relative paths.

Stable Mojo 1.2.0 is pinned. `pixi run t` runs the tests. `pixi run docs` builds
the API reference and executes marked README examples. The BAM example needs
your own indexed file.
`pixi build` creates the Mojo package with `pixi-build-mojo`.
The codec package uses Clang 18.1.8 on Linux and Apple Clang on macOS, with
`-O3 -march=native`; builds are host-specific, not portable binary artifacts.
Supported platforms are Linux x86-64/AArch64 and Apple Silicon macOS 15+.
x86 uses a SIMD sequence decoder; ARM uses a scalar decoder.
CRAM/CRAI and SAM text are unsupported. The library reads records; it does not
compute pileups.
