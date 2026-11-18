# mojo-bio

Byte-oriented bioinformatics readers for **Mojo 1.2.0**: indexed BAM/BGZF and
streaming FASTA/FASTQ. Import `bio`. Generic integer sorting is available
separately in [mojo-radix-sort](../mojo-radix-sort).

[API reference](https://sstadick.github.io/mojoverse/mojo-bio/bio/_index.html)

## Read FASTA or FASTQ

`GZFile` detects plain or gzip input by content, including concatenated gzip
members. `FastxReader` reuses its byte lists; use `to_var()` for an owned record
or `.copy()` on individual fields to retain them across reads.

```mojo {doctest="fastx" global=true}
from bio import BufferedReader, FastxReader, GZFile
from std.pathlib import Path
from std.tempfile import TemporaryDirectory
from std.testing import assert_equal

def main() raises:
    var directory = TemporaryDirectory()
    var path = String(Path(directory.name) / "reads.fq")
    with open(path, "w") as file:
        file.write_all("@read1 example\nACGT\n+\n!#$%\n".as_bytes())
    var reader = FastxReader(BufferedReader(GZFile(path)))
    var sequences = List[List[UInt8]]()
    while True:
        var length = reader.read()
        if length == -1:
            break
        if length == -2:
            raise Error("malformed FASTQ")
        sequences.append(reader.seq.copy())
    assert_equal(sequences[0], List("ACGT".as_bytes()))
```

- `read()` returns the sequence length, **including zero for an empty record**,
  `-1` at EOF, or `-2` for malformed/truncated FASTQ. I/O and decompression errors
  raise. Stop after a parse error; partial fields are not a valid record.
- `name`, `seq`, `qual`, and `comment` are `List[UInt8]`, not UTF-8 strings.
  FASTQ qualities remain ASCII bytes, unlike BAM's numeric Phred scores.
- Multiline sequences/qualities, LF/CRLF, blank sequence lines, and final lines
  without a newline are supported. Sequences are not alphabet-validated.
- By default the header splits at the first space/tab. Set
  `FastxReader[read_comment=False](...)` to keep the entire header in `name`.
- `FastxRecord.qual` is `None` for FASTA and present for FASTQ, even if empty.
- Custom sources can implement `KRead.unbuffered_read`; positive short reads
  are allowed, zero means EOF, and I/O failures raise.

## Query reads

Give an indexed, coordinate-sorted BAM and a **zero-based, half-open** region:

```mojo
from bio import Bam

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

## Reuse a reader and retain decoded sequences

This example also requires your own indexed `reads.bam` with `chr20` covering
the query coordinates. Decode bases **inside** the loop, before
the next `reader.next()` invalidates the record. Each result owns its bytes.

```mojo
from bio import Bam, Reader

def main() raises:
    var bam = Bam("reads.bam")
    var reader = Reader(bam.path)
    var sequences = List[List[UInt8]]()
    for begin in [10000000, 20000000]:
        reader.fetch(bam, bam.region("chr20", begin, begin + 1000))
        while reader.next():
            var record = reader.record.value()
            var bases = List[UInt8](length=record.nseq, fill=0)
            _ = record.decode_bases(Span(bases))
            sequences.append(bases^)
    print(len(sequences))
```

Overlapping queries can return the same read more than once. The example
collects records per query; it does not deduplicate them.

## Reuse a byte buffer

```mojo {doctest="buffer" global=true}
from bio import Buffer
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

Compile BAM/BGZF consumers with `-Xlinker -ldeflate`, and FASTX `GZFile` consumers
with `-Xlinker -lz`. Put the installed prefix's library directory on the linker
search path (`-Xlinker -L$CONDA_PREFIX/lib`). Package installation supplies zlib,
`mojo-bstr`, and `mojo-libdeflate` with its native archive; no source `-I` path
is needed. Use [Mojoverse dependency setup](https://github.com/sstadick/mojoverse#use-a-dependency)
with `subdirectory = "packages/mojo-bio"`; internal dependencies stay at the
same Git revision through relative paths. A custom FASTX source does not use zlib.

Stable Mojo 1.2.0 is pinned. `pixi run t` runs the tests. `pixi run docs` builds
the API reference and executes marked README examples. The BAM example needs
your own indexed file.
`pixi build` creates the Mojo package with `pixi-build-mojo`.
The codec package uses Clang 18.1.8 on Linux and Apple Clang on macOS, with
`-O3 -march=native`; builds are host-specific, not portable binary artifacts.
Supported platforms are Linux x86-64/AArch64 and Apple Silicon macOS 15+.
x86 uses a SIMD sequence decoder; ARM uses a scalar decoder.
CRAM/CRAI and SAM text are unsupported. The library reads records; it does not
compute pileups. FASTX parsing derives from BioRadOpenSource/ish's kseq port;
the BAM reader derives from Seqair/Goose Seqair, not an official Seqair release.
See [NOTICE.md](NOTICE.md) and [LICENSE](LICENSE) for the MIT and Apache-2.0
component licenses and source attribution.
