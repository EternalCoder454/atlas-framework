# perf

`perf/measure.sh [build-dir]` (in the dev container) builds `template/` in
Release against the installed Atlas.Ui, starts it under `dbus-run-session` and
`xvfb-run` (software renderer, temporary XDG tree) and writes `perf/out.json`:
startup (exec to mapped window, median of 3), Rss and Pss after 3 s idle, and
idle CPU over 10 s. It exits 1 when a figure is over `perf/budget.json`, and 2
when the budget file or one of its four keys is missing. In the dev container
it installs the build it measures into `/usr` first.

Measured (dev container, software rendering) and budget (measured + 25%;
the values in `budget.json` are the ones that count):

| Figure | Measured | Budget |
|---|---|---|
| startup_ms | 151 | 190 |
| rss_kb | 103368 | 129200 |
| pss_kb | 91825 | 114800 |
| idle_cpu_percent | 0.20 | 1.0 (a floor: the figure is noisy; `budget.json` has the value) |

The first start after boot is slower (427 ms seen), hence the median. CI
runners are slower than this machine; if the startup budget flaps there,
raise it from the numbers in the job summary.
