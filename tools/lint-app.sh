#!/bin/bash
# Design rule 6 (docs/DESIGN.md): never default QQC2 or Kirigami buttons.
#
#   tools/lint-app.sh <app-dir>...
#
# Output is file:line: error|warning: message. Exit 1 when there is an error.
#   errors    QQC2 (QtQuick.Controls) Button, ToolButton, RoundButton,
#             DelayButton and Switch, and Kirigami.ActionToolBar. A bare
#             `Button {` counts when the file imports QtQuick.Controls
#             unqualified, unless the app has its own Button.qml beside it.
#   warnings  default controls that Atlas.Ui now has an equivalent for:
#             TextField, TextArea, ComboBox, CheckBox, RadioButton, Slider,
#             SpinBox, ToolTip, BusyIndicator.
# A finding is silenced by `// atlas-lint: allow <reason>` on its line or the
# line before.
set -uo pipefail

if [ "$#" -eq 0 ]; then
    echo "usage: lint-app.sh <app-dir>..." >&2
    exit 2
fi

read -r -d '' program <<'AWK'
function allowed(n) { return (index(lines[n], "atlas-lint: allow") > 0) || (n > 1 && index(lines[n-1], "atlas-lint: allow") > 0) }
function report(n, level, what, why) {
    if (allowed(n)) return
    printf "%s:%d: %s: %s%s\n", file, n, level, what, why
    if (level == "error") errors++; else warnings++
}
# Does line s use `Name {` for a type reached through import alias a (a == "" for unqualified)?
function uses(s, a, name,   re) {
    re = "(^|[^A-Za-z0-9_.])" (a == "" ? "" : a "\\.") name "[ \t]*\\{"
    return match(s, re) > 0
}
BEGIN {
    n = split(locals, L, " "); for (i = 1; i <= n; i++) isLocal[L[i]] = 1
    split("Button ToolButton RoundButton DelayButton Switch", E, " ")
    split("TextField TextArea ComboBox CheckBox RadioButton Slider SpinBox ToolTip BusyIndicator", W, " ")
    errors = 0; warnings = 0; qq["-"] = 1; kq["-"] = 1; isLocal["-"] = 1
}
{ lines[NR] = $0 }
END {
    for (nr = 1; nr <= NR; nr++) {
        s = lines[nr]
        if (match(s, /^[ \t]*import[ \t]+QtQuick\.Controls/)) {
            if (match(s, /[ \t]as[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*$/)) {
                a = substr(s, RSTART, RLENGTH); sub(/^[ \t]+as[ \t]+/, "", a); sub(/[ \t]+$/, "", a); qq[a] = 1
            } else if (s !~ /\.(Basic|Material|Universal|Fusion|Imagine|FluentWinUI3|Windows|macOS|iOS|Impl)/) {
                unq = 1
            }
            continue
        }
        if (match(s, /^[ \t]*import[ \t]+org\.kde\.kirigami([ \t.]|$)/)) {
            if (match(s, /[ \t]as[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*$/)) {
                a = substr(s, RSTART, RLENGTH); sub(/^[ \t]+as[ \t]+/, "", a); sub(/[ \t]+$/, "", a); kq[a] = 1
            } else if (s !~ /org\.kde\.kirigami\.[a-z]/) {
                kunq = 1
            }
            continue
        }
        if (s ~ /^[ \t]*\/\//) continue
        for (i in E) {
            name = E[i]
            hit = 0
            for (a in qq) if (uses(s, a, name)) hit = 1
            if (!hit && unq && !(name in isLocal) && uses(s, "", name)) hit = 1
            if (hit) report(nr, "error", "default " name " (design rule 6)", ": use PrimaryButton, SecondaryButton, TextButton, ToolbarButton or AtlasSwitch from Atlas.Ui")
        }
        hit = 0
        for (a in kq) if (uses(s, a, "ActionToolBar")) hit = 1
        if (!hit && kunq && !("ActionToolBar" in isLocal) && uses(s, "", "ActionToolBar")) hit = 1
        if (hit) report(nr, "error", "Kirigami.ActionToolBar (design rule 6)", ": build the bar from Atlas.Ui buttons")
        for (i in W) {
            name = W[i]
            hit = 0
            for (a in qq) if (uses(s, a, name)) hit = 1
            if (!hit && unq && !(name in isLocal) && uses(s, "", name)) hit = 1
            if (hit) report(nr, "warning", "default " name, ": check whether Atlas.Ui has an equivalent")
        }
    }
    exit (errors > 0 ? 1 : 0)
}
AWK

status=0
total_errors=0
total_warnings=0
for app in "$@"; do
    if [ ! -d "$app" ]; then
        echo "lint-app: not a directory: $app" >&2
        exit 2
    fi
    while IFS= read -r -d '' file; do
        dir=$(dirname "$file")
        locals=$(find "$dir" -maxdepth 1 -name '*.qml' -printf '%f\n' | sed 's/\.qml$//' | tr '\n' ' ')
        out=$(awk -v file="$file" -v locals="$locals" "$program" "$file")
        rc=$?
        if [ -n "$out" ]; then
            echo "$out"
            total_errors=$((total_errors + $(grep -c ': error: ' <<<"$out")))
            total_warnings=$((total_warnings + $(grep -c ': warning: ' <<<"$out")))
        fi
        [ "$rc" -ne 0 ] && status=1
    done < <(find "$app" \( -type d \( -name '.git' -o -name 'build*' -o -name target -o -name node_modules \) -prune \) -o -type f -name '*.qml' -print0)
done
echo "lint-app: $total_errors error(s), $total_warnings warning(s)"
exit "$status"
