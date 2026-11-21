# mojo-io

Binary-safe buffered file I/O for Mojo 1.3.0.dev2026111705.
Package: `mojo-io`; import: `io`. Requires **mojo-bstr**.

[API reference](https://sstadick.github.io/mojoverse/mojo-io/io/_index.html)

## Install

Follow the [Mojoverse dependency setup](https://github.com/sstadick/mojoverse#use-a-dependency)
and add this Git dependency to your `pixi.toml`. Replace `<full-commit>` with a
Mojoverse commit and use the same revision for every Mojoverse dependency:

```toml
[dependencies]
mojo-io = { git = "https://github.com/sstadick/mojoverse.git", rev = "<full-commit>", subdirectory = "packages/mojo-io" }
```

Run `pixi install`, then `pixi run mojo run main.mojo`; no source `-I` path is
needed. Its bstr dependency resolves from the same Git revision.

## Read and write arbitrary bytes

```mojo {doctest="roundtrip" global=true}
from std.pathlib import Path
from std.tempfile import TemporaryDirectory
from std.testing import assert_equal
from io import BufferedReader, BufferedWriter

def main() raises:
    var directory = TemporaryDirectory()
    var path = String(Path(directory.name) / "records.bin")
    var bytes: List[UInt8] = [97, 0, 255, 13, 10, 116, 97, 105, 108]
    var writer = BufferedWriter(open(path, "w"), buffer_capacity=3)
    writer.write_bytes(Span(bytes))
    writer.close()

    var reader = BufferedReader(open(path, "r"), buffer_capacity=2)
    var first = reader.read_line()
    assert_equal(List(first.value()), [97, 0, 255])
    # Consume each borrowed line before the next read.
    var second = reader.read_line()
    assert_equal(List(second.value()), List("tail".as_bytes()))
    assert_equal(Bool(reader.read_line()), False)
    reader.close()
```

## Keep lines after closing the file

`read_lines` returns owned byte lists. Use it when the file fits in memory and
you need to retain its lines; use `BufferedReader` to process larger files
one borrowed line at a time. Empty lines and end-of-file are different.

```mojo {doctest="owned-lines" global=true}
from io import read_lines
from std.pathlib import Path
from std.tempfile import TemporaryDirectory
from std.testing import assert_equal

def main() raises:
    var directory = TemporaryDirectory()
    var path = String(Path(directory.name) / "names.txt")
    with open(path, "w") as file:
        file.write("alpha\r\n\nbeta")
    var saved = read_lines(path, buf_size=3)
    assert_equal(len(saved), 3)
    assert_equal(String(from_utf8=Span(saved[0])), "alpha")
    assert_equal(len(saved[1]), 0)
    assert_equal(String(from_utf8=Span(saved[2])), "beta")
```

## Contracts

- `BufferedReader` and `BufferedWriter` take ownership of a `FileHandle`.
  Buffer capacities must be positive; the default is 128 KiB.
- `read_line()` returns `Optional[Span[UInt8, ...]]`: `None` means EOF, while
  an empty span is a real empty line. LF and CRLF terminate lines; bare CR is
  data. There is no extra line after a final terminator. An unterminated tail,
  including a trailing CR, is returned.
- **A borrowed line is valid only until the next reader read, close, move,
  or destruction.** Copy with `List(line.value())` to retain it. Mojo 1.2's
  origin checker does not reject every invalidating mutation: this is a
  caller-enforced contract, not a static-safety guarantee.
- `read_until(destination, char=10)` appends bytes before the delimiter,
  consumes but excludes it, and returns bytes consumed **including** it.
  Existing destination bytes are neither cleared nor counted. Zero means EOF,
  so an empty terminated record returns one. Unlike `read_line`, it does not
  strip CR.
- `read_bytes(destination)` fills up to `len(destination)` and returns the
  number read. Pass a list or a mutable span, such as `Span(buffer)[16:32]`,
  to read into existing storage without allocating or resizing. A zero-length
  destination consumes nothing. Short underlying reads are not mistaken for
  EOF; the implementation does not seek.
- `read_lines(path, buf_size=...)` returns owned byte lists for all lines.
- `write_bytes` accepts arbitrary bytes; `write_string` accepts UTF-8 text.
  Both can raise I/O errors. `BufferedWriter` does not implement Mojo's
  non-raising `Writer` interface.
- **Call `close()` explicitly to observe write/flush errors.** Destruction
  attempts a flush but cannot report failures. A failed write poisons the
  writer to prevent duplicated output after partial writes. Closing releases
  the descriptor even after failure; repeated close is harmless. A flush
  writes to the OS; it is not an `fsync` durability guarantee.

## Develop

```sh
pixi run t
pixi run format
pixi run consumer
pixi run docs
```

Documentation uses this monorepo's root tools.
It runs the examples with the package's own locked compiler before producing
the site under `target/docs`.

MIT licensed; see [LICENSE](LICENSE) for ExtraMojo attribution.
