# hat 🎩

A thin wrapper over Pixi that makes common Mojo project tasks easier.

## Install

```sh
git clone https://github.com/sstadick/mojoverse.git
cd mojoverse
pixi run --locked hat --help
```

To install globally from this checkout, use `pixi global install --path bins/hat`
with the channels in the root manifest. Mojopt comes from the same monorepo.
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

This checkout and generated projects use stable Mojo 1.2.0 by default, require Pixi 0.76 or newer, and rely on the [`pixi-build-mojo`](https://prefix-dev.github.io/pixi-build-backends/backends/pixi-build-mojo) backend. Library names such as `amazing-lib` are mapped to importable Mojo package names such as `amazing_lib`.

Libraries and packages created this way can be used through Git paths and do not need to be published on Conda. To publish on [modular-community](https://github.com/modular/modular-community), create a `recipe.yaml` and follow that repository's publishing process.

> [!Warning]
> Since `hat` relies on `pixi.toml` and its generated `t` task, changing that task may break `hat test`.
