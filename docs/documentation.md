# Executable package documentation

## Build the complete site

From the repository root:

```sh
pixi run --locked -e docs docs-site
python3 -m http.server 8767 --directory target/docs
```

Open `http://localhost:8767/` to browse the documentation hub, package usage
guides, and Modo API references. The builder invokes each package's `docs`
task, runs its executable examples, and assembles the results in `target/docs`.
Failed builds leave the previous complete site intact. Package sites include
the original `mojo doc` JSON.

Seven packages have generated HTML references. The hub also links to
ExtraMojo's existing documentation and the mojopt/Raylib usage guides; those
are not presented as newly generated API references. To add a generated site,
give the package a `docs` task producing `target/docs`, add it to `PACKAGES`
in `scripts/build_docs.py`, and link it from `docs/index.md`.

## Build one package

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

## Publish with GitHub Pages

The `Documentation` workflow builds and archives the complete site on pull
requests and pushes to `main` or `nightly`. Only successful builds of `main`
can deploy, and only when Pages is configured to use GitHub Actions. Until
then, the workflow saves the documentation artifact and skips deployment.
Pull requests and nightly builds never replace the stable site. A manual
workflow run on `main` can rebuild it too.

For initial setup, a repository administrator must enable **Settings → Pages →
Build and deployment → Source: GitHub Actions**. The deployment job uses the
`github-pages` environment and narrowly scoped `pages: write` / `id-token: write`
permissions. The site address is `https://sstadick.github.io/mojoverse/`.
Local builds do not enable Pages or publish anything.
