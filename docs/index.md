# Mojoverse

Mojo libraries for byte strings, I/O, intervals, compression, and native threads.
Start with a package's usage examples, then browse its API reference for types,
functions, ownership rules, and errors.

Install packages with the [Git dependency setup](https://github.com/sstadick/mojoverse#use-a-dependency).
Pin the same Mojoverse revision for each dependency and use that revision's Mojo compiler.

## Libraries

<div class="library-filter" hidden>
  <label for="library-filter">Find a library</label>
  <input id="library-filter" type="search" placeholder="Filter by name or purpose…" aria-controls="library-catalog" autocomplete="off">
  <p id="library-count" role="status" aria-live="polite"></p>
</div>

| Package | Purpose | Docs |
| --- | --- | --- |
| mojo-bstr | Byte strings, SIMD search, UTF-8 | [Usage](mojo-bstr/index.md) · [API](mojo-bstr/bstr/_index.md) |
| mojo-io | Binary-safe buffered file I/O | [Usage](mojo-io/index.md) · [API](mojo-io/io/_index.md) |
| mojo-bio | Indexed BAM/BGZF and streaming FASTA/FASTQ | [Usage](mojo-bio/index.md) · [API](mojo-bio/bio/_index.md) |
| mojo-radix-sort | Integer-key radix sorting | [Usage](mojo-radix-sort/index.md) · [API](mojo-radix-sort/radix_sort/_index.md) |
| mojo-lapper | Interval overlap queries | [Usage](mojo-lapper/index.md) · [API](mojo-lapper/lapper/_index.md) |
| mojo-libdeflate | DEFLATE/gzip codecs and CRC32 | [Usage](mojo-libdeflate/index.md) · [API](mojo-libdeflate/libdeflate/_index.md) |
| mojo-threads | Owned thread jobs and synchronization | [Usage](mojo-threads/index.md) · [API](mojo-threads/threads/_index.md) |

## Other package documentation

- [ExtraMojo reference](https://extramojo.github.io/ExtraMojo/): collections, strings, I/O, and utilities. Maintained on its own documentation site.
- [mojopt usage guide](https://github.com/sstadick/mojoverse/tree/main/packages/mojopt): typed command-line parsing.
- [Raylib usage guide](https://github.com/sstadick/mojoverse/tree/main/packages/mojo-raylib): graphics, audio, and math bindings. `pixi run docs` in that package exports its API as JSON.

[Source and bins](https://github.com/sstadick/mojoverse) · [Build documentation](https://github.com/sstadick/mojoverse/blob/main/docs/development.md)
