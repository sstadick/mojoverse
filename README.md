# Mojoverse

Mojo libraries, bins, and development tools in one repository. This checkout uses **Mojo 1.3.0.dev2026112605** and **Pixi 0.80+**. `main` tracks the published nightly compiler; versioned branches such as [`stable/1.2`](https://github.com/sstadick/mojoverse/tree/stable/1.2) support stable Mojo releases across the whole workspace.

See the [nightly compatibility notes](docs/nightly.md) for compiler-specific behavior.

[Library documentation and API references](https://sstadick.github.io/mojoverse/)

## Use a dependency

Choose the compiler lane before selecting a Git revision:

| Use | Branch | Modular channel |
| --- | --- | --- |
| Nightly development | `main` | `https://conda.modular.com/max-nightly` |
| Stable Mojo 1.2.0 | `stable/1.2` | `https://conda.modular.com/max` |

Use the compiler pin and installation example from the selected revision.
The legacy `nightly` branch is a snapshot; existing nightly consumers should
move to a tested `main` commit and refresh their lockfile. Distribution names
remain unchanged: for example, install `mojo-bstr` and import `bstr`.

Choose a [tested tag](https://github.com/sstadick/mojoverse/tags) for your compiler lane and use it for every Mojoverse Git dependency. Each dependency specifies its package subdirectory. You can also pin a full commit SHA with `rev`.

```toml
[workspace]
channels = ["https://conda.modular.com/max-nightly", "conda-forge"]
platforms = ["linux-64", "linux-aarch64", "osx-arm64"]
preview = ["pixi-build"]
requires-pixi = ">=0.80"

[dependencies]
mojo = "=1.3.0.dev2026112605"
mojo-io = { git = "https://github.com/sstadick/mojoverse.git", tag = "<tested-tag>", subdirectory = "packages/mojo-io" }
```

Run `pixi install`, then import `io` normally—no source `-I` paths. Its `mojo-bstr` dependency comes from **the same commit**, through an internal relative path. Native packages document their linker flags and platform requirements.

## Libraries

| Package | Import | Purpose |
| --- | --- | --- |
| [ExtraMojo](packages/extramojo) | `extramojo` | Collections, strings, I/O and other utilities |
| [mojopt](packages/mojopt) | `mojopt` | Command-line parsing |
| [mojo-bstr](packages/mojo-bstr) | `bstr` | Byte strings, SIMD search and UTF-8 utilities |
| [mojo-io](packages/mojo-io) | `io` | Binary-safe buffered I/O |
| [mojo-bio](packages/mojo-bio) | `bio` | Indexed BAM/BGZF and streaming FASTA/FASTQ readers |
| [mojo-radix-sort](packages/mojo-radix-sort) | `radix_sort` | Generic integer-key radix sorting |
| [mojo-lapper](packages/mojo-lapper) | `lapper` | Interval data structures |
| [mojo-libdeflate](packages/mojo-libdeflate) | `libdeflate` | Inlined libdeflate bindings and native codec |
| [mojo-threads](packages/mojo-threads) | `threads` | Joinable pthread workers and synchronization |
| [mojo-raylib](packages/mojo-raylib) | `raylib` | Raylib graphics, audio and math bindings |

## Bins and tools

- [Hat](bins/hat): project scaffolding, builds and tests.
- [Mojo Perbase](bins/mojo-perbase): BAM base/depth counting and TSV merging. Experimental; no CRAM support.
- [Mojo LSP Bridge](bins/mojo-lsp-bridge): Zed, VS Code and Neovim integration with stdlib navigation and import fixes.
- [Rust → Mojo binding tooling](tools/bind-rust-to-mojo): experimental binding-generation skill.

[Build and test](docs/development.md) · [Executable documentation](docs/documentation.md) · [Project templates](templates) · [Migration and history](docs/migration.md)
