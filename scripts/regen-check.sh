#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

GENERATED_FILES=(
  mojo_raylib/__init__.mojo
  mojo_raylib/types.mojo
  mojo_raylib/safe.mojo
  mojo_raylib/raymath_safe.mojo
  mojo_raylib/raw/__init__.mojo
  mojo_raylib/raw/types.mojo
  mojo_raylib/raw/raylib.mojo
  mojo_raylib/raw/raymath.mojo
  native/mojo_raylib_shim.c
)

for file in "${GENERATED_FILES[@]}"; do
  mkdir -p "$TMP_DIR/$(dirname "$file")"
  cp "$ROOT_DIR/$file" "$TMP_DIR/$file"
done

bash "$ROOT_DIR/scripts/generate-bindings.sh"

for file in "${GENERATED_FILES[@]}"; do
  diff -u "$TMP_DIR/$file" "$ROOT_DIR/$file"
done
