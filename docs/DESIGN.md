# atlas-framework: design

atlas-framework is the shared base every Atlas app builds on, so they all
look and behave the same. It is installed once on AtlasOS, and every app uses
that copy. It holds:

- **Atlas.Ui**, the QML module of Atlas controls (`ui/`)
- **atlas-symbols-fonts**, Google's Material Symbols, which Atlas.Ui draws
  icons with (`ui/symbols/`)
- **Atlas Symbols**, a gallery of those icons (`ui/gallery/`)
- **the app template**, the starting point for a new Atlas app (`template/`)
- **the Rust crates** (`crates/`), the code every Atlas app shares: startup,
  settings, logging, crash reports, AtlasOS state, polkit checks, Flatpak
- the design rules below

The update engine (the root `atlas-system-helper` and its D-Bus protocol)
stays in the Atlas Updater repository (`EternalCoder454/atlasos-updater`):
only the Updater uses it. Everything apps share moved here from its old
atlas-core crate. The state files keep that name in their path
(`/var/lib/atlas-core/history.jsonl` and `events.jsonl`): the path is an
on-disk format other code and existing systems rely on, and a rollback
boots an older helper that still writes there (the RPM is now
`atlas-system-helper`, crate `atlas-update-engine`).

Stack: Qt 6.11 and KDE Frameworks 6.30 on Fedora 44.

## Layout

```
CMakeLists.txt                builds Atlas.Ui and the gallery
ui/                           Atlas.Ui (URI Atlas.Ui, version 1.0)
  *.qml                       the controls
  appearance.{h,cpp}          Appearance: the transparency switch and the blur
  symbols.{h,cpp}, Symbol.qml Symbols and Symbol: Material Symbols icons
  livechart, repaintarea, accessibilitystate   C++ items behind LiveChart and DataTable
  symbols/                    the fonts, and their generated name table
  symbols/generate.py         updates them from a fonts.google.com download
  gallery/                    Atlas Symbols: browse the symbols, copy the QML
Cargo.toml                    the Rust workspace
crates/atlas-framework-core/    every app: AppInfo, settings, logging, os-release
crates/atlas-framework-ui/      every GUI app: startup (C++ and Rust), app!
crates/atlas-framework-system/  system apps: crash reports, AtlasOS state, polkit
crates/atlas-framework-flatpak/ Flatpak through libflatpak: the Updater, Atlas Store
template/                     minimal Atlas app (Kirigami window, Rust backend, the crates)
packaging/atlas-framework.spec  the packages below
packaging/build-rpm.sh        builds them inside fedora:44: build-rpm.sh <out dir>
packaging/atlas-framework.conf  dnf's protected list
```

## Design rules for Atlas apps

Every Atlas app follows these. Atlas.Ui implements them, so an app that uses
its controls gets them for free.

1. **macOS-style controls.** Pill buttons (`PrimaryButton` filled with the
   accent, `SecondaryButton` soft and tinted, `TextButton` as a link), pill
   switches (`AtlasSwitch`), settings grouped in rounded cards (`Section` of
   `SectionRow`s), a sidebar of rounded selection pills (`SidebarItem`,
   `SidebarGroup`), a large bold page title (`AtlasPage`), and a big centred
   status (`StatusHero`).
2. **Windows 11 caption buttons.** The title bar is the window manager's:
   AtlasOS's Aurorae themes draw minimize, maximize and close as rounded
   squares on the right, tinted at rest, accent on hover, red for close (see
   "Window title bars" in the AtlasOS repository's DEV.md). Apps never draw
   their own title bar or caption buttons, and never ask for a frameless
   window.
3. **One blur switch for every app.** The window is `AtlasWindow`. With
   "Transparency effects" on, and a compositor that blurs, its background is
   the theme's background, partly see-through over the blurred desktop
   (Mica style). With it off, the window is opaque. The switch is
   `Transparency` under `[Appearance]` in `~/.config/atlasrc` (default on),
   read and written through the `Appearance` singleton. A change in one app,
   or in the file, reaches every open Atlas app at once. AtlasOS's Kvantum
   themes follow the same switch.
4. **The logo plus a check mark when up to date.** A screen that reports "all
   is well" (no updates, nothing to fix) shows the OS logo in its own colours
   with a check badge on its corner, not a tinted circle: `StatusHero` with
   `iconName` set to the logo (`LOGO=` from os-release, then
   `distributor-logo`), `iconIsMask: false`, `showTintCircle: false` and
   `cornerBadgeIcon: "checkmark"`. Atlas Updater's Updates page is the model.
5. **Follow the Plasma theme.** Every colour comes from `Kirigami.Theme`
   (the accent is `highlightColor`), every size from `Kirigami.Units`, every
   font from the theme's fonts. No hard-coded colours, so light, dark and the
   user's accent all work. The Qt Quick Controls style is `org.kde.desktop`.
6. **Never default QQC2 or Kirigami buttons.** No `QQC2.Button`,
   `QQC2.ToolButton`, `QQC2.Switch` or `Kirigami.Action`-made buttons in an
   app's own pages: use Atlas.Ui's buttons and switch. If Atlas.Ui lacks a
   control, add it here rather than reach for the default one.

Icons are Material Symbols through `Symbol` and the `symbol:` property of
the buttons, sidebar items and menu items, or theme icons by name where a
control takes `iconName`.

## Atlas.Ui

| Type | What it is |
|---|---|
| `AtlasWindow` | The application window: blur or opaque, following `Appearance`; `sidebarColor()` for a sidebar |
| `AtlasPage` | A scrolling page with a large bold title and centred margins |
| `PrimaryButton`, `SecondaryButton`, `TextButton`, `MenuButton` | Buttons (`AtlasButton` is their shared base) |
| `AtlasSwitch` | Pill switch |
| `Section`, `SectionRow` | A rounded card of rows; a row has a title, subtitle, value, and a checkmark, switch or chevron. A section can fold |
| `SidebarItem`, `SidebarGroup` | Sidebar entries, with a live value, a badge, and sub-entries |
| `StepItem` | One step in a setup sidebar (done, current or to come) |
| `StatusHero` | Big centred status: an icon badge with a busy or progress ring, a headline, a subtitle, actions |
| `AtlasProgressBar` | Rounded accent progress bar, or an indeterminate one |
| `ConfirmDialog` | Modal dialog with pill buttons |
| `NotesText` | Release notes from a safe HTML fragment |
| `LiveChart`, `UsageBar`, `MiniBars` | A live chart, a stacked usage bar, a row of small bars |
| `DataTable` | A sortable table in the Section style that only makes the rows on screen |
| `SearchField` | Rounded search field with a debounced `query` |
| `ContextMenu`, `ContextMenuItem`, `ContextMenuSeparator` | Right-click menu; a row can be checkable (a check mark), have a Material Symbol or an icon, open a submenu (an arrow) |
| `TabBar` | Document tabs: a pill per tab with an unsaved dot and a close button, "+" for a new tab, drag to reorder. The app owns the `model` (`title`, `modified`, `toolTip`) and answers its signals. Tabs take no keyboard focus: the app gives Ctrl+Tab and Ctrl+W. Same name as QtQuick.Controls' TabBar, so import Controls qualified (`as QQC2`) (since 1.2.0) |
| `FindBar` | Find and replace bar with match case, whole words and regex toggles; the app searches and reports `matchCount`, `currentMatch` or `error` (since 1.2.0) |
| `StatusBar`, `StatusBarItem` | A slim bottom bar of cells (Ln/Col, encoding, zoom); a cell can be clickable or open a `menu` (since 1.2.0) |
| `InfoBanner` | Inline info, warning or error banner with action buttons; slides with `shown`; its close button sets `shown` to false and emits `closed()` (since 1.2.0) |
| `Toast` | A short message at the bottom centre that goes by itself: `show("Copied")` (since 1.2.0) |
| `ToolbarButton` | Small icon button for a formatting toolbar that never takes the editor's focus; can be checkable (since 1.2.0) |
| `Symbol`, `Symbols` | A Material Symbol, and the singleton of every symbol's value |
| `Appearance` | Singleton: `transparency`, `blurAvailable`, `effective`, `refresh()`, `applyBlur()` |
| `AccessibilityState` | Singleton: whether a screen reader is active |
| `AtlasApp` | Singleton: the app's `name`, `id`, `version`, `repo`, `sourceUrl`, `issuesUrl`; the OS's `osName`, `osVersion`, `osPrettyName`, `osLogo`, `osHomeUrl`; `qtVersion`. Set by atlas-framework-ui's startup |
| `AtlasAboutPage` | The About page: icon, name, version, `description`, the version and OS rows, `license`, source and issue links; extra content goes below |

Each file's header comment says how to use it.

New types that an app might also write itself get an `Atlas` prefix
(`AtlasAboutPage`, not `AboutPage`: five apps have their own).

### Symbols

`Symbol { icon: Symbols.Settings }` draws one of about 4,000 Material
Symbols in the Outlined, Rounded (default) or Sharp style, filled or not, at
any weight from 100 to 700. `Symbols.<Name>` is Google's name in PascalCase
(`arrow_back` is `ArrowBack`; a leading number is spelled out, `10k` is
`TenK`); it is an enum, so the `<app>_qmllint` target flags a misspelled one.
`Symbol { name: "arrow_back" }` takes Google's name as a string and warns at
run time if there is none.

The fonts are installed to `/usr/share/fonts/atlas-symbols` by
atlas-symbols-fonts, and found through fontconfig. A development build (any
install prefix but `/usr`) also loads them from `$ATLAS_UI_SYMBOLS_DIR` or
`ui/symbols/` when they aren't installed. A packaged build does neither: it
holds no path into the source tree (the spec's `%check` makes sure), and
since every Atlas app loads it, it never opens a font file its environment
names.

To update the fonts, download them from fonts.google.com and run
`ui/symbols/generate.py`, which rewrites `symbolnames.h` and
`symboltable.inc`.

## The Rust crates

One Cargo workspace, four crates, so a small app pays only for what it uses:

| Crate | For | Holds |
|---|---|---|
| `atlas-framework-core` | every app | `AppInfo` and `app_info!`; `settings` (`~/.config/atlas-<app>rc`, KConfig format, atomic writes); `log` (the `log` crate to the journal, `ATLAS_LOG=debug`); `osrelease`; `fsutil`. No Qt, no async runtime |
| `atlas-framework-ui` | every GUI app | `app!`, and the startup in `include/atlas/app.h`: `atlas_app_run` (or `atlas_app_init` and `atlas_app_ready` for an app with its own shell) sets the app ID and names, the org.kde.desktop style, one instance per session (KDBusService; a second launch raises the window, with its Wayland activation token), the journal logger, Rust panic and fatal Qt message hooks, and what `AtlasApp` shows |
| `atlas-framework-system` | system apps | `crash` (opt-in crash reports), `history`, `bootc`, `events`; `polkit` (feature `polkit`: checks a D-Bus caller's authorisation, fail-closed; runs on Tokio with timers enabled) |
| `atlas-framework-flatpak` | the Updater, Atlas Store | Flatpak updates through libflatpak |

An app names itself once in its Rust library:

```rust
atlas_framework_ui::app! {
    name: "Atlas Notepad",
    id: "net.eterneon.atlas.notepad",
    repo: "atlasos-notepad",
}
```

and its `main.cpp` is one call, `atlas_app_run(argc, argv, "<QML module>",
"Main", atlas_backend_new)`. Corrosion doesn't pass a crate's native
libraries to the executable, so the app's CMake links `KF6::DBusAddons` and
`KF6::WindowSystem` itself (the template shows it).

Apps take the crates from git pinned to a commit:

```toml
atlas-framework-ui = { git = "https://github.com/EternalCoder454/atlas-framework", rev = "<commit>" }
```

Compiled into an app, the crates' file paths (panic locations, debug info)
come with them: an app's packaged build passes
`RUSTFLAGS=--remap-path-prefix=<source>=. --remap-path-prefix=$CARGO_HOME=cargo`
and `-ffile-prefix-map=<source>=.` so no build path lands in the RPM.

Unlike Atlas.Ui, the crates are compiled into each app: a change reaches an
app when it moves its `rev` forward and is rebuilt. Shared behaviour that
should change everywhere at once (look, layout, the About page) belongs in
Atlas.Ui.

Build and test the crates in the development container
(`packaging/Containerfile.dev`, `localhost/atlas-framework-dev:44`): `cargo test --workspace --all-features`
and `cargo clippy --workspace --all-features --all-targets`.

## How apps use it

Atlas.Ui is a QML module installed with Qt's own, like Kirigami:

```
/usr/lib64/qt6/qml/Atlas/Ui/
  libatlasui.so       the plugin: the C++ types and every QML file, compiled
  qmldir
  atlasui.qmltypes    the C++ types, for qmllint and qmlcachegen
  *.qml               for qmllint and qmlcachegen (the plugin loads its own copy)
```

An app:

- writes `import Atlas.Ui` in QML, and links nothing: the QML engine loads
  the plugin;
- checks at configure time that the module is installed (the template's
  `CMakeLists.txt` shows how). qmlcachegen and qmllint find it in Qt's QML
  directory on their own, so `<app>_qmllint` checks the app against it;
- gives its RPM `Requires: atlas-ui` and `BuildRequires: atlas-ui`, with
  `>= <version>` once it uses something added after 1.0.0.

There is no CMake package and no devel package: an app needs nothing from
Atlas.Ui but the installed module.

To try an Atlas.Ui change in an app before it is packaged, install it over
the packaged one inside the app's build container (never on the host):

```sh
cmake -S . -B build -G Ninja -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build && cmake --install build
```

## Compatibility

Atlas.Ui's API is a contract with every Atlas app: its type names, their
properties, signals, functions and enum values, the singletons, and
`Symbols.<Name>`. They are built separately and updated separately, so a
change that breaks an app breaks it on users' machines.

- **Adding** is fine: a new property with a default that keeps the old look,
  a new value, a new type. Raise the minor version (1.0.0 to 1.1.0) and say
  what was added in the spec's changelog, so apps can require it.
- **A new type can hide an app's own.** `import Atlas.Ui` wins over the QML
  files in an app's own directory, so an Atlas.Ui type named like an app's
  local type replaces it in that app, which then breaks (the Installer's
  `SearchField` did, and is now `ListSearchField`). Before adding a type,
  search every Atlas app for a `.qml` file of that name, and prefer a name
  no app would pick on its own (`AtlasProgressBar`, not `ProgressBar`).
- **Renaming or removing** anything, or changing what an existing property
  means, needs every app that uses it updated first, in the same AtlasOS
  build. Search all the Atlas app repositories for it before you change it,
  and raise the major version. Prefer adding the new name and keeping the old
  one working.
- **Changing the look** (colours, spacing, radii) is allowed when it follows
  these design rules: every app changes with it, which is the point.
- **The Rust crates follow semver.** Their public items are a contract too,
  but an app only gets a change when it moves its `rev`, so a break shows up
  in that app's build, not on users' machines. Still: add rather than
  rename, and raise the major version for a break. Two things are fixed
  across versions because separately built programs share them: the C
  functions in `include/atlas/app.h` (only add new ones), and anything on
  disk or on D-Bus (the settings file format, crash report and history
  files, polkit action IDs): read the old form forever.
- **Atlas.Ui is tied to the Qt minor version.** qmlcachegen compiles its
  QML against Qt's private API, so `libatlasui.so` needs the exact Qt minor
  it was built with (rpm records this as `Qt_6.11_PRIVATE_API`). A Qt minor
  update (6.11 to 6.12) means rebuilding atlas-ui, then the apps, in the same
  AtlasOS build; the image build does both. The ISO build takes Atlas.Ui
  from the image it embeds, so the installer always matches it.
- Updating the fonts can drop or rename symbols upstream: `generate.py`
  keeps Google's older names as aliases for `name:`, but check the diff of
  `symbolnames.h` for removed `Symbols.<Name>` values, which are a break.

## How a change reaches the apps

Apps don't contain Atlas.Ui: each loads `libatlasui.so`, which holds every
Atlas.Ui QML file compiled, when it starts. So a change here (a colour, a
radius, a control's behaviour) reaches every app the next time it starts,
without rebuilding any app. On AtlasOS that is the first start after the
image update that carries the new atlas-ui. (Tested: the same
`atlas-updater` binary picked up a changed button colour from a replaced
`libatlasui.so` alone.) Apps are only rebuilt for API changes, which the
rules above cover.

Already live, without a restart: the Plasma colour scheme, accent and
light or dark (through `Kirigami.Theme`), and the transparency switch
(through `Appearance`, which watches `atlasrc`).

## Packages

`packaging/atlas-framework.spec` builds:

| Package | Holds |
|---|---|
| `atlas-ui` | The module in `/usr/lib64/qt6/qml/Atlas/Ui`, and `/etc/dnf/protected.d/atlas-framework.conf`. Requires atlas-symbols-fonts, kf6-kirigami and qt6-qtdeclarative |
| `atlas-symbols-fonts` | The three fonts (noarch, Apache-2.0) |
| `atlas-symbols` | The gallery, `atlas-symbols`, with its desktop file |

atlas-ui and atlas-symbols-fonts are required parts of AtlasOS:
`atlas-framework.conf` stops dnf removing them, and the AtlasOS image build
fails without them. The AtlasOS image builds the RPMs from this repository
(its `atlas-framework` build context) and installs them before the apps,
which are built against them.
