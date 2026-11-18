# Executable package documentation

Run the tools from the Mojoverse root. The `docs` environment installs the Python documentation tools and Modo's bundled executable. It supports Linux x86-64 and macOS (with Rosetta), not Linux AArch64; this restriction does not apply to the Mojo libraries or bins:

```sh
pixi run --locked -e docs docs packages/mojo-bstr mojo_bstr --site --readme README.md
```

The output is `PACKAGE/target/docs`. Without `--site`, it is plain Markdown. Add `--readme README.md` to render the README and test its marked examples too. The project must already have a current `pixi.lock`; the documentation command intentionally uses `pixi run --locked`.

The compiler itself emits JSON, not HTML. To inspect that directly:

```sh
pixi run --locked mojo doc packages/mojo-threads/mojo_threads -o threads-api.json
```

The site builder also preserves this JSON as `target/docs/IMPORT_NAME.json`.
For native libraries, use the package's `pixi run docs` task, which supplies its
link dependencies. From the root, the equivalent thread-library command is:

```sh
pixi run --locked -e docs docs packages/mojo-threads mojo_threads \
  --site --readme README.md --link-library mojo_threads_native --link-library pthread
```

`--link-library` is repeatable and searches the documented package's installed
prefix, not the documentation tool's environment. It also accepts an absolute
static archive path. Examples are compiled with `-O3` and assertions, then run;
this supports static FFI libraries that cannot be resolved by Mojo's JIT.
The docs task does not upload the generated pages.

Modo consumes `mojo doc` JSON. Write functions and types in modules and re-export them from `__init__.mojo`. Use `[mojo_topic.module.Type]` for Modo cross-references. Do not use backticks around these links. Broken cross-references fail the strict build.

Mark executable source-docstring and Markdown examples with a unique doctest name. A complete program uses `global=true`:

````markdown
```mojo {doctest="example" global=true}
from std.testing import assert_equal
from mojo_topic.lib import pull_rabbit

def main() raises:
    assert_equal(pull_rabbit(), "🐇")
```
````

For fragments, omit `global=true`: the tools wrap the body in `def main() raises:`. Imports can be in a separate block with the same doctest name and `global=true`. Do not combine an explicit `main` with a body fragment in one doctest.

The build requires at least one doctest and runs every extracted program with assertions enabled in a temporary directory. Exceptions and failed assertions fail the command before replacing the previous generated site. Examples that write files must use relative paths or temporary directories. Compilation alone is not an example test.

The tools pin Modo 0.11.13 and override its callable signature, struct signature, and doctest templates for current Mojo. Do not remove these overrides without checking rendered signatures and executing the examples on stable and nightly. The stock templates still use `fn` and emit `fn def` for current compiler JSON.

CI should build/test docs on pull requests, archive the generated site, and publish only the stable main build to GitHub Pages. A nightly build should validate compatibility without replacing stable docs. Publishing requires the repository's Pages setup and authorization; generating HTML does not deploy it.
