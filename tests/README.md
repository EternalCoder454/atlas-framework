# tests

Built with `-DTELAMON_UI_TESTS=ON` (off by default, so the RPM build is
unchanged). In the dev container:

```sh
cmake -S . -B build -G Ninja -DTELAMON_UI_TESTS=ON && cmake --build build
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
its goldens, nothing else. A window demo (`TelamonWindowDemo`) has an
`TelamonWindow`-style root and the whole window is grabbed.

- Per-channel tolerance 2; fails when more than 0.1% of the pixels differ.
- A failure writes `<Demo>.actual.png` and `<Demo>.diff.png` (differences in
  red) to `build/visual-out/<variant>/` and names them.
- `TELAMON_UPDATE_GOLDENS=1 ctest --test-dir build -R visual` rewrites the
  goldens that fail (one that still matches within the tolerance is left
  alone, so the diff holds only real changes); `tools/dev-check.sh` passes
  the variable through. Approving a change means committing them: the reviewer sees the new
  pictures in the pull request.
- Variants, each in its own temporary `XDG_CONFIG_HOME`: `light` (Breeze
  Light), `dark` (Breeze Dark), `accent` (Breeze Light with `#e5487a` as the
  accent in kdeglobals), `opaque` (`telamonrc` `Transparency=false`; only the
  window-level demos), `contrast` (the high-contrast scheme in
  `visual/schemes/`, a Qt palette to match, and `visual/fake-portal.cpp`
  answering "contrast: more" on the private bus: Qt takes
  `Appearance.highContrast` from the settings portal only), `rtl` (the
  application's layout direction, the stage and the window overlay mirrored),
  `compact` (`TelamonStyle.density = Compact`), `text200` (Noto Sans 20, so
  `textScale` is 2). `test_variant_is_on` fails when a variant is not really on.
  Regenerate the four newest with
  `TELAMON_UPDATE_GOLDENS=1 ctest --test-dir build -R 'visual-(contrast|rtl|compact|text200)'`.
- Deterministic: `QT_QUICK_BACKEND=software`, `QT_SCALE_FACTOR=1`, Noto Sans 10,
  `org.kde.desktop`, `xvfb-run`, X11. The goldens are made in the dev
  container; another Qt or font version gives different pictures (`TelamonAboutPage`
  also shows the OS name and Qt version).
- `visual/schemes/` holds the Breeze colour schemes the variants start from, so
  the pictures do not follow the distribution's copy.
- The sample texts the pictures show are fixtures. The rename to Telamon
  (2.0.0) changed no golden, to the byte, so the texts that show in one keep
  their wording from before ("Atlas Notepad", `AtlasListView: ...`, the
  application name `atlas-visual-tests` set in `visual/main.cpp`, "Atlas Test
  OS" in `ui/telamonapp.cpp`). Change one with its golden, on purpose.

## Filled symbols on the GPU renderer (`visual-filled-symbols-<scale>`)

The visual tests draw with the software renderer, and a symbol at FILL 1 comes
out right there even when it is broken on the GPU renderer (distance-field
text), which is what a desktop runs. `visual-filled-symbols-1` and `-1.7` run
`visual/rhi-demos/SidebarItemFilledDemo.qml` (selected and unselected
`SidebarItem` with `VolumeUp`, `Monitor` and `Home`, also compact) on the scene
graph's OpenGL renderer over Mesa's software OpenGL
(`TELAMON_TEST_BACKEND=opengl` in `run-variant.sh`), at scale factor 1 and 1.7
(`TELAMON_TEST_SCALE`). Their goldens are `visual/golden-rhi/<scale>/light/`.
Another Mesa or Qt version can shift the antialiasing: regenerate them with
`TELAMON_UPDATE_GOLDENS=1 ctest --test-dir build -R filled-symbols`.

## qmllint budget

CI counts the `Warning` lines of `all_qmllint` and compares them with
`QMLLINT_MAX` in `.github/workflows/ci.yml`: more fails, and so does fewer
(lower the number to the new count). The Qt and qmllint in the dev container
set the count, so an image update can change it: re-count and set
`QMLLINT_MAX` in the same commit as the update (CI prints the Qt version
beside the count). A change that fixes warnings lowers `QMLLINT_MAX` in the
same commit; when two such changes are open, the second one rebases and
lowers it again.

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
- `status/`: `TelamonStatus` on TelamonListView, DataTable, TelamonTreeView and
  TelamonPage (every status on every view, the 300 ms spinner delay, the kept
  header, the action button, the Error announcement; the status view's
  `_announceHook` stands in for `Accessible.announce`), and TelamonSplitView's
  `collapsible` (collapse and expand at `collapseWidth`, `showPane`, Back by the
  button, Alt+Left and the mouse Back button, `currentPane` across a resize,
  right-to-left).
- `chrome/`: the frameless window: TelamonHeaderBar's drag (`_moveHook`) and
  double click (`_toggleHook`), TelamonWindow's resize handles and cursors
  (`_resizeHook`), TelamonWindowChrome's KWin button parsing. Real window moves
  need a compositor and are not covered.
- `wizard/`: the first-run setup controls of item 42: TelamonOnboarding's labels,
  busy state, `advanceRequested`, `canGoBack` and dots; TelamonPasswordStrength;
  TelamonChoiceCard and TelamonAccentPicker (selection, keys, mirrored layout, the
  edit rule in the three app styles); TelamonWindow.`kiosk` (full screen, a close
  request refused, no close button).
- `i18n/`: with `LANGUAGE=de` and a throwaway `telamon-ui_de.qm` (built from
  `i18n/telamon-ui_de.ts`), a default `SearchField` must show the German string.
  Needs qt6-linguist; skipped without it.
- `legacy/`: what Telamon.Ui 2.0.0 still reads from before the rename
  (`ui/legacyconfig.cpp`): the copy of a file under its old name with the
  `[Atlas]` group renamed, the `ATLAS_*` variables, `atlasrc` for `Appearance`.
  The same for `TelamonSettings` and the notifyrc is in `settings/`.
- `migrate/run.sh`: `tools/migrate-app-to-telamon.sh` on a made-up app: what it
  rewrites, what it leaves, the pins, the spec, the notifyrc, a dry run, a
  dirty tree and a second run.
