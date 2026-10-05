#!/bin/bash
# atlas-preview on small pages: a good page writes the 8 variant pictures and
# exits 0, a page that warns exits 1 (pictures and warnings written), a broken
# file and bad arguments exit 2.
#
#   run.sh <atlas-preview>
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bin=${1:?usage: run.sh <atlas-preview>}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "atlas-preview: $1" >&2; exit 1; }
# Nothing may reach the desktop: no display, and the tool's own offscreen platform.
unset DISPLAY WAYLAND_DISPLAY QT_QPA_PLATFORM
variants="light dark accent opaque rtl text200 compact contrast"

"$bin" "$here/good.qml" --out "$tmp/good" --size 480x320 >"$tmp/good.out" 2>"$tmp/good.err"
rc=$?
[ "$rc" -eq 0 ] || { cat "$tmp/good.err" "$tmp/good.out" >&2; fail "good.qml: exit $rc, wanted 0"; }
for v in $variants; do
    png="$tmp/good/good-$v.png"
    [ -s "$png" ] || fail "good.qml: no picture for $v"
    [ "$(head -c 4 "$png" | tail -c 3)" = PNG ] || fail "$png is not a PNG"
done
n=$(find "$tmp/good" -name '*.png' | wc -l)
[ "$n" -eq 8 ] || fail "good.qml: $n pictures, wanted 8"
[ ! -e "$tmp/good/good-warnings.txt" ] || fail "good.qml: warnings written for a clean page"
# The size is the picture's size, and the variants differ (a dark picture that
# looks like the light one would mean the scheme did not apply).
if command -v identify >/dev/null; then
    [ "$(identify -format '%wx%h' "$tmp/good/good-light.png")" = 480x320 ] || fail "good.qml: --size not applied"
fi
cmp -s "$tmp/good/good-light.png" "$tmp/good/good-dark.png" && fail "light and dark pictures are identical"
cmp -s "$tmp/good/good-light.png" "$tmp/good/good-rtl.png" && fail "light and rtl pictures are identical"
cmp -s "$tmp/good/good-light.png" "$tmp/good/good-contrast.png" && fail "light and contrast pictures are identical"

"$bin" "$here/warns.qml" --out "$tmp/warns" >"$tmp/warns.out" 2>"$tmp/warns.err"
rc=$?
[ "$rc" -eq 1 ] || { cat "$tmp/warns.err" >&2; fail "warns.qml: exit $rc, wanted 1"; }
grep -q 'missingValue' "$tmp/warns.err" || fail "warns.qml: the warning is not on stderr"
grep -q 'missingValue' "$tmp/warns/warns-warnings.txt" || fail "warns.qml: the warning is not in warns-warnings.txt"
n=$(find "$tmp/warns" -name '*.png' | wc -l)
[ "$n" -eq 8 ] || fail "warns.qml: $n pictures, wanted 8"

# A window as the root: grabbed as it is, with its own size.
cat >"$tmp/win.qml" <<'QML'
import QtQuick
import Atlas.Ui
AtlasWindow {
    width: 500
    height: 300
    visible: true
}
QML
"$bin" "$tmp/win.qml" --out "$tmp/win" >"$tmp/win.out" 2>"$tmp/win.err"
rc=$?
[ "$rc" -eq 0 ] || { cat "$tmp/win.err" >&2; fail "window root: exit $rc, wanted 0"; }
[ "$(find "$tmp/win" -name '*.png' | wc -l)" -eq 8 ] || fail "window root: not 8 pictures"
if command -v identify >/dev/null; then
    [ "$(identify -format '%wx%h' "$tmp/win/win-light.png")" = 500x300 ] || fail "window root: not its own size"
fi

expect2() { # expect2 <what> <args...>
    local what=$1
    shift
    "$bin" "$@" >"$tmp/e.out" 2>"$tmp/e.err"
    local rc=$?
    [ "$rc" -eq 2 ] || { cat "$tmp/e.err" >&2; fail "$what: exit $rc, wanted 2"; }
}
expect2 "broken file" "$here/broken.qml" --out "$tmp/broken"
grep -q 'broken.qml' "$tmp/e.err" || fail "broken file: the error does not name the file"
expect2 "missing file" "$tmp/nope.qml" --out "$tmp/x"
expect2 "not a qml file" "$here/run.sh" --out "$tmp/x"
expect2 "no --out" "$here/good.qml"
expect2 "no file"
expect2 "bad size" "$here/good.qml" --out "$tmp/x" --size 0x10
expect2 "bad size text" "$here/good.qml" --out "$tmp/x" --size big
expect2 "unknown option" "$here/good.qml" --out "$tmp/x" --nope
expect2 "size over 4096" "$here/good.qml" --out "$tmp/x" --size 5000x100
expect2 "internal mode without the parent's token" --internal-portal "$tmp/ready"
[ ! -e "$tmp/ready" ] || fail "an internal mode ran without the token"
# An output that is a symbolic link is refused, not written through.
mkdir "$tmp/link"
echo keep >"$tmp/target"
ln -s "$tmp/target" "$tmp/link/good-light.png"
expect2 "output is a symlink" "$here/good.qml" --out "$tmp/link" --size 200x100
[ "$(cat "$tmp/target")" = keep ] || fail "wrote through a symbolic link"
grep -q 'symbolic link' "$tmp/e.err" || fail "the symlink refusal is not explained"
# A new --out is private.
"$bin" "$here/good.qml" --out "$tmp/private" --size 200x100 >/dev/null 2>&1
[ "$(stat -c %a "$tmp/private")" = 700 ] || fail "a new --out directory is not mode 700"
echo "atlas-preview ok"
