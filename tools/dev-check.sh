#!/bin/bash
# The local check, run from the host in the dev container, as fast as it
# goes: an incremental build, qmllint, every test in parallel, the API check,
# the gallery lint and the docs check. Stops at the first step that fails.
#
#   tools/dev-check.sh                   everything
#   tools/dev-check.sh AtlasFoo Bar      the visual, a11y and i18n tests only
#                                        for these demos (the rest still runs)
#   tools/dev-check.sh --translations    first rewrite ui/translations/atlas-ui.ts
#
# ATLAS_DEV_BUILD_DIR is the build directory on the host (default: one per
# checkout under ~/.cache/atlas-framework-dev, so worktrees don't share one).
# ATLAS_DEV_IMAGE is the container (default localhost/atlas-framework-dev:44,
# built from packaging/Containerfile.dev).
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
key=$(printf '%s' "$root" | cksum | cut -d' ' -f1)
build=${ATLAS_DEV_BUILD_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/atlas-framework-dev/$(basename "$root" | tr -c 'A-Za-z0-9_.\n-' '_')-$key}
image=${ATLAS_DEV_IMAGE:-localhost/atlas-framework-dev:44}

translations=0
demos=()
for arg in "$@"; do
    case $arg in
    --translations) translations=1 ;;
    -h | --help)
        sed -n '2,15p' "$0"
        exit 0
        ;;
    -*)
        echo "dev-check: unknown option $arg" >&2
        exit 2
        ;;
    *)
        if [[ ! $arg =~ ^[A-Za-z][A-Za-z0-9]*$ ]]; then
            echo "dev-check: not a type name: $arg" >&2
            exit 2
        fi
        demos+=("$arg")
        ;;
    esac
done
filter=""
if [ ${#demos[@]} -gt 0 ]; then
    filter="^($(IFS='|'; echo "${demos[*]}"))\$"
fi

mkdir -p "$build"
# In a git worktree, .git is a file naming the main repository's git
# directory: mount that too (read-only, same path), or the API check can't
# read the tags.
gitmount=()
if [ -f "$root/.git" ]; then
    common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)
    gitmount=(-v "$common:$common:ro")
fi
# The source is read-only unless the translations are being rewritten.
mode=ro
[ "$translations" = 1 ] && mode=rw
exec podman run --rm --security-opt label=disable \
    -v "$root:/src:$mode" -v "$build:/b" "${gitmount[@]}" -w /src \
    -e ATLAS_DEMO_FILTER="$filter" -e TRANSLATIONS="$translations" \
    "$image" bash -euo pipefail -c '
step() { printf "\n== %s\n" "$1"; }
[ -f /b/build/build.ninja ] || cmake -S /src -B /b/build -G Ninja -DATLAS_UI_TESTS=ON >/dev/null
if [ "$TRANSLATIONS" = 1 ]; then
    step translations
    cmake --build /b/build --target atlas-ui_update_translations | grep -E "Found|Updating"
fi
step build
cmake --build /b/build | tail -n 1
step qmllint
cmake --build /b/build --target all_qmllint >/b/qmllint.log 2>&1 || { tail -n 40 /b/qmllint.log; exit 1; }
echo "ok ($(grep -c "^Warning" /b/qmllint.log || true) warnings, /b/qmllint.log)"
step tests
[ -z "$ATLAS_DEMO_FILTER" ] || echo "demos: $ATLAS_DEMO_FILTER"
ctest --test-dir /b/build -j "$(nproc)" --output-on-failure >/b/ctest.log 2>&1 || { grep -E "FAIL!|Failed|tests passed" /b/ctest.log; exit 1; }
grep "tests passed" /b/ctest.log
step api
tools/check-api.sh /b/build
step lint
tools/lint-app.sh ui/gallery | tail -n 1
step docs
python3 tools/docs.py check
'
