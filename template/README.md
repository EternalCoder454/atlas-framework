# Atlas app template

A minimal Atlas app: Kirigami UI (QML compiled ahead of time by `qt_add_qml_module`),
one Rust QObject exposed through CXX-Qt, built with CMake and Corrosion, and a
dependency on `atlas-core`, using the installed Atlas.Ui. It builds on its own.

## Start a new app from it

1. Copy this directory to the new app's repository.
2. Rename (search and replace in every file, and rename the files that carry it):
   - crate `atlas-app-template` / lib `atlas_app_template` (Cargo.toml, CMakeLists.txt)
   - QML module URI `net.eterneon.atlas.apptemplate` (CMakeLists.txt, main.cpp)
   - app ID and desktop file `net.eterneon.atlas.apptemplate` (main.cpp, data/)
   - binary name `atlas-app-template` (CMakeLists.txt, main.cpp)
   - `atlas_backend_new` and the `atlas_app` C++ namespace if you like
3. In `Cargo.toml`, pin `atlas-core` to a commit (the comment shows how).
4. Give the app's RPM `Requires: atlas-ui` and `BuildRequires: atlas-ui`
   (with `>= <version>` once it uses something newer than 1.0.0).
5. Add properties and invokables to `src/backend.rs`, pages to `qml/` and to the
   `QML_FILES` list in `CMakeLists.txt`.

## Build (Fedora 44)

```sh
dnf install cmake ninja-build gcc-c++ cargo corrosion qt6-qtbase-devel \
  qt6-qtdeclarative-devel kf6-kirigami-devel kf6-qqc2-desktop-style atlas-ui
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
QT_QPA_PLATFORM=offscreen ./build/atlas-app-template
```

## How it fits together

- `main.cpp` is the only C++: it starts Qt and loads the QML module.
- `src/lib.rs` exports `atlas_backend_new()`, which hands the Rust `Backend`
  QObject to the QML engine (`required property var backend` in `qml/Main.qml`).
- Slow work runs on a thread and posts back with `qt_thread().queue(..)`; never
  block the GUI thread.
- Atlas.Ui is installed system-wide (`/usr/lib64/qt6/qml/Atlas/Ui`, from the
  atlas-ui package) and imported with `import Atlas.Ui`, like Kirigami. Nothing
  links it; the build checks it is there.
- Follow the rules in atlas-framework's `docs/DESIGN.md`: the system Plasma
  theme (no hard-coded colours), Atlas.Ui's controls rather than QQC2's or
  Kirigami's buttons, and `AtlasWindow` for the window.

## Icons

Atlas.Ui draws Google's Material Symbols, about 4,000 icons in three styles:

```qml
Symbol { icon: Symbols.Settings }
Symbol { icon: Symbols.Favorite; filled: true; color: Kirigami.Theme.negativeTextColor }
Symbol { name: "arrow_back"; style: Symbol.Sharp; size: 24; weight: 300 }
SidebarItem { text: qsTr("Downloads"); symbol: Symbols.Download }
PrimaryButton { text: qsTr("Share"); symbol: Symbols.Share }
```

`Symbols.<Name>` is Google's name in PascalCase (`arrow_back` is `ArrowBack`;
a leading number is spelled out, `10k` is `TenK`), and the `<app>_qmllint`
target flags a misspelled one. To find one, run the gallery, Atlas Symbols
(`atlas-symbols`, from the atlas-symbols package): search, pick a style, fill
and weight, and copy the QML. The fonts come from the `atlas-symbols-fonts`
package, which atlas-ui requires.
