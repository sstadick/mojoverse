# Mojoverse

Mojo libraries for byte strings, I/O, intervals, compression, and native threads.
Start with a package's usage examples, then browse its API reference for types,
functions, ownership rules, and errors.

Install packages with the [Git dependency setup](https://github.com/sstadick/mojoverse#use-a-dependency).
Pin the same Mojoverse revision for each dependency and use that revision's Mojo compiler.

## Libraries

| Package | Purpose | Docs |
| --- | --- | --- |
| mojo-bstr | Byte strings, SIMD search, UTF-8 | [Usage](mojo-bstr/index.md) · [API](mojo-bstr/mojo_bstr/_index.md) |
| mojo-io | Binary-safe buffered file I/O | [Usage](mojo-io/index.md) · [API](mojo-io/mojo_io/_index.md) |
| mojo-bio | Integer-key radix sorting | [Usage](mojo-bio/index.md) · [API](mojo-bio/mojo_bio/_index.md) |
| mojo-lapper | Interval overlap queries | [Usage](mojo-lapper/index.md) · [API](mojo-lapper/lapper/_index.md) |
| mojo-libdeflate | DEFLATE/gzip codecs and CRC32 | [Usage](mojo-libdeflate/index.md) · [API](mojo-libdeflate/mojo_libdeflate/_index.md) |
| mojo-threads | Owned thread jobs and synchronization | [Usage](mojo-threads/index.md) · [API](mojo-threads/mojo_threads/_index.md) |
| mojo-seqair | Indexed BAM/BGZF reading | [Usage](mojo-seqair/index.md) · [API](mojo-seqair/mojo_seqair/_index.md) |

## Other package documentation

- [ExtraMojo reference](https://extramojo.github.io/ExtraMojo/): collections, strings, I/O, and utilities. Maintained on its own documentation site.
- [mojopt usage guide](https://github.com/sstadick/mojoverse/tree/main/packages/mojopt): typed command-line parsing.
- [Raylib usage guide](https://github.com/sstadick/mojoverse/tree/main/packages/mojo-raylib): graphics, audio, and math bindings. `pixi run docs` in that package exports its API as JSON.

[Source and bins](https://github.com/sstadick/mojoverse) · [Build documentation](https://github.com/sstadick/mojoverse/blob/main/docs/development.md)
