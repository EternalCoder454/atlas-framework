# atlas-framework

Atlas.Ui (the QML module every Atlas app imports), the Material Symbols
fonts, the Atlas Symbols gallery and the app template. Qt 6.11 and KF6 on
Fedora 44. Read `docs/DESIGN.md` first: the design rules, how apps use
Atlas.Ui, and the compatibility rules. Change it together with the code.

## Hard rules

- **Atlas.Ui's API is a contract** with every Atlas app (Atlas Updater,
  AtlasOS Installer, Atlas Monitor, ...). Add freely; never rename or remove a
  type, property, signal, function, enum value or `Symbols.<Name>` without
  updating every app first (see "Compatibility" in docs/DESIGN.md). Before
  adding a type, check no app has a `.qml` file of that name: the import
  would hide the app's own.
- **Build and test in a container**, never on the host (no Qt -devel there):
  `localhost/atlas-ui-dev:44`, or `registry.fedoraproject.org/fedora:44` for
  RPMs. Mount the repo at `/src` (the path has a space; quote it) with
  `--security-opt label=disable`.
- **Never run the GUI on the user's display.** Use `xvfb-run -a -s "-screen 0
  1920x1080x24"` inside the container, and `import -window` for screenshots.
- Packaged builds (prefix `/usr`) must not hold paths into the source tree;
  the spec's `%check` fails if they do.
- Commit only the paths you own. Don't push without the user's OK.
- Licence: MIT (fonts: Apache-2.0).

## Commands

| Task | Command (inside the container, in /src) |
|---|---|
| Build | `cmake -S . -B build -G Ninja && cmake --build build` |
| qmllint | `cmake --build build --target all_qmllint` |
| Gallery | `xvfb-run -a build/atlas-symbols` |
| RPMs | `packaging/build-rpm.sh /src/out` (in fedora:44; `ATLAS_BUILD_CACHE=<dir>` outside the tree for fast rebuilds) |
