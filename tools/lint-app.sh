#!/bin/bash
# Design rule 6 (docs/DESIGN.md): never default QQC2 or Kirigami buttons.
#
#   tools/lint-app.sh [--allow-empty] <app-dir>...
#
# Output is file:line: error|warning: message. Exit 1 when there is an error
# or an app directory holds no QML file (a wrong path must not pass; an app
# that really has none passes --allow-empty). Exit 2 on a usage error.
# Directories named build, build-*, _build, target, node_modules and .git
# are skipped.
#   errors    QQC2 (QtQuick.Controls and its style modules, such as
#             QtQuick.Controls.Basic or .Material) Button, ToolButton, RoundButton,
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
#             Raw values where Atlas.Ui has a token: a colour string ("#rgb",
#             "#rrggbb", "#aarrggbb", a named colour such as "red" in a
#             `...color:` binding) or Qt.rgba/hsla/hsva with literal numbers
#             (AtlasStyle.<colour>); a literal `duration:` in an animation
#             (AtlasStyle.duration, durationShort, durationLong); a literal
#             `radius:` other than 0 (AtlasStyle.radiusSmall, radius,
#             radiusLarge, radiusPill). Warnings never change the exit code.
# A finding is silenced by `// atlas-lint: allow <reason>` on its line or the
# line before; `// atlas-lint: allow-raw` does the same for the raw-value rules.
set -uo pipefail

allow_empty=0
if [ "${1:-}" = "--allow-empty" ]; then
    allow_empty=1
    shift
fi
if [ "$#" -eq 0 ]; then
    echo "usage: lint-app.sh [--allow-empty] <app-dir>..." >&2
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
    # Capped: braces that never balance must not make every line scan to EOF.
    for (i = n; i <= NR && i < n + SCAN_LINES; i++) {
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
    for (i = n; i <= NR && i < n + SCAN_LINES; i++) {
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
# The open items after the text str, given the stack st before it (item type
# names joined by "|"; "-" for a block that is not an item, such as a JS body).
# Strings and comments are skipped. Used to tell what a `duration:` belongs to.
function scanStack(st, str,   i, n, c, q, pre, t) {
    n = length(str)
    for (i = 1; i <= n; i++) {
        c = substr(str, i, 1)
        if (c == "\"" || c == "'") {
            q = c
            for (i++; i <= n; i++) {
                c = substr(str, i, 1)
                if (c == "\\") i++
                else if (c == q) break
            }
        } else if (c == "/" && substr(str, i + 1, 1) == "/") {
            break
        } else if (c == "{") {
            pre = substr(str, 1, i - 1)
            t = "-"
            if (match(pre, /[A-Za-z_][A-Za-z0-9_.]*[ \t]+on[ \t]+[A-Za-z_][A-Za-z0-9_.]*[ \t]*$/)) {
                t = substr(pre, RSTART, RLENGTH); sub(/[ \t].*$/, "", t)
            } else if (match(pre, /[A-Za-z_][A-Za-z0-9_.]*[ \t]*$/)) {
                t = substr(pre, RSTART, RLENGTH); sub(/[ \t]+$/, "", t)
            }
            sub(/^.*\./, "", t)
            st = st "|" t
        } else if (c == "}") {
            sub(/\|[^|]*$/, "", st)
        }
    }
    return st
}
function topOf(st) { return match(st, /[^|]*$/) ? substr(st, RSTART) : "" }
# Raw colours, animation durations and corner radii that have a token in AtlasStyle.
function rawChecks(n, s,   c, rest, tok, w, v, hint, st, pre, off) {
    if (incomment[n] || index(lines[n], "atlas-lint: allow-raw") > 0) return
    c = s
    sub(/[ \t]\/\/.*$/, "", c)
    # Colour strings: "#rgb", "#argb", "#rrggbb", "#aarrggbb". Not in text (qsTr, text:).
    if (c !~ /qsTr[ \t]*\(/ && c !~ /(^|[^A-Za-z0-9_.])(text|title|placeholderText|toolTip|description|subtitle)[ \t]*:/) {
        rest = c
        while (match(rest, /"#[0-9A-Fa-f]+"/)) {
            w = RLENGTH - 3
            tok = substr(rest, RSTART, RLENGTH)
            rest = substr(rest, RSTART + RLENGTH)
            if (w == 3 || w == 4 || w == 6 || w == 8)
                report(n, "warning", "raw colour " tok, ": use an AtlasStyle colour (AtlasStyle.accent, text, textMuted, surface, error, success, warning...); `// atlas-lint: allow-raw` if it must stay")
        }
    }
    # Named colours in a colour binding.
    if (c ~ /(^|[^A-Za-z0-9_])[A-Za-z]*[cC]olor[ \t]*:/) {
        rest = c
        sub(/^.*[cC]olor[ \t]*:/, "", rest)
        while (match(rest, /"[A-Za-z]+"/)) {
            w = tolower(substr(rest, RSTART + 1, RLENGTH - 2))
            rest = substr(rest, RSTART + RLENGTH)
            if (!(w in NAMED)) continue
            hint = "an AtlasStyle colour (AtlasStyle.text, textMuted, surface, accent...)"
            if (w == "red") hint = "AtlasStyle.error"
            else if (w == "green") hint = "AtlasStyle.success"
            else if (w == "orange" || w == "yellow") hint = "AtlasStyle.warning"
            report(n, "warning", "raw colour \"" w "\"", ": use " hint "; `// atlas-lint: allow-raw` if it must stay")
        }
    }
    # Qt.rgba, Qt.hsla, Qt.hsva with nothing but numbers.
    rest = c
    while (match(rest, /Qt\.(rgba|hsla|hsva)[ \t]*\([ \t0-9.,+-]*\)/)) {
        tok = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        sub(/[ \t]*\(.*$/, "", tok)
        report(n, "warning", tok " with literal numbers", ": use an AtlasStyle colour, or Qt.alpha(AtlasStyle.<colour>, <alpha>) for a tint; `// atlas-lint: allow-raw` if it must stay")
    }
    # Literal durations of animations: the item the line is in must be one.
    off = 0; rest = c
    while (match(rest, /(^|[^A-Za-z0-9_.])duration[ \t]*:[ \t]*[0-9]+[ \t]*(;|\}|$)/)) {
        pre = substr(c, 1, off + RSTART - 1)
        tok = substr(rest, RSTART, RLENGTH)
        off += RSTART + RLENGTH - 1
        rest = substr(rest, RSTART + RLENGTH)
        v = tok; sub(/^[^0-9]*duration[ \t]*:[ \t]*/, "", v); sub(/[^0-9].*$/, "", v)
        if (v + 0 == 0) continue
        st = scanStack(ctx[n], pre)
        if (topOf(st) !~ /(Animation|Animator)$/) continue
        hint = (v + 0 <= 100) ? "durationShort (100 ms)" : ((v + 0 <= 150) ? "duration (150 ms)" : "durationLong (250 ms)")
        report(n, "warning", "literal animation duration " v, ": use AtlasStyle." hint " (it is 0 when the user turned motion off); `// atlas-lint: allow-raw` if it must stay")
    }
    # Literal radii other than 0.
    if (match(c, /(^|[^A-Za-z0-9_.])radius[ \t]*:[ \t]*[0-9.]+[ \t]*(;|\}|$)/)) {
        tok = substr(c, RSTART, RLENGTH)
        v = tok; sub(/^[^r]*radius[ \t]*:[ \t]*/, "", v); sub(/[^0-9.].*$/, "", v)
        if (v + 0 != 0) {
            hint = (v + 0 >= 100) ? "radiusPill" : ((v + 0 <= 4) ? "radiusSmall (4)" : ((v + 0 <= 6) ? "radius (6)" : "radiusLarge (8)"))
            report(n, "warning", "literal radius " v, ": use AtlasStyle." hint "; `// atlas-lint: allow-raw` if it must stay")
        }
    }
}
BEGIN {
    split("red green blue white black gray grey yellow orange purple pink cyan magenta brown lime navy teal maroon olive silver aqua fuchsia gold crimson coral salmon tomato violet indigo khaki orchid plum tan beige ivory lavender turquoise darkgray darkgrey lightgray lightgrey darkred darkgreen darkblue lightblue lightgreen skyblue steelblue royalblue slategray", NC, " ")
    for (i in NC) NAMED[NC[i]] = 1
    # From the environment, not -v: awk would read backslashes in them as escapes.
    SCAN_LINES = 200
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
    # Per line: is it inside a block comment, and which items are open at its start.
    blk = 0; ctxst = ""
    for (nr = 1; nr <= NR; nr++) {
        ctx[nr] = ctxst
        s = lines[nr]
        if (blk) {
            incomment[nr] = 1
            if (index(s, "*/") > 0) blk = 0
        } else {
            if (s ~ /^[ \t]*\/\*/) incomment[nr] = 1
            if (match(s, /\/\*/) && index(substr(s, RSTART), "*/") == 0 && s !~ /"[^"]*\/\*/) blk = 1
            ctxst = scanStack(ctxst, s)
        }
    }
    for (nr = 1; nr <= NR; nr++) {
        s = lines[nr]
        # A trailing comment must not hide an `as` alias.
        if (s ~ /^[ \t]*import[ \t]/) { sub(/\/\*.*\*\//, "", s); sub(/[ \t]*\/[\/*].*$/, "", s) }
        # QtQuick.Controls and every style module (.Basic, .Material,
        # .Universal, .Fusion, ...) export the QQC2 Button and friends;
        # only .impl (internal types) does not.
        if (match(s, /^[ \t]*import[ \t]+QtQuick\.Controls([ \t.]|$)/)) {
            if (s ~ /^[ \t]*import[ \t]+QtQuick\.Controls\.[iI]mpl([ \t]|$)/) continue
            if (match(s, /[ \t]as[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*$/)) {
                a = substr(s, RSTART, RLENGTH); sub(/^[ \t]+as[ \t]+/, "", a); sub(/[ \t]+$/, "", a); qq[a] = 1
            } else {
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
        rawChecks(nr, s)
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
    done < <(find "$app/" \( -type d \( -name '.git' -o -name 'build' -o -name 'build-*' -o -name '_build' -o -name target -o -name node_modules \) -prune \) -o -type f -name '*.qml' -print0)
    if [ "$count" -eq 0 ]; then
        echo "lint-app: no QML files in ${app//[[:cntrl:]]/?}"
        [ "$allow_empty" -eq 1 ] || status=1
    fi
done
echo "lint-app: $total_errors error(s), $total_warnings warning(s)"
exit "$status"
