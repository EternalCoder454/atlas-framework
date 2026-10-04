#!/bin/bash
# Runs the visual tests for one variant (light, dark, accent, opaque) in a
# private, deterministic environment: its own XDG directories, the software
# renderer, scale 1, the org.kde.desktop style, an X server of its own.
#
#   run-variant.sh <variant>
#
# Needs ATLAS_TEST_BIN, ATLAS_DEMO_DIR, ATLAS_GOLDEN_DIR, ATLAS_OUT_DIR (ctest
# sets them), and the colour schemes under tests/visual/schemes.
set -euo pipefail

variant=${1:?usage: run-variant.sh light|dark|accent|opaque}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
: "${ATLAS_TEST_BIN:?}" "${ATLAS_DEMO_DIR:?}" "${ATLAS_GOLDEN_DIR:?}" "${ATLAS_OUT_DIR:?}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_CONFIG_HOME=$tmp/config XDG_DATA_HOME=$tmp/data XDG_CACHE_HOME=$tmp/cache
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

accent="229,72,122" # #e5487a
case $variant in
light | opaque) cp "$here/schemes/BreezeLight.colors" "$XDG_CONFIG_HOME/kdeglobals" ;;
dark) cp "$here/schemes/BreezeDark.colors" "$XDG_CONFIG_HOME/kdeglobals" ;;
accent)
    # What Plasma writes when an accent colour is chosen: the colour in the
    # highlight, focus and hover decorations, and the selection background.
    awk -v c="$accent" '
        /^\[/ { section = $0 }
        /^DecorationFocus=|^DecorationHover=/ { sub(/=.*/, "=" c) }
        section == "[Colors:Selection]" && /^BackgroundNormal=/ { sub(/=.*/, "=" c) }
        { print }
        END { print "\n[General]\nAccentColor=" c }
    ' "$here/schemes/BreezeLight.colors" >"$XDG_CONFIG_HOME/kdeglobals"
    ;;
*)
    echo "unknown variant: $variant" >&2
    exit 2
    ;;
esac
if [ "$variant" = opaque ]; then
    # Transparency off. It only shows on windows, so only those are compared.
    printf '[Appearance]\nTransparency=false\n' >"$XDG_CONFIG_HOME/atlasrc"
    export ATLAS_DEMO_FILTER='^(AtlasWindow|AtlasPage|AtlasAboutPage)$'
fi

export ATLAS_VARIANT=$variant
# The About page shows the OS and Qt version: pin them for the pictures.
export ATLAS_UI_TEST_FIXED_ENV=1
export QT_QUICK_BACKEND=software
export QT_SCALE_FACTOR=1
export QT_FONT_DPI=96
export QT_QPA_PLATFORM=xcb
export QT_QUICK_CONTROLS_STYLE=org.kde.desktop
export QT_QPA_PLATFORMTHEME=
export QT_LOGGING_RULES='qt.qpa.fonts=false'
unset WAYLAND_DISPLAY KDE_FULL_SESSION XDG_CURRENT_DESKTOP
# English, whatever the machine's language, so a translation never reaches the
# pictures. The i18n test brings its own catalogue and language: it keeps them.
if [ -z "${ATLAS_UI_TRANSLATIONS_DIR:-}" ]; then
    export LANG=C.UTF-8 LC_ALL=C.UTF-8
    unset LANGUAGE
fi

# Passing the dbus session keeps KDE libraries from starting services on the
# user's bus when this runs on a desktop. Not `exec`: the EXIT trap removes
# the temporary directory, and the test's status is passed on.
rc=0
dbus-run-session -- xvfb-run -a -s "-screen 0 1920x1080x24" "$ATLAS_TEST_BIN" -platform xcb || rc=$?
exit "$rc"
