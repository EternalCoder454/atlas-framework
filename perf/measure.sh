#!/bin/bash
# Measures the app template running on the built Atlas.Ui, headless, and
# compares the numbers with perf/budget.json.
#
#   perf/measure.sh [framework-build-dir]     (default ./build; run in the dev container)
#
#   startup_ms        from exec until the app's window is mapped (median of 3 starts)
#   rss_kb, pss_kb    from /proc/<pid>/smaps_rollup after 3 s idle
#   idle_cpu_percent  CPU time over 10 s idle (all threads), as a share of one core
#                     (not zero: the template's page shows live data, two charts
#                     and a table updated once a second, as a monitor app would)
#
# Writes perf/out.json (or $PERF_OUT) and exits 1 when any figure is over budget.
# Atlas.Ui has to be installed where Qt looks (the template's CMake reads it
# from there); as root in a container the script always installs the build it
# measures into /usr, so an older copy there is never measured by mistake.
# Anywhere else the installed qmldir must be the build's own, or it exits 2.
# Exit 2 also when the budget file or one of its four keys is missing.
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
        local t0 t1 deadline win=""
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
    # Nanoseconds on a CPU, summed over the app's threads (schedstat's first
    # field). The stat file's clock ticks are 10 ms: over 5 s that reads only
    # in 0.2 % steps, too coarse for the budget. A thread that ends in the
    # window takes its time with it, which an idle app doesn't do.
    # An unreadable schedstat (not enabled, no permission) or a zero total
    # would read as 0 % CPU and pass: fail instead.
    oncpu() {
        local total
        total=$(cat /proc/"$pid"/task/*/schedstat 2>/dev/null | awk '{ns += $1} END {printf "%.0f", ns}')
        if [ -z "$total" ] || [ "$total" -le 0 ]; then
            echo "measure: cannot read CPU time from /proc/$pid/task/*/schedstat (is it enabled?)" >&2
            return 1
        fi
        printf '%s' "$total"
    }
    c0=$(oncpu) || exit 1
    s0=$(date +%s%N)
    sleep 10
    c1=$(oncpu) || exit 1
    s1=$(date +%s%N)
    cpu=$(awk -v a="$c0" -v b="$c1" -v s="$s0" -v e="$s1" 'BEGIN { printf "%.2f", (b - a) / (e - s) * 100 }')
    stop

    jq -n --argjson all "$(printf '%s\n' "${starts[@]}" | jq -s .)" \
        --argjson startup "$median" --argjson rss "$rss" --argjson pss "$pss" --argjson cpu "$cpu" \
        '{startup_ms: $startup, rss_kb: $rss, pss_kb: $pss, idle_cpu_percent: $cpu, startups_ms: $all}' >"$work/result.json"
    exit 0
fi

build=${1:-$root/build}
build=$(cd "$build" && pwd) || {
    echo "measure: no build directory $build" >&2
    exit 2
}
# The budget first: a missing file or key must not cost a full measurement.
if [ ! -f "$budget" ]; then
    echo "measure: no budget at $budget" >&2
    exit 2
fi
for key in startup_ms rss_kb pss_kb idle_cpu_percent; do
    if ! jq -e --arg k "$key" '.[$k] | type == "number"' "$budget" >/dev/null 2>&1; then
        echo "measure: $budget has no number for $key" >&2
        exit 2
    fi
done
work=$(mktemp -d "${TMPDIR:-/tmp}/atlas-perf.XXXXXX")
trap 'rm -rf "$work"' EXIT

# Atlas.Ui where the template's CMake looks for it: always the build being
# measured, never whatever copy was installed before.
qml_dir=$(qmake6 -query QT_INSTALL_QML)
if [ "$(id -u)" -eq 0 ] && { [ -e /run/.containerenv ] || [ -e /.dockerenv ] || [ "${ATLAS_PERF_INSTALL:-}" = 1 ]; }; then
    # Only into a container's /usr, never over a host system's.
    cmake --install "$build" --prefix /usr >/dev/null
elif [ ! -f "$qml_dir/Atlas/Ui/qmldir" ]; then
    echo "measure: Atlas.Ui is not installed in $qml_dir; run as root in the dev container (or install it yourself)" >&2
    exit 2
elif ! cmp -s "$build/Atlas/Ui/qmldir" "$qml_dir/Atlas/Ui/qmldir"; then
    echo "measure: the Atlas.Ui in $qml_dir is not the one built in $build; install the build, or run as root in the dev container" >&2
    exit 2
fi

# The template, in Release, with its own target directory. CI keeps the
# build tree between runs (ATLAS_PERF_TEMPLATE_BUILD) so it only rebuilds what
# changed; by default it is temporary.
tbuild=${ATLAS_PERF_TEMPLATE_BUILD:-$work/template}
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$tbuild/target}
cmake -S "$root/template" -B "$tbuild" -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$tbuild" >"$work/build.log" 2>&1 || {
    tail -n 40 "$work/build.log" >&2
    echo "measure: the template did not build" >&2
    exit 1
}
bin=$tbuild/atlas-app-template
[ -x "$bin" ] || {
    echo "measure: $bin was not built" >&2
    exit 1
}

dbus-run-session -- xvfb-run -a -s "-screen 0 1920x1080x24" "$here/measure.sh" --inner "$bin" "$work"
cp "$work/result.json" "$out.tmp"
mv "$out.tmp" "$out"
echo "measure: wrote $out"
cat "$out"

# Compare with the budget. Keys in PERF_WARN_ONLY (space-separated; CI passes
# startup_ms, which a shared runner makes noisy) warn instead of failing.
status=0
for key in startup_ms rss_kb pss_kb idle_cpu_percent; do
    limit=$(jq -r --arg k "$key" '.[$k]' "$budget")
    value=$(jq -r --arg k "$key" '.[$k]' "$out")
    if awk -v v="$value" -v l="$limit" 'BEGIN { exit !(v > l) }'; then
        if [[ " ${PERF_WARN_ONLY:-} " == *" $key "* ]]; then
            echo "::warning::over budget (not failing): $key is $value, budget $limit"
        else
            echo "OVER BUDGET: $key is $value, budget $limit"
            status=1
        fi
    else
        echo "ok: $key $value (budget $limit)"
    fi
done
exit "$status"
