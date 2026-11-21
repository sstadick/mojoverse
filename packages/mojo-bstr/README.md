# mojo-bstr

Arbitrary byte strings for Mojo 1.3.0.dev2026111705. The distribution is `mojo-bstr`; import
`bstr`. NUL and malformed UTF-8 are ordinary input bytes.

[API reference](https://sstadick.github.io/mojoverse/mojo-bstr/bstr/_index.html)

## Install with Pixi

Choose a commit from `main` for nightly Mojo or `stable/1.2` for Mojo 1.2.0.
Match the compiler pin and channel to that revision: `max-nightly` for
nightly, `max` for stable. Use one revision for all Mojoverse dependencies.

With [Pixi](https://pixi.prefix.dev/) 0.80 or newer, add to your `pixi.toml`.
Replace `<full-commit>` with a Mojoverse commit and use the same revision for
every Mojoverse dependency:

```toml
[workspace]
channels = ["https://conda.modular.com/max-nightly", "conda-forge"]
platforms = ["linux-64", "linux-aarch64", "osx-arm64"]
preview = ["pixi-build"]
requires-pixi = ">=0.80"

[dependencies]
mojo = "=1.3.0.dev2026111705"
mojo-bstr = { git = "https://github.com/sstadick/mojoverse.git", rev = "<full-commit>", subdirectory = "packages/mojo-bstr" }
```

Run `pixi install`, then `pixi run mojo run main.mojo`.
`pixi-build-mojo` installs the compiled module into the environment's `lib/mojo`
directory; no source `-I` path is needed.

## Use

```mojo {doctest="bytes" global=true}
from std.testing import assert_equal, assert_true
from bstr import memchr, lines, trim, to_str_lossy

def main() raises:
    var data: List[UInt8] = [32, 97, 0, 255, 13, 10, 98]
    assert_equal(memchr(0, Span(data)), 2)
    var sizes = List[Int]()
    for line in lines(Span(data)):
        sizes.append(len(trim(line)))
    assert_equal(sizes, [3, 1])
    var valid = to_str_lossy(Span(data))
    var expected = String(" a\0�\r\nb")
    assert_true(Span(valid) == expected.as_bytes())
```

Use `Span(buffer)` for a `List[UInt8]` or `Array[UInt8, N]`, and
`text.as_bytes()` for a Mojo `String`. No wrapper allocation is required.
Read-only functions accept immutable spans (mutable spans coerce). Mutation
functions require mutable spans. Owned transformations return `List[UInt8]`.

**Views and searchers borrow their source. Keep the owner alive and unchanged
while using them.** Origins reject returning a view of destroyed local storage,
but Mojo 1.2 does **not** reject every invalidating mutation: `List.append` can
reallocate underneath a live `Span`. This is a verified compiler/stdlib safety
limitation, not a supported use. Make an owned copy when mutation or a longer
lifetime is needed. `_into` functions append without clearing; their output
must not alias an input view.

## Reuse a searcher across records

A `Finder` prepares one needle and borrows its bytes. The records may change
between calls, but the needle must stay alive and unchanged.

```mojo {doctest="prepared-search" global=true}
from bstr import finder
from std.testing import assert_equal

def main() raises:
    var needle = String("ERROR")
    var search = finder(needle.as_bytes())
    assert_equal(search.find("WARN: retry".as_bytes()), -1)
    assert_equal(search.find("id=7 ERROR: timeout".as_bytes()), 5)
    assert_equal(search.find("ERROR".as_bytes()), 0)
```

## Split binary fields without copying

Each part is a borrowed span, not a new string. Copy a part with `List(part)`
only when it must outlive the original bytes.

```mojo {doctest="binary-fields" global=true}
from bstr import split_str
from std.testing import assert_equal

def main() raises:
    var record: List[UInt8] = [65, 0, 9, 255, 9, 90]
    var fields = List[List[UInt8]]()
    for part in split_str(Span(record), "\t".as_bytes()):
        fields.append(List(part))
    assert_equal(fields[0], [65, 0])
    assert_equal(fields[1], [255])
    assert_equal(fields[2], [90])
```

## API contracts

The API covers searching, splitting, byte transforms, and UTF-8 decoding.

| Area | Public API |
| --- | --- |
| Equality | `equal` |
| Substrings | `find`, `rfind`, `Finder`, `FinderReverse`, `finder`, `finder_reverse`, `contains_str`, `starts_with_str`, `ends_with_str` |
| Bytes | `find_byte`, `rfind_byte`, `find_byteset`, `rfind_byteset`, `find_not_byteset`, `rfind_not_byteset`, `find_char`, `rfind_char` |
| Memchr additions | `memchr`, `memrchr`, `memchr2`, `memrchr2`, `memchr3`, `memrchr3` |
| Streaming matches/splits | `find_iter`, `rfind_iter`, `split_str`, `rsplit_str`, `splitn_str`, `rsplitn_str`, `split_once_str`, `rsplit_once_str` |
| Owned output | `replace`, `replacen`, `replace_into`, `replacen_into`, `repeatn` |
| Lines/fields/trim | `lines`, `lines_with_terminator`, `fields`, `fields_with`, `trim`, `trim_start`, `trim_end`, `trim_with`, `trim_start_with`, `trim_end_with`, `is_whitespace` |
| UTF-8 | `decode_utf8`, `decode_last_utf8`, `decode_utf8_lossy`, `decode_last_utf8_lossy`, `validate_utf8`, `is_utf8`, `chars`, `char_indices`, `utf8_chunks`, `to_str_lossy`, `to_str_lossy_into` |
| Byte transforms | `is_ascii`, `find_non_ascii_byte`, `to_ascii_lowercase`, `to_ascii_uppercase`, `make_ascii_lowercase`, `make_ascii_uppercase`, `reverse_bytes`, `reverse_chars`, `escape_bytes`, `unescape_bytes` |

- `equal(a, b)` compares lengths and bytes without allocating or reading outside
  either span. Two empty spans compare equal; a matching prefix alone does not.
- Search returns a byte offset or **-1**. `memchr*` takes
  needle byte(s) before the haystack; other searches take haystack first.
  Prepared searchers expose `needle()` for inspection; construct a new searcher
  to change its needle.
- Empty substring needles match all byte boundaries, including both ends and
  boundaries *inside* UTF-8 encodings. Matches never overlap; reverse matches
  may select different positions from forward matches.
- Streaming iterators work with
  `for`, `break`, and `__next__()`. Calling `__iter__()` copies the current
  cursor; `__next__()` advances the iterator itself. Fields accepts copyable
  non-raising predicates (including closures) and supports structural `for`
  iteration; unlike other iterators it cannot currently conform to Mojo 1.2's
  non-capturing `Iterator` trait for arbitrary captured predicates.
- `split_once_str`/`rsplit_once_str` return `Optional[Tuple[Span, Span]]`.
  Limited splits take `(s, needle, n)`.
- Negative split/replacement/repeat limits and non-scalar `find_char` arguments
  raise `Error`, including release builds. Zero limits yield no split pieces,
  unchanged replacement output, or an empty repetition.
- Lines strip LF and a directly preceding CR; bare CR is data. A final LF
  does not create an extra empty line. Empty input yields no lines.
- Malformed UTF-8 consumes maximal subparts and decodes to U+FFFD.
  `decode_utf8` returns `(scalar, consumed, valid)`, and `validate_utf8` returns
  `(valid_up_to, error_len)` with 0 for success and -1 for truncation.
- `to_str_lossy` returns **owned valid UTF-8 bytes**, not `String`.
  `find_char` searches encoded scalars and does not
  interpret malformed bytes as U+FFFD. `reverse_chars` preserves bytes within
  each decoded scalar or malformed subpart; it is not grapheme reversal.
- Trimming/fields use Unicode White_Space. ASCII casing never changes bytes
  outside A–Z/a–z. Escaping retains valid non-ASCII UTF-8, escapes ASCII space,
  and uses uppercase hex for invalid bytes. Unknown/incomplete escapes remain
  literal, including bytes consumed while attempting a hex escape.

## Verify

```sh
pixi run t             # Hat-compatible test_*.mojo discovery, assertions enabled
pixi run examples      # Executable example
pixi run consumer      # Fresh consumer install and execution, without -I
pixi run differential # Requires Cargo; 71,784 cases against bstr 1.13.1
pixi run ownership    # Compile-fail origin safety checks
pixi run doc-examples # Execute marked README examples
pixi run docs         # API site, using this monorepo's root tools
pixi run bench-verify # Untimed benchmark protocol checks
```

## Attribution

MIT licensed; see [LICENSE](LICENSE) and [NOTICE](NOTICE). API semantics, UTF-8
algorithms, tests, and benchmark methodology derive from Seth Stadick's goostr
and Andrew Gallant's bstr/memchr.
