#!/bin/bash
# lint-app.sh's deprecation and replacement rules on tests/lint/banner.qml:
# the lines marked `// WANT` get one warning each, nothing else is reported,
# and the `atlas-lint: allow` twins are silent.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=$(ATLAS_LINT_DEPRECATED="$here/deprecated.txt" "$here/../../tools/lint-app.sh" "$here")
want=$(grep -n '// WANT$' "$here/banner.qml" | cut -d: -f1)
got=$(sed -nE 's|^.*/banner\.qml:([0-9]+): warning: .*$|\1|p' <<<"$out")
n=$(wc -l <<<"$want")
if [ "$got" != "$want" ] || ! grep -q "^lint-app: 0 error(s), $n warning(s)\$" <<<"$out"; then
    echo "lint rules: unexpected findings" >&2
    printf -- '--- wanted lines\n%s\n--- got\n%s\n' "$want" "$out" >&2
    exit 1
fi
echo "lint rules ok ($n findings)"

# Error paths and false-pass cases, on throwaway apps.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
lint="$here/../../tools/lint-app.sh"
fail() { echo "lint rules: $1" >&2; exit 1; }
expect() { # expect <exit code> <description> <args...>
    local want=$1 what=$2
    shift 2
    "$lint" "$@" >"$tmp/out" 2>&1
    local rc=$?
    [ "$rc" -eq "$want" ] || { cat "$tmp/out" >&2; fail "$what: exit $rc, wanted $want"; }
}
expect 2 "missing directory" "$tmp/nope"
expect 2 "no arguments"
mkdir "$tmp/empty"
expect 1 "no QML files" "$tmp/empty"
expect 0 "no QML files with --allow-empty" --allow-empty "$tmp/empty"
mkdir "$tmp/pruned" "$tmp/pruned/build" "$tmp/pruned/buildings"
printf 'import QtQuick.Controls\nButton {}\n' >"$tmp/pruned/build/A.qml"
expect 1 "only a build dir holds QML" "$tmp/pruned"
printf 'import QtQuick.Controls\nButton {}\n' >"$tmp/pruned/buildings/A.qml"
expect 1 "build* other than build, build-*, _build is linted" "$tmp/pruned"
grep -q ': error: default Button' "$tmp/out" || fail "buildings/ was pruned"
n=0
while IFS= read -r import; do
    n=$((n + 1))
    mkdir "$tmp/c$n"
    printf '%s\nItem {\n    Button {}\n}\n' "$import" >"$tmp/c$n/A.qml"
    expect 1 "false pass: $import" "$tmp/c$n"
done <<'IMPORTS'
import QtQuick.Controls // the default controls
import QtQuick.Controls.Basic
import QtQuick.Controls.Material 2.15
import QtQuick.Controls.Universal
import QtQuick.Controls.Fusion
IMPORTS
mkdir "$tmp/alias"
printf 'import QtQuick.Controls as Q // note\nItem {\n    Q.Button {}\n}\n' >"$tmp/alias/A.qml"
expect 1 "alias followed by a comment" "$tmp/alias"
mkdir "$tmp/impl"
printf 'import QtQuick.Controls.impl\nItem {\n    Button {}\n}\n' >"$tmp/impl/A.qml"
expect 0 "QtQuick.Controls.impl exports no Button" "$tmp/impl"
mkdir "$tmp/blockc"
printf 'import QtQuick.Controls /* the defaults */\nItem {\n    Button {}\n}\n' >"$tmp/blockc/A.qml"
expect 1 "block comment after an import" "$tmp/blockc"
# Braces that never close: must finish fast (scans are capped).
mkdir "$tmp/hostile"
{ echo 'import QtQuick'; for _ in $(seq 1 3000); do echo 'Rectangle {'; done; } >"$tmp/hostile/A.qml"
timeout 20 "$lint" "$tmp/hostile" >/dev/null 2>&1
[ $? -ne 124 ] || fail "unbalanced braces made the lint run away"
names="$here/../../tools/check-app-names.sh"
"$names" "$tmp/empty" >/dev/null 2>&1
[ $? -eq 1 ] || fail "check-app-names: no QML files must exit 1"
"$names" --allow-empty "$tmp/empty" >/dev/null 2>&1 || fail "check-app-names --allow-empty"
echo "lint error paths ok"

# Raw colours, literal durations and radii (token-only lint): `// WANT` lines get
# one warning each, the rest none, and warnings never change the exit code.
mkdir "$tmp/raw"
cat >"$tmp/raw/Raw.qml" <<'QML'
import QtQuick
Rectangle {
    color: "#fff" // WANT
    border.color: "#e5487a" // WANT
    color: "#80e5487a" // WANT
    color: ok ? "red" : "transparent" // WANT
    color: Qt.rgba(1, 0, 0, 0.5) // WANT
    color: Qt.hsla(0.5, 1, 0.5, 1) // WANT
    radius: 6 // WANT
    Behavior on x { NumberAnimation { duration: 200 } } // WANT
    NumberAnimation on y {
        duration: 90 // WANT
    }
    ColorAnimation { duration: 150; to: "transparent" } // WANT
    color: "#abc" // atlas-lint: allow-raw
    radius: 8 // atlas-lint: allow-raw
    Behavior on y { NumberAnimation { duration: 99 } } // atlas-lint: allow-raw
    color: AtlasStyle.surface
    color: Qt.rgba(c.r, c.g, c.b, 0.5)
    color: Qt.alpha(AtlasStyle.text, 0.5)
    radius: 0
    radius: height / 2
    radius: AtlasStyle.radius
    text: "#123"
    title: qsTr("Issue #1234")
    Timer { interval: 200; }
    Toast { duration: 4000 }
    NumberAnimation { duration: AtlasStyle.duration }
    NumberAnimation { duration: 0 }
    // color: "#fff"
    /* color: "#fff" */
}
QML
out=$("$lint" "$tmp/raw")
rc=$?
want=$(grep -n '// WANT$' "$tmp/raw/Raw.qml" | cut -d: -f1)
got=$(sed -nE 's|^.*/Raw\.qml:([0-9]+): warning: .*$|\1|p' <<<"$out")
n=$(wc -l <<<"$want")
if [ "$got" != "$want" ] || [ "$rc" -ne 0 ] || ! grep -q "^lint-app: 0 error(s), $n warning(s)\$" <<<"$out"; then
    printf -- '--- wanted lines\n%s\n--- got (exit %s)\n%s\n' "$want" "$rc" "$out" >&2
    fail "raw-value rules: unexpected findings"
fi
grep -q 'AtlasStyle.error' <<<"$out" || fail "a raw red names no token"
grep -q 'AtlasStyle.durationShort' <<<"$out" || fail "a 90 ms duration names no token"
grep -q 'AtlasStyle.radius (6)' <<<"$out" || fail "a radius of 6 names no token"
echo "lint raw-value rules ok ($n findings)"
