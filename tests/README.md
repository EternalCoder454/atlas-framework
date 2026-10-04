# tests

Built with `-DATLAS_UI_TESTS=ON` (off by default, so the RPM build is
unchanged). In the dev container:

```sh
cmake -S . -B build -G Ninja -DATLAS_UI_TESTS=ON && cmake --build build
ctest --test-dir build --output-on-failure
```

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
  window-level demos).
- Deterministic: `QT_QUICK_BACKEND=software`, `QT_SCALE_FACTOR=1`, Noto Sans 10,
  `org.kde.desktop`, `xvfb-run`, X11. The goldens are made in the dev
  container; another Qt or font version gives different pictures (`AtlasAboutPage`
  also shows the OS name and Qt version).
- `visual/schemes/` holds the Breeze colour schemes the variants start from, so
  the pictures do not follow the distribution's copy.
