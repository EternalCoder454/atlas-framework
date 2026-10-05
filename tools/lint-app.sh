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
#             SpinBox, ToolTip, BusyIndicator; Kirigami.PasswordField and a
#             TextField or AtlasTextField with a Password `echoMode`
#             (AtlasPasswordField); an AtlasPasswordField that sets
#             `echoMode` or `inputMethodHints`; Kirigami.PlaceholderMessage
#             (AtlasEmptyState); Kirigami.Heading (AtlasLabel with a
#             textStyle); a ToolTip (`ToolTip {` or `ToolTip.text:`) from
#             QtQuick.Controls (AtlasToolTip); a hand-made tinted banner, a
#             Rectangle whose colour is Qt.alpha or Qt.tint of a Kirigami
#             negative, neutral or positive colour with a Label inside
#             (InfoBanner); and every name in tools/deprecated.txt
#             (`Name<TAB>since<TAB>replacement`; ATLAS_LINT_DEPRECATED names
#             another list).
#             AtlasPortal.notify(...) with `markup: true` whose body is not a
#             literal and does not go through AtlasPortal.escape().
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
# Does the item that opens on line n set a property matching re itself, not in
# a child item? Counts braces to find its end.
function setsOwn(n, re,   i, l, depth) {
    depth = 0
    for (i = n; i <= NR; i++) {
        l = lines[i]
        if (l ~ /^[ \t]*\/\//) continue
        sub(/[ \t]\/\/.*$/, "", l)
        if (i == n) {
            if (match(l, /\{/) && substr(l, RSTART + 1) ~ re) return 1
        } else if (depth == 1) {
            # `Child { echoMode: ... }` on one line is the child's.
            if ((match(l, /\{/) ? substr(l, 1, RSTART - 1) : l) ~ re) return 1
        }
        depth += gsub(/\{/, "{", l) - gsub(/\}/, "}", l)
        if (depth <= 0) return 0
    }
    return 0
}
# Does the item that opens on line n contain, anywhere inside, a line matching re?
function blockHas(n, re,   i, l, depth) {
    depth = 0
    for (i = n; i <= NR; i++) {
        l = lines[i]
        if (l ~ /^[ \t]*\/\//) continue
        sub(/[ \t]\/\/.*$/, "", l)
        if (i > n && l ~ re) return 1
        depth += gsub(/\{/, "{", l) - gsub(/\}/, "}", l)
        if (depth <= 0) return 0
    }
    return 0
}
# Does line s use `Name {` for a type reached through import alias a (a == "" for unqualified)?
function uses(s, a, name,   re) {
    re = "(^|[^A-Za-z0-9_.])" (a == "" ? "" : a "\\.") name "[ \t]*\\{"
    return match(s, re) > 0
}
BEGIN {
    # From the environment, not -v: awk would read backslashes in them as escapes.
    file = ENVIRON["LINT_FILE"]
    n = split(ENVIRON["LINT_LOCALS"], L, "\n"); for (i = 1; i <= n; i++) isLocal[L[i]] = 1
    split("Button ToolButton RoundButton DelayButton Switch", E, " ")
    split("TextField TextArea ComboBox CheckBox RadioButton Slider SpinBox ToolTip BusyIndicator", W, " ")
    # Any Password echo mode, also in a binding (`show ? TextInput.Normal : TextInput.Password`).
    PASSWORD = "(^|[^A-Za-z0-9_.])echoMode[ \t]*:.*Password"
    MASKING = "(^|[^A-Za-z0-9_.])(echoMode|inputMethodHints)[ \t]*:"
    nd = split(ENVIRON["LINT_DEPRECATED"], D, "\n")
    for (i = 1; i <= nd; i++) {
        if (D[i] ~ /^[ \t]*(#|$)/) continue
        split(D[i], F, "\t")
        if (F[1] ~ /^[ \t]*$/) continue
        dn++; dname[dn] = F[1]; dsince[dn] = F[2]; drepl[dn] = F[3]
        dre[dn] = F[1]; gsub(/\./, "\\.", dre[dn])
    }
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
        hit = 0
        for (a in kq) if (uses(s, a, "PasswordField")) hit = 1
        if (!hit && kunq && !("PasswordField" in isLocal) && uses(s, "", "PasswordField")) hit = 1
        if (hit) report(nr, "warning", "default Kirigami.PasswordField", ": use AtlasPasswordField from Atlas.Ui")
        split("PlaceholderMessage Heading", KN, " ")
        KM["PlaceholderMessage"] = "use AtlasEmptyState from Atlas.Ui"
        KM["Heading"] = "use AtlasLabel from Atlas.Ui with textStyle Title or Heading"
        for (i in KN) {
            name = KN[i]
            hit = 0
            for (a in kq) if (uses(s, a, name)) hit = 1
            if (!hit && kunq && !(name in isLocal) && uses(s, "", name)) hit = 1
            if (hit) report(nr, "warning", "Kirigami." name, ": " KM[name])
        }
        if (s ~ /(^|[^A-Za-z0-9_.])Rectangle[ \t]*\{/ && setsOwn(nr, "(^|[^A-Za-z0-9_.])color[ \t]*:.*Qt\\.(alpha|tint).*Theme\\.(negative|neutral|positive)") && blockHas(nr, "(^|[ \t])([A-Za-z0-9_]+\\.)?(Atlas)?Label[ \t]*\\{"))
            report(nr, "warning", "hand-made tinted banner", ": use InfoBanner from Atlas.Ui")
        tt = 0
        for (a in qq) if (s ~ ("(^|[^A-Za-z0-9_.])" a "\\.ToolTip\\.(text|visible|delay|timeout)[ \t]*:")) tt = 1
        if (!tt && unq && !("ToolTip" in isLocal) && s ~ /(^|[^A-Za-z0-9_.])ToolTip\.(text|visible|delay|timeout)[ \t]*:/) tt = 1
        # One finding per tooltip: its text, visible and delay lines run together.
        if (tt && lastTT != nr - 1) report(nr, "warning", "default ToolTip attached property", ": use AtlasToolTip from Atlas.Ui")
        if (tt) lastTT = nr
        for (i = 1; i <= dn; i++)
            if (s ~ ("(^|[^A-Za-z0-9_])" dre[i] "[ \t]*[{:]") || s ~ ("\\." dre[i] "([^A-Za-z0-9_]|$)"))
                report(nr, "warning", dname[i] " is deprecated since " dsince[i], ": use " drepl[i])
        for (i in W) {
            name = W[i]
            hit = 0
            for (a in qq) if (uses(s, a, name)) hit = 1
            if (!hit && unq && !(name in isLocal) && uses(s, "", name)) hit = 1
            if (hit && name == "TextField" && setsOwn(nr, PASSWORD)) report(nr, "warning", "default TextField with echoMode Password", ": use AtlasPasswordField from Atlas.Ui")
            else if (hit && name == "ToolTip") report(nr, "warning", "default ToolTip", ": use AtlasToolTip from Atlas.Ui")
            else if (hit) report(nr, "warning", "default " name, ": check whether Atlas.Ui has an equivalent")
        }
        if (s ~ /(^|[^A-Za-z0-9_])AtlasTextField[ \t]*\{/ && setsOwn(nr, PASSWORD)) report(nr, "warning", "AtlasTextField with echoMode Password", ": use AtlasPasswordField from Atlas.Ui")
        if (s ~ /(^|[^A-Za-z0-9_])AtlasPasswordField[ \t]*\{/ && setsOwn(nr, MASKING)) report(nr, "warning", "AtlasPasswordField sets echoMode or inputMethodHints", ": it sets both itself; yours can show the password or let the keyboard remember it")
        if (s ~ /(^|[^A-Za-z0-9_])AtlasPortal\.notify[ \t]*\(/) {
            # The whole call (up to 12 lines, until its parentheses close).
            call = ""; depth = 0
            for (i = nr; i <= NR && i < nr + 12; i++) {
                l = lines[i]
                call = call " " l
                depth += gsub(/\(/, "(", l) - gsub(/\)/, ")", l)
                if (depth <= 0) break
            }
            if (call ~ /markup[ \t]*:[ \t]*true/ && call !~ /AtlasPortal\.escape[ \t]*\(/) {
                t = call
                sub(/^.*AtlasPortal\.notify[ \t]*\(/, "", t)
                gsub(/"[^"]*"/, "S", t); gsub(/qsTr[ \t]*\([ \t]*S[ \t]*\)/, "S", t)
                if (t !~ /^[ \t]*S[ \t]*,[ \t]*S[ \t]*[,)]/)
                    report(nr, "warning", "AtlasPortal.notify with markup: true and a body that is not escaped", ": pass the body through AtlasPortal.escape(), or drop markup (the body is plain text by default)")
            }
        }
    }
    exit (errors > 0 ? 1 : 0)
}
AWK

deprecated_file=${ATLAS_LINT_DEPRECATED:-$(dirname "$0")/deprecated.txt}
deprecated=""
[ -r "$deprecated_file" ] && deprecated=$(cat "$deprecated_file")
status=0
total_errors=0
total_warnings=0
for app in "$@"; do
    if [ ! -d "$app" ]; then
        echo "lint-app: not a directory: $app" >&2
        exit 2
    fi
    count=0
    while IFS= read -r -d '' file; do
        count=$((count + 1))
        dir=$(dirname "$file")
        locals=$(find "$dir" -maxdepth 1 -name '*.qml' -printf '%f\n' | sed 's/\.qml$//')
        # Control characters in a name could forge CI log commands (::error::).
        out=$(LINT_FILE=${file//[[:cntrl:]]/?} LINT_LOCALS=$locals LINT_DEPRECATED=$deprecated awk "$program" "$file")
        rc=$?
        if [ -n "$out" ]; then
            echo "$out"
            total_errors=$((total_errors + $(grep -c ': error: ' <<<"$out")))
            total_warnings=$((total_warnings + $(grep -c ': warning: ' <<<"$out")))
        fi
        [ "$rc" -ne 0 ] && status=1
    done < <(find "$app/" \( -type d \( -name '.git' -o -name 'build*' -o -name target -o -name node_modules \) -prune \) -o -type f -name '*.qml' -print0)
    [ "$count" -eq 0 ] && echo "lint-app: no QML files in ${app//[[:cntrl:]]/?}"
done
echo "lint-app: $total_errors error(s), $total_warnings warning(s)"
exit "$status"
