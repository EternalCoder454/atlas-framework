#!/bin/bash
# tools/migrate-app-to-telamon.sh on a small made-up app (a throwaway git
# repository): what it rewrites, what it leaves, the pins, the spec, the
# renamed notifyrc, a dry run, a dirty tree, a second run.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tool="$here/../../tools/migrate-app-to-telamon.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "migrate: $1" >&2; exit 1; }
app=$tmp/app
mkdir -p "$app/qml" "$app/src" "$app/cpp" "$app/packaging" "$app/data" "$app/.github/workflows" "$app/ci"
cd "$app" || exit 1

cat >Cargo.toml <<'T'
[workspace]
members = ["src"]
[workspace.dependencies]
atlas-framework-core = { git = "https://github.com/EternalCoder454/atlas-framework", tag = "v1.5.1" }
atlas-framework-ui = { git = "https://github.com/EternalCoder454/atlas-framework", rev = "7a114a112bd1fff4fe3d6facc81b0a81e5d2db30" }
atlas-framework-system = { git = "https://github.com/EternalCoder454/atlas-framework", branch = "main", features = ["notify"] }
# not the framework's:
serde = { git = "https://github.com/serde-rs/serde", tag = "v1.0.0" }
T
cat >src/Cargo.toml <<'T'
[package]
name = "atlas-demo"
[dependencies]
atlas-framework-ui.workspace = true
[dependencies.atlas-framework-flatpak]
git = "https://github.com/EternalCoder454/atlas-framework"
tag = "v1.6.0"
T
cat >src/lib.rs <<'T'
// AtlasObjects is the app's own. atlas_framework_ui is not.
atlas_framework_ui::app! {
    name: "Atlas Demo",
    id: "net.eterneon.atlas.demo",
    repo: "atlasos-demo",
    ui: "1.4.0",
}
use atlas_framework_core::settings::Settings;
use atlas_framework_ui::atlas_framework_core as core;
struct AtlasObjects;
fn atlas_objects_new() {}
T
cat >cpp/main.cpp <<'T'
#include <atlas/app.h>
#include "atlas/textview.h"
int main(int argc, char *argv[])
{
    atlas_app_init();
    atlas_app_ready();
    return atlas_app_run(argc, argv, "net.eterneon.atlas.demo", "Main", atlas_backend_new);
}
T
cat >qml/Main.qml <<'T'
import QtQuick
import Atlas.Ui
import Atlas.Ui 1.0 as Old
AtlasWindow {
    title: "Atlas Demo on AtlasOS"
    color: AtlasStyle.surface
    AtlasTextField { text: "AtlasStyleX AtlasObjects MyAtlasButton Atlas.UiX" }
    Old.AtlasLabel { font.family: "Material Symbols Rounded" }
    // atlas-lint: allow raw
    Item { property string atlasRepo: "x" }
}
T
cat >CMakeLists.txt <<'T'
if(NOT EXISTS "${QT6_INSTALL_PREFIX}/${QT6_INSTALL_QML}/Atlas/Ui/qmldir")
    message(FATAL_ERROR "Atlas.Ui is not installed: install atlas-ui")
endif()
T
cat >packaging/demo.spec <<'T'
Name:           atlas-demo
Requires:       atlas-ui >= 1.4.0
BuildRequires:  atlas-ui
Requires:       atlas-symbols-fonts
BuildRequires:  atlas-symbols-fonts-extra = 1.5.1
Requires:       atlas-symbolsfoo
%changelog
* Tue Oct 06 2026 Atlas <atlas@eterneon.net> - 1.0-1
- Needs atlas-ui >= 1.2.0 and Atlas.Ui.
T
cat >CHANGELOG.md <<'T'
Needs Atlas.Ui and atlas-ui 1.0.
T
cat >data/atlas-demo.notifyrc <<'T'
[Global]
IconName=atlas-demo
T
cat >data/CMakeLists.txt <<'T'
install(FILES atlas-demo.notifyrc DESTINATION share/knotifications6)
T
cat >.github/workflows/ci.yml <<'T'
jobs:
  checks:
    uses: EternalCoder454/atlas-framework/.github/workflows/app-checks.yml@v1.5.1
    with:
      framework-ref: v1.5.1
  pinned:
    uses: EternalCoder454/atlas-framework/.github/workflows/app-checks.yml@7a114a112bd1fff4fe3d6facc81b0a81e5d2db30 # v1.4.0
T
cat >ci/run.sh <<'T'
dnf install -y atlas-ui atlas-symbols-fonts
ATLAS_SOFTWARE_RENDERING=1 ATLAS_LOG=debug ATLAS_LOCAL_RPMS=/x atlas-preview page.qml
QT_LOGGING_RULES="atlas.ui.renderer=true"
T
printf 'binary\0AtlasOS Atlas.Ui\n' >data/blob.bin
git init -q . && git add -A && git -c user.name=t -c user.email=t@example.org commit -q -m start || fail "cannot make the test repository"

# A dry run changes nothing and says so.
before=$(git status --porcelain | wc -l)
out=$("$tool" --dry-run) || fail "dry run failed"
[ "$(git status --porcelain | wc -l)" = "$before" ] || fail "a dry run changed files"
grep -q 'would change' <<<"$out" || fail "dry run: no summary: $out"
grep -q 'would be renamed' <<<"$out" || fail "dry run: no rename: $out"

# A dirty tree is refused (without --allow-dirty).
echo x >>CHANGELOG.md
"$tool" >/dev/null 2>&1
[ $? -eq 2 ] || fail "a dirty tree was not refused"
git checkout -q CHANGELOG.md

out=$("$tool" --rev 0123456789abcdef0123456789abcdef01234567) || fail "migration failed: $out"
echo "$out" | tail -n 25

has() { grep -qF -- "$2" "$1" || { echo "--- $1" >&2; cat "$1" >&2; fail "$1 should have: $2"; }; }
hasnt() { ! grep -qF -- "$2" "$1" || { echo "--- $1" >&2; cat "$1" >&2; fail "$1 should not have: $2"; }; }

# Cargo: names, pins (rev given), a table, the unrelated dependency untouched.
has Cargo.toml 'telamon-framework-core = { git = "https://github.com/EternalCoder454/atlas-framework", rev = "0123456789abcdef0123456789abcdef01234567" }'
has Cargo.toml 'telamon-framework-ui = { git = "https://github.com/EternalCoder454/atlas-framework", rev = "0123456789abcdef0123456789abcdef01234567" }'
has Cargo.toml 'telamon-framework-system = { git = "https://github.com/EternalCoder454/atlas-framework", rev = "0123456789abcdef0123456789abcdef01234567", features = ["notify"] }'
has Cargo.toml 'serde = { git = "https://github.com/serde-rs/serde", tag = "v1.0.0" }'
has src/Cargo.toml 'telamon-framework-ui.workspace = true'
has src/Cargo.toml '[dependencies.telamon-framework-flatpak]'
has src/Cargo.toml 'rev = "0123456789abcdef0123456789abcdef01234567"'
hasnt src/Cargo.toml 'tag = "v1.6.0"'
has src/Cargo.toml 'name = "atlas-demo"'
# Rust: paths, the app! version, the app's own names.
has src/lib.rs 'telamon_framework_ui::app! {'
has src/lib.rs 'ui: "2.0.0",'
has src/lib.rs 'use telamon_framework_core::settings::Settings;'
has src/lib.rs 'use telamon_framework_ui::telamon_framework_core as core;'
has src/lib.rs 'struct AtlasObjects;'
has src/lib.rs 'fn atlas_objects_new() {}'
has src/lib.rs 'id: "net.eterneon.atlas.demo"'
has src/lib.rs 'repo: "atlasos-demo"'
has src/lib.rs 'name: "Atlas Demo"'
# C++
has cpp/main.cpp '#include <telamon/app.h>'
has cpp/main.cpp '#include "telamon/textview.h"'
has cpp/main.cpp 'telamon_app_init();'
has cpp/main.cpp 'telamon_app_run(argc, argv, "net.eterneon.atlas.demo", "Main", telamon_backend_new)'
# QML: whole words only.
has qml/Main.qml 'import Telamon.Ui'
has qml/Main.qml 'import Telamon.Ui 1.0 as Old'
has qml/Main.qml 'TelamonWindow {'
has qml/Main.qml 'TelamonStyle.surface'
has qml/Main.qml 'Old.TelamonLabel'
has qml/Main.qml '"Atlas Demo on AtlasOS"'
has qml/Main.qml 'AtlasStyleX AtlasObjects MyAtlasButton Atlas.UiX'
has qml/Main.qml 'font.family: "Telamon Symbols Rounded"'
has qml/Main.qml '// telamon-lint: allow raw'
has qml/Main.qml 'property string atlasRepo: "x"'   # a property name, not the quoted setProperty key
# CMake, spec, CI, scripts.
has CMakeLists.txt 'Telamon/Ui/qmldir'
has CMakeLists.txt 'install telamon-ui'
has packaging/demo.spec 'Requires:       telamon-ui >= 2.0.0'
has packaging/demo.spec 'BuildRequires:  telamon-ui >= 2.0.0'
has packaging/demo.spec 'Requires:       telamon-symbols-fonts >= 2.0.0'
has packaging/demo.spec 'BuildRequires:  telamon-symbols-fonts-extra >= 2.0.0'
has packaging/demo.spec 'Requires:       atlas-symbolsfoo'
has packaging/demo.spec 'Name:           atlas-demo'
has packaging/demo.spec '- Needs atlas-ui >= 1.2.0 and Atlas.Ui.'
has CHANGELOG.md 'Needs Atlas.Ui and atlas-ui 1.0.'
has .github/workflows/ci.yml 'app-checks.yml@v2.0.0'
has .github/workflows/ci.yml 'framework-ref: v2.0.0'
has .github/workflows/ci.yml '@7a114a112bd1fff4fe3d6facc81b0a81e5d2db30 # v1.4.0'
grep -q 'pinned to the commit 7a114a112bd1' <<<"$out" || fail "a commit-pinned app-checks.yml is not reported"
has ci/run.sh 'dnf install -y telamon-ui telamon-symbols-fonts'
has ci/run.sh 'TELAMON_SOFTWARE_RENDERING=1 TELAMON_LOG=debug ATLAS_LOCAL_RPMS=/x telamon-preview page.qml'
has ci/run.sh 'telamon.ui.renderer=true'
# The notifyrc is renamed, and named where it is mentioned.
[ -f data/telamon-demo.notifyrc ] && [ ! -e data/atlas-demo.notifyrc ] || fail "the notifyrc was not renamed"
has data/CMakeLists.txt 'telamon-demo.notifyrc'
has data/telamon-demo.notifyrc 'IconName=atlas-demo'
# Binary files are not touched.
cmp -s data/blob.bin <(printf 'binary\0AtlasOS Atlas.Ui\n') || fail "a binary file changed"
# The pin without --rev is a tag.
git checkout -q . && git reset -q --hard && git clean -fdq
"$tool" --no-pin >/dev/null || fail "--no-pin failed"
has Cargo.toml 'tag = "v1.5.1"'
hasnt Cargo.toml 'v2.0.0'
git checkout -q . && git reset -q --hard && git clean -fdq
"$tool" >/dev/null || fail "default pin failed"
has Cargo.toml 'telamon-framework-core = { git = "https://github.com/EternalCoder454/atlas-framework", tag = "v2.0.0" }'
has Cargo.toml 'telamon-framework-ui = { git = "https://github.com/EternalCoder454/atlas-framework", tag = "v2.0.0" }'
has src/Cargo.toml 'tag = "v2.0.0"'
# A second run changes nothing.
git add -A && git -c user.name=t -c user.email=t@example.org commit -q -m moved
out=$("$tool") || fail "second run failed"
grep -q 'changed 0 place(s) in 0 file(s), renamed 0 file(s)' <<<"$out" || fail "a second run changed something: $out"
[ -z "$(git status --porcelain)" ] || fail "a second run left changes"
echo "migrate tool ok"
