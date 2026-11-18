# Build and test

## Install

Install [Pixi](https://pixi.prefix.dev/) 0.80 or newer and a native C linker. Use Clang; macOS needs Xcode command-line tools. Clone the whole repository so internal path dependencies remain together:

```sh
git clone https://github.com/sstadick/mojoverse.git
cd mojoverse
git submodule update --init
pixi install --locked
pixi run --locked test
```

The root environment builds the nongraphical libraries, Hat and Perbase. The `graphics` environment builds Raylib with the same compiler, without adding display/audio libraries to command-line consumers. Pixi resolves the dependency graph and invokes the package backends. There is no Bazel configuration or parallel build graph. Cargo and npm are used only for the LSP and Rust binding tooling.

The root `pixi.lock` covers the combined environments. Package workspaces retain manifests, tasks and lockfiles for scoped development and external consumers. `pixi run lock-all` refreshes all locks, and `pixi run check-locks` rejects stale ones. A package's own lockfile does not constrain an external consumer's environment. Compiler and internal-dependency consistency is enforced by `pixi run check-workspace`, not by asking maintainers to remember every pin.

Pixi's build support is experimental. Previously built, same-version local artifacts can collide in the shared extracted-package cache. If migrating an old checkout produces a compiler-version mismatch, use a fresh cache for that checkout and reinstall:

```sh
export PIXI_CACHE_DIR="$PWD/.pixi/fresh-cache"
pixi reinstall
pixi run --locked test
```

Keep that cache setting for subsequent commands in the shell. Do not delete another project's environment or the user's shared cache.

## Scoped checks

```sh
pixi run --locked test-packages mojo-bstr mojo-io
pixi run --locked test-installed mojo-bstr mojo-io
pixi run --locked test-bins
pixi run --locked -e docs test-docs
pixi run --locked -e lsp test-lsp
pixi run --locked -e graphics test-graphics
```

The package runner discovers existing `test_*.mojo` programs, enables assertions and rejects empty discovery. `test-packages` uses a compiler/native-only environment: installed `.mojoc` files otherwise shadow source `-I` paths. `test-installed` uses the combined environment without source include paths. Bin checks run Hat's existing tests and Perbase's independent BAM/TSV CLI fixtures. Raylib tests call native scalar/aggregate APIs without a display, then compile the examples. The LSP task runs Rust/Python/query/Node checks and creates a local VSIX; it does not publish it. Real-editor and native-server integration checks are described in [the LSP README](../bins/mojo-lsp-bridge).

Use a package's own tasks for its extra checks and examples:

```sh
pixi run --locked --manifest-path packages/mojo-bstr/pixi.toml ownership
pixi run --locked --manifest-path packages/mojo-bstr/pixi.toml differential
pixi run --locked --manifest-path packages/mojo-io/pixi.toml consumer
pixi run --locked --manifest-path bins/mojo-perbase/pixi.toml consumer
```

For performance work, keep compilation and fixture generation outside timing. Run benchmarks serially on an idle host, compare matching operations and complete output hashes, and retain raw samples. Perbase's [benchmark protocol and historical results](../bins/mojo-perbase/README.md#performance-and-verification) are not a language-wide ranking.

## Dependency changes

Internal dependencies are relative `path` dependencies in the relevant development/build/host/runtime sections. Do not pin a package to an older Git copy of another package in this repository. Consumers that import a Mojo dependency while compiling need it in their host dependencies as well as their build dependencies.

External consumers use a Git URL, full commit and `subdirectory`, as shown in the [README](../README.md). Pixi resolves internal paths within that Git checkout, including native subpackages. Pin directly requested Mojoverse dependencies to the same revision and commit the consumer's lockfile. A change to both sides of an API can then land in one commit.

Check the committed graph from a clean external prefix:

```sh
pixi run --locked consumer --repository "file://$PWD" --rev "$(git rev-parse HEAD)"
```

This uses the commit, not uncommitted edits. To test the published source, omit `--repository` and provide a pushed revision. The check installs I/O, the BAM reader, workers and Perbase, exercising transitive bstr/libdeflate/native dependencies without source include paths. Package `consumer` tasks separately exercise immutable local conda artifacts. Local build/export commands do not upload packages.

## Compilers and platforms

The root manifest pins the compiler for every library and bin. Mojo builds use `-O3` and the compiler's default host CPU/features where explicitly configured. `--target-cpu=native` is not a valid Mojo 1.2 option. Native codec/glue builds use **Clang `-O3 -march=native`**, including dependencies. These artifacts are host-tuned, not universal binary releases; rebuild them on the destination CPU.

The stable workspace targets Linux x86-64, Linux AArch64 and Apple-silicon macOS. CI runs native jobs on those platforms. The separate documentation environment supports Linux x86-64 and macOS only: Modo's bundled executable does not support Linux AArch64, and its macOS executable requires Rosetta. CI checks documentation on both supported hosts, separately from the native package suite. A resolved lockfile alone is not evidence of native execution or performance. GPU checks additionally require suitable hardware.

Raylib uses the same stable compiler as the rest of `main`; its graphics environment currently targets Linux x86-64 and Apple-silicon macOS. To work on it:

```sh
pixi run --locked -e graphics test-graphics
pixi run --locked --manifest-path packages/mojo-raylib/pixi.toml -e codegen regen-check
```

## Compiler updates

```sh
python scripts/toolchain.py update --channel stable
# On the nightly branch:
python scripts/toolchain.py update --channel nightly
```

The updater queries Modular's published packages, selects a matching Mojo/MAX release available on every root platform, updates all development/build/host/runtime and example pins, and regenerates all locks. `--version` selects a particular published compiler; `--no-lock` allows inspecting the pin diff first. It does not migrate Mojo source automatically. Run the complete checks and repair incompatible APIs before considering an update supported.

The nightly workflow brings `main` into `nightly`, updates that branch, and runs the same graph checks. Conflicts or compiler failures remain visible; no agent repairs or nightly-to-main merges happen automatically. Stable promotion is a deliberate source/compiler update on `main`, not a merge of nightly pins.

## Documentation and editor setup

Use the root [documentation tools](documentation.md) or a package's `docs` task. APIs belong in modules and are re-exported from `__init__.mojo`, because the supported documentation generator otherwise omits root declarations. Preserve public contracts, errors, origins/ownership, byte offsets and binary/UTF-8 distinctions.

The root default Pixi environment includes the Mojo language server, so the [LSP Bridge](../bins/mojo-lsp-bridge) can discover it. In Zed, select `bins/mojo-lsp-bridge` for the dev extension; in VS Code install the VSIX built under that directory's `vscode/`. Open a package directory to have its source layout and local workspace detected; install its Pixi environment when using a compiler different from the root. There are no machine-specific editor paths checked in.

Package licenses remain beside their source. The root tools' license does not replace imported licenses. The repository-specific agent guidance is [AGENTS.md](../AGENTS.md); Modular's skills remain the authority for Mojo syntax, Python interop and GPU programming.
