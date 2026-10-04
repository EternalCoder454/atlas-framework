# atlas-framework

The shared base every Atlas app builds on, so they look and behave the same:

- **Atlas.Ui** (`ui/`): the QML module of Atlas controls. Pill buttons,
  grouped sections, the status hero, sidebar items, setup steps, charts,
  tables, menus, the window that follows the shared transparency switch, and
  about 4,000 Material Symbols icons.
- **atlas-symbols-fonts** (`ui/symbols/`): the Material Symbols fonts.
- **Atlas Symbols** (`ui/gallery/`): browse the icons and copy the QML.
- **The Rust crates** (`crates/`): app startup and single instance, settings,
  journal logging, crash reports, AtlasOS state, polkit checks and Flatpak.
  `atlas-framework-core` and `-ui` for every app, `-system` and `-flatpak`
  only for the apps that need them.
- **The app template** (`template/`): start a new Atlas app from it.

It is installed once on AtlasOS (the atlas-ui, atlas-symbols-fonts and
atlas-symbols packages) and every app uses that copy:

```qml
import Atlas.Ui

PrimaryButton { text: qsTr("Share"); symbol: Symbols.Share }
```

Read [docs/DESIGN.md](docs/DESIGN.md) first: the design rules for Atlas apps,
how apps use Atlas.Ui, and the compatibility rules for changing it.

## Build

Fedora 44, in a container (the host has no Qt development packages):

```sh
dnf install cmake ninja-build gcc-c++ qt6-qtbase-devel qt6-qtdeclarative-devel \
  kf6-kirigami-devel kf6-kwindowsystem-devel kf6-kconfig-devel kf6-qqc2-desktop-style
cmake -S . -B build -G Ninja && cmake --build build
build/atlas-symbols
```

The Rust crates (also needs kf6-kdbusaddons-devel, kf6-kwindowsystem-devel,
flatpak-devel, cargo and clippy):

```sh
cargo test --workspace --all-features
```

RPMs: `packaging/build-rpm.sh <out dir>` inside `registry.fedoraproject.org/fedora:44`.

## Licence

MIT. The Material Symbols fonts are Apache-2.0 (`ui/symbols/LICENSE.txt`).
