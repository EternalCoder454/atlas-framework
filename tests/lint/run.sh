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
