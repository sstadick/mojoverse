# ⚡ extramojo ⚡

Extra functionality to extend the Mojo std lib.

## Install / Usage

Choose a commit from `main` for nightly Mojo or `stable/1.2` for Mojo 1.2.0.
Match the compiler pin and channel to that revision: `max-nightly` for
nightly, `max` for stable. Use one revision for all Mojoverse dependencies.

Follow the [Mojoverse dependency setup](../../README.md#use-a-dependency) and
use the compiler pinned by the same revision. Replace `<full-commit>` with a
Mojoverse commit and use the same revision for every Mojoverse dependency:

```toml
[dependencies]
extramojo = { git = "https://github.com/sstadick/mojoverse.git", rev = "<full-commit>", subdirectory = "packages/extramojo" }
```

Run `pixi install`, then `pixi run mojo run my_example_file.mojo`. No source
include path is needed: `pixi-build-mojo` installs the compiled library into
the environment's `lib/mojo` directory. ExtraMojo remains self-contained;
its buffered I/O and byte-string APIs do not require `mojo-io` or `mojo-bstr`.

## Documentation and Examples

[ExtraMojo Docs](https://extramojo.github.io/ExtraMojo/)

Also see any of the tests in the `test_*.mojo` files.

## Notable Functionality

- Buffered Reading and writing for files
- CLI opts parser
- For bytestrings (`List/Span[UInt8]`), SIMD version of: memchr, to_uppercase, to_lowercase, SplitIterator
- BBHash
- BitVec
- `saturating_add` and `saturating_sub` for integral types
- Decimal integer and float formatting into existing Writers
- reservoir sampling

See [docs for details](https://extramojo.github.io/ExtraMojo/)

## Embedding files at compile time

```mojo
from extramojo.utils import (
    include_bytes_requires_cache_clear_on_edit,
    include_string_requires_cache_clear_on_edit,
)

comptime message = include_string_requires_cache_clear_on_edit["message.txt"]()
comptime logo = include_bytes_requires_cache_clear_on_edit["logo.png"]()
```

The string function validates UTF-8 at compile time and returns a `StaticString`.
The bytes function returns the exact file contents as a read-only
`Span[Byte, ImmStaticOrigin]`. Use an absolute path or a path relative to the
compiler's working directory. The compiled program can run without the input files.

**After editing an embedded file, run `mojo --clear-cache` and rebuild.**
Mojo can reuse the previous contents when only the asset changes. Builds that
share a compiler cache can also reuse the same relative path from a different
working directory. Use distinct absolute paths for those files or clear the
cache when switching directories.

## Number formatting

`extramojo.format.write_int` writes signed and unsigned integers up to 64 bits
in decimal. `write_float` writes Float32/64 with the pinned Mojo stdlib's
shortest round-trip representation, including scientific notation and special
values. Both append to any `Writer` on the CPU, using stack buffers without
allocating an intermediate String.

```mojo {doctest="format_numbers" global=true}
from extramojo.format import write_float, write_int
from std.testing import assert_equal

def main() raises:
    var text = String("count=")
    write_int(text, Int64(-12345))
    text += ", value="
    write_float(text, Float64(1.25))
    assert_equal(text, "count=-12345, value=1.25")
```

Integers use a two-digit lookup table; floats batch their ASCII output while
retaining the stdlib's private `_to_decimal` conversion. Compiler upgrades need
output-compatibility testing. These APIs do not support GPU targets, integer
bases other than decimal, integers wider than 64 bits, or float precision options.

## Line callbacks

`for_each_line(path, callback, buf_size=...)` takes a runtime callback.
Define callbacks with explicit
capture lists (`{imm ...}` / `{mut ...}`), without `@parameter`.

## Tasks

```bash
pixi install --locked
pixi run build   # Precompile the library for local development
pixi run t       # All existing tests; also used by `hat test`
pixi run t-asan  # AddressSanitizer tests
pixi run rbuild  # Build a Conda archive in dist/ with pixi-build-mojo
pixi run rtest   # Build, install into a temporary consumer, run all tests
```

The consumer test copies only `tests/` outside the checkout, installs the exact
archive from `dist/`, and runs without `-I .` or a source import path. CI runs
source and installed-package tests on Linux x86-64, Linux ARM64, and macOS ARM64,
plus AddressSanitizer on Linux x86-64. Neither packaging task uploads a release.

`pixi.toml` defines the package build. `LICENSE` includes the applicable license texts;
see also `LICENSE-MIT`, `UNLICENSE`, and source attribution notices.

## Attribution

- File and Tensor code includes work from [MojoFastTrim](https://github.com/MoSafi2/MojoFastTrim/tree/restructed), maintained as [BlazeSeq](https://github.com/MoSafi2/BlazeSeq).
- Float formatting adapts Modular's text-layout code under Apache-2.0 with LLVM
  exceptions. Integer digit-pair formatting adapts Mojoverse's MIT-licensed
  BED coverage formatter. Source revisions and notices are in
  `extramojo/format/numbers.mojo` and `LICENSE`.
