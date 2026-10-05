# Changelog

What each atlas-framework release brings to apps. One version covers the whole
repository: Atlas.Ui (`atlas-ui`), the fonts, the gallery and the Rust crates.
Apps pin a release tag (`tag = "vX.Y.Z"` on the crates) and require the same
Atlas.Ui (`Requires: atlas-ui >= X.Y.Z`, `ui: "X.Y.Z"` in `app!`) once they use
something it added. The packaging spec's `%changelog` repeats the package side.

## 1.4.0 (unreleased)

- Atlas.Ui: AtlasPasswordField, a rounded password field with a show/hide eye
  that hides the text again when focus leaves, the window goes to the
  background, or the field is hidden or disabled. `lint-app.sh` points
  Kirigami.PasswordField and password TextFields to it.
- Atlas.Ui: AtlasAction (Qt's Action with `symbol`, `toolTip` and `section`),
  the AtlasShortcuts registry that warns about shortcut conflicts,
  AtlasShortcutLabel (keycaps) and AtlasShortcutsDialog (searchable list of an
  app's shortcuts).
- Atlas.Ui: the `AtlasStyle` singleton (colours by role, spacing, radii, font
  sizes, durations, `density`, `rowHeight`) and the system preferences on
  `Appearance` (`colorScheme`, `darkMode`, `highContrast`, `reducedMotion`,
  `textScale`), live. Durations are 0 when animations are off in Plasma or
  `ATLAS_REDUCED_MOTION=1`.

## 1.3.0

- Atlas.Ui form controls: AtlasTextField (error text, clear button),
  AtlasTextArea, AtlasComboBox, AtlasCheckBox (tristate), AtlasRadioButton,
  AtlasSlider and AtlasSpinBox (prefix, suffix).
- Atlas.Ui feedback: AtlasToolTip, AtlasSpinner, AtlasPlaceholder (loading
  lines), AtlasEmptyState and AtlasFocusRing.
- Atlas.Ui for file managers, stores and launchers: AtlasBreadcrumb,
  AtlasIconGrid, AtlasAppCard, AtlasScreenshotCarousel, AtlasInstallButton
  (with progress and cancel) and AtlasSearchResults (keyboard navigation).
- Atlas.Ui version check: `ui: "1.3.0"` in `app!` (or
  `atlas_app_require_ui()`) stops an app with a plain message when the
  installed Atlas.Ui is older than it needs. `AtlasApp.uiVersion` reports it.
- `atlas_framework_system::notify` (feature `notify`): desktop notifications
  for every app, the sender Atlas Updater used. The template ships a
  `.notifyrc`.
- The template's live demo data stops while its window is minimized or
  hidden, the way an app's polling should.
- On-disk formats carry a version: `"format": 1` on history and event lines,
  `[Atlas] Format=1` in settings. Readers accept files without it.
- Crash report scrubbing is tested against a set of fake secrets.
- atlas-symbols is now the Atlas Gallery: every Atlas.Ui control live (with
  a Disabled switch and the QML to copy) next to the symbol browser.
- atlas-symbols-fonts ships Material Symbols Rounded only, the style Atlas.Ui
  uses; Outlined and Sharp are in atlas-symbols-fonts-extra (about 20 MB less
  on disk for a system without the gallery). `Symbols.available(style)` says
  whether a style is installed.
- Checks for apps: `tools/lint-app.sh` (default buttons and controls Atlas.Ui
  replaces) and `tools/check-app-names.sh`, as a reusable workflow
  (`app-checks.yml`).
- Releases: `vX.Y.Z` tags publish a release from this file and open a pull
  request in every app that moves its crates to the tag. Apps pin
  `tag = "vX.Y.Z"` instead of a commit.

Upgrading:

- A system upgraded from 1.2.0 keeps only the Rounded symbols unless
  atlas-symbols-fonts-extra is installed (the gallery recommends it; dnf
  installs a new recommendation on upgrade only with weak dependencies on).
  No Atlas app uses Outlined or Sharp today.
- Apps that move from `rev =` to `tag =` must build with `cargo build --locked`
  (or `--frozen`), so the commit in Cargo.lock, not the tag, decides what is
  built.
- `InfoBanner`'s close button and the current `TabBar` tab now take keyboard
  focus with Tab (never on click), and show the focus ring.
- The crates require the dependency versions they are tested with (zbus
  5.19, tokio 1.53, serde 1.0.229, ...), so `cargo update` moves an app's
  older ones up; the release pull request does this.

## 1.2.0

- Atlas.Ui: TabBar, FindBar, StatusBar, StatusBarItem, InfoBanner, Toast and
  ToolbarButton (from Atlas Notepad).
- ContextMenuItem: a check mark for checked checkable rows, `icon.source`, a
  submenu arrow; hidden rows and separators take no room.
- Crates: `bootc::utc_second` and `bootc::TRANSPORTS` are public; crash
  report scrubbing handles `::` paths, quoted values and secrets in more forms.

## 1.1.0

- Atlas.Ui: AtlasApp and AtlasAboutPage.
- atlas-ui ships `/usr/share/atlas/crash-reporting.toml`: crash reports go to
  the AtlasOS relay, which posts them as GitHub issues.

## 1.0.0

- First release: Atlas.Ui, atlas-symbols-fonts and Atlas Symbols, moved out of
  atlasos-updater, and the atlas-framework crates (startup, settings, logging,
  crash reports, polkit, Flatpak).
