#!/bin/bash
# Measures the app template running on the built Atlas.Ui, headless, and
# compares the numbers with perf/budget.json.
#
#   perf/measure.sh [framework-build-dir]     (default ./build; run in the dev container)
#
#   startup_ms        from exec until the app's window is mapped (median of 3 starts)
#   rss_kb, pss_kb    from /proc/<pid>/smaps_rollup after 3 s idle
#   idle_cpu_percent  CPU time over 5 s idle, as a share of one core
#
# Writes perf/out.json (or $PERF_OUT) and exits 1 when any figure is over budget.
# Atlas.Ui has to be installed where Qt looks (the template's CMake reads it
# from there); as root the script installs the build into /usr when it is not.
# Everything the app writes goes to a temporary XDG tree.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(dirname "$here")
out=${PERF_OUT:-$here/out.json}
budget=${PERF_BUDGET:-$here/budget.json}

if [ "${1:-}" = "--inner" ]; then
    # Inside dbus-run-session and xvfb-run: $2 is the binary, $3 the work dir.
    bin=$2
    work=$3
    export XDG_CONFIG_HOME=$work/config XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work/cache XDG_STATE_HOME=$work/state
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
    export QT_QPA_PLATFORM=xcb QT_QUICK_BACKEND=software QT_SCALE_FACTOR=1
    unset WAYLAND_DISPLAY

    pid=
    stop() {
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
        pid=
    }
    trap stop EXIT

    # Starts the app, waits for its window to be mapped, and sets START_MS.
    # (Not run in a subshell: `pid` has to stay known to stop().)
    start() {
        local t0 t1 win= deadline
        t0=$(date +%s%N)
        "$bin" >"$work/app.log" 2>&1 &
        pid=$!
        deadline=$((t0 / 1000000 + 60000))
        # xdotool's own --sync waits without a limit; this polls every 10 ms.
        while [ -z "$win" ]; do
            win=$(xdotool search --onlyvisible --pid "$pid" 2>/dev/null | head -n1 || true)
            [ -n "$win" ] && break
            if ! kill -0 "$pid" 2>/dev/null || [ "$(($(date +%s%N) / 1000000))" -gt "$deadline" ]; then
                echo "measure: no window (the app exited or took over 60 s); it said:" >&2
                tail -n 20 "$work/app.log" >&2
                exit 1
            fi
            sleep 0.01
        done
        t1=$(date +%s%N)
        START_MS=$(((t1 - t0) / 1000000))
    }

    starts=()
    for _ in 1 2 3; do
        start
        starts+=("$START_MS")
        stop
    done
    median=$(printf '%s\n' "${starts[@]}" | sort -n | sed -n 2p)

    # One more run for memory and CPU.
    start
    sleep 3
    rss=$(awk '/^Rss:/ {print $2}' "/proc/$pid/smaps_rollup")
    pss=$(awk '/^Pss:/ {print $2}' "/proc/$pid/smaps_rollup")
    ticks() { sed 's/.*) //' "/proc/$pid/stat" | awk '{print $12 + $13}'; }
    c0=$(ticks)
    s0=$(date +%s.%N)
    sleep 5
    c1=$(ticks)
    s1=$(date +%s.%N)
    cpu=$(awk -v a="$c0" -v b="$c1" -v s="$s0" -v e="$s1" -v hz="$(getconf CLK_TCK)" 'BEGIN { printf "%.2f", (b - a) / hz / (e - s) * 100 }')
    stop

    jq -n --argjson all "$(printf '%s\n' "${starts[@]}" | jq -s .)" \
        --argjson startup "$median" --argjson rss "$rss" --argjson pss "$pss" --argjson cpu "$cpu" \
        '{startup_ms: $startup, rss_kb: $rss, pss_kb: $pss, idle_cpu_percent: $cpu, startups_ms: $all}' >"$work/result.json"
    exit 0
fi

build=${1:-$root/build}
build=$(cd "$build" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/atlas-perf.XXXXXX")
trap 'rm -rf "$work"' EXIT

# Atlas.Ui where the template's CMake looks for it.
qml_dir=$(qmake6 -query QT_INSTALL_QML)
if [ ! -f "$qml_dir/Atlas/Ui/qmldir" ]; then
    if [ "$(id -u)" -ne 0 ]; then
        echo "measure: Atlas.Ui is not installed in $qml_dir; run as root in the container or install it" >&2
        exit 2
    fi
    cmake --install "$build" --prefix /usr >/dev/null
fi

# The template, in Release, with its own target directory.
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$work/target}
cmake -S "$root/template" -B "$work/template" -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$work/template" >"$work/build.log" 2>&1 || {
    tail -n 40 "$work/build.log" >&2
    echo "measure: the template did not build" >&2
    exit 1
}
bin=$work/template/atlas-app-template
[ -x "$bin" ] || {
    echo "measure: $bin was not built" >&2
    exit 1
}

dbus-run-session -- xvfb-run -a -s "-screen 0 1920x1080x24" "$here/measure.sh" --inner "$bin" "$work"
cp "$work/result.json" "$out.tmp"
mv "$out.tmp" "$out"
echo "measure: wrote $out"
cat "$out"

# Compare with the budget.
status=0
if [ ! -f "$budget" ]; then
    echo "measure: no budget at $budget; nothing to compare" >&2
else
    for key in startup_ms rss_kb pss_kb idle_cpu_percent; do
        limit=$(jq -r --arg k "$key" '.[$k] // empty' "$budget")
        value=$(jq -r --arg k "$key" '.[$k]' "$out")
        [ -n "$limit" ] || continue
        if awk -v v="$value" -v l="$limit" 'BEGIN { exit !(v > l) }'; then
            echo "OVER BUDGET: $key is $value, budget $limit"
            status=1
        else
            echo "ok: $key $value (budget $limit)"
        fi
    done
fi
exit "$status"
