# Changelog

What each atlas-framework release brings to apps. One version covers the whole
repository: Atlas.Ui (`atlas-ui`), the fonts, the gallery and the Rust crates.
Apps pin a release tag (`tag = "vX.Y.Z"` on the crates) and require the same
Atlas.Ui (`Requires: atlas-ui >= X.Y.Z`, `ui: "X.Y.Z"` in `app!`) once they use
something it added. The packaging spec's `%changelog` repeats the package side.

## 1.4.0 (unreleased)

- Atlas.Ui: AtlasClipboard (text, rich text and image on the system clipboard
  from QML), AtlasCodeView (read-only monospace text with copy button, line
  numbers and a height cap), AtlasCopyButton and AtlasCommandPalette (a
  Ctrl+K search over the app's AtlasActions).
- Atlas.Ui: AtlasUrlValidator, AtlasEmailValidator, AtlasPathValidator and
  AtlasNumberValidator, validators for an AtlasTextField; AtlasDoubleSpinBox
  (AtlasSpinBox with decimals and locale-formatted text); AtlasShortcutField,
  a field that records a key combination and reports a conflict with another
  AtlasAction.
- Atlas.Ui: AtlasCalendar (month grid with keyboard navigation, minimum and
  maximum), AtlasDatePicker (a pill that opens it) and AtlasTimePicker (hours,
  minutes, `minuteStep`, 12 or 24 h from the locale, optional day of week).
- Atlas.Ui: AtlasSegmentedControl (joined pill segments, one selected),
  AtlasSplitButton (a main button with an arrow menu), AtlasChip (plain,
  checkable or closable) and AtlasChipGroup (a wrapping, exclusive-capable
  group with one Tab stop).
- Atlas.Ui: AtlasSidebar, a scrolling sidebar with selected/focused entry kept in
  view, `filterText` and a placeholder, `contextMenuRequested`, drop targets and
  Tab landing on the selected entry; AtlasWindow `widthClass` and
  `sidebarCollapsed`.
- Atlas.Ui: SectionRow slots `leading` (items before the title, replacing the
  icon), `content` (replaces the title and subtitle, e.g. a slider) and
  `busy` (a spinner at the trailing edge, no activation while it shows;
  `animated` turns the spinner off for screenshots). A control in `trailing`
  keeps its own focus: the row's ring and Enter/Space no longer follow it.
  AtlasPage: `headerTrailing` (items at the end of the title row) and a
  writable `maxContentWidth`. docs/DESIGN.md "States" says what every control
  does disabled, read only, in error, busy, hovered, pressed and focused, and
  `tests/state` checks the disabled and focus rules on every demo.
- Atlas.Ui: AtlasSplitView (Atlas divider, remembers sizes), AtlasNavigationStack
  (pages with a Back header) and AtlasViewSwitcher (page tabs with symbols and
  badges).
- Atlas.Ui: AtlasColorField (colour pill with palette, hex field and system
  dialog), AtlasFileField and AtlasFolderField (path field with a Browse button
  for the system dialog), AtlasAutocompleteField (suggestions while typing) and
  AtlasFontPicker (family and size, optionally monospace only).
- Atlas.Ui: AtlasDropZone (a dashed drop area with symbol, text, optional Browse
  button, MIME and name filters, accepted URLs only) and AtlasOnboarding (a
  setup scaffold: steps, one page at a time, Back, Skip and Next or Finish).
- Atlas.Ui: AtlasToolbar (actions as buttons, the rest in a "more" menu),
  AtlasFloatingToolbar (a capsule that floats over content and never takes the
  editor's focus) and AtlasFlowLayout (wrapping layout that honours `Layout.*`).
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
- Atlas.Ui: ConfirmDialog gains `alternativeText` and `alternative()` (a third
  button), `defaultButton` and `destructive`; its text and body now wrap to the
  card and scroll when taller than the window. AtlasSpinBox is as wide as its
  widest value instead of a fixed size, gains `showButtons`, and PageUp and
  PageDown move ten steps. AtlasComboBox gains `filterable` (type to narrow the
  choices). AtlasTextField gains `showCounter`, `prefix`, `suffix`,
  `invalidText` and `validateOn`. A compact SidebarItem shows its title and
  value as a tooltip.
- Atlas.Ui: ToolbarButton gets `symbol`, a clearer checked style (accent fill
  and icon) and `focusable` (Tab reaches it, with the focus ring). It, and
  ContextMenuItem and MenuButton, follow an `action` (`symbol`, tooltip,
  shortcut), a plain Qt Action included.
- Atlas.Ui: ContextMenuItem `radio` (a dot, exclusive through a ButtonGroup or
  ActionGroup); a ContextMenu taller than the window scrolls and keeps the
  current row in view.
- Atlas.Ui: StatusBarItem `symbol`; its `menu` opens above the cell from its
  leading edge, kept inside the window.
- Atlas.Ui: AtlasLabel (a Label in one of five text styles: Body, Title,
  Heading, Caption, Mono). AtlasEmptyState gains `actionSymbol`, InfoBanner
  `closeName`, Toast an action button (`showAction()`, `actionTriggered()`),
  AtlasProgressBar `text` and `status` ("paused", "error"), and AtlasAboutPage
  a "Copy system info" button and `systemInfo()`.

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
