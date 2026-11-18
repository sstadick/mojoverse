---
name: updating-mojoverse-nightly
description: Updates Mojoverse's nightly compiler and repairs compatibility using existing Pixi tooling. Use when asked to update or repair the nightly branch.
---

# Update Mojoverse nightly

Minimize context, not verification. Run existing tools; read their implementation only when they fail. Save verbose output in ignored `.amp/in/` logs; inspect exit status and the first failure, not entire logs or lockfile diffs.

1. Record starting HEAD/compiler and CI status. Use a clean `nightly` worktree, reusing one if available. Fetch, fast-forward from `origin/nightly`, then merge `origin/main`, preserving nightly-only repairs. Keep stable pins on `main`. Resolve manifest/source conflicts; regenerate conflicting lockfiles. Read `docs/nightly.md` if present for known failures; repeat diagnosis only when evidence changes.
2. From the repo root, run `python3 scripts/toolchain.py update --channel nightly`, then `python3 scripts/toolchain.py check --lane nightly`. The updater selects a published Mojo/MAX pair across all platforms and updates every manifest/lock. Do not discover versions or edit pins individually. If the resulting tree is unchanged and no requested repair remains, report the existing CI result and stop.
3. After a compiler change, set `PIXI_CACHE_DIR` to a checkout-local, compiler-version-specific directory and reinstall the environments being tested. Same-version cached `.mojoc` packages can retain the old compiler.
4. Load `mojo-syntax` before source repairs. Fix one failure, rerun its targeted check, then run the complete checks in `AGENTS.md` and `.github/workflows/test.yml`, including source **and installed** packages. Keep `-O3`; debug/ASAN success does not excuse a release-build failure. Use native CI for other platforms when pushing is authorized.
5. Update the compatibility note from observed results. Leave unresolved failures enabled. Report compiler change, fixes, checks/blockers, and delivery state briefly. Do not dispatch the publishing workflow as a substitute for local checks.
