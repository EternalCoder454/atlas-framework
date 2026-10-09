#!/bin/bash
# The local check, run from the host in the dev container, as fast as it
# goes: an incremental build, qmllint, every test in parallel, the API check,
# the gallery lint, the docs check and the bundle tools' test. Stops at the first step that fails.
# It does not run the Rust crates: use the `cargo test` line in CLAUDE.md for
# those. A second run in the same checkout waits for no one: it fails at once
# while the first holds the build directory.
#
#   tools/dev-check.sh                   everything
#   tools/dev-check.sh TelamonFoo Bar      the visual, a11y and i18n tests only
#                                        for these demos (the rest still runs)
#   tools/dev-check.sh --translations    first rewrite ui/translations/telamon-ui.ts
#
# TELAMON_DEV_BUILD_DIR is the build directory on the host, an absolute path (default: one per
# checkout under ~/.cache/telamon-framework-dev, so worktrees don't share one).
# TELAMON_DEV_JOBS caps the build and test jobs (default: every CPU), for several runs at once.
# TELAMON_UPDATE_GOLDENS=1 rewrites the goldens that fail (look at each changed PNG before committing).
# TELAMON_DEV_IMAGE is the container (default localhost/telamon-framework-dev:44,
# built from packaging/Containerfile.dev).
set -euo pipefail

jobs=${TELAMON_DEV_JOBS:-}
if [ -n "$jobs" ] && ! [[ $jobs =~ ^[1-9][0-9]*$ ]]; then
    echo "dev-check: TELAMON_DEV_JOBS must be a positive number: $jobs" >&2
    exit 1
fi

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
key=$(printf '%s' "$root" | cksum | cut -d' ' -f1)
build=${TELAMON_DEV_BUILD_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/telamon-framework-dev/$(basename "$root" | tr -c 'A-Za-z0-9_.\n-' '_')-$key}
image=${TELAMON_DEV_IMAGE:-localhost/telamon-framework-dev:44}
# podman reads "-v src:dst:opts" by splitting on ":" and ",": a path holding
# either could add mount options.
for p in "$root" "$build"; do
    case $p in
    *[:,]*)
        echo "dev-check: ':' and ',' are not allowed in $p (podman would read them as mount options)" >&2
        exit 2
        ;;
    esac
done
# An image name that starts with a dash would be read by podman as an option.
case $image in
-*)
    echo "dev-check: TELAMON_DEV_IMAGE must be an image name, not an option: $image" >&2
    exit 2
    ;;
esac
# A relative path would be read by podman as a named volume.
case $build in
/*) ;;
*)
    echo "dev-check: TELAMON_DEV_BUILD_DIR must be an absolute path: $build" >&2
    exit 2
    ;;
esac

translations=0
demos=()
for arg in "$@"; do
    case $arg in
    --translations) translations=1 ;;
    -h | --help)
        sed -n '2,20p' "$0"
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
        if [ ! -f "$root/ui/gallery/demos/${arg}Demo.qml" ]; then
            echo "dev-check: no demo for $arg (ui/gallery/demos/${arg}Demo.qml does not exist)" >&2
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
# One run at a time per build directory: two ninja/ctest runs would corrupt
# each other's build and test output. Held until this script exits.
exec 9>"$build/.dev-check.lock"
if ! flock -n 9; then
    echo "dev-check: another dev-check is using $build; wait for it, or set TELAMON_DEV_BUILD_DIR for a separate build" >&2
    exit 2
fi
# In a git worktree, .git is a file naming the main repository's git
# directory: mount that too (read-only, same path), or the API check can't
# read the tags.
gitmount=()
if [ -f "$root/.git" ]; then
    common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)
    gitmount=(-v "$common:$common:ro")
fi
# The source is read-only unless the translations or the goldens are being
# rewritten.
mode=ro
[ "$translations" = 1 ] && mode=rw
[ -n "${TELAMON_UPDATE_GOLDENS:-}" ] && mode=rw
# --init reaps ninja and ctest children and forwards Ctrl-C; --name makes a
# stray container easy to find (podman ps --filter name=telamon-dev-check).
rc=0
podman run --rm --init --name "telamon-dev-check-$key-$$" --ulimit core=0 --security-opt label=disable --security-opt no-new-privileges \
    -v "$root:/src:$mode" -v "$build:/b" "${gitmount[@]}" -w /src \
    -e PYTHONDONTWRITEBYTECODE=1 -e TELAMON_DEMO_FILTER="$filter" -e TRANSLATIONS="$translations" \
    -e JOBS="$jobs" -e CMAKE_BUILD_PARALLEL_LEVEL="$jobs" -e TELAMON_UPDATE_GOLDENS="${TELAMON_UPDATE_GOLDENS:-}" \
    "$image" bash -euo pipefail -c '
step() { printf "\n== %s\n" "$1"; }
[ -f /b/build/build.ninja ] || cmake -S /src -B /b/build -G Ninja -DTELAMON_UI_TESTS=ON >/dev/null
if [ "$TRANSLATIONS" = 1 ]; then
    step translations
    cmake --build /b/build --target telamon-ui_update_translations | { grep -E "Found|Updating" || true; }
fi
step build
cmake --build /b/build >/b/build.log 2>&1 || {
    # The failing commands and their first errors, not only the last line.
    grep -A14 "^FAILED" /b/build.log || tail -n 40 /b/build.log
    exit 1
}
tail -n 1 /b/build.log
step qmllint
cmake --build /b/build --target all_qmllint >/b/qmllint.log 2>&1 || {
    # An Error (a duplicate id, a syntax error) stops the target: show those.
    grep -A2 "^Error" /b/qmllint.log || tail -n 40 /b/qmllint.log
    exit 1
}
# The same exact budget as CI: over it fails at the end, so the tests still run.
lintn=$(grep -c "^Warning" /b/qmllint.log || true)
lintmax=$(sed -n "s/^ *QMLLINT_MAX: *\([0-9]*\).*/\1/p" .github/workflows/ci.yml | head -n 1)
lintbad=
if [ -n "$lintmax" ] && [ "$lintn" -ne "$lintmax" ]; then
    lintbad="qmllint has $lintn warnings, CI expects exactly $lintmax (QMLLINT_MAX in .github/workflows/ci.yml): fix the new ones, or lower the budget when there are fewer"
    echo "$lintbad"
else
    echo "ok ($lintn warnings, /b/qmllint.log)"
fi
step tests
rm -rf /b/build/visual-out
[ -z "$TELAMON_DEMO_FILTER" ] || echo "demos: $TELAMON_DEMO_FILTER"
ctest --test-dir /b/build -j "${JOBS:-$(nproc)}" --output-on-failure >/b/ctest.log 2>&1 || { grep -E "FAIL!|Failed|tests passed" /b/ctest.log; exit 1; }
grep "tests passed" /b/ctest.log
step api
tools/check-api.sh /b/build
step lint
# Strict and with the template, as CI runs it: warnings fail too.
if ! { tools/lint-app.sh --strict ui/gallery template && tools/check-app-names.sh template; } >/b/lint.log 2>&1; then
    grep -E ": (error|warning): |^lint-app: |clash" /b/lint.log || cat /b/lint.log
    exit 1
fi
tail -n 1 /b/lint.log
step docs
python3 tools/test_docs.py 2>&1 | tail -n 3
python3 tools/docs.py check
step bundles
tools/test-make-bundle.sh >/b/bundles.log 2>&1 || { grep -E "^FAIL|^     [|]" /b/bundles.log || tail -n 30 /b/bundles.log; exit 1; }
tail -n 1 /b/bundles.log
if [ -n "$lintbad" ]; then
    echo "$lintbad" >&2
    exit 1
fi
' || rc=$?
if [ "$rc" -ne 0 ] && grep -qE "FAIL|Failed" "$build/ctest.log" 2>/dev/null; then
    echo "dev-check: pictures of the failed tests are in $build/build/visual-out; the log is $build/ctest.log" >&2
fi
exit "$rc"
