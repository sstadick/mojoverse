#!/usr/bin/env bash
# Publish an annotated snapshot of a commit that has already passed CI.
set -euo pipefail

revision=$(git rev-parse --verify "${1:?expected a verified revision}^{commit}")
day=$(TZ=UTC git show -s --date=format-local:%Y-%m-%d --format=%cd "$revision")
tag="nightly-$day-${revision:0:7}"
ref="refs/tags/$tag"

remote_target() {
    # The peeled entry sorts last for an annotated tag.
    git ls-remote --sort=refname origin "$ref" "$ref^{}" | tail -n 1 | cut -f1
}

check_target() {
    if [[ $1 != "$revision" ]]; then
        echo "$tag already points to $1, expected $revision" >&2
        exit 1
    fi
}

target=$(remote_target)
if [[ -n $target ]]; then
    check_target "$target"
else
    if git show-ref --verify --quiet "$ref"; then
        check_target "$(git rev-parse "$ref^{commit}")"
        test "$(git cat-file -t "$ref")" = tag
    else
        git tag -a "$tag" "$revision" -m "Mojoverse nightly snapshot of $revision"
    fi
    # Another run may have published the same tag between lookup and push.
    if ! git push origin "$ref:$ref"; then
        check_target "$(remote_target)"
    fi
fi
echo "$tag -> $revision"
