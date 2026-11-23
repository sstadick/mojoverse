---
name: updating-mojoverse-nightly
description: Updates Mojoverse's nightly compiler and repairs compatibility on main using existing Pixi tooling. Use when asked to update the nightly compiler or repair nightly compatibility; stable releases live on versioned stable branches.
---

# Update Mojoverse nightly

Minimize context, not verification. Run existing tools; read their implementation only when they fail. Save verbose output in ignored `.amp/in/` logs; inspect exit status and the first failure, not entire logs or lockfile diffs.

`main` is the nightly development branch. Stable Mojo releases use versioned branches such as `stable/1.2`; preserve their compiler pins and backport fixes deliberately. The legacy `nightly` branch is retained for existing references and is no longer maintained. Do not rebase stable branches after pushes to `main` or synchronize a separate nightly branch.

1. Record starting HEAD/compiler and CI status. Use a clean `main` worktree, reusing one if available. Fetch and fast-forward from `origin/main`, preserving existing compatibility repairs. Keep stable branches unchanged. Read `docs/nightly.md` if present for known failures; repeat diagnosis only when evidence changes.
2. From the repo root, run `python3 scripts/toolchain.py update --channel nightly`, then `python3 scripts/toolchain.py check --lane nightly`. The updater selects a published Mojo/MAX pair across all platforms and updates every manifest/lock. Do not discover versions or edit pins individually. If the resulting tree is unchanged and no requested repair remains, report the existing CI result and stop.
3. After a compiler change, set `PIXI_CACHE_DIR` to a checkout-local, compiler-version-specific directory and reinstall the environments being tested. Same-version cached `.mojoc` packages can retain the old compiler.
4. Load `mojo-syntax` before source repairs. Fix one failure, rerun its targeted check, then run the complete checks in `AGENTS.md` and `.github/workflows/test.yml`, including source **and installed** packages. Keep `-O3`; debug/ASAN success does not excuse a release-build failure. Use native CI for other platforms when pushing is authorized.
5. Update the compatibility note from observed results and align documented compiler requirements and installation snippets with the package pins. Leave unresolved failures enabled. Push validated updates to `main` when authorized; use normal fast-forward pushes and reconcile remote advances. Report compiler change, fixes, checks/blockers, and delivery state briefly. Do not dispatch the publishing workflow as a substitute for local checks.
6. After a push, verify the annotated `nightly-YYYY-MM-DD-<short-sha>` tag on the tested commit. Actions creates it after workspace and documentation checks pass, including for the manual updater. Report the tag consumers can pin. When shipping a public package API change, bump the affected package version and refresh its locks. Stable GitHub Releases are deliberate selections from a versioned stable branch. See [Release tags](../../../docs/development.md#release-tags).
