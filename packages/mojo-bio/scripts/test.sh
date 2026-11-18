#!/usr/bin/env bash
set -euo pipefail
features=()
# Keep test binaries compatible with CI hosts that do not expose AVX-512.
if [[ "$(uname -m)" == x86_64 ]]; then
    features=(--target-features=-avx512f,-avx512bw,-avx512cd,-avx512dq,-avx512vl,-avx512ifma,-avx512vbmi,-avx512vbmi2,-avx512vnni,-avx512bitalg,-avx512vpopcntdq,-avx512fp16,-avx512bf16)
fi
mkdir -p target
for test in tests/test_*.mojo; do
    binary="target/$(basename "$test" .mojo)"
    mojo build -O3 "${features[@]}" -D ASSERT=all -I src \
        -Xlinker "-L$CONDA_PREFIX/lib" -Xlinker -ldeflate -Xlinker -lz "$test" -o "$binary"
    "$binary"
done
