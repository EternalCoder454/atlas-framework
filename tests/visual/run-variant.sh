#!/bin/bash
# Runs the visual tests for one variant (light, dark, accent, opaque, contrast, rtl, compact,
# text200) in a
# private, deterministic environment: its own XDG directories, the software
# renderer, scale 1, the org.kde.desktop style, an X server of its own.
#
#   run-variant.sh <variant>
#
# Needs TELAMON_TEST_BIN, TELAMON_DEMO_DIR, TELAMON_GOLDEN_DIR, TELAMON_OUT_DIR (ctest
# sets them), and the colour schemes under tests/visual/schemes.
#
# Optional: TELAMON_TEST_BACKEND=opengl runs the GPU renderer (Mesa's software
# OpenGL in the container) instead of the software one, and TELAMON_TEST_SCALE
# sets the scale factor (default 1). Only visual-filled-symbols uses them.
set -euo pipefail

variant=${1:?usage: run-variant.sh light|dark|accent|opaque|contrast|rtl|compact|text200}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
: "${TELAMON_TEST_BIN:?}" "${TELAMON_DEMO_DIR:?}" "${TELAMON_GOLDEN_DIR:?}" "${TELAMON_OUT_DIR:?}"

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
    printf '[Appearance]\nTransparency=false\n' >"$XDG_CONFIG_HOME/telamonrc"
    export TELAMON_DEMO_FILTER='^(TelamonWindow|TelamonPage|TelamonAboutPage|ContextMenu|TelamonPopover|TelamonDialog|ConfirmDialog|TelamonCommandPalette|TelamonShortcutsDialog|Toast|TelamonToolTip|TelamonComboBox|TelamonDatePicker|TelamonTransparencySwitch)$'
fi

export TELAMON_VARIANT=$variant
# The About page shows the OS and Qt version: pin them for the pictures.
export TELAMON_UI_TEST_FIXED_ENV=1
backend=${TELAMON_TEST_BACKEND:-software}
case $backend in
software) export QT_QUICK_BACKEND=software ;;
opengl)
    # The scene graph's own renderer, the one a desktop runs, on Mesa's software
    # OpenGL so that it needs no GPU and draws the same on every machine.
    unset QT_QUICK_BACKEND
    export QSG_RHI_BACKEND=opengl LIBGL_ALWAYS_SOFTWARE=1
    ;;
*)
    echo "run-variant: unknown TELAMON_TEST_BACKEND: $backend" >&2
    exit 2
    ;;
esac
# Pin TelamonStyle.softwareRendering to false: the flag is detected on the first
# frame, which would race the first grabs, and the goldens show the animated
# controls. A test sets TELAMON_SOFTWARE_RENDERING (even empty, for detection).
export TELAMON_SOFTWARE_RENDERING="${TELAMON_SOFTWARE_RENDERING-0}"
export QT_SCALE_FACTOR=${TELAMON_TEST_SCALE:-1}
export QT_FONT_DPI=96
export QT_QPA_PLATFORM=xcb
export QT_QUICK_CONTROLS_STYLE=org.kde.desktop
export QT_QPA_PLATFORMTHEME=
if [ "$variant" = contrast ]; then
    # Qt learns "high contrast" only from the settings portal: a stand-in
    # answers on the private bus (see fake-portal.cpp).
    : "${TELAMON_FAKE_PORTAL:?}"
    export QT_QPA_PLATFORMTHEME=xdgdesktopportal
fi
export QT_LOGGING_RULES='qt.qpa.fonts=false'
unset WAYLAND_DISPLAY KDE_FULL_SESSION XDG_CURRENT_DESKTOP
# English, whatever the machine's language, so a translation never reaches the
# pictures. The i18n test brings its own catalogue and language: it keeps them.
if [ -z "${TELAMON_UI_TRANSLATIONS_DIR:-}" ]; then
    export LANG=C.UTF-8 LC_ALL=C.UTF-8
    unset LANGUAGE
fi

# Passing the dbus session keeps KDE libraries from starting services on the
# user's bus when this runs on a desktop. Not `exec`: the EXIT trap removes
# the temporary directory, and the test's status is passed on.
# Each test starts looking for a free X display at its own number: tests run
# in parallel (ctest -j), and two `xvfb-run -a` started at once can pick the
# same display and draw into each other's screen.
# The test bus: no service directories, and its socket in this run's own
# private directory (removed with $tmp by the trap above).
busconf=$tmp/bus.conf
case $tmp in
*[\<\>\&\"\,\;\%]*)
    echo "run-variant: unsafe characters in $tmp" >&2
    exit 1
    ;;
esac
template=$(<"$here/../private-bus.conf")
[[ $template == *@LISTEN@* ]] || {
    echo "run-variant: private-bus.conf has no @LISTEN@ line" >&2
    exit 1
}
# printf, so nothing in $tmp is read as a replacement pattern.
printf '%s\n' "${template%%@LISTEN@*}unix:dir=$tmp${template#*@LISTEN@}" >"$busconf"
grep -q '<listen>unix:dir=' "$busconf" || {
    echo "run-variant: the test bus config has no listen address" >&2
    exit 1
}
display=$((100 + $(printf '%s' "$TELAMON_TEST_BIN $variant $TELAMON_OUT_DIR" | cksum | cut -d' ' -f1) % 800))
rc=0
if [ "$variant" = contrast ]; then
    # Start the portal stand-in inside the bus, wait until it answers, run the
    # test, then stop it. $1 is the portal, $2 the ready file; the rest is the
    # test command.
    dbus-run-session --config-file="$busconf" -- bash -c '
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
    ' bash "$TELAMON_FAKE_PORTAL" "$tmp/portal-ready" \
        xvfb-run -a -n "$display" -s "-screen 0 1920x1080x24" "$TELAMON_TEST_BIN" -platform xcb || rc=$?
else
    dbus-run-session --config-file="$busconf" -- xvfb-run -a -n "$display" -s "-screen 0 1920x1080x24" "$TELAMON_TEST_BIN" -platform xcb || rc=$?
fi
exit "$rc"
