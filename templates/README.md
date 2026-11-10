# Hat library + Mojoverse documentation

Hat owns the library layout, compiler setup, build configuration, and tests.
This overlay adds executable docs and a read-only documentation CI workflow.
It never overwrites existing files or a `docs` task.

From a Mojoverse checkout, with Hat installed:

```sh
hat new --lib --name mojo-example --location ..
python3 scripts/apply_template.py ../mojo-example mojo_example
pixi run --manifest-path ../mojo-example/pixi.toml t
pixi run --manifest-path ../mojo-example/pixi.toml docs
```

Hat generates projects using its supported stable compiler. Check the generated
pins before starting; a compiler upgrade must align development, build, host,
runtime dependencies, and the lockfile. Use `hat new --nightly` only for the
nightly lane. Do not repin stable main to nightly to make a test pass.

The example asserts Hat's `pull_rabbit()` result; replace it with the package's
real public API. Add tests before adding features. `pixi build` must produce an
installable artifact, and a clean consumer must import it without `-I` pointing
at the source checkout.

Documentation defaults to a sibling Mojoverse checkout; set `MOJOVERSE` when it
lives elsewhere. CI checks out the tools separately, tests docs with the
package's locked compiler, and saves `target/docs` as an artifact. The template
requires the Mojoverse repository to be published before remote CI can use it.
Pin a reviewed tools revision when releasing a package.

The workflow deliberately does not deploy. After Pages is configured, the
reviewed stable-main artifact can be published through GitHub Pages; nightly
validation must not overwrite stable documentation.
