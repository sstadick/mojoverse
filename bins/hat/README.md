# hat 🎩

A thin wrapper over Pixi that makes common Mojo project tasks easier.

## Install

Choose a commit from `main` for nightly Mojo or `stable/1.2` for Mojo 1.2.0.
Match the compiler pin and channel to that revision: `max-nightly` for
nightly, `max` for stable. Use one revision for all Mojoverse dependencies.

With [Pixi](https://pixi.prefix.dev/) 0.80 or newer, install directly from Git.
Replace `<full-commit>` with a Mojoverse commit:

```sh
pixi global install --git https://github.com/sstadick/mojoverse.git \
  --rev '<full-commit>' --subdirectory bins/hat \
  -c https://conda.modular.com/max-nightly -c conda-forge
hat --help
```

Mojopt comes from the same Git revision; no local checkout is required.
For a project dependency, use [Mojoverse dependency setup](../../README.md#use-a-dependency)
with `subdirectory = "bins/hat"`.

## Usage

```bash
# Create a new binary project
hat new --name mojo-grep

# Create a new lib project
hat new --lib --name amazing-lib

# Track the latest nightly compiler instead of stable Mojo 1.2.0
hat new --nightly --name nightly-project

# Build project (defaults to release build)
hat build 

# Build with debug and asserts on
hat build --debug

# Test your project
hat test
```

This checkout uses the workspace's pinned nightly compiler. Generated projects use stable Mojo 1.2.0 by default, require Pixi 0.76 or newer, and rely on the [`pixi-build-mojo`](https://prefix-dev.github.io/pixi-build-backends/backends/pixi-build-mojo) backend. Library names such as `amazing-lib` are mapped to importable Mojo package names such as `amazing_lib`.

Libraries and packages created this way can be used through Git paths and do not need to be published on Conda. To publish on [modular-community](https://github.com/modular/modular-community), create a `recipe.yaml` and follow that repository's publishing process.

> [!Warning]
> Since `hat` relies on `pixi.toml` and its generated `t` task, changing that task may break `hat test`.
