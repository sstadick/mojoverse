# Mojo Seqair

Experimental native Mojo **BAM** reader used by Mojo Perbase. This is not an
official Seqair release or a complete port of its public API. BAM/BGZF parsing,
BAI/CSI lookup, auxiliary validation and CG long-CIGAR resolution are Mojo;
libdeflate 1.26 handles DEFLATE/CRC32 through direct static FFI calls.

Public imports are `Bam`, `Reader`, `Record`, `Reference`, `Region`, `Input`,
`Buffer` and `decode_sequence`. `Bam` owns an immutable dictionary/index that
can be shared. Each worker owns a `Reader`. A returned record borrows bytes
that expire on the next reader operation. Record names are bytes, not assumed
UTF-8. `Buffer` views expire on growth, move or destruction; append sources
must not alias the buffer. The unchecked `decode_sequence` primitive requires
non-overlapping buffers of at least ceil(n/2) source and n destination bytes.

```mojo
from mojo_seqair import Bam, Reader, Region

def count(path: String) raises -> Int:
    var bam = Bam(path)
    var reader = Reader(path)
    var total = 0
    for tid in range(len(bam.references)):
        reader.fetch(bam, Region(tid, 0, bam.references[tid].length))
        while reader.next():
            total += 1
    return total
```

Compile consumers with `-Xlinker -ldeflate` and their installed prefix's library
directory on the linker search path. `mojo-libdeflate` and its native dependency
install the bindings and static archive; no checkout-specific include path is
needed after package installation. Keep the unpublished `mojo-libdeflate`
repository beside this one for source builds.

Stable Mojo 1.2.0 is pinned. `pixi run t` runs assertion-enabled SIMD/scalar
sequence tests. `pixi build` creates the Mojo package with `pixi-build-mojo`.
The codec package uses Clang 18.1.8 on Linux and Apple Clang on macOS, with
`-O3 -march=native`; builds are host-specific, not portable binary artifacts.
Linux x86-64 and Apple Silicon macOS have native installed-consumer checks.
Linux AArch64 is a declared source target, not yet native-tested. x86 retains
the SIMD decoder; ARM uses the existing scalar fallback. CRAM/CRAI and SAM text
are unsupported. The application supplies counting/pileup algorithms.
