# atlas-framework

Atlas.Ui (the QML module every Atlas app imports), the Material Symbols
fonts, the Atlas Symbols gallery, the app template and the Rust crates
(`crates/`: startup, settings, logging, crash reports, polkit, Flatpak). Qt 6.11 and KF6 on
Fedora 44. Read `docs/DESIGN.md` first: the design rules, how apps use
Atlas.Ui, and the compatibility rules. Change it together with the code.

## Hard rules

- **Atlas.Ui's API is a contract** with every Atlas app (Atlas Updater,
  AtlasOS Installer, Atlas Monitor, ...). Add freely; never rename or remove a
  type, property, signal, function, enum value or `Symbols.<Name>` without
  updating every app first (see "Compatibility" in docs/DESIGN.md). Before
  adding a type, check no app has a `.qml` file of that name: the import
  would hide the app's own. The crates' public items, the C functions in
  `crates/atlas-framework-ui/include/atlas/app.h` and every on-disk or D-Bus
  format are contracts too.
- **Build and test in a container**, never on the host (no Qt -devel there):
  `localhost/atlas-framework-dev:44` (`packaging/Containerfile.dev` builds it;
  the older `localhost/atlas-ui-dev:44` lacks flatpak-devel), or `registry.fedoraproject.org/fedora:44` for
  RPMs. Mount the repo at `/src` (the path has a space; quote it) with
  `--security-opt label=disable`.
- **Never run the GUI on the user's display.** Use `xvfb-run -a -s "-screen 0
  1920x1080x24"` inside the container, and `import -window` for screenshots.
- Packaged builds (prefix `/usr`) must not hold paths into the source tree;
  the spec's `%check` fails if they do.
- Commit only the paths you own. Don't push without the user's OK.
- Licence: MIT (fonts: Apache-2.0).

## Commands

**The everyday check is one command from the host:** `tools/dev-check.sh`
(incremental build, qmllint, every test in parallel, API check, gallery lint;
about 25 s). `tools/dev-check.sh AtlasFoo` runs the visual and a11y tests for
that demo only; `--translations` also rewrites `ui/translations/atlas-ui.ts`.
Each checkout gets its own build directory, so worktrees can run it at once.
Run it yourself; it needs no tester agent. The commands below are what it
runs, for when you need one step on its own.

| Task | Command (inside the container, in /src) |
|---|---|
| Build | `cmake -S . -B build -G Ninja -DATLAS_UI_TESTS=ON && cmake --build build` |
| Crates | `cargo test --workspace --all-features && cargo clippy --workspace --all-features --all-targets` (QMAKE=/usr/bin/qmake6) |
| qmllint | `cmake --build build --target all_qmllint` |
| Visual tests | `ctest --test-dir build -j$(nproc) --output-on-failure` (light, dark, accent, opaque, a11y, i18n; `ATLAS_DEMO_FILTER='^(AtlasFoo)$'` for one demo) |
| Accept new pictures | `ATLAS_UPDATE_GOLDENS=1 ctest --test-dir build`, then look at every changed PNG before committing |
| API check | `tools/check-api.sh build`; after adding API, `tools/update-api.sh build` and commit `api/` |
| Semver (crates) | `cargo semver-checks --workspace --baseline-rev <last v* tag>` |
| App checks | `tools/lint-app.sh <app dir>` and `tools/check-app-names.sh <app dir>` |
| Performance | `perf/measure.sh build` (budgets in `perf/budget.json`) |
| Gallery | `xvfb-run -a build/atlas-symbols` |
| RPMs | `packaging/build-rpm.sh /src/out` (in fedora:44; `ATLAS_BUILD_CACHE=<dir>` outside the tree for fast rebuilds) |

CI (`.github/workflows/ci.yml`) runs all of these. A release is a `vX.Y.Z`
tag: the version in `CMakeLists.txt`, `Cargo.toml` and the spec must match it,
and `CHANGELOG.md` needs its section (`.github/workflows/release.yml`).
New controls are named `Atlas<Name>` and get a `ui/gallery/demos/<Type>Demo.qml`, goldens (tests/README.md) and
an API line.
