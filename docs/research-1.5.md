# Research for 1.5.0 and after

> Written before the 2.0.0 rename and left as it was: Atlas.Ui is now Telamon.Ui,
> every `Atlas<Name>` type is `Telamon<Name>`, `atlas-ui` is `telamon-ui` and
> the `atlas-framework-*` crates are `telamon-framework-*` (see CHANGELOG.md).

October 2026. How to make Atlas.Ui and the crates more consistent, less code
for apps, faster and easier to use, from what Qt, KDE, GNOME, Apple, Google
and Microsoft do now, plus measurements of the framework itself. The items to
act on are filed in [ROADMAP.md](ROADMAP.md) (A2, the P-phase notes and
B2); this page keeps the evidence and the sources.

Web findings come from primary sources where a page was fetched (Qt docs and
blogs, KDE blogs and repositories, libadwaita docs, Apple and Android docs).
Items marked *unverified* came from search summaries or general knowledge:
check them before relying on them.

## Measured here

**Compiled QML.** The `all_aotstats` target works with the open-source
qmlcachegen (no commercial qmlsc needed). Atlas.Ui compiles 4377 of 5529
bindings and functions to C++ (79.2 %); the gallery 32 %. What stops the
rest, by count:

| Cause | Count |
|---|---|
| "Could not find property" (untyped or duck-typed access) | 276 |
| Calls to untyped JS functions, and functions without type annotations | 113 + 78 |
| `Qt.alpha` / `Qt.rgba` return a QVariant, not a `color` | 107 |
| "Cannot access value for name control/root" (unbound component scope) | 31 + 23 |
| An array stored in a non-sequence property | 26 |
| LoadClosure (closures over outer scope) | 23 |

Worst files (not compiled / total): DataTable 79/209, ConfirmDialog 37/54,
AtlasShortcutsDialog 35/57, AtlasWindow 35/46, AtlasSidebar 29/87,
AtlasViewSwitcher 29/79, AtlasTreeView 27/115, SectionRow 27/108,
AtlasNavigationStack 26/50, UsageBar 26/50, AtlasStat 23/48,
AtlasDetailGrid 20/68, AtlasSplitView 19/22.

`pragma ComponentBehavior: Bound` with id-qualified access already took
qmllint from 172 warnings to 119 in 1.5.0 (TabBar, SidebarItem and others).

**Type names Qt now has too.** Qt 6.9 added an attached `ContextMenu` and
Qt 6.10 a `SearchField` to QtQuick.Controls. Atlas.Ui has both names. In
a file that imports `QtQuick.Controls` without an alias and `Atlas.Ui`,
Atlas's `ContextMenu` hides Qt's in either import order
(`ContextMenu.menu: Menu {}` fails with "Non-existent attached object";
tested in the dev container on Qt 6.11.2). The gallery and the template
import `QtQuick.Controls as QQC2`, so they are not affected, but nothing
tells apps to.

**Per-instance cost.** Creating N = 1000 of one type with
`Component.createObject` (offscreen, in the dev container, median of 5 runs,
spread under 5 %; Qt Quick Controls in the container's default style as the
baseline):

| Type | µs each | KB RSS each | QObjects | Against Qt's control |
|---|---|---|---|---|
| AtlasDetailGrid (4 rows) | 3265 | 887 | 75 | |
| SectionRow | 2469 | 343 | 29 | (955 µs at N = 200: grows with count) |
| SidebarItem | 764 | 195 | 16 | |
| AtlasComboBox | 686 | 244 | 6 | 5.0x time, 2.4x memory |
| AtlasTextField | 293 | 140 | 13 | 6.8x, 2.2x |
| AtlasStat | 289 | 165 | 13 | |
| ToolbarButton | 270 | 116 | 11 | 6.6x, 2.0x |
| AtlasButton | 246 | 112 | 11 | 6.0x, 1.9x |
| AtlasCheckBox | 132 | 74 | 6 | 1.3x, 1.3x |
| AtlasCard | 111 | 122 | 15 | |
| AtlasListView default row | 109 | 113 | 24 | 3.9x, 2.5x (ListView with ItemDelegate) |
| Symbol | 92 | 33 | 2 | |
| AtlasSwitch | 30 | 68 | 5 | 0.4x, 0.6x |
| Rectangle and Text | 7 | 21 | 2 | the floor |

An active AtlasEdgeGlow took about 12 % of a core under the offscreen
(software) renderer at 1920x1080; inactive, nothing. The likely causes,
from reading the files (not profiled yet): AtlasDetailGrid builds 8 cells
of nested items in a GridLayout; SectionRow has 3 layouts and 2 Behaviors
around its slots; AtlasComboBox's 6 objects carry many bindings,
transitions and a Behavior; buttons and fields add a focus ring, a Loader
and their own background to every instance.

**From the apps.** Atlas Monitor measured its RSS on 1.4.0 and Atlas Updater
measured AtlasEdgeGlow at 40 to 145 % of a core under software rendering
(llvmpipe); both are in the P-phase notes.

## Performance

1. **Get more of the module compiled to C++.** Qt's guidance: qualify
   access through ids under `pragma ComponentBehavior: Bound`, use
   `required property` in delegates instead of injected roles, annotate
   every function's parameter and return types, and use typed properties
   and `as` casts instead of `var` (Qt's own example went from 804 to
   654 µs). The causes above map onto these one for one; the colour helpers
   need a typed replacement for `Qt.alpha`/`Qt.rgba` (a C++ invokable on
   AtlasStyle returning `QColor`). Gate it in CI with `all_aotstats` and a
   ratchet like the qmllint one.
   [Qt blog: fixing unqualified access](https://www.qt.io/blog/compiling-qml-to-c-fixing-unqualfied-access),
   [Qt blog: optimizing for compilation](https://www.qt.io/blog/optimizing-your-qml-application-for-compilation-to-c),
   [QML script compiler](https://doc.qt.io/qt-6/qtqml-qml-script-compiler.html)
2. **qmlsc's static and direct modes stay out.** They are part of the
   commercial Qt Quick Compiler Extensions, and static mode generates wrong
   code when a property is shadowed. Qt 6.11's `virtual`/`override`
   keywords and the `[shadow]` qmllint warning (off by default) find the
   shadowing that also costs performance in qmlcachegen.
   [QML tooling in 6.11, part 2](https://www.qt.io/blog/whats-new-in-qml-tooling-for-qt-6.11-part-2)
3. **AtlasEdgeGlow under software rendering.** Under Qt's software
   adaptation ShaderEffect does not render and any running animation
   repaints the whole window; under llvmpipe the RHI reports OpenGL or
   Vulkan, so the graphics API alone doesn't reveal it (check `GL_RENDERER`
   for "llvmpipe" too). Make the glow static, or throttle it to 15 to 30
   fps, when rendering is in software, and never animate the full window.
   [Software adaptation](https://doc.qt.io/qt-6/qtquick-visualcanvas-adaptations-software.html),
   [KDAB: Qt Quick without a GPU](https://www.kdab.com/qt-quick-without-a-gpu-i-mx6-ull/),
   [Qt Quick performance](https://doc.qt.io/qt-6/qtquick-performance.html)
4. **Per-instance cost of cards and rows.** Create late (Loader, with
   `asynchronous: true` for what isn't needed for the first frame), destroy
   what is hidden, reuse delegates (`reuseItems`), and avoid `clip`,
   `layer.enabled` and a Behavior on every instance. Qt's old numbers (2021,
   Qt 5.15) show style choice alone changing 500 buttons from 31 MB to
   555 MB, so measure ours rather than guess; Qt's
   `tests/benchmarks/quickcontrols2/creationtime` is the model.
   [Qt Quick performance](https://doc.qt.io/qt-6/qtquick-performance.html),
   [qt-interest, May 2021](https://lists.qt-project.org/pipermail/interest/2021-May/037050.html)
5. **Startup.** Keep the bytecode cache; qmltc (`ENABLE_TYPE_COMPILER`) is
   optional and roughly halved load time in Qt's embedded benchmark. Defer
   what the first frame doesn't need. Profile imports with
   `QML_IMPORT_TRACE`.
   [Qt Quick Compiler benchmark](https://www.qt.io/blog/benchmark-of-qtquickcompiler-on-low-end-embedded-linux)

## Less code for apps, and more consistent apps

Ranked by how much app code each removes. Most are new API and so belong to
1.6.0 unless an app needs them sooner (1.5.0 is the robustness release).

1. **Forms as structure, not layout.** KDE's new Kirigami Forms has Form,
   FormGroup, FormEntry and FormSeparator wrapping the stock controls, and
   one environment switch draws the same markup flat or as cards. Atlas has
   Section and SectionRow; a FormEntry that takes any control, its label,
   help text and `errorText`, with field `validator`s and a form-level
   `valid`, removes the label/control/error plumbing every settings page
   repeats. Kirigami Forms is still experimental, so copy the shape, don't
   depend on it.
   [Kirigami Forms](https://notmart.org/blog/2026/04/kirigami-forms-and-configurations/)
2. **Settings pages that save themselves.** libadwaita's preferences dialog
   (searchable pages, groups and Switch/Spin/Entry/Password rows) plus a
   `settingKey` on each row bound to AtlasSettings, as SwiftUI's
   `@AppStorage` does, removes the settings window, its persistence and its
   search from every app.
   [libadwaita 1.8](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1.8/),
   [SwiftUI Settings](https://developer.apple.com/documentation/swiftui/settings)
3. **Declare each action once.** KDE's new ActionCollection
   (kirigami-app-components) defines actions in QML with user-configurable
   shortcuts, because the older StatefulApplication needed C++ subclasses.
   AtlasAction already exists; a registry of them can feed menus, the
   command palette, AtlasShortcutsDialog and hover shortcut hints (KF 6.24
   shows a button's shortcut on hover), so an app declares an action in one
   place.
   [kirigami-app-components](https://notmart.org/blog/2026/05/kirigami-app-components/),
   [KF 6.24](https://9to5linux.com/kde-frameworks-6-24-improves-support-for-plasma-and-kirigami-based-apps)
4. **View states as one property.** SwiftUI's ContentUnavailableView and
   Kirigami's PlaceholderMessage: a `status` (loading, empty, error, no
   results, ready) on AtlasListView, DataTable and AtlasPage that shows
   AtlasEmptyState or AtlasSpinner itself replaces the `visible:` plumbing
   in every view.
   [ContentUnavailableView](https://www.createwithswift.com/display-empty-states-with-contentunavailableview-in-swiftui/)
5. **Adaptive layout without `width < N`.** libadwaita's breakpoints and
   NavigationSplitView and Compose's NavigationSuiteScaffold pick the shell
   from the window size class. AtlasWindow has `widthClass`; an adaptive
   scaffold on top of it (sidebar or tab bar, split or stack) does the
   switching for the app.
   [libadwaita 1.8](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1.8/),
   [Compose adaptive navigation](https://developer.android.com/develop/adaptive-apps/guides/build-adaptive-navigation)
6. **Imperative helpers for one-off UI.** `Toast` exists; a singleton
   `toast(text, {action})` with a queue, and a `confirm()` with a callback,
   save a declared component per use. (QML has no await; a callback or a
   signal it is.)
7. **Slots take any content, and the defaults are right.** KDE developers'
   main complaints about Kirigami were defaults every app overrides and
   APIs that accept only one item type (the global drawer only takes
   Actions, so no unread counts). Keep slots as `default property` lists of
   Items. *Thread may be dated.*
   [KDE Discuss: thoughts on Kirigami](https://discuss.kde.org/t/we-need-your-thoughts-on-kirigami/6115)
8. **Tokens only, enforced.** Slint and libadwaita expose semantic tokens
   only; lint can enforce the same for apps (no raw colours, durations or
   radii; named springs only), as a qmllint plugin (work in progress in
   6.11) or in lint-app, with `--fix` where Qt provides fixits.
   [qmllint in 6.11, part 3](https://www.qt.io/blog/whats-new-in-qmllint-for-qt-6.11-part-3)

## Modern Qt and desktop features

1. **`Accessible.announce()`** (Qt 6.8): speak toasts, validation errors and
   page changes. Test with Orca.
   [Accessible](https://doc.qt.io/qt-6/qml-qtquick-accessible.html)
2. **Contrast and colour scheme from Qt.** `QStyleHints.colorScheme` (6.5)
   and `accessibility.contrastPreference` (6.10). KDE's portal provides
   color-scheme, accent-color and reduced-motion, but not contrast.
   [QStyleHints](https://doc.qt.io/qt-6/qstylehints.html),
   [portal Settings](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Settings.html),
   [xdg-desktop-portal-kde settings.cpp](https://github.com/KDE/xdg-desktop-portal-kde/blob/master/src/settings.cpp)
3. **Reduced motion.** KDE sets it as AnimationDurationFactor 0 (the portal
   maps it to `reduced-motion`, and Kirigami's durations become 0). Qt 6.12
   adds `QAccessibilityHints.motionPreference`; until Atlas moves to 6.12,
   keep reading Kirigami's durations.
   [QAccessibilityHints](https://doc.qt.io/qt-6/qaccessibilityhints.html),
   [Kirigami Units](https://api.kde.org/frameworks/kirigami/html/units_8h_source.html)
4. **Popups as real windows.** `popupType: Popup.Window` (6.8) lets menus,
   the command palette and tooltips leave the window's bounds; it falls
   back to an item when unsupported. Set it explicitly and test on KWin.
   [Popup](https://doc.qt.io/qt-6/qml-qtquick-controls-popup.html)
5. **New Qt types to build on or align with.** ContextMenu (6.9),
   SearchField (6.10), DoubleSpinBox and DialogButtonBox `defaultButton`
   (6.11), RectangularShadow (6.9, per-corner radius in 6.11, cheaper than
   MultiEffect), the Switch accessible role and orientation (6.11).
   [What's new in 6.9](https://doc.qt.io/qt-6/whatsnew69.html),
   [6.10](https://doc.qt.io/qt-6/whatsnew610.html),
   [6.11](https://doc.qt.io/qt-6/whatsnew611.html)
6. **Wayland.** Give dialogs their transient parent (xdg-dialog-v1 in Qt
   6.8 only works then), set the window icon (xdg-toplevel-icon-v1, 6.9),
   and watch xx-session-management (experimental in 6.10 and 6.11).
   [xdg-dialog in Qt and KWin](https://planet.kde.org/david-redondo-2024-04-04-implementing-xdg-dialog-v1-in-qt-and-kwin)
7. **Blur.** KWin is moving from its private blur protocol to
   ext-background-effect-v1; keep calling KWindowEffects and keep the solid
   fallback. [KWin issue 221](https://invent.kde.org/plasma/kwin/-/issues/221)
8. **Testing through accessibility.** KDE's selenium-webdriver-at-spi drives
   Qt apps by accessible name and role, so the same names serve tests and
   screen readers.
   [Selenium AT-SPI](https://planet.kde.org/harald-sitter-2022-12-14-selenium-at-spi-gui-testing)
9. **Translations.** `qt_add_translations` makes a plurals-only source
   `.ts` by default (6.7); the lupdate `//=` metastring is deprecated in
   6.11. [qt_add_translations](https://doc.qt.io/qt-6.9/qtlinguist-cmake-qt-add-translations.html)

## Developer experience

- **Hot reload.** Qt 6.12 reloads QML in place, keeping C++ objects,
  and restarts with input replay when it can't. It needs a QML debug build
  and `qt_add_qml_module`, through Qt Creator 19 or the `qmlpreview` CLI,
  with the new `qt_add_qml_preview()` CMake helper; it is off with
  `QMLPREVIEW_HOTRELOAD=0`. The source carries the usual LGPL/GPL headers.
  Keep gallery demos free of C++ so they reload.
  [Hot reload in Qt 6.12](https://www.qt.io/blog/hot-reload-in-qt-6.12),
  [qt_add_qml_preview](https://doc.qt.io/qt-6/qt-add-qml-preview.html)
- **A preview matrix.** Flutter's widget previewer takes size, text scale,
  brightness, theme and locale per preview. The gallery's golden variants
  (light, dark, accent, opaque, a11y, i18n) are the same idea; letting an
  app run its own pages through that matrix (an `AtlasPreview` wrapper and
  a runner) removes each app's throwaway demo mains.
  [Flutter widget previewer](https://docs.flutter.dev/tools/widget-previewer)
- **Translation checks.** Qt 6.11's `lcheck` validates `.ts` files
  (accelerators, whitespace, ending punctuation, `%1` markers) and exits
  non-zero, so it fits CI. No Qt pseudo-localisation tool exists; a small
  `.ts` transform (accents and about 30 % longer text) would catch strings
  that aren't translatable or that truncate.
  [lcheck](https://doc.qt.io/qt-6/linguist-lcheck.html)
- **qmlls** in 6.11 jumps to C++ definitions and handles multi-project
  workspaces. [qmlls in 6.11](https://www.qt.io/blog/whats-new-in-qml-language-server-in-6.11)
- **No QML codemod tool exists**; a rename across apps stays a script.

## The crates

1. **cxx-qt is at 0.10.0** (2026-08-24); 0.8.1 had breaking changes. Upgrade
   on a branch. [cxx-qt changelog](https://github.com/KDAB/cxx-qt/blob/main/CHANGELOG.md)
2. **One async pattern.** A tokio runtime on its own thread; results back
   with `CxxQtThread::queue(...)`, which returns an error once the QObject
   is gone (checking `is_destroyed()` first is racy: call `queue` and drop
   the result on error); a cancellation token and a timeout on every D-Bus
   and network call. A small shared helper makes it one line per call for
   apps. [CxxQtThread](https://docs.rs/cxx-qt/latest/cxx_qt/struct.CxxQtThread.html)
3. **Portal Settings in one place.** Read color-scheme, accent-color,
   contrast and reduced-motion once, follow `SettingChanged`, treat a
   missing key as "no preference", and fall back to QStyleHints. `ashpd`
   wraps it. [ashpd](https://docs.rs/ashpd)
4. **Crash reports.** Out-of-process minidumps (crash-handler and
   minidumper), deduplicated by signature with a local cooldown; on Plasma,
   systemd-coredump and DrKonqi stay the fallback. Reports of DrKonqi
   filling disks in 2026 make the caps matter.
   [DrKonqi and coredumpd](https://planet.kde.org/harald-sitter-2022-05-25-drkonqi-coredumpd/),
   [sentry-contrib-native](https://github.com/daxpedda/sentry-contrib-native)
5. **Settings.** Watch the directory, not the file (inotify on a file is
   lost after a rename), and keep a `schema_version` with sequential
   migrations.
6. **Packaging.** Fedora's qt6-rpm-macros (`%{_qt6_qmldir}`); reproducible
   builds with `SOURCE_DATE_EPOCH` and `--remap-path-prefix`. KDE's Flatpak
   runtime supports the two newest Qt minors (6.10 is on freedesktop SDK
   25.08). [qt6-rpm-macros](https://packages.fedoraproject.org/pkgs/qt6/qt6-rpm-macros/),
   [KDE Flatpak runtime policy](https://community.kde.org/Policies/Flatpak_Runtime_Update_Policy)

## Component API conventions

From Compose's component guidelines, WinUI and SwiftUI. Most of these are
rules for new API rather than new types.

- **Slots, not strings,** and one way to pass defaults: a component takes
  `leading`/`trailing`/`contentItem` slots, and its default sizes and
  colours live in one place that a wrapping component can reuse.
  [Compose component API guidelines](https://android.googlesource.com/platform/frameworks/support/+/androidx-main/compose/docs/compose-component-api-guidelines.md)
- **Hoisted state:** `value` plus a `valueEdited` signal (the user's
  change), so a binding to `value` is never broken by the control itself.
  This is the A1 binding rule.
- **Per-child metadata through attached properties.** SwiftUI's container
  values let a container read metadata from its children. In QML an
  attached type (`Form.label`, `Form.help`) lets a form or section read
  each child's label without a parallel model.
  [SwiftUI ContainerValues](https://developer.apple.com/documentation/swiftui/containervalues)
- **Inline status with a severity.** WinUI's InfoBar takes layout space,
  has a severity (colour, icon and accessible role together), one action
  and an optional close. InfoBanner is this; check it covers the four
  severities and the action.
  [WinUI InfoBar](https://learn.microsoft.com/en-us/windows/apps/design/controls/infobar)
- **Bind to derived values.** Compose re-runs only when a derived result
  changes (`derivedStateOf`) and keys lazy items by id. In QML, bind to a
  derived `bool` (`scrolled: flick.contentY > 0`) rather than the raw
  value, and give delegates stable identity. WinUI's own measured startup
  costs were wrapper items around icons and repeated token lookups.
  [Compose performance](https://developer.android.com/develop/ui/compose/performance/bestpractices),
  [Windows App SDK 2.0 notes](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-notes/windows-app-sdk-2-0)

## Platform services

- **Global shortcuts.** The GlobalShortcuts portal (v2) is implemented by
  KDE on top of kglobalacceld; since Plasma 6.7.4 a shortcut is active
  only after `BindShortcuts`. Qt doesn't wrap it, so a framework wrapper
  saves every app the D-Bus session code.
  [GlobalShortcuts portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html),
  [KDE bug 523063](https://bugs.kde.org/show_bug.cgi?id=523063)
- **Notifications.** Portal v2 has buttons with purposes, icons, sounds
  and categories; for RPM apps on Plasma, KNotification (what the notify
  crate uses) stays simpler. Use the portal for Flatpak.
  [Notification portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Notification.html)
- **Tray.** On Plasma, QSystemTrayIcon is backed by KStatusNotifierItem
  through the platform integration plugin, so Qt's API is enough.
- **Decorations.** Qt 6.11 prefers server-side decorations on Wayland, and
  KWin draws them; AtlasWindowChrome's own buttons stay for frameless
  windows only. [What's new in 6.11](https://doc.qt.io/qt-6/whatsnew611.html)
- **Fractional scaling.** Qt implements wp-fractional-scale-v1 and keeps
  the `PassThrough` rounding policy; forum advice to switch to
  `RoundPreferFloor` gives up true 1.5x. Keep PassThrough and snap 1 px
  lines and borders to device pixels in the style. *Snapping guidance is
  our inference.* [High DPI](https://doc.qt.io/qt-6/highdpi.html)
- **Text rendering.** QtRendering (the default) is fast but costs memory
  and shows artifacts at large sizes; NativeRendering looks native but is
  poor under transforms and animation; CurveRendering (6.7) suits large or
  scaled text. Keep the default.
  [Text improvements in 6.7](https://www.qt.io/blog/text-improvements-in-qt-6.7)

## Qt versions and bindings

- **Qt 6.12 LTS was released on 2026-09-30** (support to 2031-09-30); Qt
  6.11's standard support ends on 2027-03-17. Fedora 44 and 45 ship Qt
  6.11.2, and no Fedora change for 6.12 was found, so 6.12 most likely
  arrives with Fedora 46 (*inferred*). Atlas stays on 6.11 for 1.5.0;
  6.12-only features (motionPreference, hot reload, ToolTip `policy`,
  MenuItem shortcuts, Menu `separatorsCollapsible`) wait for the Fedora
  that ships it. Open-source users get only the first patch releases of an
  LTS. [Qt 6.12 released](https://qt.io/blog/qt-6.12-released),
  [Qt releases](https://doc.qt.io/qt-6/qt-releases.html),
  [What's new in 6.12](https://doc.qt.io/qt-6/whatsnew612.html),
  [qt6-qtbase in Fedora](https://packages.fedoraproject.org/pkgs/qt6-qtbase/qt6-qtbase)
- **motionPreference** reads the portal's `reduced-motion` (which KDE's
  portal sets from AnimationDurationFactor 0), so on 6.12 it can replace
  the Kirigami-duration check.
- **Qt's own Rust binding.** Qt Bridges for Rust (`qtbridge`) has been in
  public beta since 2026-07-01: LGPL-3.0 or commercial, cargo-only, Qt 6.10
  or later, QML-only (`#[qobject]`, properties, slots, signals, list and
  table models, a thread-safe invoker with a tokio example). Its README
  points projects that mix Rust and C++ or need C++-only Qt modules to
  cxx-qt. The crates mix both (C functions in `atlas/app.h`, CMake builds),
  so cxx-qt stays; look again when qtbridge reaches a stable release.
  [Qt Bridges public beta for Rust](https://www.qt.io/blog/qt-bridges-public-beta-for-rust),
  [qtbridge-rust](https://codeberg.org/qtproject/qtbridge-rust)
