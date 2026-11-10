# Mojoverse

Seth's Mojo packages, shared development practices, executable documentation, and project templates. Each package owns its repository, releases, tests, and reproducible dependencies. This repository is a catalog, not a coordinated distribution.

## Projects

| Project | Purpose |
| --- | --- |
| [ExtraMojo](https://github.com/ExtraMojo/ExtraMojo) | Utilities beyond the standard library |
| [mojopt](https://github.com/sstadick/mojopt) | Command-line parsing |
| [Hat](https://github.com/sstadick/hat) | Pixi-based Mojo project scaffolding, builds, and tests |
| [Rust → Mojo bindings](https://github.com/sstadick/mojo-import-crates-skill) | Crate-agnostic binding generation and packaging tooling |
| [mojo-lapper](https://github.com/sstadick/mojo-lapper) | Interval data structures |
| [mojo-bstr](https://github.com/sstadick/mojo-bstr) | Byte-string searching, transformations, and UTF-8 utilities |
| [mojo-io](https://github.com/sstadick/mojo-io) | Binary-safe buffered file I/O |
| [mojo-bio](https://github.com/sstadick/mojo-bio) | Generic integer-key sorting |

Dependency order: **mojo-bstr → mojo-io**, and **mojopt → Hat**. Catalog links follow moving branches; packages pin their own compatible dependencies.

## Shared practices

The [working-with-mojo skill](.agents/skills/working-with-mojo/SKILL.md) adds package conventions to Modular's existing `mojo-syntax`, `mojo-python-interop`, `mojo-gpu-fundamentals`, and `new-modular-project` skills. It does not duplicate their language guidance.

Install the local skill into another checkout:

```sh
amp skill add /path/to/mojoverse/.agents/skills/working-with-mojo
```

Packages use **Pixi + pixi-build-mojo**, Hat-compatible tests, and clean consumer-install checks. `main` tracks stable Mojo; a rolling `nightly` branch tracks actual nightly compiler packages. Stable promotion remains manual. Linux x86-64, Linux AArch64, and Apple-silicon macOS are the intended package platforms; native checks are required before claiming support.

Use Hat to create a package, then apply the [documentation/CI overlay](templates/README.md).
Hat remains the source of the project scaffold; the overlay adds executable docs.

## Documentation

`mojoverse-docs` generates API documentation and runs executable examples with the package's locked compiler and dependencies. It produces Markdown or GitHub Pages-ready HTML; deployment is separate.

```sh
pixi install
pixi run docs /path/to/package mojo_topic --site
```

See the [documentation conventions](.agents/skills/working-with-mojo/reference/documentation.md) for executable examples and CI. Builds fail on broken or missing examples and unsupported root-module declarations.

## Performance

mojo-bstr is compared with Goose and Rust bstr/memchr; mojo-io is compared with goose-io on matched read/write workloads. Package benchmark documentation includes results, measured gaps, and reproduction commands. Run timings serially on an idle host.

## Distribution

Use Pixi Git dependencies pinned to a compatible full commit, keeping compiler constraints aligned. Local path dependencies require sibling checkouts and are not portable release dependencies.

`pixi publish --path . --target-dir dist --force --clean` builds local conda artifacts; it does not upload them. Verify a clean consumer installation before sharing an artifact or release.

The [Modular community submission workflow](https://github.com/modular/modular-community#submitting-a-package) currently requires a pull request adding `recipes/<package>/recipe.yaml` and an installed-package test. It is not a direct upload of a pixi-build-mojo artifact. Once releases exist, those small channel recipes can pin source releases and compiler versions while the source repositories keep pixi-build-mojo. Channel submission is optional; immutable Git dependencies work without it.

## Develop the tools

```sh
pixi run test
```

The root Pixi lockfile covers the Python documentation tools, not the versions of catalogued Mojo packages. Documentation tests run real Mojo compilers and example assertions.
