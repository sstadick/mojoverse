# mojo-radix-sort

Generic in-place integer radix sorting, built with
**Mojo 1.3.0.dev2026112605**. Package name: `mojo-radix-sort`; import: `radix_sort`.
Interval data structures belong to the separate **mojo-lapper** package.

[API reference](https://sstadick.github.io/mojoverse/mojo-radix-sort/radix_sort/_index.html)

## Install

Choose a commit from `main` for nightly Mojo or `stable/1.2` for Mojo 1.2.0.
Match the compiler pin and channel to that revision: `max-nightly` for
nightly, `max` for stable. Use one revision for all Mojoverse dependencies.

With [Pixi](https://pixi.prefix.dev/) 0.80 or newer, add to your `pixi.toml`.
Replace `<full-commit>` with a Mojoverse commit and use the same revision for
every Mojoverse dependency:

```toml
[workspace]
name = "radix-sort-example"
channels = ["https://conda.modular.com/max-nightly", "conda-forge"]
platforms = ["linux-64", "linux-aarch64", "osx-arm64"]
preview = ["pixi-build"]
requires-pixi = ">=0.80"

[dependencies]
mojo = "=1.3.0.dev2026112605"
mojo-radix-sort = { git = "https://github.com/sstadick/mojoverse.git", rev = "<full-commit>", subdirectory = "packages/mojo-radix-sort" }
```

Run `pixi install`, then `pixi run mojo run main.mojo`. No source `-I` path is
needed.

## Sort integers

```mojo {doctest="integers" global=true}
from radix_sort import radix_sort
from std.testing import assert_equal

def main() raises:
    var values: List[Int16] = [256, -4, 1, 0, -20]
    radix_sort(Span(values))
    var expected: List[Int16] = [-20, -4, 0, 1, 256]
    assert_equal(values, expected)
```

## Sort records while retaining payloads

```mojo {doctest="records" global=true}
from radix_sort import radix_sort
from std.testing import assert_equal

@fieldwise_init
struct Read(Copyable):
    var position: Int32
    var name: String

def position(reading: Read) -> Int32:
    return reading.position

def main() raises:
    var reads = [Read(42, "later"), Read(-5, "earlier")]
    radix_sort[key=position](Span(reads))
    assert_equal(reads[0].position, Int32(-5))
    assert_equal(reads[0].name, "earlier")
    assert_equal(reads[1].name, "later")
```

## API contract

- `radix_sort(Span(values))` sorts `Int8`, `Int16`, `Int32`, `Int64`,
  `UInt8`, `UInt16`, `UInt32`, or `UInt64` in ascending numeric order.
  Use these scalar types, not a SIMD vector or native `Int`.
- `radix_sort[key=key_function](Span(records))` accepts records conforming to
  `Copyable & Deinitable` and a compile-time, non-capturing, non-raising key
  function returning one of those scalar integer types. Ordinary `Copyable`
  structs have automatic destruction and satisfy this constraint.
- Keys must be deterministic and must not mutate the input or invalidate its
  storage. They may be evaluated repeatedly; there is no key cache.
- Empty and singleton spans work. Sorting a subspan leaves its neighbors alone.
- **Radix sort is unstable.** Do not depend on the order of equal-key records,
  regardless of input size. Complete record values retain their payloads.
- `insert_sort` has the same two calling forms and integer-key requirements,
  but guarantees stability.

Copying records with owning payloads may allocate according to their copy
semantics; the sort is not an allocation-free guarantee for such records.

## Development and packaging

Install [Pixi](https://pixi.prefix.dev/) and a host C linker, then:

```sh
pixi run t                  # Hat-compatible task; five parameterized test groups
pixi run example
pixi run check-consumer     # build and test installed artifact in fresh environment
pixi run docs              # executable examples and API site
pixi publish --path . --target-dir build
```

`pixi-build-mojo` puts `radix_sort.mojoc` in `lib/mojo` and includes LICENSE.
The artifact pins `mojo-compiler ==1.3.0.dev2026112605`; compiled Mojo modules are tied to
their compiler version. Supported platforms are Linux x86-64, Linux ARM64,
and macOS ARM64. The command above writes a local archive, not a remote publication.

See [NOTICE.md](NOTICE.md) for source attribution and licensing.
Documentation uses this monorepo's root tools.
It checks examples with this package's locked compiler before building
`target/docs`.
