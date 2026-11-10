---
name: working-with-mojo
description: Applies Mojoverse package, testing, documentation, performance, and stable/nightly conventions. Use when creating or changing Mojo libraries, Hat templates, package dependencies, or release maintenance.
---

# Working with Mojoverse packages

Load Modular's `mojo-syntax` skill before writing Mojo. Also load `mojo-python-interop` for Python integration and `mojo-gpu-fundamentals` for GPU work. Use `new-modular-project` when creating a project. These upstream skills own language guidance; this skill adds Seth's package conventions.

## Packages and dependency direction

- Keep independent repositories and release versions. Mojoverse is their catalog and shared tooling, not a source monorepo.
- Use `mojo-topic` for new distributions and `mojo_topic` for import packages. Preserve established names such as `extramojo`, `mojopt`, and `hat`.
- `mojo-io` depends on `mojo-bstr` for byte searches and line delimiters. Neither depends on ExtraMojo. Retain ExtraMojo's existing buffered I/O and imports during extraction.
- `mojo-bio` starts with generic radix sorting; interval data structures stay in `mojo-lapper`.
- `mojopt` precedes Hat. Test dependencies before consumers when changing compatible compiler versions.

## Packaging and compiler lanes

- Use Pixi and `pixi-build-mojo` for Mojo libraries and executables. Hat owns basic project scaffolding; apply the Mojoverse documentation/CI overlay rather than introducing a second implementation of Hat's templates.
- Keep a `t` task compatible with `hat test`, a formatting task, and tests runnable with assertions. A test runner must fail on any failed test and on accidental empty discovery.
- `main` tracks stable Mojo. The rolling `nightly` branch tracks a real published nightly compiler, not a Modular source commit or a stable lockfile with a nightly label.
- Align compiler versions across development, build, host, runtime dependencies, and lockfiles. Pin package dependencies to compatible immutable revisions for reproducible builds; the catalog can link to moving branches.
- Test package installation from a clean consumer prefix without checkout-specific `-I` paths. Running source tests alone does not verify packaging. Rust bindings additionally require native-library packaging and execution checks.
- Stable promotion is manual. Do not merge all of nightly merely because a new stable release exists; select the compatible changes and revalidate stable builds.

## Documentation and tests

Use `mojoverse-docs PROJECT PACKAGE --site` for API docs and executable examples. Read `reference/documentation.md` when adding documentation or configuring CI. It uses the project's locked Mojo, Modo, and stock MkDocs; no custom Hugo build is needed.

Put APIs in modules and re-export them from `__init__.mojo`: the supported Modo version otherwise omits root declarations. Document public contracts, errors, ownership/origins, byte offsets, and binary/UTF-8 behavior. Test real results, including NUL, malformed UTF-8, empty inputs, and boundary-spanning data where relevant.

Preserve source licenses and attribution when extracting or porting code. Borrowed byte views must not outlive their backing data; do not turn arbitrary bytes into unchecked UTF-8 just to reuse a text API.

## Performance acceptance

- Compare `mojo-bstr` with goostr/goose-bstr and Rust bstr/memchr using their existing benchmark fixtures and matched operations. The goal is close to the fastest Rust/Goose implementations or better; scalar functional coverage alone is not completion.
- Compare `mojo-io` with goose-io using matching buffer sizes, line-ending rules, returned data, and read/write workloads. Verify outputs before timing.
- Run timings serially on an otherwise idle host. Record source/compiler versions, build flags, CPU, raw samples, coverage, and per-workload results. Report slow cases and missing coverage instead of hiding them in an aggregate.
- Keep compilation, fixture generation, and process startup outside timed library operations. Separate prepared-search setup from one-shot search costs.

Update the existing external maintenance automation only after packages, docs, tests, and benchmarks are ready. Preserve dependency order and the stable/nightly policy; scheduling and remote publication remain separate from preparing local changes.
