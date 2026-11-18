#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/bin"

"${CC:-clang}" -O3 -march=native -Wall -Wextra \
  -o "$ROOT_DIR/build/bin/rlparser" \
  "$ROOT_DIR/patch/rlparser.c"
