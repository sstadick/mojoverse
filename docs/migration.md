# Migration and history

Mojoverse imports the existing projects without squashing their Git history. The original commits remain ancestors; use `git log --all -- <old-path>` when inspecting history before a subtree import. Existing import names and package names are retained. Libraries live under `packages/`, executables/editor integrations under `bins/`, and binding-generation tooling under `tools/`.

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
