## BAM/BGZF

Native Mojo translation using goose-seqair revision
f4baea82bed484f2debb7dbcb30b99e87d65e51e and the local C Perbase reader as
references. Seqair-derived algorithms are attributed to Pascal Hertleif;
the Goose translation and application adaptations to Seth Stadick. The MIT
notices are retained in LICENSE. No Rust or Goose runtime/code is linked.

libdeflate 1.26 is now provided by mojo-libdeflate, with the unmodified source
snapshot at upstream revision 8fcf5832a3fa680f4c6a5332e2436f8a6dd5c299.
The original MIT notice is retained there in native/vendor/libdeflate/COPYING
and installed with the native package. Seqair no longer owns a codec copy.

SIMD nibble lookup uses the SSSE3 pshufb LLVM intrinsic through Mojo, with a
scalar fallback/tail. It does not bind goose-simd or copy its C kernel.

## FASTA/FASTQ

`src/bio/fastx.mojo` adapts `ishlib/vendor/kseq.mojo` and the read-only
gzip input support from `ishlib/vendor/zlib.mojo` in
[BioRadOpenSource/ish](https://github.com/BioRadOpenSource/ish), revision
`304233bc80b14c18f6f1497d17116d2328d2474f`.

Copyright Bio-Rad Laboratories, Inc. 2025-present. All rights reserved.
The Bio-Rad software and related Bio-Rad materials are published under the
Apache-2.0 license. Bio-Rad makes no representations or warranties regarding
third-party software components; their use is subject to their own terms.
The full Apache-2.0 license and these attribution notices are included in LICENSE.

The original reader identifies itself as a Mojo port of kseq based on the
Crystal implementation in [biofast](https://github.com/lh3/biofast).
kseq is MIT licensed, Copyright (c) 2008, 2009, 2011 Attractive Chaos
<attractor@live.co.uk>; its permission and warranty terms are retained in LICENSE.

This adaptation uses current Mojo syntax, standard List-owned buffers and
mojo-bstr byte searching in place of ish's ByteString and ExtraMojo dependency.
It handles positive short reads, CRLF and unterminated final lines, retains empty
FASTQ qualities in owned records, and rejects missing/mismatched FASTQ qualities.
Only the reader and its gzip input support are adapted; no search, alignment,
GPU, CLI, or application code from ish is included.

zlib is an external dependency, not vendored source. Its license is distributed
with that dependency; the Mojo input bindings retain ish's Apache-2.0 terms.
