# telamon-framework

The shared base every Telamon app builds on, so they look and behave the same:

- **Telamon.Ui** (`ui/`): the QML module of Telamon controls: buttons with 4 px
  corners, grouped sections, fields and pickers, lists and tables, sidebars
  and navigation, dialogs, charts, a frameless window with its own header
  bar that follows the shared transparency switch, and about 4,000 Material
  Symbols icons.
- **telamon-symbols-fonts** (`ui/symbols/`): the Material Symbols fonts.
- **Telamon Symbols** (`ui/gallery/`): browse the icons and copy the QML.
- **The Rust crates** (`crates/`): app startup and single instance, settings,
  journal logging, crash reports, Telamon OS state, polkit checks and Flatpak.
  `telamon-framework-core` and `-ui` for every app, `-system` and `-flatpak`
  only for the apps that need them.
- **The app template** (`template/`): start a new Telamon app from it.
- **Native app bundles** (`tools/make-bundle.sh`, `.github/workflows/bundle.yml`):
  package an app that is not part of the OS image for Telamon Store, from its
  GitHub release, without Flatpak: [docs/BUNDLES.md](docs/BUNDLES.md).

It is installed once on Telamon OS (the telamon-ui, telamon-symbols-fonts and
telamon-symbols packages) and every app uses that copy:

```qml
import Telamon.Ui

PrimaryButton { text: qsTr("Share"); symbol: Symbols.Share }
```

Until 2.0.0 this was atlas-framework (Atlas.Ui, `atlas-ui`, the Atlas crates). An app moves with
[`tools/migrate-app-to-telamon.sh`](tools/migrate-app-to-telamon.sh); the old and new
packages install side by side meanwhile (see [CHANGELOG.md](CHANGELOG.md)).

The API reference is on <https://telamon.eterneon.net/framework>; its source,
[docs/reference/](docs/reference/), is the one place the API is described.
Read [docs/DESIGN.md](docs/DESIGN.md) first: the design rules for Telamon apps,
how apps use Telamon.Ui, and the compatibility rules for changing it.

## Build

Fedora 44, in a container (the host has no Qt development packages):

```sh
dnf install cmake ninja-build gcc-c++ qt6-qtbase-devel qt6-qtdeclarative-devel \
  kf6-kirigami-devel kf6-kwindowsystem-devel kf6-kconfig-devel kf6-qqc2-desktop-style
cmake -S . -B build -G Ninja && cmake --build build
build/telamon-symbols
```

The Rust crates (also needs kf6-kdbusaddons-devel, kf6-kwindowsystem-devel,
flatpak-devel, cargo and clippy):

```sh
cargo test --workspace --all-features
```

RPMs: `packaging/build-rpm.sh <out dir>` inside `registry.fedoraproject.org/fedora:44`.

## Licence

MIT. The Material Symbols fonts are Apache-2.0 (`ui/symbols/LICENSE.txt`).
