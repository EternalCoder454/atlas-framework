# tests

Built with `-DATLAS_UI_TESTS=ON` (off by default, so the RPM build is
unchanged). In the dev container:

```sh
cmake -S . -B build -G Ninja -DATLAS_UI_TESTS=ON && cmake --build build
ctest --test-dir build -j"$(nproc)" --output-on-failure
```

Or, from the host, `tools/dev-check.sh [Type...]` does the build, the tests
and the other checks in the container. The tests run in parallel: each one
starts its own X server at a display number of its own, and a picture is
compared as soon as the demo is drawn, then again every 200 ms (up to 3 s)
until it matches, so a busy machine is slower, not red.

## Visual tests (`visual/`)

Qt Quick Test. Every `ui/gallery/demos/*Demo.qml` is found at run time, shown,
grabbed and compared with `visual/golden/<variant>/<Demo>.png`. A new control
needs a `<Type>Demo.qml` (an `Item` or layout, no window, no timers or
randomness; a root `property bool animate` is switched off before the grab) and
its goldens, nothing else. A window demo (`AtlasWindowDemo`) has an
`AtlasWindow`-style root and the whole window is grabbed.

- Per-channel tolerance 2; fails when more than 0.1% of the pixels differ.
- A failure writes `<Demo>.actual.png` and `<Demo>.diff.png` (differences in
  red) to `build/visual-out/<variant>/` and names them.
- `ATLAS_UPDATE_GOLDENS=1 ctest --test-dir build -R visual` rewrites the
  goldens. Approving a change means committing them: the reviewer sees the new
  pictures in the pull request.
- Variants, each in its own temporary `XDG_CONFIG_HOME`: `light` (Breeze
  Light), `dark` (Breeze Dark), `accent` (Breeze Light with `#e5487a` as the
  accent in kdeglobals), `opaque` (`atlasrc` `Transparency=false`; only the
  window-level demos), `contrast` (the high-contrast scheme in
  `visual/schemes/`, a Qt palette to match, and `visual/fake-portal.cpp`
  answering "contrast: more" on the private bus: Qt takes
  `Appearance.highContrast` from the settings portal only), `rtl` (the
  application's layout direction, the stage and the window overlay mirrored),
  `compact` (`AtlasStyle.density = Compact`), `text200` (Noto Sans 20, so
  `textScale` is 2). `test_variant_is_on` fails when a variant is not really on.
  Regenerate the four newest with
  `ATLAS_UPDATE_GOLDENS=1 ctest --test-dir build -R 'visual-(contrast|rtl|compact|text200)'`.
- Deterministic: `QT_QUICK_BACKEND=software`, `QT_SCALE_FACTOR=1`, Noto Sans 10,
  `org.kde.desktop`, `xvfb-run`, X11. The goldens are made in the dev
  container; another Qt or font version gives different pictures (`AtlasAboutPage`
  also shows the OS name and Qt version).
- `visual/schemes/` holds the Breeze colour schemes the variants start from, so
  the pictures do not follow the distribution's copy.

## Accessibility and translation tests

- `a11y/`: loads every demo and fails on any visible, enabled item that Tab
  reaches without an `Accessible.role` or `Accessible.name`, naming the demo,
  the item type and its path. A new control with a demo is covered at once.
  It also walks every demo with Tab (200 presses at most, else a focus trap):
  each item reached must be visible and sized, the order must be reading order
  (rows top to bottom, left to right, right to left under RTL; compared as a
  ring) and Shift+Tab must retrace it. `tabOrderExceptions` at the top of
  `tst_a11y.qml` lists the demos with another intended order, each with its reason.
- `state/`: the state contract of docs/DESIGN.md on every demo, in 4 shards
  (`state-0` to `state-3`): with the root disabled Tab reaches nothing and the
  picture changes; each item Tab reaches looks different with keyboard focus
  (its picture plus 12 px around it, with and without focus; the pictures of
  a failure go to `build/state-out-<n>/`). The allow-list at the top of
  `tst_state.qml` names the demos where a check cannot apply, with the reason;
  a listed demo that passes fails the test until the entry is removed.
- `i18n/`: with `LANGUAGE=de` and a throwaway `atlas-ui_de.qm` (built from
  `i18n/atlas-ui_de.ts`), a default `SearchField` must show the German string.
  Needs qt6-linguist; skipped without it.
