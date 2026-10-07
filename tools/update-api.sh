#!/bin/bash
# Rewrites the API baseline in api/ from the built module. Run it when the API
# grew on purpose, raise the minor version in packaging/telamon-framework.spec,
# and commit api/ with the change so a reviewer sees what was added.
#
#   tools/update-api.sh [build-dir]
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build=${1:-$root/build}
if [ ! -x "$build/apidump" ]; then
    echo "update-api: $build/apidump not found: configure with -DTELAMON_UI_TESTS=ON and build first" >&2
    exit 2
fi
mkdir -p "$root/api"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
"$build/apidump" "$build" "$tmp/telamon-ui.api" "$tmp/symbols.txt"
# Same directory, then rename: a crash never leaves half a baseline.
for name in telamon-ui.api symbols.txt; do
    cp "$tmp/$name" "$root/api/.$name.new"
    mv "$root/api/.$name.new" "$root/api/$name"
done
echo "update-api: wrote api/telamon-ui.api and api/symbols.txt"
