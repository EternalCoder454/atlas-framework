#!/bin/bash
# Fails when an app has a .qml file named like an Atlas.Ui type.
#
#   tools/check-app-names.sh <app-dir>...
#
# `import Atlas.Ui` wins over the QML files in an app's own directory, so an
# Atlas.Ui type named like an app's local type replaces it in that app, which
# then breaks (docs/DESIGN.md, "Compatibility"). The Atlas.Ui names are the
# basenames of ui/*.qml and the QML_ELEMENT / QML_NAMED_ELEMENT names in ui/*.h.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [ "$#" -eq 0 ]; then
    echo "usage: check-app-names.sh <app-dir>..." >&2
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
if [ ! -s "$names" ]; then
    echo "check-app-names: found no Atlas.Ui type names under $root/ui" >&2
    exit 2
fi

status=0
for app in "$@"; do
    if [ ! -d "$app" ]; then
        echo "check-app-names: not a directory: $app" >&2
        exit 2
    fi
    while IFS= read -r -d '' file; do
        base=$(basename "$file" .qml)
        if grep -qxF -- "$base" "$names"; then
            echo "$file: clashes with the Atlas.Ui type $base."
            echo "  Rule: 'import Atlas.Ui' hides an app's own QML file of the same name, so the app's $base.qml"
            echo "  is replaced by the framework's. Rename the app's file (the Installer's SearchField became ListSearchField)."
            status=1
        fi
    done < <(find "$app" \( -type d \( -name '.git' -o -name 'build*' -o -name target -o -name node_modules \) -prune \) -o -type f -name '*.qml' -print0)
done
if [ "$status" -eq 0 ]; then
    echo "check-app-names: no clashes"
fi
exit "$status"
