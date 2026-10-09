#!/bin/bash
# Safety tests of the scripts that run on other people's trees (an app's
# checkout, from another repository): migrate-app-to-telamon.sh, lint-app.sh and
# check-app-names.sh must not write through a link someone left, hang on a pipe,
# or print a terminal escape or a CI log command from a file name.
# Needs bash, git, python3, timeout and mkfifo (about 3 s).
#
#   tools/test-tool-scripts.sh
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for tool in git python3 timeout mkfifo; do
    command -v "$tool" >/dev/null || { echo "test-tool-scripts: $tool is not installed" >&2; exit 2; }
done
scratch=$(mktemp -d "${TMPDIR:-/tmp}/telamon-test-tools.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
passed=0
failed=0
ok() { passed=$((passed + 1)); echo "ok   $1"; }
bad() {
    local line
    failed=$((failed + 1))
    echo "FAIL $1" >&2
    [ -z "${2:-}" ] || while IFS= read -r line; do echo "     | $line" >&2; done <<<"$2"
}
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.org GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.org
esc=$(printf '\033')

# ----------------------------------------------------------- migrate-app-to-telamon.sh
app=$scratch/app
mkdir -p "$app/qml" "$app/-dash" && cd "$app" || exit 2
git init -q .
echo 'import Atlas.Ui' >qml/Main.qml
printf 'import Atlas.Ui\n' >"qml/Esc${esc}[31mape.qml"
echo victim >"$scratch/victim"
ln -s ../../victim qml/Main.qml.migrate-tmp
printf '[Global]\n' >-dash/atlas-demo.notifyrc
git add -A && git commit -q -m app

out=$(timeout 60 "$here/migrate-app-to-telamon.sh" "$app" 2>&1)
rc=$?
if [ "$rc" = 0 ] && grep -q 'import Telamon.Ui' qml/Main.qml; then ok "migrate: the app is migrated"; else bad "migrate runs" "rc=$rc $out"; fi
if [ "$(cat "$scratch/victim")" = victim ]; then ok "migrate: a link left at the old fixed temp name is not written through"
else bad "migrate wrote through a link" "$(cat "$scratch/victim")"; fi
if ! grep -q "$esc" <<<"$out"; then ok "migrate: a terminal escape in a file name is not printed"; else bad "migrate printed an escape sequence" "$(cat -v <<<"$out")"; fi
if [ -f ./-dash/telamon-demo.notifyrc ] && [ ! -e ./-dash/atlas-demo.notifyrc ]; then ok "migrate: a directory named -dash does not turn git mv's argument into an option"
else bad "migrate: notifyrc in a directory named -dash" "$(ls -A ./-dash)"; fi
if [ -z "$(find "$app" -name '.migrate-*' -print -quit)" ]; then ok "migrate: no temporary file is left behind"; else bad "migrate left a temporary file" "$(find "$app" -name '.migrate-*')"; fi

# a tree that is not a git repository, with a pipe in it
plain=$scratch/plain
mkdir -p "$plain/qml"
echo 'import Atlas.Ui' >"$plain/qml/Main.qml"
mkfifo "$plain/qml/pipe.qml"
if out=$(timeout 30 "$here/migrate-app-to-telamon.sh" --allow-dirty "$plain" 2>&1) && grep -q 'import Telamon.Ui' "$plain/qml/Main.qml"; then
    ok "migrate: a named pipe in a tree that is not a repository is skipped, not read (it would hang)"
else bad "migrate with a pipe in the tree" "$out"; fi

# a repository whose own configuration names a program to run: git must not run it
evil=$scratch/evil
mkdir -p "$evil" && (cd "$evil" && git init -q . && echo 'import Atlas.Ui' >a.qml && git add -A && git commit -q -m x &&
    git config core.fsmonitor "touch $scratch/fsmonitor-ran; echo")
timeout 30 "$here/migrate-app-to-telamon.sh" "$evil" >/dev/null 2>&1
if [ ! -e "$scratch/fsmonitor-ran" ]; then ok "migrate: core.fsmonitor of the tree's own configuration is not run"; else bad "migrate ran core.fsmonitor"; fi

# ------------------------------------------------------------- lint-app.sh, check-app-names.sh
lint=$scratch/lint
mkdir -p "$lint/d${esc}[31mir" "$lint/::set-output name=x::y"
echo 'import QtQuick.Controls
Button { }' >"$lint/d${esc}[31mir/Bad.qml"
echo 'import QtQuick' >"$lint/::set-output name=x::y/Fine.qml"
echo 'import QtQuick
Item { }' >"$lint/TelamonButton.qml"
echo "Button {}" >"$scratch/outside.qml"
ln -s ../outside.qml "$lint/link.qml"
mkdir "$scratch/outside-dir" && echo 'import QtQuick.Controls
Button {}' >"$scratch/outside-dir/Linked.qml" && ln -s ../outside-dir "$lint/linked-dir"

out=$(timeout 60 "$here/lint-app.sh" "$lint" 2>&1)
rc=$?
if [ "$rc" = 1 ] && grep -q 'default Button' <<<"$out"; then ok "lint-app: an error in the tree is found"; else bad "lint-app finds the error" "rc=$rc $out"; fi
if ! grep -q "$esc" <<<"$out" && ! grep -q '^::' <<<"$out"; then ok "lint-app: control characters in a path are made harmless in the report (no escape, no line that starts a CI command)"
else bad "lint-app output" "$(cat -v <<<"$out")"; fi
if ! grep -q 'Linked.qml\|link.qml\|outside' <<<"$out"; then ok "lint-app: a link to a file or a folder outside the tree is not followed"; else bad "lint-app followed a link" "$out"; fi

out=$(timeout 60 "$here/check-app-names.sh" "$lint" 2>&1)
rc=$?
if [ "$rc" = 1 ] && grep -q 'clashes with the Telamon.Ui type TelamonButton' <<<"$out"; then ok "check-app-names: a clash is found"; else bad "check-app-names finds the clash" "rc=$rc $out"; fi
mkdir "$lint/e${esc}[31mvil"
echo 'import QtQuick' >"$lint/e${esc}[31mvil/TelamonButton.qml"
out=$(timeout 60 "$here/check-app-names.sh" "$lint" 2>&1)
if ! grep -q "$esc" <<<"$out"; then ok "check-app-names: control characters in a path are made harmless in the report"; else bad "check-app-names output" "$(cat -v <<<"$out")"; fi
out=$(timeout 60 "$here/check-app-names.sh" "$(printf 'no%s[31msuch' "$esc")" 2>&1)
if [ $? = 2 ] && ! grep -q "$esc" <<<"$out"; then ok "check-app-names: a missing directory with a control character in its name is reported plainly"; else bad "check-app-names, missing directory" "$(cat -v <<<"$out")"; fi
out=$(timeout 60 "$here/lint-app.sh" "$(printf 'no%s[31msuch' "$esc")" 2>&1)
if [ $? = 2 ] && ! grep -q "$esc" <<<"$out"; then ok "lint-app: a missing directory with a control character in its name is reported plainly"; else bad "lint-app, missing directory" "$(cat -v <<<"$out")"; fi

echo
echo "test-tool-scripts: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
