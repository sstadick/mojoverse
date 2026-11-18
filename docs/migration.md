# Migration and history

Mojoverse imports the existing projects without squashing their Git history. The original commits remain ancestors; use `git log --all -- <old-path>` when inspecting history before a subtree import. The initial import retained package and import names; subsequent changes are listed below. Libraries live under `packages/`, executables/editor integrations under `bins/`, and binding-generation tooling under `tools/`.

| Destination | Imported source revision |
| --- | --- |
| `packages/extramojo` | `2c7531d494b8bf529f890d9d83dcbcb15cf8d631` |
| `packages/mojopt` | `ef76ea00e49483b65b01774829d4c44fbd466b5c` |
| `packages/mojo-bio` | `e1744a1d58799beed905a57c28289ef3c4262eac` |
| `packages/mojo-lapper` | `1a2ba808c28e4ac03d127b901e308f39582ce5b0` |
| `packages/mojo-bstr` | `8baa38cfa9fc1f2e5519aaa626094c156124c703` |
| `packages/mojo-io` | `17b29ed7178b791673401407e9267b82ec50f4c5`, plus the local benchmark-argument fix |
| `packages/mojo-raylib` | `3d49cea57c0974590e35a7facd28ecc5ca672428`, plus the local bindings/generator changes |
| `bins/hat` | `3872a6226f75b32ab51289f3582631fcf9b53844` |
| `bins/mojo-lsp-bridge` | `4b46c5d83b9742fd14178b5f8a9af7fbe29cdf0c` |
| `tools/bind-rust-to-mojo` | `e8ba10e00230963a6eb4d4da6287989f0576d120` |

`mojo-libdeflate`, `mojo-threads`, `mojo-seqair`, and `mojo-perbase` were uncommitted local projects and enter as source snapshots. Perbase result files preserve measurements while replacing machine-specific path prefixes with placeholders. Generated build artifacts and environments are not imported. Licenses and attribution remain with each project.

ExtraMojo comes from the stable maintenance checkout, not the separate experimental checkout. This migration does not delete the other checkout or declare its experimental work superseded. Raylib's native submodule remains pinned at `8e82249f6572ae2683a9cade6addd9b404abd710`; initialize it from the monorepo root.

Internal dependencies now use relative paths within this repository. External consumers use one Git revision and package subdirectories; see the [landing page](../README.md). The root [build documentation](development.md) owns workspace/compiler maintenance. Workflows below package directories are historical standalone configurations; GitHub runs only the root `.github/workflows`.

`main` uses one stable compiler throughout. Raylib's generated bindings were migrated from Mojo 1.0 to that compiler by changing their generator. Its native recipe now uses the same Clang/native-optimization policy and Pixi's cache, instead of a separate cache that did not include compiler flags.

The migration itself does not archive or delete the old GitHub repositories, publish conda releases, replace existing ExtraMojo APIs, or claim new performance measurements. Original local checkouts remain under `mojo-projects` as recovery copies. New coordinated development belongs here.

## Bio readers and standalone radix sorting

The generic sorter now lives in `packages/mojo-radix-sort`, imported as
`radix_sort`. Replace `from mojo_bio import radix_sort, insert_sort` with
`from radix_sort import radix_sort, insert_sort` and change the Pixi
dependency/subdirectory to `mojo-radix-sort`. Lapper depends only on this sorter,
not the bio readers or their compression libraries.

The former `mojo-seqair` package is now part of `packages/mojo-bio`. Change the
dependency to `mojo-bio` and `mojo_seqair` imports to `bio`; `bam`, `bgzf`,
and `buffer` keep their APIs. There is no legacy namespace shim. Consumers pinned
to older Git revisions retain the old packages and imports.

`mojo-bio` also includes the FASTX reader and its read-only gzip support from
BioRadOpenSource/ish revision `304233bc80b14c18f6f1497d17116d2328d2474f`, adapted
to the workspace compiler. No other ish code was imported, and ish itself is
unchanged. FASTX fields use standard `List[UInt8]` rather than ish's private
ByteString. The reader's Apache-2.0 and kseq MIT notices remain with the code;
BAM/BGZF and the standalone sorter retain their MIT terms.

## Unprefixed library imports

The `mojo-*` libraries keep their Pixi dependency names and package directories,
but their import namespaces no longer include `mojo_`:

| Pixi dependency | Import |
| --- | --- |
| `mojo-bio` | `bio` |
| `mojo-bstr` | `bstr` |
| `mojo-io` | `io` |
| `mojo-libdeflate` | `libdeflate` |
| `mojo-radix-sort` | `radix_sort` |
| `mojo_raylib` | `raylib` |
| `mojo-threads` | `threads` |
| `mojo-lapper` | `lapper` (unchanged) |

Update root imports and qualified module paths, for example `from bio import Bam`
and `from bio.bam import Region`. The old prefixed namespaces are not re-exported.
`extramojo`, `mojopt`, executable names, and native linker symbols are unchanged.

## Standalone repositories to revisit later

Keep these active while trying the monorepo. After checking downstream consumers, releases and outstanding work, they are candidates for archiving—not repositories already archived by this migration:

| Standalone repository | Monorepo destination |
| --- | --- |
| [sstadick/mojopt](https://github.com/sstadick/mojopt) | [packages/mojopt](../packages/mojopt) |
| [sstadick/mojo-bio](https://github.com/sstadick/mojo-bio) | [packages/mojo-radix-sort](../packages/mojo-radix-sort) (original sorter) |
| [sstadick/mojo-lapper](https://github.com/sstadick/mojo-lapper) | [packages/mojo-lapper](../packages/mojo-lapper) |
| [sstadick/mojo-bstr](https://github.com/sstadick/mojo-bstr) | [packages/mojo-bstr](../packages/mojo-bstr) |
| [sstadick/mojo-io](https://github.com/sstadick/mojo-io) | [packages/mojo-io](../packages/mojo-io) |
| [sstadick/mojo-raylib](https://github.com/sstadick/mojo-raylib) | [packages/mojo-raylib](../packages/mojo-raylib) |
| [sstadick/hat](https://github.com/sstadick/hat) | [bins/hat](../bins/hat) |
| [sstadick/mojo-lsp-bridge](https://github.com/sstadick/mojo-lsp-bridge) | [bins/mojo-lsp-bridge](../bins/mojo-lsp-bridge) |
| [sstadick/mojo-import-crates-skill](https://github.com/sstadick/mojo-import-crates-skill) | [tools/bind-rust-to-mojo](../tools/bind-rust-to-mojo) |

ExtraMojo is not on this list: its shared repository and separate experimental work need a distinct decision. The four source-snapshot projects had no standalone published repository at migration time.
