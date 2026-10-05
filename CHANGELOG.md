# Changelog

What each atlas-framework release brings to apps. One version covers the whole
repository: Atlas.Ui (`atlas-ui`), the fonts, the gallery and the Rust crates.
Apps pin a release tag (`tag = "vX.Y.Z"` on the crates) and require the same
Atlas.Ui (`Requires: atlas-ui >= X.Y.Z`, `ui: "X.Y.Z"` in `app!`) once they use
something it added. The packaging spec's `%changelog` repeats the package side.

## 1.5.0 (unreleased)

- Fix: `ConfirmDialog` with `destructive: true` draws the accept button in
  AtlasButton's Destructive look again (error text and border on a faint
  error fill); since 1.4.0 it was drawn in the accent.
- Fix: `AtlasSidebar` no longer logs "TypeError: Property 'findSelected' of
  object [null]"; the selection highlight follows when the selected entry or
  group is hidden or a group header is selected.
- Fix: `AtlasSidebar` uses `AtlasScrollBar`, hides it when `compact`, and
  keeps its width free on its side (also in right-to-left) so it no longer
  covers labels and values.
- Fix: a compact `SidebarItem`'s tooltip includes `badgeText`.
- Fix: in right-to-left a `SidebarItem` without a value keeps its label next
  to its icon instead of at the far edge.
- Fix: `AtlasDialog` with nothing focusable in the body no longer gives the
  first focus to a footer button (Cancel): it stays on the dialog, so Return
  right after opening presses nothing. (The header was already excluded.)
- Fix: `ToolbarButton`'s tooltip hides while the button is pressed and after
  it was clicked (a menu or popup it opened is not covered by the tooltip), and
  returns once the pointer has left and come back.
- Fix: `TabBar` with more tabs than fit: the strip now shrinks to the bar and
  scrolls, so the "+" button stays in view, and a tab made current after it
  was added scrolls into view. Before, the strip kept its full width, ran past
  the bar's edge and never scrolled (since 1.3.0). A wheel scroll is kept
  until the current tab changes, the strip doesn't move under a pressed or
  dragged tab, a dragged tab drops only on tabs in view, and the wheel stops
  at the strip's real start.
- Fix: `AtlasTreeModel` no longer follows a `QModelIndex` that is another
  model's or outlived `setItems()` (best effort), caps its nodes at
  100000 and reads `symbol` safely; `AtlasShortcuts` ignores NaN, infinite
  and out-of-range numbers as key sequences; `Appearance.textScale` is kept
  between 0.5 and 4.
- Fix: an `AtlasPage` in an `AtlasNavigationStack` whose header shows no
  longer repeats its title under the header (its `headerTrailing` items
  stay); the header's title is heading-sized (it took the point size as
  pixels and came out small).
- Fix: a frameless `AtlasWindow` is easier to resize: its edge handles reach
  6 px in (4 before) and each corner is an L running 16 px along both edges;
  along the top edge the corners stop where the header's buttons begin. A
  scrollbar at the window's right edge loses 6 px to the handle (4 before).
- Fix: a user's edit no longer ends an app's binding on the edited property
  of `AtlasRating` (`value`), `AtlasSegmentedControl` (`currentIndex`),
  `AtlasCalendar` (`selectedDate`, `month`, `year`), `AtlasDatePicker`
  (`selectedDate`), `AtlasColorField` (`color`) and `AtlasFontPicker`
  (`font.family`, `font.pointSize`). If the app stores the edit in the edit
  signal's handler, the binding follows the model; if it ignores it, the
  property returns to the model's value one event-loop turn later. A literal
  value or no binding keeps the edit, as before.
- Fix: the same holds for `AtlasComboBox.currentIndex`, `AtlasFileField` and
  `AtlasFolderField` `path`, and FindBar's `findText`, `replaceText`,
  `matchCase`, `wholeWords` and `regularExpression` (their `onXChanged`
  handlers still fire on every edit).
- Fix: `InfoBanner`'s close button no longer writes `shown`, so an app's
  `shown: x` binding keeps working; new read-only `dismissed`. A dismissed
  banner comes back on a new `text` or `type`, or when the app writes
  `shown = true`. This applies to every closable banner: one whose text
  changes often (a count, progress) should not be closable.
- Added: `AtlasTimePicker.minuteArrowStep`, `minimumHours`,
  `minimumMinutes` and `adjusted()`: arrows, the wheel and screen-reader
  steps move by the arrow step and stop at the minimum; an earlier time is
  raised to it.
- Added: `AtlasCopyButton.label` and `copiedLabel`, a button with text.
- Added: `AtlasFormat.bytes` and `bytesPerSecond` take `system` ("iec", the
  default, or "si"); `date()` has the styles `longAtTime`, `atTimeSentence`
  and `relativeSentence`. A size that rounds up to the next unit is shown in
  it ("1.0 MB", not "1000.0 kB").
- Added: `AtlasAboutPage.showSystemRows` (hide the OS and Qt rows) and
  `links`, rows that replace Source code and Report a problem (https, http
  and mailto only; when no entry is valid the built-in rows stay).
- Added: `AtlasDetailGrid.title`, `footer` and `framed` (a heading, a note
  and a Section-style card). The grid builds only what each cell needs: about
  half the time and a third of the memory per grid. Fix: a model given as a
  C++ list (`QVariantList`) is shown; it was empty.
- Added: `AtlasBreadcrumb.hiddenText` (the "Hidden folders" text) and
  `AtlasCodeView.inset` (side room for an unframed view).
- Fix: `AtlasSidebar.filterText` follows the same edit rule: text typed in
  the built-in field no longer ends an app's binding.
- Added: `AtlasSidebar.footer` (entries pinned under the scrolling list, such
  as Settings and About) and `footerSeparator`; `SidebarGroup.symbol`,
  `badge` and `badgeText`.
- Fix: `AtlasAboutPage` leaves no empty space above the app's name when the
  app's icon isn't installed.
- Added: `AtlasPage.subtitle` (muted lines under the title, read as the
  page's description), `busy` and `busyText` (a spinner row under the title,
  announced once the text settles); `AtlasAboutPage` has them too.
- Added: `AtlasDialog.scrollToTop()`; a dialog also scrolls to the top each
  time it opens.
- Added: `AtlasWindow.toast()` (a queue of toasts, one at a time, announced)
  and `confirm()` (a ConfirmDialog whose answer comes once through `done`);
  `compactBreakpoint` and `wideBreakpoint` set where `widthClass` changes.
- Added: `AtlasNavigationStack` announces the new page's title to screen
  readers on push, pop and replace.
- Docs: `TextButton` is not an `AtlasButton` preset and has no `variant`.
- Added (atlas-framework-flatpak): `list_updates_report` with `ListOptions`
  (refresh, no interaction, a `CancelToken`, a timeout per libflatpak call
  (60 s by default) and an overall deadline) returning `ListOutcome`
  (updates, the installations that failed, how many were checked, whether it
  was cancelled); `update_cancellable`. All new structs are
  `#[non_exhaustive]`: start from `ListOptions::default()` or `with_*`.
- Fix (atlas-framework-flatpak): `list_updates` returns the updates it found
  when one installation fails (it fails only when all do, and logs a warning
  for a partial result); download sizes are looked up only with `refresh`,
  and a remote that failed to refresh or answer is not asked again in the run.
- Fix (atlas-framework-core, -system): settings and event-log locks wait at
  most 2 s, then fail with `TimedOut` (show it); reads are capped and never
  block on a FIFO or take a terminal; a settings file that isn't UTF-8 still
  reads but is not rewritten; leftover settings temp files older than a day
  are removed; event names and versions are capped, oversized lines refused,
  and trimming the log never empties it; history appends are locked.
- Fix (atlas-framework-system): a polkit check is cancelled (`CancelCheck`)
  when it times out, the caller leaves the bus or the future is dropped, and
  an interactive check gives up after 120 s; bootc status without an `image`
  parses; notifications fall back to the installed `.notifyrc`.
- Fix (atlas-framework-ui): `atlas_app_init` may be called more than once;
  the startup error window also quits when the scene graph fails, the window
  is destroyed or after 5 minutes.
- Tools: the API snapshot records each type's base class, and `check-api.sh`
  treats a changed base as breaking; on a tag push it compares against the
  previous tag, not the tag itself.
- Tools: `dev-check.sh` holds a lock per build directory, runs under an init
  so Ctrl-C stops ninja and ctest, refuses a demo name that matches no demo,
  and prints lint findings as file:line.
- Tools: `perf/measure.sh` measures the build it is given (it installed or
  compared nothing before) and fails when the budget file or a key is
  missing.
- Tools: `lint-app.sh` no longer passes apps that import
  `QtQuick.Controls.Basic` (or another style), hide imports behind comments,
  or have no QML files (`--allow-empty` for those); `check-app-names.sh`
  fails on an empty app.
- Tools: `dev-check.sh` takes `ATLAS_DEV_JOBS` (fewer build and test jobs,
  for several checkouts at once) and passes `ATLAS_UPDATE_GOLDENS` through;
  an update run rewrites only the goldens that fail, not every picture.
- Tools: `ATLAS_UPDATE_GOLDENS=1 tools/dev-check.sh` can write the goldens
  (it mounted the source read-only).
- Packaging: `build-rpm.sh` packages the committed tree only (git archive of
  HEAD) and refuses a dirty one; the spec builds and ships the translations.
- Template: drill-down pages use `AtlasNavigationStack`; `main.cpp`
  includes `atlas/app.h` (found through `cargo metadata --locked`); a worker
  that panics no longer leaves `busy` set; the page timer stops while another
  page covers it; the notifyrc names a real icon; a per-app CI workflow
  (`.github/workflows/atlas.yml`) pinned to a framework tag; the minimum
  Atlas.Ui is 1.4.0.
- Crates: `atlas_framework_core::task` (cargo feature `task`, off by default):
  one tokio runtime thread for the app and `spawn_ui(post, timeout, future,
  on_done)`, which runs a future with a timeout and a cancellable
  `TaskHandle` and posts the `Outcome` back to the UI thread (with cxx-qt,
  `post` is `move |job| qt_thread.queue(job)`; a gone QObject is ignored).
- Crates: `Settings::migrate(&[Migration])` upgrades a settings file by
  `[Atlas] SchemaVersion` (missing is 0), keeping the old file as `<name>.bak`
  first; a failing step names its version and changes nothing, and a file
  newer than the app is an error and is left alone.
- Crates: `Settings::watch(callback)` reports changes to the file, also an
  editor's rename over it, debounced by 200 ms, with the new values in a
  `Snapshot` (inotify on the directory through `libc`, no new dependency).

## 1.4.0

- Look changes apps will see without changing code: buttons, text fields,
  combo boxes and search fields have small rounding (4 px) instead of pills;
  buttons and fields are 28 px high (24 compact), down from about 30 and 34;
  hover is grey; the focus ring is a 2 px magenta-violet ring with a gap;
  validation errors appear after the field loses focus (or on Return), with a
  red border, faint red fill and an icon; neutrals are tinted violet with
  tonal steps. Check fixed heights and width-tuned rows in apps.
- Design pass, fields: text fields, password, text area, search, combo box,
  spin boxes, date, time, colour, font and shortcut fields use small corners
  (`radiusSmall`), `controlHeight` (growing with large text), `control` fill,
  `controlBorder` edge and grey hover. An error shows a red border, a faint
  red fill, an error symbol at the trailing edge and the message a full
  `spacing` below. `AtlasTextField` validator errors appear after the field
  loses focus or on Return, then follow live (`errorText` shows at once).
  `AtlasFocusRing` is a 2 px `focus` ring with a 2 px gap that grows into
  place. `AtlasColorField` shows and accepts `rgba(r, g, b, a)`.
  `AtlasDropZone` swells slightly for an acceptable drag.
- Atlas.Ui design pass, surfaces: menus, popovers, tooltips, toasts, the
  command palette and dialogs use `AtlasStyle.floatingBackground` (strong tint
  over the blur, solid without it) with radius 6 (dialogs and the command palette 8, toasts round); the header bar
  and floating toolbar use `chromeBackground`; the window is `AtlasStyle.base`;
  `Section` and `AtlasCard` are solid surfaces with light separators;
  `AtlasCodeView` has its own `codeSurface`. `AtlasLabel` gains the
  `WindowTitle` and `Code` styles (Code is Mono) and Heading uses the full
  text colour. `AtlasShortcutLabel` shows a comma between the steps of a
  two-step shortcut. `AtlasProgressBar` shimmers violet to sakura while it is
  working (`animated: false` holds it still; flat under reduced motion). New
  `AtlasEdgeGlow`: a soft violet-to-sakura glow along the edges of its parent,
  for one meaning only, "the system is doing something for you now" (since 1.4.0;
  `reach` sets how far it reaches in, and the corners overlap by design).
- Buttons, switch, segmented control and chips follow the new design: small
  corners (buttons go from 4 to 6 px while pressed), grey hover, `controlHeight`, readable disabled
  text. `AtlasButton` gains `variant` (Default, Prominent, Destructive, Ghost;
  `prominent` still works) and `busy` (spinner, presses ignored); a checked
  button or toolbar button has a clear on state. The switch thumb slides with a
  small overshoot and an off switch is visible when disabled. The segmented
  control's highlight springs to the new segment, never on resize, and elides
  long text. `AtlasSpinner` gains `color`. New `AtlasSpringAnimation`:
  standard settles in about 240 ms, expressive overshoots about 7%.
- Atlas.Ui fixes to 1.3.0 controls: `ToolbarButton` with `focusable` now takes
  Return/Enter through the normal click path, so a bound `action` fires and a
  `checked` binding survives. `AtlasProgressBar` fills its height again when it
  has no `text` (the thin centred track only beside a label), no longer
  overflows when narrower than its label room, follows `LayoutMirroring` for
  the fill side, and warns once about an unknown `status`.
- Atlas.Ui fixes: ConfirmDialog no longer runs a destructive (or Cancel-first)
  accept when Return is pressed in a field of the body; the date picker's popup
  follows the picker after a pick or clear; pickers give the focus back after
  closing only if it was inside them; AtlasDropZone no longer sticks in the
  error state after an unacceptable drag; AtlasAutocompleteField acts on the
  typed text on a fast Return or Tab and starts with nothing highlighted;
  AtlasShortcutField ignores key repeat; AtlasToolbar keeps its overflow menu
  while it is open.
- Atlas.Ui: AtlasSettings (an app's settings file, shared with the Rust
  `settings` module, same lock; typed values, batched atomic writes,
  `changed(key)` from other writers), AtlasWindow.stateKey (saves and restores
  the window's size and maximised state) and AtlasPortal (`openUrl` for http,
  https, mailto and existing file URLs only; `notify` with actions and
  `actionInvoked`). A second launch already raises the running window.
- Atlas.Ui: the merged header. An `AtlasWindow` given an `AtlasHeaderBar` as its
  `header` becomes frameless (opt-in; other windows are unchanged) and draws
  its own title row: window menu, title, main tools with overflow, and
  `AtlasWindowButtons` matching the AtlasOS KWin decoration, in KWin's button
  layout. The header drags and maximises the window, the window resizes
  through 4 px edge handles, and `AtlasAppMenu` exports the app's menus to the
  global menu when there is one (`AtlasWindowChrome`), or shows a menu button.
- Atlas.Ui: menus, tooltips, popovers, dialogs, toasts, the command palette and
  the combo box and date picker popups are tinted and translucent over the
  blurred window, and solid when `Appearance.effective` is off. New
  AtlasTransparencySwitch, a settings row for `Appearance.transparency`.
- Atlas.Ui: the Atlas look. Violet accent (and pink focus rings,
  `AtlasStyle.focus`) unless the user chose a Plasma accent; IBM Plex Sans as
  the application font and JetBrains Mono in code (`AtlasStyle.fontFamily`,
  `monoFamily`, with fallback to the system fonts; the `atlas-ui` package
  requires both fonts); smaller corners (4, 6, 8) and quicker motion
  (100, 150, 250 ms). Every picture of a control changes.
- Atlas.Ui: AtlasTreeView, a tree on Qt Quick's TreeView in the Atlas list
  look (single or multi selection, keyboard, type-ahead, RTL), and
  AtlasTreeModel, a tree model built from nested JS objects.
- Atlas.Ui: AtlasClipboard (text, rich text and image on the system clipboard
  from QML), AtlasCodeView (read-only monospace text with copy button, line
  numbers and a height cap), AtlasCopyButton and AtlasCommandPalette (a
  Ctrl+K search over the app's AtlasActions).
- Atlas.Ui: AtlasListView, a ListView in the Atlas look with single or multiple
  selection, a default row (symbol, text, subtitle), type-ahead, a placeholder,
  `contextMenuRequested` and drag or Alt+arrow reordering (`moveRequested`).
- Atlas.Ui: DataTable `resizableColumns` (drag or double-click a header boundary,
  `columnWidths`, `columnResized`), `columnsMenu` and `hiddenColumns`,
  `selectionMode` with `selectedRows` (Ctrl/Shift click, Shift+arrows, Ctrl+A),
  `rowContextMenuRequested` and `density`; it reads AtlasStyle tokens.
- Atlas.Ui: AtlasUrlValidator, AtlasEmailValidator, AtlasPathValidator and
  AtlasNumberValidator, validators for an AtlasTextField; AtlasDoubleSpinBox
  (AtlasSpinBox with decimals and locale-formatted text); AtlasShortcutField,
  a field that records a key combination and reports a conflict with another
  AtlasAction.
- Atlas.Ui: AtlasCalendar (month grid with keyboard navigation, minimum and
  maximum), AtlasDatePicker (a field that opens it) and AtlasTimePicker (hours,
  minutes, `minuteStep`, 12 or 24 h from the locale, optional day of week).
- Atlas.Ui: AtlasSegmentedControl (joined segments in a rounded 8 px track, one selected),
  AtlasSplitButton (a main button with an arrow menu), AtlasChip (plain,
  checkable or closable) and AtlasChipGroup (a wrapping, exclusive-capable
  group with one Tab stop).
- Atlas.Ui: AtlasSidebar, a scrolling sidebar with selected/focused entry kept in
  view, `filterText` and a placeholder, `contextMenuRequested`, drop targets and
  Tab landing on the selected entry; AtlasWindow `widthClass` and
  `sidebarCollapsed`.
- Atlas.Ui: AtlasStat (a figure with unit, trend and sparkline), AtlasDetailGrid
  (label/value pairs with copy buttons), AtlasSparkline (a C++ axis-less line
  chart), AtlasAvatar (image or initials), AtlasRating (zero to five stars,
  halves, optionally editable) and AtlasBadge (a round label or dot with a tint).
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
- Atlas.Ui: AtlasColorField (a field with a colour swatch, palette, hex field and system
  dialog), AtlasFileField and AtlasFolderField (path field with a Browse button
  for the system dialog), AtlasAutocompleteField (suggestions while typing) and
  AtlasFontPicker (family and size, optionally monospace only).
- Atlas.Ui: AtlasDropZone (a dashed drop area with symbol, text, optional Browse
  button, MIME and name filters, accepted URLs only) and AtlasOnboarding (a
  setup scaffold: steps, one page at a time, Back, Skip and Next or Finish).
- Atlas.Ui: AtlasToolbar (actions as buttons, the rest in a "more" menu),
  AtlasFloatingToolbar (a capsule that floats over content and never takes the
  editor's focus) and AtlasFlowLayout (wrapping layout that honours `Layout.*`).
- Atlas.Ui: AtlasPopover (a card with an arrow that opens next to a control),
  AtlasScrollBar (thin, widens on hover, fades when idle), AtlasDialog (the
  general dialog: title row with Back and Close, scrolling body, footer
  buttons), AtlasCard (a padded, optionally clickable surface) and
  AtlasExpandableSection (a header that folds its content, animated).
- Atlas.Ui: AtlasPasswordField, a password field with small corners and a show/hide eye
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
- Atlas.Ui: the existing controls read the `AtlasStyle` tokens (radii, spacing,
  fonts, durations) and stop looping animations under reduced motion; SectionRow,
  TabBar, StatusBar and SidebarItem follow `AtlasStyle.density` (Compact is about
  75% of the height) and have a local `density` property.
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
- Atlas.Ui: AtlasFormat, a singleton that writes sizes, speeds, percentages,
  numbers, durations and dates ("1.5 MiB", "42%", "1 h 5 min", "5 minutes
  ago") in the user's locale, with Atlas.Ui's own translated wording.

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
