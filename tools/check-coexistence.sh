#!/bin/bash
# Checks that the Telamon framework's RPMs install beside the Atlas.Ui 1.x ones
# (apps that have not moved yet still need those), in a fedora:44 container:
#
#   tools/check-coexistence.sh <dir with atlas-ui 1.x RPMs> <dir with telamon-ui RPMs>
#
# - no file path is in both sets, and no path of the Telamon set has "atlas" in it;
# - both sets install in ONE dnf transaction with no conflict, and the packages
#   of both generations are installed afterwards;
# - the font families do not clash ("Material Symbols Rounded" and "Telamon
#   Symbols Rounded" are both there);
# - a QML file importing Atlas.Ui loads, one importing Telamon.Ui loads, and
#   one importing both (each as a prefix of its own) loads and uses a type of each.
#
# The container is started from registry.fedoraproject.org/fedora:44 (it
# downloads the RPMs' dependencies) and runs nothing on the host. The RPM
# directories are mounted read-only.
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: check-coexistence.sh <atlas rpm dir> <telamon rpm dir>" >&2
    exit 2
fi
old=$(cd "$1" && pwd)
new=$(cd "$2" && pwd)
for d in "$old" "$new"; do
    case $d in
    *[:,]*)
        echo "check-coexistence: ':' and ',' are not allowed in $d (podman would read them as mount options)" >&2
        exit 2
        ;;
    esac
    if ! ls "$d"/*.rpm >/dev/null 2>&1; then
        echo "check-coexistence: no RPMs in $d" >&2
        exit 2
    fi
done

exec podman run --rm --security-opt label=disable -v "$old:/old:ro" -v "$new:/new:ro" \
    registry.fedoraproject.org/fedora:44 bash -euo pipefail -c '
fail() { echo "check-coexistence: FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

# 1. File paths
for set in old new; do
    : >/tmp/$set.files
    # Files and links only: directories (/usr/lib/.build-id, /usr/share/fonts) may be owned by both.
    for r in /$set/*.rpm; do rpm -qp --qf "[%{FILEMODES:perms} %{FILENAMES}\\n]" "$r" 2>/dev/null | grep -v "^d" | cut -d" " -f2- >>/tmp/$set.files; done
    sort -u -o /tmp/$set.files /tmp/$set.files
    echo "$set: $(ls /$set/*.rpm | wc -l) packages, $(wc -l </tmp/$set.files) paths"
done
shared=$(comm -12 /tmp/old.files /tmp/new.files | grep -v "^/usr/share/licenses/\|^/usr/share/doc/" || true)
if [ -n "$shared" ]; then
    echo "$shared" >&2
    fail "these paths are in both sets"
fi
ok "no file or link is in both sets (licence and doc files aside)"
if grep -i atlas /tmp/new.files >&2; then
    fail "a path of the Telamon set has atlas in it"
fi
ok "no path of the Telamon set has atlas in it"
# the build-id links of two packages cannot be the same file either
dup=$(comm -12 <(grep "^/usr/lib/.build-id/" /tmp/old.files) <(grep "^/usr/lib/.build-id/" /tmp/new.files) || true)
[ -z "$dup" ] || fail "the same build-id link is in both sets: $dup"

# 2. One transaction
dnf -y -q install --setopt=install_weak_deps=False /old/*.rpm /new/*.rpm >/tmp/dnf.log 2>&1 || { tail -30 /tmp/dnf.log >&2; fail "dnf could not install both sets together"; }
for p in atlas-ui atlas-symbols-fonts telamon-ui telamon-symbols-fonts; do
    rpm -q "$p" >/dev/null || fail "$p is not installed after the transaction"
done
rpm -qa | grep -E "^(atlas|telamon)-" | sort
ok "both generations installed in one transaction"

# 3. Fonts
fc-cache -f >/dev/null 2>&1 || true
fonts=$(fc-list : family | sort -u)
echo "$fonts" | grep -E "Material Symbols|Telamon Symbols" || true
echo "$fonts" | grep -q "^Material Symbols Rounded" || fail "the 1.x font family is gone"
echo "$fonts" | grep -q "^Telamon Symbols Rounded" || fail "the Telamon font family is missing"
ok "both Symbols font families are there"

# 4. QML
dnf -y -q install --setopt=install_weak_deps=False qt6-qtdeclarative-devel qt6-qtbase-gui >/tmp/dnf2.log 2>&1 || { tail -20 /tmp/dnf2.log >&2; fail "cannot install the qml tool"; }
qml=/usr/lib64/qt6/bin/qml
mkdir /tmp/q && cd /tmp/q
cat >atlas.qml <<QML
import QtQuick
import Atlas.Ui
Item {
    Component.onCompleted: {
        console.warn("LOADED atlas " + AtlasApp.uiVersion + " " + (typeof AtlasStyle.accent));
        Qt.quit();
    }
    AtlasButton { text: "x" }
}
QML
cat >telamon.qml <<QML
import QtQuick
import Telamon.Ui
Item {
    Component.onCompleted: {
        console.warn("LOADED telamon " + TelamonApp.uiVersion + " " + (typeof TelamonStyle.accent));
        Qt.quit();
    }
    TelamonButton { text: "x" }
}
QML
cat >both.qml <<QML
import QtQuick
import Atlas.Ui as A
import Telamon.Ui as T
Item {
    Component.onCompleted: {
        console.warn("LOADED both " + A.AtlasApp.uiVersion + " " + T.TelamonApp.uiVersion);
        Qt.quit();
    }
    A.AtlasButton { text: "old" }
    T.TelamonButton { text: "new" }
}
QML
export LANG=C.UTF-8 QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen
for f in atlas telamon both; do
    # console.warn: the distribution turns debug messages off.
    out=$(timeout 60 "$qml" $f.qml 2>&1) || { echo "$out" >&2; fail "$f.qml did not run"; }
    echo "$out" | grep -q "LOADED $f" || { echo "$out" >&2; fail "$f.qml did not load"; }
    # Nothing but the load message and what any headless Qt app prints.
    extra=$(echo "$out" | grep -vE "LOADED|^kf.windowsystem: Could not find any platform plugin|^(Atlas|Telamon).Ui: graphics API|^Detected locale|^Qt depends on a UTF-8|^If this causes|^for more information|^$" || true)
    [ -z "$extra" ] || { echo "$extra" >&2; fail "$f.qml logged something unexpected"; }
    echo "$out" | grep "LOADED"
done
ok "QML files importing Atlas.Ui, Telamon.Ui and both load"
echo "check-coexistence: all checks passed"
'
