# Mojoverse

Mojo libraries, bins, and development tools in one repository. This checkout uses **Mojo 1.2.0** and **Pixi 0.80+**. `main` follows stable; `nightly` tracks the published nightly compiler across the whole workspace.

[Library documentation and API references](https://sstadick.github.io/mojoverse/)

## Use a dependency

Add a Git dependency with its package subdirectory to your `pixi.toml`. Replace `<full-commit>` with a Mojoverse commit and use that same revision for every Mojoverse dependency:

```toml
[workspace]
channels = ["https://conda.modular.com/max", "conda-forge"]
platforms = ["linux-64", "linux-aarch64", "osx-arm64"]
preview = ["pixi-build"]
requires-pixi = ">=0.80"

[dependencies]
mojo = "=1.2.0"
mojo-io = { git = "https://github.com/sstadick/mojoverse.git", rev = "<full-commit>", subdirectory = "packages/mojo-io" }
```

Run `pixi install`, then import `mojo_io` normally—no source `-I` paths. Its `mojo-bstr` dependency comes from **the same commit**, through an internal relative path. For local development, use `{ path = "../mojoverse/packages/mojo-io" }` instead. Native packages document their linker flags and platform requirements.

## Libraries

| Package | Import | Purpose |
| --- | --- | --- |
| [ExtraMojo](packages/extramojo) | `extramojo` | Collections, strings, I/O and other utilities |
| [mojopt](packages/mojopt) | `mojopt` | Command-line parsing |
| [mojo-bstr](packages/mojo-bstr) | `mojo_bstr` | Byte strings, SIMD search and UTF-8 utilities |
| [mojo-io](packages/mojo-io) | `mojo_io` | Binary-safe buffered I/O |
| [mojo-bio](packages/mojo-bio) | `mojo_bio` | Generic integer-key radix sorting |
| [mojo-lapper](packages/mojo-lapper) | `lapper` | Interval data structures |
| [mojo-libdeflate](packages/mojo-libdeflate) | `mojo_libdeflate` | Inlined libdeflate bindings and native codec |
| [mojo-threads](packages/mojo-threads) | `mojo_threads` | Joinable pthread workers and synchronization |
| [mojo-seqair](packages/mojo-seqair) | `mojo_seqair` | Indexed BAM/BGZF reader; not an official Seqair release |
| [mojo-raylib](packages/mojo-raylib) | `mojo_raylib` | Raylib graphics, audio and math bindings |

## Bins and tools

- [Hat](bins/hat): project scaffolding, builds and tests.
- [Mojo Perbase](bins/mojo-perbase): BAM base/depth counting and TSV merging. Experimental; no CRAM support.
- [Mojo LSP Bridge](bins/mojo-lsp-bridge): Zed, VS Code and Neovim integration with stdlib navigation and import fixes.
- [Rust → Mojo binding tooling](tools/bind-rust-to-mojo): experimental binding-generation skill.

[Build and test](docs/development.md) · [Executable documentation](docs/documentation.md) · [Project templates](templates) · [Migration and history](docs/migration.md)
