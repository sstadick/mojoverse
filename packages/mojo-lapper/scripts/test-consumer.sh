#!/usr/bin/env bash
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pixi build --path ../mojo-radix-sort --output-dir "$tmp/packages"
pixi build --path . --output-dir "$tmp/packages"
# Isolate extraction before the consumer installs same-version local archives.
export PIXI_CACHE_DIR="$tmp/consumer-cache"
pixi init "$tmp/consumer" -c https://conda.modular.com/max -c conda-forge
mojo_version=$(mojo --version | awk '{print $2}')
pixi add --manifest-path "$tmp/consumer/pixi.toml" "$tmp"/packages/*.conda "mojo=$mojo_version"
cp -R tests "$tmp/consumer/tests"

# No source checkout or -I flags: imports must resolve from the installed package.
unset MOJO_PATH MOJO_INCLUDE_PATH MODULAR_MOJO_IMPORT_PATH PIXI_PROJECT_MANIFEST PIXI_WORKSPACE_MANIFEST CONDA_PREFIX
count=0
while IFS= read -r file; do
    pixi run --manifest-path "$tmp/consumer/pixi.toml" mojo run -D ASSERT=all "$file"
    count=$((count + 1))
done < <(find "$tmp/consumer/tests" -name 'test_*.mojo' -type f | sort)
test "$count" -gt 0
