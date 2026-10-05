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

# --strict: a warning fails too.
mkdir "$tmp/strict"
printf 'import QtQuick\nRectangle { radius: 6 }\n' >"$tmp/strict/A.qml"
expect 0 "a warning without --strict" "$tmp/strict"
expect 1 "a warning with --strict" --strict "$tmp/strict"
expect 0 "--strict on a clean app" --strict "$tmp/c1/../impl"
echo "lint --strict ok"

# allow-raw silences the raw-value rules only: errors and password findings stay.
mkdir "$tmp/rawonly"
cat >"$tmp/rawonly/A.qml" <<'QML'
import QtQuick
import QtQuick.Controls
import Atlas.Ui
Item {
    Button { } // atlas-lint: allow-raw
    AtlasTextField { echoMode: TextInput.Password } // atlas-lint: allow-raw
    AtlasPasswordField { echoMode: TextInput.Normal } // atlas-lint: allow-raw
    Rectangle { radius: 6; color: "#fff" } // atlas-lint: allow-raw
}
QML
expect 1 "allow-raw does not silence an error" "$tmp/rawonly"
grep -q 'A.qml:5: error: default Button' "$tmp/out" || fail "allow-raw hid the default Button error"
grep -q 'A.qml:6: warning: AtlasTextField with echoMode Password' "$tmp/out" || fail "allow-raw hid the password finding"
grep -q 'A.qml:7: warning: AtlasPasswordField sets' "$tmp/out" || fail "allow-raw hid the masking finding"
! grep -q 'A.qml:8:' "$tmp/out" || fail "allow-raw did not silence the raw values"
# Deep nesting and a very long line: bounded work, and still a result.
mkdir "$tmp/deep"
{ echo 'import QtQuick'; for _ in $(seq 1 2000); do echo 'Item { NumberAnimation {'; done; echo 'duration: 200'; } >"$tmp/deep/A.qml"
{ printf 'Item { color: "'; head -c 200000 /dev/zero | tr '\0' 'x'; echo '" }'; } >"$tmp/deep/B.qml"
start=$SECONDS
timeout 30 "$lint" "$tmp/deep" >/dev/null 2>&1
[ $? -ne 124 ] || fail "deep nesting made the lint run away"
[ $((SECONDS - start)) -lt 20 ] || fail "deep nesting took too long"
echo "lint allow-raw scope and bounds ok"

# allow-raw on the line before silences the next line's raw values (as `allow` does).
mkdir "$tmp/prev"
printf 'import QtQuick\nItem {\n    // atlas-lint: allow-raw sample colour\n    Rectangle { color: "#fff"; radius: 6 }\n    Rectangle { color: "#fff" }\n}\n' >"$tmp/prev/A.qml"
"$lint" "$tmp/prev" >"$tmp/out" 2>&1
grep -q 'A.qml:4:' "$tmp/out" && fail "allow-raw on the previous line did not silence line 4"
grep -q 'A.qml:5: warning: raw colour' "$tmp/out" || fail "allow-raw on the previous line silenced two lines"

# Hostile files finish fast: a 2 MB line of colour strings, and 2000 lines of braces.
mkdir "$tmp/hostile2" "$tmp/hostile3"
{ printf 'Item { color: "#fff"'; for _ in $(seq 1 80000); do printf ' "#fff" "#fff" "#fff" "#fff" "#fff"'; done; echo ' }'; } >"$tmp/hostile2/A.qml"
line=$(printf 'a{}%.0s' $(seq 1 100))
{ echo 'NumberAnimation {'; for _ in $(seq 1 2000); do echo "$line"; done; echo 'duration: 200 }'; } >"$tmp/hostile3/B.qml"
for d in hostile2 hostile3; do
    start=$(date +%s.%N)
    timeout 30 "$lint" "$tmp/$d" >/dev/null 2>&1
    elapsed=$(awk -v a="$start" -v b="$(date +%s.%N)" 'BEGIN { printf "%d", (b - a) * 1000 }')
    [ "$elapsed" -lt 2000 ] || fail "$d took $elapsed ms (limit 2000)"
    echo "lint bounds $d ok ($elapsed ms)"
done
