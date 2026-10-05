#!/bin/bash
# Runs the visual tests for one variant (light, dark, accent, opaque, contrast, rtl, compact,
# text200) in a
# private, deterministic environment: its own XDG directories, the software
# renderer, scale 1, the org.kde.desktop style, an X server of its own.
#
#   run-variant.sh <variant>
#
# Needs ATLAS_TEST_BIN, ATLAS_DEMO_DIR, ATLAS_GOLDEN_DIR, ATLAS_OUT_DIR (ctest
# sets them), and the colour schemes under tests/visual/schemes.
set -euo pipefail

variant=${1:?usage: run-variant.sh light|dark|accent|opaque|contrast|rtl|compact|text200}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
: "${ATLAS_TEST_BIN:?}" "${ATLAS_DEMO_DIR:?}" "${ATLAS_GOLDEN_DIR:?}" "${ATLAS_OUT_DIR:?}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_CONFIG_HOME=$tmp/config XDG_DATA_HOME=$tmp/data XDG_CACHE_HOME=$tmp/cache
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

accent="229,72,122" # #e5487a
case $variant in
light | opaque | rtl | compact | text200) cp "$here/schemes/BreezeLight.colors" "$XDG_CONFIG_HOME/kdeglobals" ;;
dark) cp "$here/schemes/BreezeDark.colors" "$XDG_CONFIG_HOME/kdeglobals" ;;
contrast) cp "$here/schemes/BreezeHighContrast.colors" "$XDG_CONFIG_HOME/kdeglobals" ;;
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
    export ATLAS_DEMO_FILTER='^(AtlasWindow|AtlasPage|AtlasAboutPage|ContextMenu|AtlasPopover|AtlasDialog|ConfirmDialog|AtlasCommandPalette|AtlasShortcutsDialog|Toast|AtlasToolTip|AtlasComboBox|AtlasDatePicker|AtlasTransparencySwitch)$'
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
if [ "$variant" = contrast ]; then
    # Qt learns "high contrast" only from the settings portal: a stand-in
    # answers on the private bus (see fake-portal.cpp).
    : "${ATLAS_FAKE_PORTAL:?}"
    export QT_QPA_PLATFORMTHEME=xdgdesktopportal
fi
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
# Each test starts looking for a free X display at its own number: tests run
# in parallel (ctest -j), and two `xvfb-run -a` started at once can pick the
# same display and draw into each other's screen.
display=$((100 + $(printf '%s' "$ATLAS_TEST_BIN $variant $ATLAS_OUT_DIR" | cksum | cut -d' ' -f1) % 800))
rc=0
if [ "$variant" = contrast ]; then
    # Start the portal stand-in inside the bus, wait until it answers, run the
    # test, then stop it. $1 is the portal, $2 the ready file; the rest is the
    # test command.
    dbus-run-session -- bash -c '
        portal=$1 ready=$2
        shift 2
        "$portal" "$ready" &
        pid=$!
        trap "kill $pid 2>/dev/null; wait $pid 2>/dev/null" EXIT
        for _ in $(seq 100); do
            [ -e "$ready" ] && break
            kill -0 "$pid" 2>/dev/null || { echo "fake-portal exited" >&2; exit 1; }
            sleep 0.1
        done
        [ -e "$ready" ] || { echo "fake-portal did not start" >&2; exit 1; }
        "$@"
    ' bash "$ATLAS_FAKE_PORTAL" "$tmp/portal-ready" \
        xvfb-run -a -n "$display" -s "-screen 0 1920x1080x24" "$ATLAS_TEST_BIN" -platform xcb || rc=$?
else
    dbus-run-session -- xvfb-run -a -n "$display" -s "-screen 0 1920x1080x24" "$ATLAS_TEST_BIN" -platform xcb || rc=$?
fi
exit "$rc"
