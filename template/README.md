# Telamon app template

A minimal Telamon app: Kirigami UI (QML compiled ahead of time by `qt_add_qml_module`),
one Rust QObject exposed through CXX-Qt, built with CMake and Corrosion, on
telamon-framework's Rust crates and the installed Telamon.Ui. The framework starts
the app (app ID, one instance per session, journal logging, crash hooks) and
Telamon.Ui gives it the look and an About page. It builds on its own.

## Start a new app from it

1. Copy this directory to the new app's repository.
2. Rename (search and replace in every file, and rename the files that carry it):
   - crate `telamon-app-template` / lib `telamon_app_template` (Cargo.toml, CMakeLists.txt)
   - QML module URI `net.eterneon.telamon.apptemplate` (CMakeLists.txt, main.cpp)
   - app ID and desktop file `net.eterneon.telamon.apptemplate` (main.cpp,
     src/lib.rs, data/), and the name and repository in `src/lib.rs`'s `app!`
   - `data/telamon-apptemplate.notifyrc`: named `telamon-` and the last part of
     the app ID, and its `DesktopEntry=` is the app ID and its `IconName=` is the same as
     `Icon=` in the desktop file (an icon the app ships or the theme has)
   - binary name `telamon-app-template` (CMakeLists.txt, main.cpp)
   - `telamon_backend_new` and the `telamon_app` C++ namespace if you like
3. In `Cargo.toml`, take `telamon-framework-ui` from git pinned to a release tag (the
   comment shows how; the tag is what the framework's update pull requests
   move forward), and add `telamon-framework-system` or
   `telamon-framework-flatpak` only if the app needs them.
4. Replace `vX.Y.Z` in `.github/workflows/telamon.yml` (Telamon.Ui rule checks and
   desktop-file validation on every push) with the tag `Cargo.toml` uses.
   The framework's update pull requests move `Cargo.toml`; move the workflow by hand.
5. Give the app's RPM `Requires: telamon-ui` and `BuildRequires: telamon-ui`
   `>= 1.4.0` (or whatever `ui:` in `src/lib.rs` says; keep the two the same).
6. Add properties and invokables to `src/backend.rs`, pages to `qml/` and to the
   `QML_FILES` list in `CMakeLists.txt`.

## Build (Fedora 44)

```sh
dnf install cmake ninja-build gcc-c++ cargo corrosion qt6-qtbase-devel \
  qt6-qtdeclarative-devel kf6-kirigami-devel kf6-qqc2-desktop-style \
  kf6-kdbusaddons-devel kf6-kwindowsystem-devel telamon-ui
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
QT_QPA_PLATFORM=offscreen ./build/telamon-app-template
```

## How it fits together

- `src/lib.rs` names the app once with `telamon_framework_ui::app!`, and exports
  `telamon_backend_new()`, which hands the Rust `Backend` QObject to the QML
  engine (`required property var backend` in `qml/Main.qml`).
- `main.cpp` is the only C++, one call: `telamon_app_run` (telamon-framework-ui's
  `include/telamon/app.h`) sets up Qt and the app ID, keeps one instance per
  session (a second launch raises the window), starts logging and crash
  hooks, and loads `Main` from the QML module.
- The app links `KF6::DBusAddons` and `KF6::WindowSystem` in CMake for that
  startup code (Corrosion doesn't pass a crate's native libraries on).
- `TelamonApp` (name, version, OS, links) and `TelamonAboutPage` come from
  Telamon.Ui; `qml/Main.qml` pushes the About page.
- `ui: "1.4.0"` in `app!` is the oldest Telamon.Ui the app works with. At
  startup, before any of the app's QML, the framework asks the installed
  Telamon.Ui (`TelamonApp.uiVersion`); if it is older, or missing, the app shows
  a plain window saying which version it needs and exits with code 1. Raise
  it when the app starts using something newer. Leave `ui:` out and nothing is
  checked. (C++ apps without `app!`: `telamon_app_require_ui("1.4.0")`.)
- Notifications: `telamon_framework_system::notify` (feature `notify`) sends
  them the way KNotification does, so Plasma groups them under the app and its
  notification settings apply. The "Send a Notification" button in
  `qml/MainPage.qml` calls `sendNotification` in `src/backend.rs`, which sends
  the `demoAction` event from a worker thread. The events are declared in
  `data/telamon-apptemplate.notifyrc`, installed to
  `share/knotifications6/`; every event id you send needs an `[Event/<id>]`
  there (camelCase, letters and digits). Notify only when the user can act on
  it: popups only, no sounds, persistent only when ignoring it has
  consequences, actions short verbs that open the right page, and no
  notifications from a root service (the user-session app notices and notifies).
- Settings: `telamon_framework_ui::telamon_framework_core::settings::Settings::for_app`
  reads and writes `~/.config/telamon-<app>rc`. Logging: the `log` crate's
  macros (add `log = "0.4"`) go to the journal (`journalctl -t telamon-<app>`).
- Slow work runs on a thread and posts back with `qt_thread().queue(..)`; never
  block the GUI thread.
- Telamon.Ui is installed system-wide (`/usr/lib64/qt6/qml/Telamon/Ui`, from the
  telamon-ui package) and imported with `import Telamon.Ui`, like Kirigami. Nothing
  links it; the build checks it is there.
- Follow the rules in telamon-framework's `docs/DESIGN.md`: the system Plasma
  theme (no hard-coded colours), Telamon.Ui's controls rather than QQC2's or
  Kirigami's buttons, and `TelamonWindow` for the window.

## Icons

Telamon.Ui draws Google's Material Symbols, about 4,000 icons (Rounded; Outlined
and Sharp with the `telamon-symbols-fonts-extra` package):

```qml
Symbol { icon: Symbols.Settings }
Symbol { icon: Symbols.Favorite; filled: true; color: Kirigami.Theme.negativeTextColor }
Symbol { name: "arrow_back"; style: Symbol.Sharp; size: 24; weight: 300 }
SidebarItem { text: qsTr("Downloads"); symbol: Symbols.Download }
PrimaryButton { text: qsTr("Share"); symbol: Symbols.Share }
```

`Symbols.<Name>` is Google's name in PascalCase (`arrow_back` is `ArrowBack`;
a leading number is spelled out, `10k` is `TenK`), and the `<app>_qmllint`
target flags a misspelled one. To find one, run the gallery, Telamon Symbols
(`telamon-symbols`, from the telamon-symbols package): search, pick a style, fill
and weight, and copy the QML. The Rounded font comes from the
`telamon-symbols-fonts` package, which telamon-ui requires; Outlined and Sharp from
`telamon-symbols-fonts-extra`.
