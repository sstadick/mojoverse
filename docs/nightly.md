# Nightly compatibility

`main` follows published Mojo nightlies; versioned branches such as `stable/1.2` retain stable compiler support. The legacy `nightly` branch is retained as a snapshot; use `main` for ongoing development. Updates are manual: use the [nightly maintenance skill](../.agents/skills/updating-mojoverse-nightly/SKILL.md) to update compiler pins and lockfiles together and check compatibility. An update does not imply that CI passed. Pin a tested commit rather than depending on a moving branch.

## November 21, 2026: synchronize current package APIs

Rebased onto `main` at `5e0b4bd`, retaining Mojo `1.3.0.dev2026111705` and MAX `26.8.0.dev2026111705`. Packages now expose the current unprefixed modules, including `bstr`, `io`, `bio`, and `radix_sort`.

On Linux x86-64, the source and installed suites still reproduce the ExtraMojo iterator crash documented below, and ASAN still reports the same buffer error. The other 15 library test programs pass in both modes, along with bin, documentation-tool, graphics, LSP, and lockfile checks. A fresh Git consumer, 31 executable documentation examples, bstr ownership/differential/benchmark-correctness checks, Raylib regeneration/documentation, native LSP integration, and both Zed WebAssembly builds pass. The full suite remains failing; the iterator test is enabled and optimization settings are unchanged.

Lapper's GPU benchmark callbacks now use the concrete context type required by nightly MAX. CPU and NVIDIA `sm_80` benchmark compilation passes; GPU execution and performance were not tested.

## November 18, 2026: optimized iterator failure

Mojo `1.3.0.dev2026111705` with MAX `26.8.0.dev2026111705` compiles the workspace, but ExtraMojo's existing `tests/test_file.mojo` crashes in `test_delim_reader_writer` at `-O3`. The test remains enabled and blocks a green nightly suite:

```sh
pixi run --locked -e source test-packages extramojo
```

On Linux x86-64, full-debug probes and some AddressSanitizer configurations pass. However, the package's `t-asan` task reports a heap-buffer-overflow in this same iterator: an atomic reference-count decrement writes before the line buffer's allocation. GDB locates the normal optimized crash in destruction of the optional stack trace inside `Error`, with an invalid pointer. The passing probes do not establish correctness; no optimization flag or assertion has been disabled to hide the failing configurations.

The following stdlib-only reduction also crashes at `-O3` with this nightly, with or without `-D ASSERT=all`. It passes with Mojo 1.2.0 at `-O3`, and with the nightly at `-O0` or `-O3 --debug-level=full`. This points to a nightly compiler/API compatibility problem in legacy `Error`-raising iterators, not the BAM reader, native bindings, or monorepo dependency paths. The precise compiler defect is not established. A migration to the current `StopIteration` protocol also needs an explicit design for propagating parsing and I/O errors.

```mojo
from std.testing import assert_equal

@fieldwise_init
struct Row(Copyable, Movable):
    var index: Int
    var name: String

struct Rows(Movable):
    var next_elem: Optional[Row]
    var index: Int

    def __init__(out self):
        self.index = 0
        self.next_elem = Row(0, "MyNameIs0")

    def __has_next__(self) -> Bool:
        return Bool(self.next_elem)

    def __iter__(var self) -> Self:
        return self^

    def __next__(mut self) raises -> Row:
        if not self.next_elem:
            raise Error("past end")
        var row = self.next_elem.take()
        self.index += 1
        if self.index < 1000:
            self.next_elem = Row(self.index, "MyNameIs" + String(self.index))
        else:
            self.next_elem = None
        return row^

def main() raises:
    var rows = Rows()
    var index = 0
    for row in rows^:
        assert_equal(row.index, index)
        assert_equal(row.name, "MyNameIs" + String(index))
        index += 1
    assert_equal(index, 1000)
    print("PASS")
```

The compatibility work also retains the tuple-movability fix and nested-container tests from [mojopt's prior nightly](https://github.com/sstadick/mojopt/commit/e7c5586aaad7ff345679fe7a8f6406aa8dab80c9), and allocation, hash import and file-close repairs from [ExtraMojo's prior nightly](https://github.com/ExtraMojo/ExtraMojo/commit/397aa784169e7987ecae0d7d3ec52f52d424668a). Those branches targeted November 11; they are useful source history, not evidence that the November 17 compiler passes.
