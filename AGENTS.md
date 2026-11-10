# Mojoverse

- Read `.agents/skills/working-with-mojo/SKILL.md` before changing package conventions, templates, or Mojo examples. Load Modular's `mojo-syntax` skill before writing Mojo.
- This repository is a catalog and development toolkit, not a monorepo. Packages own their source, releases, compiler pins, and lockfiles. The root lockfile covers only this repository's Python tools.
- Keep public catalog links on moving branches. Distinguish existing public projects from work not yet published; do not publish private maintenance reports, local paths, or credentials here.
- Run `pixi run test` for documentation-tool changes. Tests execute real Mojo examples; do not replace them with mocked compiler success.
- Documentation must use the target package's locked compiler and dependencies. Do not let the tools environment silently select its own Mojo version.
- Existing ExtraMojo APIs remain in place during extraction. New packages live in their own repositories.
