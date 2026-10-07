# telamon-framework: design

telamon-framework is the shared base every Telamon app builds on, so they all
look and behave the same. It is installed once on Telamon OS, and every app uses
that copy. (Until 2.0.0 it was atlas-framework, Telamon.Ui was Atlas.Ui and
everything was named Atlas; see "The rename" under "Compatibility".) It holds:

- **Telamon.Ui**, the QML module of Telamon controls (`ui/`)
- **telamon-symbols-fonts**, Google's Material Symbols, which Telamon.Ui draws
  icons with (`ui/symbols/`)
- **the Telamon Gallery** (`telamon-symbols`), every control live and every
  symbol, with the QML to copy (`ui/gallery/`)
- **the app template**, the starting point for a new Telamon app (`template/`)
- **the Rust crates** (`crates/`), the code every Telamon app shares: startup,
  settings, logging, crash reports, Telamon OS state, polkit checks, Flatpak
- the design rules below, and the checks that enforce them (`tests/`,
  `tools/`, `api/`, `perf/`, `.github/workflows/`)

The update engine (the root `atlas-system-helper` and its D-Bus protocol)
stays in the Telamon Updater repository (`EternalCoder454/atlasos-updater`):
only the Updater uses it. Everything apps share moved here from its old
atlas-core crate. The state files keep that name in their path
(`/var/lib/atlas-core/history.jsonl` and `events.jsonl`): the path is an
on-disk format other code and existing systems rely on, and a rollback
boots an older helper that still writes there (the RPM is now
`atlas-system-helper`, crate `telamon-update-engine`).

Stack: Qt 6.11 and KDE Frameworks 6.30 on Fedora 44.

## Layout

```
CMakeLists.txt                builds Telamon.Ui and the gallery
ui/                           Telamon.Ui (URI Telamon.Ui, version 1.0)
  *.qml                       the controls
  appearance.{h,cpp}          Appearance: the transparency switch and the blur
  symbols.{h,cpp}, Symbol.qml Symbols and Symbol: Material Symbols icons
  livechart, repaintarea, accessibilitystate   C++ items behind LiveChart and DataTable
  symbols/                    the fonts, and their generated name table
  symbols/generate.py         updates them from a fonts.google.com download
  gallery/                    the Telamon Gallery: every control (demos/) and symbol, with the QML
  gallery/demos/              <Type>Demo.qml per control: the gallery, the visual and a11y tests
Cargo.toml                    the Rust workspace
crates/telamon-framework-core/    every app: AppInfo, settings, logging, os-release
crates/telamon-framework-ui/      every GUI app: startup (C++ and Rust), app!
crates/telamon-framework-system/  system apps: crash reports, Telamon OS state, polkit
crates/telamon-framework-flatpak/ Flatpak through libflatpak: the Updater, Telamon Store
template/                     minimal Telamon app (Kirigami window, Rust backend, the crates)
packaging/telamon-framework.spec  the packages below
packaging/build-rpm.sh        builds them inside fedora:44: build-rpm.sh <out dir>
packaging/telamon-framework.conf  dnf's protected list
tests/                        visual (golden pictures) and accessibility tests of every demo
tools/                        API dump and check, app lint and name check, update pull requests
api/                          the recorded Telamon.Ui API (telamon-ui.api, symbols.txt)
perf/                         the template's startup, memory and idle CPU against budget.json
CHANGELOG.md                  what each release brings to apps
.github/workflows/            ci.yml, app-checks.yml (for apps), release.yml
```

## Design rules for Telamon apps

Every Telamon app follows these. Telamon.Ui implements them, so an app that uses
its controls gets them for free.

1. **Pages built from Telamon controls.** Buttons with 4 px corners
   (`PrimaryButton` filled with `accentStrong`, `SecondaryButton` soft and
   tinted with a hairline border, `TextButton` as a link), round switches
   (`TelamonSwitch`), settings grouped in 6 px cards (`Section` of
   `SectionRow`s), a sidebar whose selection is a 4 px highlight
   (`SidebarItem`, `SidebarGroup`), a large bold page title (`TelamonPage`), and
   a big centred status (`StatusHero`). The tokens are on the
   [Style and theming](reference/telamon-ui/style-and-theming.md) page.
2. **Windows 11 caption buttons.** The title bar is the window manager's:
   Telamon OS's Aurorae themes draw minimize, maximize and close as rounded
   squares on the right, tinted at rest, accent on hover, red for close (see
   "Window title bars" in the Telamon OS repository's DEV.md). Apps never draw
   their own title bar or caption buttons. The one exception is the merged
   header (since 1.4.0): a `TelamonWindow` with a `TelamonHeaderBar` as its
   `header` is frameless and draws the title row and `TelamonWindowButtons`,
   matched to that decoration and KWin's button layout. Apps never make a
   window frameless any other way.
3. **One blur switch for every app.** The window is `TelamonWindow`. With
   "Transparency and blur" on, and a compositor that blurs, its background is
   the theme's background, partly see-through over the blurred desktop
   (Mica style). With it off, the window is opaque. The switch is
   `Transparency` under `[Appearance]` in `~/.config/telamonrc` (default on),
   read and written through the `Appearance` singleton. A change in one app,
   or in the file, reaches every open Telamon app at once. Telamon OS's Kvantum
   themes follow the same switch.
4. **The logo plus a check mark when up to date.** A screen that reports "all
   is well" (no updates, nothing to fix) shows the OS logo in its own colours
   with a check badge on its corner, not a tinted circle: `StatusHero` with
   `iconName` set to the logo (`LOGO=` from os-release, then
   `distributor-logo`), `iconIsMask: false`, `showTintCircle: false` and
   `cornerBadgeIcon: "checkmark"`. Telamon Updater's Updates page is the model.
5. **The Telamon look, on the Plasma theme.** Calm and precise, Light and Dark
   equally. Violet is the accent (`TelamonStyle.accent`: #6858E2 in Light,
   #8A7AF4 in Dark) for buttons and selection; magenta-violet (`TelamonStyle.focus`:
   #A62A8C in Light, #E28BE0 in Dark, each 3:1 or more against the window)
   is for focus rings and decoration. When the user has chosen an accent in
   Plasma, that accent wins, as in other KDE apps. Fonts are IBM Plex Sans
   (the application font's family; its size stays the user's) and JetBrains
   Mono for code (`TelamonStyle.fontFamily`, `monoFamily`), falling back to
   the system fonts when not installed. Corners are small (4, 6 and 8) and
   motion is quick and subtle (100, 150 and 250 ms). Every colour comes from
   `TelamonStyle` or `Kirigami.Theme` (Telamon.Ui puts the violet in the
   application palette, so `Kirigami.Theme.highlightColor` is the accent
   too), every size from `Kirigami.Units`. No hard-coded colours, so light,
   dark and the user's accent all work. The Qt Quick Controls style is
   `org.kde.desktop`.
6. **Never default QQC2 or Kirigami buttons.** No `QQC2.Button`,
   `QQC2.ToolButton`, `QQC2.Switch` or `Kirigami.Action`-made buttons in an
   app's own pages: use Telamon.Ui's buttons and switch. If Telamon.Ui lacks a
   control, add it here rather than reach for the default one. The same
   goes for the controls Telamon.Ui now has (text fields, combo boxes, check
   boxes, sliders, spin boxes, tooltips, busy indicators): `tools/lint-app.sh`
   fails an app on default buttons and warns on the others.
7. **Everyone can use it.** Every control has an accessible role and name
   (screen readers), takes keyboard focus where it acts and shows
   `TelamonFocusRing` when focus came from the keyboard, and stops animating
   while hidden or when Plasma's animation speed is "Instant"
   (`TelamonStyle` durations are 0 then). Text a user reads is in `qsTr()`.

Icons are Material Symbols through `Symbol` and the `symbol:` property of
the buttons, sidebar items and menu items, or theme icons by name where a
control takes `iconName`.

Filled symbols: only the selected item of a navigation control (sidebar
entry, tab bar or view switcher tab) turns solid (`Symbol.filled`);
everything else, selected or not, uses the outline. The selection tint of
those controls is one rectangle that slides to the new item (an expressive
`TelamonSpringAnimation`, off under reduced motion, never on the first layout).

New animated or shader effects check
[`TelamonStyle.softwareRendering`](reference/telamon-ui/telamon-style.md) and go
static or slow under it.

## Telamon.Ui

The reference pages in `docs/reference/` are the single source for what each
type, property, signal and method does (published at
<https://telamon.eterneon.net/framework>). This file keeps the design rules,
the architecture and the reasoning, and does not describe types: change the
page in the same commit as the API, and link to it from anywhere else.

- [Telamon.Ui overview and the list of types](reference/telamon-ui/index.md),
  grouped as windows and pages, buttons, fields and pickers, lists and
  tables, navigation, menus, dialogs and popups, feedback and status,
  charts, text and code, layout, style and motion, icons, services and
  validators.
- [Style and theming](reference/telamon-ui/style-and-theming.md) and
  [TelamonStyle](reference/telamon-ui/telamon-style.md): the tokens behind rule 5.
- [Accessibility](reference/telamon-ui/accessibility.md): the behaviour behind
  rule 7.
- [Symbols](reference/telamon-ui/symbols.md), [Symbol](reference/telamon-ui/symbol.md)
  and [the icon fonts](reference/symbols/index.md).

Each QML file's header comment says how to use it; its example becomes the
gallery's "Copy QML" snippet and the page's example.

New controls are named `Telamon<Name>` (`TelamonAboutPage`, not `AboutPage`: five
apps had their own), which keeps them clear of the apps' files and of
QtQuick.Controls' names. Each new control comes with
`ui/gallery/demos/<Type>Demo.qml` (it then shows in the gallery and in the
visual and accessibility tests without more work), its goldens, its line in
`api/telamon-ui.api` and its page `docs/reference/telamon-ui/<type>.md`;
`tools/docs.py check` fails when a type or public member has no page entry.

### Symbols

How to use symbols is in the [Symbols reference](reference/telamon-ui/symbols.md).
What is design or packaging stays here.

telamon-symbols-fonts ships Rounded, the default and the only style Telamon.Ui
uses. Outlined and Sharp are in telamon-symbols-fonts-extra, which the gallery
recommends. The split saves about 20 MB on disk; unused styles never cost
memory (a font is only mapped once drawn).

The fonts are installed to `/usr/share/fonts/telamon-symbols`, and found
through fontconfig. A development build (`-DTELAMON_UI_DEV_PATHS=ON`) also
loads them from `$TELAMON_UI_SYMBOLS_DIR` or `ui/symbols/` when they aren't
installed, reads translations from the build tree (or
`$TELAMON_UI_TRANSLATIONS_DIR`) and honours the `TELAMON_UI_TEST_FIXED_ENV` test
hook. The option defaults to ON for any install prefix but `/usr`, and to OFF
for `/usr`; `-DTELAMON_UI_TESTS=ON` forces it ON. A packaged build has none of
it: it holds no path into the source tree (the spec's `%check` makes sure),
and since every Telamon app loads it, it never opens a font or catalogue file
its environment names.

To update the fonts, download them from fonts.google.com and run
`ui/symbols/generate.py`, which rewrites `symbolnames.h` and
`symboltable.inc`.

### States

Every control behaves the same way in each state. `tests/state` walks every
gallery demo and checks the three rules that can be measured (marked *test*);
a control that cannot follow one is listed in that test's allow-list with the
reason.

- **Disabled (`enabled: false`).** Dimmed (opacity or the disabled colours),
  takes no focus (Tab skips it), no hover or press reaction, no cursor change,
  and `Accessible` reports it as disabled. A disabled parent disables its
  children. *test*: with the demo's root disabled Tab reaches nothing in it,
  and its picture differs from the enabled one.
- **Read only (`readOnly`, text fields and the like).** The value is shown
  normally (not dimmed), cannot be edited, and the control keeps focus and
  selection and copy.
- **Error.** The error colour (`TelamonStyle.error`) on the border or text and
  a message beside the field. The message is announced (`Accessible.description`
  or an alert), not only coloured.
- **Busy.** A spinner (`TelamonSpinner`) replaces the value or chevron; the
  control stays enabled but does not act again until the work ends (no double
  activation), and `Accessible.description` says it is busy.
- **Hover.** A light tint of the text colour, only for a control that acts,
  never for a disabled or busy one. The pointer shows a hand on a clickable
  row or button.
- **Pressed.** A stronger tint than hover, gone on release or when the pointer
  leaves.
- **Focus.** `TelamonFocusRing` (or the control's own ring) shows only for
  keyboard focus, never after a click. *test*: every item Tab reaches looks
  different with and without keyboard focus.

A control that holds other controls (a `SectionRow` with `trailing` items)
shows its own ring only while it has focus itself, not while an item inside it
does, and does not take the keys its inner controls leave unused.

## The Rust crates

One Cargo workspace, four crates, so a small app pays only for what it uses.
Each crate's modules, functions and formats are in the reference:

- [`telamon-framework-core`](reference/telamon-framework-core/index.md), for every
  app: no Qt, no async runtime.
- [`telamon-framework-ui`](reference/telamon-framework-ui/index.md), for every GUI
  app: `app!` and the startup in `include/telamon/app.h`.
- [`telamon-framework-system`](reference/telamon-framework-system/index.md), for
  system apps: crash reports, history, bootc, events, polkit and
  notifications.
- [`telamon-framework-flatpak`](reference/telamon-framework-flatpak/index.md), for
  the Updater and Telamon Store.

An app names itself once in its Rust library:

```rust
telamon_framework_ui::app! {
    name: "Telamon Notepad",
    id: "net.eterneon.telamon.notepad",
    repo: "atlasos-notepad",
    ui: "2.0.0",
}
```

`ui:` is the oldest Telamon.Ui the app works with; keep it equal to the RPM's
`Requires: telamon-ui >=`. How the check works and what an app sees is in
[the `app!` reference](reference/telamon-framework-ui/app-macro.md). `app!` is the
only supported way to define the app info: the C++ side reads it from the Rust
library.

The app's `main.cpp` is one call, `telamon_app_run(argc, argv, "<QML module>",
"Main", telamon_backend_new)`. Corrosion doesn't pass a crate's native
libraries to the executable, so the app's CMake links `KF6::DBusAddons` and
`KF6::WindowSystem` itself (the template shows it).

Apps take the crates from git pinned to a release tag:

```toml
telamon-framework-ui = { git = "https://github.com/EternalCoder454/atlas-framework", tag = "v2.0.0" }
```

Each release opens a pull request in every app that moves the tag (see
"Releases"), except one that changes the major version (2.0.0, the rename: the
crates' names changed, and an app moves with `tools/migrate-app-to-telamon.sh`).
The repository keeps its GitHub name, `atlas-framework`, until it is renamed
in one batch with the others; the URL above is the one to use until then.
Apps build with `cargo build --locked` (or `--frozen`), so a
moved tag can't change their dependencies.

Telamon.Ui's translation is chosen once per process, from `QLocale` at the first
load; a language change shows after the app restarts.

Compiled into an app, the crates' file paths (panic locations, debug info)
come with them: an app's packaged build passes
`RUSTFLAGS=--remap-path-prefix=<source>=. --remap-path-prefix=$CARGO_HOME=cargo`
and `-ffile-prefix-map=<source>=.` so no build path lands in the RPM.

Unlike Telamon.Ui, the crates are compiled into each app: a change reaches an
app when it moves its tag forward and is rebuilt. Shared behaviour that
should change everywhere at once (look, layout, the About page) belongs in
Telamon.Ui.

Build and test the crates in the development container
(`packaging/Containerfile.dev`, `localhost/telamon-framework-dev:44`): `cargo test --workspace --all-features`
and `cargo clippy --workspace --all-features --all-targets`.

### Notifications and on-disk formats

[Notifications](reference/telamon-framework-system/notify.md) holds the Telamon OS
notification rules (only when the user can act, popups only, never `Critical`,
never from root). [On-disk formats](reference/telamon-framework-system/formats.md)
holds every file format. The principle stays here: every file an app or a
service writes for another to read carries its format version, readers
accept a missing or a higher one forever, and the number is raised only for a
change an old reader would misread. `crates/*/tests/fixtures/` holds files
written by older versions; tests read them, and they are never edited, only
added to.

## How apps use it

Telamon.Ui is a QML module installed with Qt's own, like Kirigami:

```
/usr/lib64/qt6/qml/Telamon/Ui/
  libtelamonui.so       the plugin: the C++ types and every QML file, compiled
  qmldir
  telamonui.qmltypes    the C++ types, for qmllint and qmlcachegen
  *.qml               for qmllint and qmlcachegen (the plugin loads its own copy)
```

An app:

- writes `import Telamon.Ui` in QML, and links nothing: the QML engine loads
  the plugin;
- checks at configure time that the module is installed (the template's
  `CMakeLists.txt` shows how). qmlcachegen and qmllint find it in Qt's QML
  directory on their own, so `<app>_qmllint` checks the app against it;
- gives its RPM `Requires: telamon-ui` and `BuildRequires: telamon-ui`, with
  `>= <version>` once it uses something added after 1.0.0, and the same
  version as `ui:` in `app!`;
- runs the framework's checks in its CI (`app-checks.yml`, see "Checks").

There is no CMake package and no devel package: an app needs nothing from
Telamon.Ui but the installed module.

To try a Telamon.Ui change in an app before it is packaged, install it over
the packaged one inside the app's build container (never on the host):

```sh
cmake -S . -B build -G Ninja -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build && cmake --install build
```

That build has `TELAMON_UI_DEV_PATHS` off, like a package; add
`-DTELAMON_UI_DEV_PATHS=ON` to keep the source-tree paths.

## Compatibility

Telamon.Ui's API is a contract with every Telamon app: its type names, their
properties, signals, functions and enum values, the singletons, and
`Symbols.<Name>`. They are built separately and updated separately, so a
change that breaks an app breaks it on users' machines.

- **Not API:** members whose name starts with `_`, and C++ helper types
  whose name ends in `Private` (`TelamonColorsPrivate`, behind TelamonStyle's
  colour functions). Apps don't use them; `api/` leaves them out.
- **Adding** is fine: a new property with a default that keeps the old look,
  a new value, a new type. Raise the minor version (2.0.0 to 2.1.0) and say
  what was added in the spec's changelog, so apps can require it.
- **A new type can hide an app's own.** `import Telamon.Ui` wins over the QML
  files in an app's own directory, so a Telamon.Ui type named like an app's
  local type replaces it in that app, which then breaks (the Installer's
  `SearchField` did, and is now `ListSearchField`). Before adding a type,
  search every Telamon app for a `.qml` file of that name, and prefer a name
  no app would pick on its own (`TelamonProgressBar`, not `ProgressBar`).
- **Renaming or removing** anything, or changing what an existing property
  means, needs every app that uses it updated first, in the same Telamon OS
  build. Search all the Telamon app repositories for it before you change it,
  and raise the major version. Prefer adding the new name and keeping the old
  one working.
- **Changing the look** (colours, spacing, radii) is allowed when it follows
  these design rules: every app changes with it, which is the point.
- **The Rust crates follow semver.** Their public items are a contract too,
  but an app only gets a change when it moves its `rev`, so a break shows up
  in that app's build, not on users' machines. Still: add rather than
  rename, and raise the major version for a break. Two things are fixed
  across versions because separately built programs share them: the C
  functions in `include/telamon/app.h` (only add new ones), and anything on
  disk or on D-Bus (the settings file format, crash report and history
  files, polkit action IDs): read the old form forever.
- **Deprecation.** A type or property can be deprecated for one more minor
  version before it is removed in the next major. It keeps working; its
  header comment says "Deprecated since X.Y: use Z"; its reference page
  says so (`deprecated:` in the frontmatter); and `tools/lint-app.sh` warns (not errors) when an app uses it. The
  names live in `tools/deprecated.txt` (`Name<TAB>since<TAB>replacement`),
  which lint-app.sh reads; it is empty for now.
- **Dependency floors are what CI tests.** A crate's requirement on another
  crate names the version in this repository's Cargo.lock (`zbus =
  "5.19.0"`, not `"5"`). CI builds only against the lock, so a looser floor
  lets an app with an older lock resolve a version that was never built
  and fail to compile (zbus 5.16 lacks `Error::Connection`). When
  `cargo update` moves the lock past an API the code starts using, raise
  the floor with it. An app moving to a release whose floor is above its
  own lock entry for that crate (it uses tokio itself, say) gets "failed to
  select a version for `tokio`" from `cargo update -p telamon-framework-...`:
  add `-p tokio` and run it again, once per crate named. `--recursive`
  doesn't cover a crate the framework didn't use in the old lock (a newly
  enabled feature). The release pull request does this by itself, up to
  10 crates; when cargo's error names no crate, its lock job fails with
  cargo's message and that app is moved by hand. `-p` takes the newest
  compatible version, so the pull request can move such a crate further
  than the floor needs.
- **The version check.** An app that needs something new says so twice:
  `Requires: telamon-ui >= X.Y.Z` in its spec (dnf), and `ui: "X.Y.Z"` in
  `app!` (a plain error at startup when an older Telamon.Ui is installed some
  other way). `TelamonApp.uiVersion` is the project version in `CMakeLists.txt`.
- **Telamon.Ui is tied to the Qt minor version.** qmlcachegen compiles its
  QML against Qt's private API, so `libtelamonui.so` needs the exact Qt minor
  it was built with (rpm records this as `Qt_6.11_PRIVATE_API`). A Qt minor
  update (6.11 to 6.12) means rebuilding telamon-ui, then the apps, in the same
  Telamon OS build; the image build does both. The ISO build takes Telamon.Ui
  from the image it embeds, so the installer always matches it.
- Updating the fonts can drop or rename symbols upstream: `generate.py`
  keeps Google's older names as aliases for `name:`, but check the diff of
  `symbolnames.h` for removed `Symbols.<Name>` values, which are a break.

### The rename (2.0.0)

2.0.0 renamed everything from Atlas to Telamon at once: the QML module
(`Atlas.Ui` to `Telamon.Ui`), every `Atlas<Name>` type to `Telamon<Name>`
(types without the prefix, such as `Section` or `DataTable`, and every
member of every type, are unchanged), the crates (`atlas-framework-*` to
`telamon-framework-*`), the C header and its functions
(`include/atlas/app.h`, `atlas_*` to `include/telamon/app.h`, `telamon_*`),
the packages (`atlas-ui` to `telamon-ui`, `atlas-symbols*` to
`telamon-symbols*`), the font families (`Material Symbols <Style>` to
`Telamon Symbols <Style>`, the same glyphs) and the environment variables
(`ATLAS_*` to `TELAMON_*`). An app moves with
`tools/migrate-app-to-telamon.sh`; `CHANGELOG.md` has the list.

- **Both frameworks install side by side** while apps move one by one: no
  package name, file path, font family or QML module is shared, and
  telamon-ui does not `Obsoletes:` the atlas-ui packages (a later release
  will, once no app needs them). The spec's `%check` fails if an installed
  path has "atlas" in it.
- **What a program of 1.x wrote is read, never written.** Where a crate or
  Telamon.Ui owns a name on disk, the new name is used, and the old one is
  read while the new one is absent: the settings file `atlas-<app>rc`
  (copied to `telamon-<app>rc` the first time, `[Atlas]` becomes `[Telamon]`),
  the shared `atlasrc`, `~/.config/atlas/crash-reporting.toml` and the
  per-user state in `$XDG_STATE_HOME/atlas` (crash reports, markers; moved),
  `/etc/atlas` and `/usr/share/atlas`, the user's `atlas-<app>.notifyrc`, and
  the variables `ATLAS_SOFTWARE_RENDERING`, `ATLAS_REDUCED_MOTION` and
  `ATLAS_LOG`. The old files stay (an app of 1.x keeps using them), so the
  two sides stop following each other once the new one exists. Each has a
  test. Remove these reads only in a major version, after the last app moved.
- **Names other components own stay until they rename them:** the crash
  relay's DSN key (`atlasos@`), its payload's field names and category, the
  `AtlasOS` issue repository, `/var/lib/atlas-core` and `/var/lib/atlasos`,
  the os-release `ID`, the image name and `atlas-system-helper`. They change
  in the same release as the component that owns them.

## Checks

CI (`.github/workflows/ci.yml`) runs in the development container on every
push and pull request:

- **Build, qmllint, `cargo test`, clippy** (warnings fail).
- **Visual tests** (`tests/visual`): every demo, in Breeze Light, Breeze
  Dark, a custom accent, and with transparency off, compared with
  `tests/visual/golden/`. A changed picture fails until its new golden is
  committed (`TELAMON_UPDATE_GOLDENS=1`), so every visible change is approved
  in review. The failed run uploads the actual and diff pictures.
- **Accessibility test** (`tests/a11y`): every demo's focusable controls have
  a role and a name.
- **API check** (`tools/check-api.sh`): the API of the built module against
  `api/`. A removed or changed line fails as a break; an added one fails
  until `tools/update-api.sh` records it and the version is raised.
- **cargo-semver-checks** for the crates, against the last `v*` tag.
- **Performance** (`perf/measure.sh`): the template's startup time, RSS, PSS
  and idle CPU against `perf/budget.json`, with the numbers in the run's
  summary.
- **The apps** (`tools/apps.txt`): each is cloned and checked with
  `lint-app.sh` and `check-app-names.sh`, so a new Telamon.Ui type that would
  hide an app's file fails here first.

Apps run `lint-app.sh` and `check-app-names.sh` themselves through the
reusable `app-checks.yml` (`tools/README.md` shows the five lines).
`// telamon-lint: allow <reason>` on or above a line silences a finding.

## Releases

One version covers the repository: `project(... VERSION)` in
`CMakeLists.txt`, `Version:` in the spec and `[workspace.package] version`
in `Cargo.toml` move together. To release:

1. Write the `## X.Y.Z` section of `CHANGELOG.md` (for apps: what they can
   now use and what they should change) and the spec's `%changelog`.
2. Raise the three versions, commit, and tag `vX.Y.Z`.
3. Push main, wait for CI, then push the tag. `release.yml` checks that the
   tagged commit is on main and passed CI, that the versions match the tag
   and that the CHANGELOG section is finished (not "unreleased"); publishes
   the GitHub release with that section; and opens a pull request in every
   app in `tools/apps.txt` that moves its crates to the tag. When the tag
   raises the major version (the crates' names or API may have changed) it
   opens none: apps are moved by hand, and the workflow says so.

The app pull requests need a fine-grained token with Contents and Pull
requests (read and write) on the app repositories. It is a secret of the
`release` environment only (Settings, Environments), never of the
repository:

- `release` has a required reviewer and a deployment rule for `v*` tags, and
  a ruleset protects `v*` tags. The checks in `release.yml` are part of the
  tagged commit, so they stop mistakes, not someone who can push: approve
  only a tag whose commit is on main.
- The token never meets an app's code. An app checkout is not trusted
  (cargo runs what its `.cargo/config.toml` names), so
  `tools/open-update-pr.sh` works in two jobs: `lock`, with no secret,
  clones the app and runs `cargo update` for the telamon-framework crates
  (plus each crate cargo names as a conflict, see "Dependency floors") and
  hands back only the `Cargo.lock` files; `publish`, with the token, runs
  nothing from the app, builds the commit from git objects and accepts only
  lock files in cargo's own layout whose changes a framework update can
  make (telamon-framework at the tagged commit, crates.io packages the app or
  the framework already uses). Anything else, and nothing is pushed.
- If any app's lock job fails, no pull request is opened (a failed one can
  mean another job forged its output). Fix the cause and "Re-run all jobs":
  the release step finds the release made, and an existing pull request is
  left alone.
- A pin the script cannot move (a `[dependencies.telamon-framework-x]` table)
  is a warning in the run's log: move it by hand.

Each app reviews its pull request, builds with `--locked`, and raises its
`telamon-ui >=` and `ui:` when it adopts something new.

## How a change reaches the apps

Apps don't contain Telamon.Ui: each loads `libtelamonui.so`, which holds every
Telamon.Ui QML file compiled, when it starts. So a change here (a colour, a
radius, a control's behaviour) reaches every app the next time it starts,
without rebuilding any app. On Telamon OS that is the first start after the
image update that carries the new telamon-ui. (Tested: the same
`telamon-updater` binary picked up a changed button colour from a replaced
`libtelamonui.so` alone.) Apps are only rebuilt for API changes, which the
rules above cover.

Already live, without a restart: the Plasma colour scheme, accent and
light or dark (through `Kirigami.Theme`), and the transparency switch
(through `Appearance`, which watches `telamonrc`).

## Packages

`packaging/telamon-framework.spec` builds:

| Package | Holds |
|---|---|
| `telamon-ui` | The module in `/usr/lib64/qt6/qml/Telamon/Ui`, and `/etc/dnf/protected.d/telamon-framework.conf`. Requires telamon-symbols-fonts, kf6-kirigami and qt6-qtdeclarative |
| `telamon-symbols-fonts` | Material Symbols Rounded, family "Telamon Symbols Rounded" (noarch, Apache-2.0) |
| `telamon-symbols-fonts-extra` | Outlined and Sharp (noarch, Apache-2.0); requires telamon-symbols-fonts of the same release |
| `telamon-symbols` | The Telamon Gallery, `telamon-symbols`, with its desktop file; recommends telamon-symbols-fonts-extra |

telamon-ui and telamon-symbols-fonts are required parts of Telamon OS:
`telamon-framework.conf` stops dnf removing them, and the Telamon OS image build
fails without them. The Telamon OS image builds the RPMs from this repository
(its `telamon-framework` build context) and installs them before the apps,
which are built against them.
