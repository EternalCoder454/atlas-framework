#!/bin/bash
# Compares Atlas.Ui's API, as the built module exposes it, with the committed
# baseline in api/ (see docs/DESIGN.md, "Compatibility").
#
#   tools/check-api.sh [build-dir]      build-dir defaults to ./build and must be
#                                       configured with -DATLAS_UI_TESTS=ON
#
# - a line gone or changed:  "BREAKING: removed or renamed: ..."  (fails)
# - a line added:            "API grew: run tools/update-api.sh and raise the
#                             minor version"                        (fails)
# - api/ changed since the last v* tag while `Version:` in
#   packaging/atlas-framework.spec is not greater than that tag     (fails)
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build=${1:-$root/build}
dump=$build/apidump
if [ ! -x "$dump" ]; then
    echo "check-api: $dump not found: configure with -DATLAS_UI_TESTS=ON and build first" >&2
    exit 2
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
"$dump" "$build" "$tmp/atlas-ui.api" "$tmp/symbols.txt"

status=0
for name in atlas-ui.api symbols.txt; do
    if [ ! -f "$root/api/$name" ]; then
        echo "check-api: api/$name is missing: run tools/update-api.sh" >&2
        exit 2
    fi
    LC_ALL=C sort -u "$root/api/$name" >"$tmp/old"
    LC_ALL=C sort -u "$tmp/$name" >"$tmp/new"
    while IFS= read -r line; do
        echo "BREAKING: removed or renamed: $line   (api/$name)"
        status=1
    done < <(LC_ALL=C comm -23 "$tmp/old" "$tmp/new")
    while IFS= read -r line; do
        echo "API grew: run tools/update-api.sh and raise the minor version: $line   (api/$name)"
        status=1
    done < <(LC_ALL=C comm -13 "$tmp/old" "$tmp/new")
done

# The version rule: a change to api/ since the last release needs a new version.
tag=$(git -C "$root" describe --tags --match 'v*' --abbrev=0 2>/dev/null || true)
if [ -z "$tag" ]; then
    echo "notice: no v* tag yet, so the version check is skipped"
elif ! git -C "$root" diff --quiet "$tag" -- api; then
    spec_version=$(sed -n 's/^Version:[[:space:]]*//p' "$root/packaging/atlas-framework.spec" | head -n1)
    tag_version=${tag#v}
    newest=$(printf '%s\n%s\n' "$tag_version" "$spec_version" | sort -V | tail -n1)
    if [ -z "$spec_version" ] || [ "$spec_version" = "$tag_version" ] || [ "$newest" != "$spec_version" ]; then
        echo "api/ changed since $tag but Version: ${spec_version:-?} in packaging/atlas-framework.spec is not greater than $tag_version: raise it" >&2
        status=1
    fi
fi

if [ "$status" -eq 0 ]; then
    echo "check-api: the API matches api/"
fi
exit "$status"
