#!/bin/bash
# Fails when an app has a .qml file named like a Telamon.Ui type.
#
#   tools/check-app-names.sh [--allow-empty] <app-dir>...
#
# Exit 1 on a clash, and when an app directory holds no QML file (a wrong path
# must not pass; --allow-empty for an app that has none). Directories named
# build, build-*, _build, target, node_modules and .git are skipped.
#
# `import Telamon.Ui` wins over the QML files in an app's own directory, so a
# Telamon.Ui type named like an app's local type replaces it in that app, which
# then breaks (docs/DESIGN.md, "Compatibility"). The Telamon.Ui names are the
# basenames of ui/*.qml and the QML_ELEMENT / QML_NAMED_ELEMENT names in ui/*.h.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
allow_empty=0
if [ "${1:-}" = "--allow-empty" ]; then
    allow_empty=1
    shift
fi
if [ "$#" -eq 0 ]; then
    echo "usage: check-app-names.sh [--allow-empty] <app-dir>..." >&2
    exit 2
fi

names=$(mktemp)
trap 'rm -f "$names"' EXIT
{
    for f in "$root"/ui/*.qml; do
        basename "$f" .qml
    done
    awk '
        match($0, /^[ \t]*(class|struct)[ \t]+[A-Za-z_][A-Za-z0-9_]*/) {
            s = substr($0, RSTART, RLENGTH); sub(/^[ \t]*(class|struct)[ \t]+/, "", s); cls = s
        }
        /QML_NAMED_ELEMENT\(/ {
            s = $0; sub(/.*QML_NAMED_ELEMENT\(/, "", s); sub(/\).*/, "", s); print s
        }
        /QML_ELEMENT/ && cls != "" { print cls }
    ' "$root"/ui/*.h
} | sort -u >"$names"
# Atlas.Ui 1.x's names too (AtlasButton for TelamonButton): an app that has not
# moved to Telamon.Ui yet says `import Atlas.Ui`, which hides its own files the
# same way.
# (read to a variable first: sed would read the file it appends to)
atlas_names=$(sed -n 's/^Telamon/Atlas/p' "$names")
[ -z "$atlas_names" ] || printf '%s\n' "$atlas_names" >>"$names"
sort -u -o "$names" "$names"
if [ ! -s "$names" ]; then
    echo "check-app-names: found no Telamon.Ui type names under $root/ui" >&2
    exit 2
fi

status=0
for app in "$@"; do
    if [ ! -d "$app" ]; then
        echo "check-app-names: not a directory: ${app//[[:cntrl:]]/?}" >&2
        exit 2
    fi
    count=0
    while IFS= read -r -d '' file; do
        count=$((count + 1))
        base=$(basename "$file" .qml)
        if grep -qxF -- "$base" "$names"; then
            # Control characters in a name could forge CI log commands (::error::).
            echo "${file//[[:cntrl:]]/?}: clashes with the Telamon.Ui type $base."
            echo "  Rule: 'import Telamon.Ui' hides an app's own QML file of the same name, so the app's $base.qml"
            echo "  is replaced by the framework's. Rename the app's file (the Installer's SearchField became ListSearchField)."
            status=1
        fi
    done < <(find "$app/" \( -type d \( -name '.git' -o -name 'build' -o -name 'build-*' -o -name '_build' -o -name target -o -name node_modules \) -prune \) -o -type f -name '*.qml' -print0)
    if [ "$count" -eq 0 ]; then
        echo "check-app-names: no QML files in ${app//[[:cntrl:]]/?}"
        [ "$allow_empty" -eq 1 ] || status=1
    fi
done
if [ "$status" -eq 0 ]; then
    echo "check-app-names: no clashes"
fi
exit "$status"
