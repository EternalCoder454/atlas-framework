# Roadmap

## 1.4.0

Everything below ships in 1.4.0 (decided 2026-10-04). The goal is to tag it
fast: a finding blocks the tag only when it is Critical or High, or when it
touches the API (names, types, property meanings, defaults), because 1.4.1
can fix behaviour but never rename. Everything else is filed for 1.4.1.

Sources: the requests from Notepad, the Installer, the Updater and the
Monitor, and a comparison with libadwaita 1.9, Kirigami Addons and Qt 6.11
Quick Controls. Checked against Qt 6.11.2 in the dev image:
`T.DoubleSpinBox` exists, `Flickable.positionViewAtChild` exists,
`DialogButtonBox.defaultButton` exists, `QAccessible::Switch` exists.
StyleKit is a technology preview and is not used.

Already there, not to be built again: the gallery (one demo per type), visual
tests (light, dark, accent, opaque), the API snapshot (`api/`,
`tools/check-api.sh`), the a11y audit (role and name), ContextMenu submenus,
ConfirmDialog's body slot, `maximumLength` and `validator` on the text fields
(inherited from Qt), notification actions (`notify::Note.actions`), the
single-instance D-Bus name, the settings file (`atlas_framework_core::settings`).
Durations already come from `Kirigami.Units`, which follows Plasma's
animation speed.

### How the work runs

1. **API sketch first** (one pass, reviewed once): every new type and
   property below gets its name, properties, signals and defaults written in
   `docs/api-1.4.0.md`. Names are the contract; once the sketch is agreed,
   implementers follow it and don't invent API.
2. **Batches F0 to F5**, each split into units that touch different files.
   A unit is one implementer in its own worktree off main: code, demo,
   goldens (looked at), the `api/` line, CHANGELOG line, translations.
   At most three run at a time. The lead merges each unit after its tests
   pass.
3. **Gates once per batch**, not per unit: tester (build, qmllint, ctest,
   check-api, lint), ui-checker on the batch's demos, reviewer and
   security-reviewer on the batch diff (split by area past ~1,000 lines).
4. **Release**: P pass (`perf/measure.sh`, budgets in `perf/budget.json`),
   versions in CMakeLists.txt and Cargo.toml, tag with the user's OK, then
   tell the app sessions.

### F0: bugs and AtlasPasswordField

- [x] AtlasPasswordField (9bd6564 and its review fixes)
- [x] Section's fold header toggles on Return and Enter, not only Space
- [x] LiveChart.setValues/setValues2 skip the repaint when nothing changed
- [x] AtlasSwitch reports the Switch accessible role

### F1: foundations

- [x] `AtlasStyle` singleton: colours by role (accent, surface, text, success,
      warning, error; from Kirigami.Theme), spacing, radii (today 6, 8 and 10
      are hard-coded), font sizes, durations; controls read it
- [x] `Appearance` gains the system's colour scheme, high contrast, reduced
      motion and text scale (one place for system preferences)
- [x] Global density: `AtlasStyle.density` (normal, compact) read by TabBar,
      StatusBar, SectionRow and the rows of lists; one reduced-motion flag
      every animation reads
- [x] `AtlasLabel { textStyle: Title | Heading | Body | Caption | Mono }`
      (replaces the planned AtlasHeading and AtlasCaption)
- [x] `AtlasAction` on Qt's `Action`: text, symbol, shortcut, enabled,
      checkable, toolTip. ToolbarButton, ContextMenuItem, MenuButton,
      AtlasFloatingToolbar and AtlasCommandPalette take one; an icon-only
      button gets its tooltip from the action's text
- [x] Shortcut registry (collects actions' shortcuts, warns on conflicts),
      `AtlasShortcutsDialog`, `AtlasShortcutLabel`
- [x] Slots: SectionRow `leading`, `trailing` (any control) and `content`;
      `SectionRow.busy` (replaces the planned AtlasBusyRow); AtlasPage
      `headerTrailing` and writable `maxContentWidth`
- [x] The state contract in DESIGN.md (enabled, readOnly, error, busy,
      hover, pressed, focus) and a test that walks every demo for it
- [x] Changes to existing types: ToolbarButton `symbol`, checkable style,
      `focusable`; StatusBarItem `symbol` and its menu no longer covering
      neighbours; ConfirmDialog third button, default button, destructive
      style, body capped to the panel width; AtlasSpinBox narrower and
      `showButtons`; ContextMenu exclusive radio groups and fitting the
      available height; AtlasComboBox type-to-filter; AtlasEmptyState
      `actionIcon`; InfoBanner `closeName`; SidebarItem tooltip when compact;
      Toast action button (Undo); AtlasProgressBar label and paused/error
      states; AtlasAboutPage "Copy system info"; AtlasTextField character
      counter, prefix, suffix and validating while typing or on leaving

### F2: inputs

- [x] `AtlasValidators` (C++ validators): url(schemes), email, path, number;
      replaces the planned AtlasUrlField
- [x] `AtlasDoubleSpinBox` on Qt 6.11's DoubleSpinBox (decimals); with
      `AtlasSpinBox.showButtons: false` it replaces the planned AtlasNumberField
- [x] `AtlasSegmentedControl`
- [x] `AtlasTimePicker` (minuteStep, optional day, 12/24 h from the locale)
- [x] `AtlasDatePicker` and `AtlasCalendar`
- [x] `AtlasColorField`, `AtlasFileField`, `AtlasFolderField` (the file
      chooser portal through QtQuick.Dialogs)
- [x] `AtlasShortcutField` (records a key combination)
- [x] `AtlasSplitButton`
- [x] `AtlasChip`, `AtlasChipGroup`
- [x] `AtlasAutocompleteField`
- [x] `AtlasFontPicker`

### F3: surfaces, layout and navigation

- [x] `AtlasSidebar`: scrolls the focused item into view
      (`positionViewAtChild`), filtering, an empty placeholder, item context
      menus, drop targets, focus lands on the selected row
- [x] Width classes on AtlasWindow (compact, medium, wide); sidebars collapse
      the same way everywhere
- [x] `AtlasSplitView` (remembers its sizes), `AtlasNavigationStack`
      (push, pop, Back), `AtlasViewSwitcher` (page tabs)
- [x] `AtlasToolbar` (overflows into a "more" menu), `AtlasFloatingToolbar`
      (Notepad's ToolCapsule), `AtlasFlowLayout`
- [x] `AtlasPopover`, `AtlasScrollBar`, `AtlasDialog` (title, Back and Close,
      scrolling body, slots), `AtlasCard` (padded body, slots),
      `AtlasExpandableSection`
- [x] `AtlasDropZone`, an onboarding scaffold on StepItem (Back, Next, Skip)

### F4: lists and display

- [x] `AtlasTreeView`
- [x] `AtlasListView` (single and multi-select, type-ahead, context menu,
      drag to reorder)
- [x] DataTable: column resize, show and hide columns, multi-select, row
      context menu, sticky header
- [x] `AtlasStat` (value, label, unit, trend; replaces AtlasBigStat),
      `AtlasDetailGrid`, `AtlasSparkline` (C++; NaN gaps, auto-scale with a
      minimum, no repaint when equal)
- [x] `AtlasAvatar`, `AtlasRating`, `AtlasBadge`
- [x] `AtlasCodeView` (read-only monospace, framed or not, max height,
      optional copy), `AtlasCopyButton`
- [x] `AtlasCommandPalette` (AtlasSearchResults fed by AtlasAction)

### F5: services, checks and lint

- [x] `AtlasFormat`: bytes, percentages, durations, numbers and dates (long,
      short, date-time, at a time, relative); Atlas.Ui owns the strings
- [x] `AtlasClipboard`: text, rich text and images
- [x] `AtlasSettings` in QML on the existing settings file: typed values with
      defaults; restores window size, sidebar width and split sizes
- [x] Portal helpers: open a URL; notification actions from QML (the crate
      has them); a second launch raises the running window (check what the
      single-instance name already does)
- [x] Visual test variants: high contrast, right-to-left, compact, 200% text
- [x] a11y: a tab-order test per demo
- [x] Deprecation rule in DESIGN.md (one more minor version, with a
      lint-app.sh warning)
- [x] lint-app.sh: Kirigami.PlaceholderMessage, a hand-made tinted banner,
      QQC2.ToolTip, Kirigami.Heading (use AtlasLabel)

### F6: the Atlas look

- [x] Violet accent (buttons, selection) and pink focus rings by default; a
      Plasma accent colour, when chosen, wins
- [x] IBM Plex Sans for UI, JetBrains Mono for code (system fonts when absent)
- [x] Small rounding, quick and subtle motion
- [x] Blur on most surfaces (popups, menus, dialogs), tinted, each with a
      solid fallback; `AtlasTransparencySwitch` for the settings page
- [x] Merged header: `AtlasHeaderBar` (title, tools, window buttons matched
      to the AtlasOS KWin decoration) on an opt-in frameless `AtlasWindow`;
      `AtlasAppMenu` exports menus to Plasma's global menu when present

Dropped: AtlasCoreGrid (AtlasCard and MiniBars cover it), AtlasHeading,
AtlasCaption, AtlasBusyRow, AtlasNumberField, AtlasUrlField, AtlasBigStat.

## 1.5.0

Started 2026-10-05. There is no 1.4.1: bug fixes and new API both land here.
1.5.0 is a robustness release and runs the full F.S.R.P plan, phase by phase:
a phase starts only when the one before has no open problems, every finding is
fixed (not only Critical and High), and the same check runs again on the fixes
until it comes back clean. Every new member gets its line on its
docs/reference page in the same commit (`tools/docs.py check` fails
otherwise). Versions are bumped at release.

### Plan: what done means

**Study (before the F phase closes).** One read-only review per area of the
whole framework, not just the diff, for wrong behaviour, unhandled states and
fragile code: (1) fields and inputs, (2) lists, tables, trees and their
models, (3) dialogs, popups, navigation, window and chrome, (4) the C++
singletons and services (Appearance, settings, shortcuts, clipboard,
validators, formatting), (5) the Rust crates, (6) tools, CI and packaging.
Findings become units below (B1 onwards); the security and performance ones
wait for their phase.

**F, Functional.** Every B and A item below done and shown working: a test
for each fix that failed before it, a demo and goldens (looked at) for each
new member or visible change, the `api/` line and the reference page. Every
state handled: empty, loading, error, huge (10k rows, 200 sidebar entries,
very long text), first run, RTL, text at 200 %, compact, high contrast,
reduced motion. `tools/dev-check.sh` clean, the gallery walked headless with
no warnings, and the apps CI job building Updater, Installer, Monitor and
Notepad against it.

**S, Secure.** One security review over everything that takes outside input:
files and drops (AtlasDropZone, file and folder fields, path and URL
validators), clipboard, settings files and `atlasrc`, D-Bus (global menu,
window chrome, notifications), the crates' polkit, Flatpak and crash-report
paths, the packaging and the CI workflows (tokens, `pull_request_target`,
pinned actions). Done when every item in "S gate" below is fixed or closed
with a reason, and the review of the fixes comes back clean.

**R, Reliable.** One reliability review over the whole module: every error
shown in plain words, no warnings or TypeErrors in normal use (a test fails
on any QML warning during the visual and state runs), no leaked connections,
timers or popups when items are created and destroyed many times, settings
written atomically and surviving a crash or a full disk, D-Bus and file calls
that can't hang the GUI thread (AtlasPathValidator, settings lock), and
everything working after a restart and with an older `atlasrc`.

**P, Performant.** Measured with `perf/measure.sh` against `perf/budget.json`
(startup 190 ms, RSS 129.2 MB, PSS 114.8 MB, idle CPU 1 %): no figure worse
than 1.4.0. Plus: `libatlasui.so` smaller (28 MB in Release; try hidden
visibility), list and table scrolling at 10k rows without dropped frames,
the new floating toolbar and popover idle at zero CPU, and qmllint warnings
at or below 162.

### B0: bugs the apps hit on 1.4.0

- [x] AtlasSidebar: `priv.watch()` connects the bare `updateTarget` to
  `selectedChanged` and `visibleChanged`, so it runs without scope: "TypeError:
  Property 'findSelected' of object [null] is not a function" at every Atlas
  Monitor start, and the highlight doesn't follow when the selected entry is
  hidden. (Monitor)
- [x] AtlasSidebar: the scroll bar shows in compact (icons-only) mode and takes
  about 14 px of a 64 px sidebar; it is the stock bar, not AtlasScrollBar. A
  focused entry's ring may be clipped next to it. (Monitor)
- [x] SidebarItem: the compact tooltip leaves out `badgeText`. (Monitor)
- [x] AtlasDialog focus on open: reported by Monitor, then withdrawn (1.4.0
  already kept the focus out of the header). Tightened anyway: a footer button
  no longer counts as the body either, and tests cover a labels-only body.
- [x] ToolbarButton: its tooltip stays up while the menu it opened is open.
  (Monitor)
- [x] ConfirmDialog: `destructive` drew the accept button violet since the
  1.4.0 restyle; it uses the Destructive look again (fixed on main, 7dc2806).
- [x] TabBar: with more tabs than fit, the strip kept its content width, ran
  past the bar (hiding "+") and never scrolled; a tab made current after it
  was added stayed out of view. (Notepad; since 1.3.0)
- [x] AtlasTreeModel: `node()` checks the index (this model, column 0, a live
  node) before following `internalPointer`; foreign and stale indexes answer
  empty. The reference page says "small trees".
- [x] AtlasShortcuts::toSequence: numbers are range-checked (NaN, infinity and
  values outside int are no key); `conflicts()` was already a pure getter
  (cached by `recompute()`), now covered by a test.
- [x] Appearance.textScale: kept between 0.5 and 4; non-finite is the default.

### A1: new API the apps asked for (sketch in docs/api-1.5.0.md first)

- AtlasPopover: open beside the target too (`side`: below, above, start, end)
  with a matching arrow. (Notepad's code popover beside its vertical capsule)
- AtlasHeaderBar: a stretch slot for a full-width row such as a TabBar;
  `leading` and `trailing` are capped at half the bar each. (Notepad)
- AtlasDialog: expose the scrolling Flickable, or `scrollToTop()`. (Monitor)
- AtlasPage: a `subtitle` under the title. (Monitor)
- AtlasSidebar: a footer pinned to the bottom (Settings, About) that shares
  compact mode, focus order and selection with the entries. (Monitor)
- ToolbarButton: a round variant, a tooltip side (start/end as well as
  below), and its own tooltip text (multi-key shortcuts). (Notepad)
- AtlasFloatingToolbar, so it can replace Notepad's ToolCapsule: vertical
  `orientation`; a dimmed level (0.35 until the pointer is within 80 px, full
  while a menu or popover is open or a button has focus); wheel scrolling with
  chevrons as an alternative to the "more" menu; Esc back to the content, a
  menu returning focus to its button, Tab-follows-focus scrolling, and a
  Tab-only focus policy (a click never takes focus); menu and popover buttons
  in the strip, not only a flat actions list. (Notepad)
- AtlasAppMenu, so it can replace Notepad's GlobalMenu and FallbackMenu:
  nested submenus, model-driven entries (Open Recent bound to a list, with a
  lead item), shortcuts shown in the global-menu export, and tall groups that
  don't hit the ContextMenu height cap. (Notepad)

- AtlasFormat.bytes: an SI (decimal) option, "1.2 GB". (Updater)
- AtlasFormat.date: a long "date at time" style ("Thursday, 1 January 2099
  at 03:00") and a sentence-start relative form ("Today at 9:41"). (Updater)
- AtlasTimePicker: an arrow step separate from the allowed values (typed 07
  is snapped to 05 today, without a word), and a minimum time. (Updater)
- ConfirmDialog: `width`/`maximumWidth` instead of the fixed 25 grid units.
  (Updater)
- AtlasCopyButton: a text mode ("Copy Details", then "Copied"). (Updater)
- AtlasSidebar footer: also asked for by Updater (Settings, Crash Reports,
  About).
- AtlasWindow: tunable `widthClass` thresholds (Updater folds at 38 units).
- InfoBanner: `shown` stays bound; the close button sets an internal
  `dismissed` flag that a new `text` resets. (Updater)
- AtlasAboutPage: hide the OS and Qt rows, override the links, a footer.
  (Updater)
- AtlasDetailGrid: a title and a footer, so it can replace a Section of
  label/value rows. (Updater)
- A page-level busy row (spinner and label); SectionRow `busy` covers rows
  only. (Updater)
- SidebarGroup: `symbol` and `badge` like SidebarItem. (study 3)
- AtlasBreadcrumb: the "Hidden folders" text as a property. (study 3)

### B1: bugs other apps reported

- [ ] AtlasCodeView: the horizontal scroll bar covers the last line, and as
  the content "fits" there is no vertical scroll to reach it (also at the end
  of a scroll capped by maximumHeight); it uses QQC2.ScrollBar, not
  AtlasScrollBar. Also an inset option to line up with SectionRow text.
  (Updater)
- [ ] DESIGN.md calls AtlasButton TextButton's base with `variant`; TextButton
  is a T.AbstractButton without it (setting it fails to load). Fix the docs,
  or give TextButton `variant` (Ghost link buttons). (Updater)
- [ ] AtlasSettings: FileLock can msleep the GUI thread up to 1 s per flush
  while another process holds the lock, and AtlasWindow.stateKey flushes on
  resize. (Updater)

### B2: study findings (F and R), whole framework

Studies 1-3 (fields and buttons; lists and data; dialogs, popups and the
window) read every file at 413cfb2; studies 5 (crates) and 6 (tools, CI,
packaging, template) at 930c8ae. Study 4 (C++ services) is running. Items marked "verify" come from reading only: reproduce
first. Fix in batches by file; every fix gets a test that fails before it.

#### Fields and buttons

- [ ] High: AtlasColorField:194-200, AtlasFontPicker:189, AtlasDatePicker:183
  call `Item.contains(item)` (it takes a point): a TypeError on close, and the
  focus doesn't return to the field.
- [ ] Return/Enter call `clicked()` not `click()` in AtlasButton, TextButton,
  AtlasChip and AtlasInstallButton: an `action` isn't triggered and a
  checkable button doesn't toggle.
- [ ] AtlasSplitButton: no Return/Enter on its parts, though the header says
  so (verify).
- [ ] Internal assignments break app bindings after the first edit: AtlasRating,
  AtlasSegmentedControl, AtlasCalendar, AtlasComboBox (filterable),
  AtlasColorField, AtlasDatePicker, AtlasFontPicker, AtlasFileField,
  AtlasFolderField; also FindBar's three toggles, AtlasSidebar's filter
  (`visible`), InfoBanner (B1 above). One rule for all.
- [ ] AtlasChipGroup: the roving Tab stop isn't moved when its chip is hidden
  or disabled, so the group can't be reached.
- [ ] AtlasAutocompleteField: the clear button leaves the popup open with
  stale suggestions; `mark()` offsets after toLowerCase; rowsMoved; forceAll
  stays on.
- [ ] AtlasInstallButton: NaN progress shows "NaN%".
- [ ] AtlasDropZone: a Browse click may emit `browseRequested` twice (verify);
  glob `?`/`*` don't match a newline.
- [ ] AtlasComboBox: filtering hides delegates instead of filtering the model
  (10k rows are all built); null entries or a missing textRole throw.
- [ ] AtlasSpinBox has no validator; SearchField's `query` lags on Return and
  its clear button works on a read-only field; AtlasShortcutField can't record
  Ctrl+Delete, Shift+Delete, Ctrl+Escape; AtlasSegmentedControl with a
  ListModel or number, and a click doesn't focus it; AtlasFontPicker reads the
  families once and shows "-1 pt" for pixel fonts; AtlasUrlValidator refuses
  "example.com" silently; AtlasColorField alpha 0.999 and duplicate swatches;
  AtlasChip and AtlasButton have no elide or maximum width; menus of
  AtlasSplitButton and MenuButton don't flip in RTL; AtlasSwitch's indicator in
  a wide RTL switch; AtlasRating's count text replace; AtlasFileField's
  folder symbol, silent dialog failure, no validator hook. (Low)

#### Lists, tables and data

- [ ] StatusHero: the ring keeps the busy spinner's angle when progress
  starts, so the arc starts at a random angle.
- [ ] AtlasTreeView: `anchorRow` is a row number, so expanding a row moves
  the Shift-click anchor to another item.
- [ ] DataTable: sorting, column resize and the columns menu are mouse-only.
- [ ] DataTable: Down on an empty multi-select table selects row 0 for later.
- [ ] DataTable: a shorter `columns` array throws in header, cell and menu
  bindings before the Repeater shrinks.
- [ ] AtlasFlowLayout: a child with only an explicit `width` gets width 0;
  `_busy` without try/finally stops all later layouts after one throw.
- [ ] AtlasTreeView and AtlasIconGrid: no focus ring after a mouse click then
  arrow keys (AtlasListView's `_mouseFocus` fix).
- [ ] Low: AtlasSearchResults swallows Enter with no results; AtlasProgressBar
  NaN and >1, and its indeterminate slide in RTL; UsageBar NaN parts;
  AtlasScreenshotCarousel `currentIndex` out of range; AtlasAppCard rating not
  localised or clamped; AtlasCard press action when not clickable;
  AtlasListView selection on a mode change, `_hover`/`_dragFrom` on a model
  reset, hover after scrolling (also AtlasTreeView); a `symbol` role holding a
  name gives NaN (four views); AtlasIconGrid's Menu-key popup in RTL;
  DataTable's Delete accepted with no handler; AtlasStat and LiveChart labels
  don't elide; AtlasDetailGrid values not reachable by keyboard and copy
  replaces the selection; Symbol throws for a codepoint out of range;
  `Symbols::codepoint` warns on every call; AtlasTreeModel drops bad entries
  without a word; LiveChart NaN setters repaint; a lone sparkline sample is
  twice the line width; AtlasTreeView's column width on resize (verify).

#### Dialogs, popups, menus and the window

- [ ] ContextMenuItem shows "&Save" for an action's mnemonic text (also its
  accessible name).
- [ ] AtlasNavigationStack: the RTL Back arrow flips around the stack's
  middle, not the button's (verify).
- [ ] AtlasBreadcrumb: `Accessible.announce` on a QtObject (verify); the
  chevron and "…" use absolute x in RTL (verify).
- [ ] ContextMenu's width doesn't follow its items' widths, so long labels
  elide (verify).
- [ ] AtlasPopover isn't re-placed on a window resize or a target move, and
  opens at 0,0 with no target.
- [ ] AtlasDialog's body doesn't scroll to the focused field.
- [ ] FindBar: Enter in the replace field with no matches.
- [ ] Low: high contrast leaves selection, hover and pressed faint;
  StatusBarItem not keyboard reachable; SectionRow's press action when
  disabled; AtlasEdgeGlow's gradient in RTL (verify); AtlasShortcutsDialog's
  section "constructor"; AtlasToolTip with empty text, and no flip below;
  AtlasAppMenu's native items (shortcut, icon, checked binding) and teardown;
  AtlasToolbar's text-only actions; AtlasWindowButtons draws an unknown name
  as Maximize; AtlasWindow overrides app `flags`; AtlasHeaderBar's fixed 32 px
  at 200 % text and Maximize on a fixed-size window; AtlasAboutPage's links
  section with only `issuesUrl`; Section's Return auto-repeat; stock
  QQC2.ToolTip in ToolbarButton, StatusBarItem, TabBar, InfoBanner and stock
  ScrollBar in ConfirmDialog, AtlasShortcutsDialog; InfoBanner reads
  `icon.name` of a non-Action; ConfirmDialog's accessible text; negative
  dialog width in a tiny window; Toast `show(undefined)`; AtlasPage's scroll
  bar in RTL; AtlasPortal stale notification ids after a server restart;
  AtlasWindowChrome reads kwinrc on the GUI thread.

#### Crates (study 5)

crash.rs has uncommitted work from another session: its items wait until
that lands, then go in one batch.

- [ ] crash.rs: the 5-an-hour limit is per process and `pending/` has no cap
  (a restart loop queues 5 per launch); dedupe by crash key, an on-disk hour
  counter, cap about 50 files.
- [ ] crash.rs: no length cap on `message` (a 50 MB panic payload allocates
  about 1 GB in the hook); `github_issue_url` never shortens `head` past 7 KB.
- [ ] crash.rs: `journalctl` and `rpm -qf` (waits on the rpmdb lock during an
  update, up to 500 times) have no timeout; document that `collect_*` block.
- [ ] crash.rs: reports and markers are written in place (no temp, fsync,
  rename): a crash leaves a truncated report that stays invisible, or an empty
  coredump marker that skips every crash since. Quarantine unparsable files.
- [ ] crash.rs Low: `--noproxy "*"`; two senders of one report file two
  issues; `ram_total_kb * 1024` overflow; the "prunes the sent history"
  comment; the C++ `alarm(10)` turns a hung save into SIGALRM (no core).
- [x] flatpak: one failing installation (an unmounted extra one) fails all of
  `list_updates`; failed remote refreshes are dropped without a log line.
- [x] flatpak: no Cancellable or deadline on any libflatpak call; a stalled
  remote blocks the worker for good (add `*_with` variants).
- [x] flatpak: `fetch_remote_size_sync` runs even with `refresh=false`
  (network, serial, errors become size 0), contrary to updates.md (verify).
- [x] atlas_app_init isn't idempotent: a second call installs the message
  handler as its own previous one, and the first qDebug recurses to a stack
  overflow. showUiError's loop never ends if the window never shows.
- [x] settings.rs and events.rs: `flock` waits forever while holding the
  process-wide WRITERS mutex (a stopped holder or a hung NFS home freezes every
  `Settings::set`); use a deadline.
- [x] Low: events `event`/`version` unbounded, `eprintln!` instead of `log`;
  history `append_if_new` without a lock; unbounded `read_to_string` (a FIFO
  blocks, non-UTF-8 makes a key unwritable); temp files never swept; polkit
  interactive check without a cancellation id or timeout; bootc required
  `image` fields and `utc_second` digits; notify's shipped-file Popup
  fallback isn't read (and is blocking I/O in an async fn).

#### Tools, CI, packaging and the template (study 6)

- [x] High: check-api.sh fails every commit that changes `api/` while the
  version is still 1.4.0: raise the in-tree version to 1.5.0 with the first
  API commit (CMake, Cargo, Cargo.lock, spec).
- [x] apidump records no base type: changing a root from T.AbstractButton to
  Item removes `clicked`, `text` and more, and the check still passes.
- [ ] No RPM build in CI or release.yml, so `%check` and the file lists only
  run by hand; translations would break the RPM build (no LinguistTools
  BuildRequires, `.qm` files owned by no `%files`).
- [x] On a tag push the semver baseline and check-api's "since the last tag"
  diff are the commit itself (vacuous); release.yml accepts the tag run alone.
- [x] dev-check: no `--init`/`--name` (Ctrl-C may leave ninja and ctest
  running), two runs in one checkout share a build dir, a mistyped demo name
  may test nothing.
- [x] perf/measure.sh: measures an already installed qmldir instead of the
  build; a missing budget file or key passes; unreadable schedstat gives 0 %
  CPU; the CI perf job measures a dev-paths build.
- [x] lint-app.sh false passes: a trailing comment on an import, the
  `QtQuick.Controls.Basic`/Material/... imports, `build*` pruning, zero QML
  files exits 0, no error-path test.
- [x] Low: CI swallows lint exit 2 and never lints the gallery or template,
  no qmllint warning gate; cache keys end in the sha (churn, evictions), one
  buildx scope for three jobs, push plus pull_request runs; no
  `cargo --locked` or Cargo.lock version check; build-rpm.sh tars the working
  tree (untracked files, dirty tree) and exits 0 with no RPM; release.yml's
  rc tags and tag ordering; perf/README's 5 s and 0.5 figures; dev-check
  hides details (lint file:line, visual-out path), treats a relative build
  dir as a volume, runs no crates; open-update-pr.sh misses a failed
  ls-tree; app-checks.yml can't fetch a short sha.
- [x] Template (every new app copies it): README says pin to a commit, the
  Cargo.toml a tag; MainPage's timer runs while hidden; a worker panic leaves
  `busy` stuck; the notifyrc icon doesn't exist; main.cpp redeclares
  `atlas_app_run` instead of including atlas/app.h; no CI workflow; StackView
  with no Esc or reduced motion (AtlasNavigationStack exists).

### S-phase notes (from the studies; handled in the S pass)

- crash.rs: a coredump's `app_name` is the full exe path, not redacted
  (`/mnt/clients/acme/...` reaches the public issue); scrub gaps
  (`--password x`, single name parts, a deny-list of private prefixes, Event
  scrubbed for hosts only); markers not reset when reporting is turned on by
  hand; `discard()` deletes any `Report.path`.
- Unpinned `fedora:44` base image; no dependabot for the pinned action SHAs;
  app-checks.yml tracks main by default.

- AtlasPortal: reject userinfo (`https://good@evil`); file type sniffing and
  canonicalFilePath on the GUI thread; notification markup is the caller's
  duty (document). AtlasAboutPage uses Qt.openUrlExternally, not AtlasPortal.
- NotesText: RichText loads `<img>` itself, remote URLs included; strip it.
- AtlasAvatar: any URL, no timeout or size cap (copy the carousel's
  `vetted()`).
- AtlasCopyButton: no sensitive hint or auto-clear; AtlasPathValidator's "~".

### P-phase notes (from the studies; measured in the P pass)

- AtlasTreeView `selectRange` on a non-AtlasTreeModel: one select per row,
  quadratic on 10k rows. AtlasCodeView's line numbers on a 100k-line log.
- AtlasComboBox filtering (above); AtlasListView and AtlasTreeView type-ahead
  scans; DataTable's RepaintArea content on GPU backends; Symbol's
  `variableAxes` per row and `Symbols::names()`.
- TabBar builds every tab (cacheBuffer) so it scrolls by real widths: measure
  restoring 300+ tabs.
- AtlasEdgeGlow repaints every frame while active (160 Hz); AtlasStyle's
  hidden probe Window at startup; AtlasSidebar `entries()` per drag move;
  AtlasToolbar fit O(n²); AtlasInstallButton's hidden shimmer; AtlasChipGroup
  and AtlasFontPicker per-instance work.

### Release

- [ ] `APP_UPDATE_TOKEN` is not set in the "release" environment, so the
  v1.4.0 Release run opened no app PRs. The user adds the secret.

### Follow-ups from the 1.4.0 gates

Non-blocking findings (Medium and Low) filed while shipping 1.4.0.

#### S gate (C++ and file/drop QML)
- AtlasDropZone: compile nameFilters once per change, cap URLs examined (~10k), collapse repeated `*` (backtracking); say in docs that folders named *.png pass.
- AtlasFileField/AtlasFolderField toUrl/fromUrl: reject control chars and lone surrogates; require file:/// in fromUrl; show an error when decode fails.
- AtlasPathValidator.mustExist: stat on every keystroke can hang on a stale NFS/FUSE mount; check on commit or debounce; docs: not a containment check.
- AtlasUrlValidator: consider rejecting userinfo (https://good@evil); docs: apps must check acceptableInput.

#### Earlier
- AtlasSearchResults is allow-listed in tests/state.
- AtlasShortcutField.conflictText doesn't refresh when another action's shortcut changes.
- AtlasExpandableSection sets `expanded` itself (breaks a binding on it); consider Section's ask-the-page pattern.

#### Look
- Stock Qt Quick/Kirigami controls used directly by apps still take Breeze's highlight: set Kirigami.Theme highlight/focus from AtlasStyle at the AtlasWindow root.

#### R gate, data controls
- AtlasListView: drag-reorder auto-scroll in long lists.
- AtlasCodeView: wrapped lines vs line numbers over 5000 lines.
- Selection API shapes: contextMenuRequested signatures differ (ListView/Tree point vs DataTable x,y); textRole default "text" vs "display".
#### S gate 2
- Settings: GUI-thread flock wait (now 1 s); consider a worker thread.
- Settings symlink policy differs from Rust (documented).
- AtlasSettings: new files briefly exist with default mode before fchmod 0600 (KConfig save); create with umask 077 around sync.

#### From chrome/popups review (Low)
- AtlasWindow._saveState: maximize geometry may be saved as Windowed size if geometry arrives before visibility; debounce.
- Alt+Space registered per AtlasHeaderBar: ambiguous with two headers in a window.
- AtlasWindowButtons focusPolicy NoFocus: keyboard only via Alt+Space (a11y audit note).
- AtlasPopover arrow seam at alpha 0.85 (arrow overlaps card 1px).
- ConfirmDialog body now in a Flickable: fillHeight bodies behave differently.
#### From f5-3
- Variant goldens exactly 700 high (AtlasEmptyState, AtlasTextArea, AtlasTextField, AtlasValidators) and AtlasCalendar 900 wide in the new variants: demos clip under text200/compact.

#### From F2/F3 review (Low, not in fix-pickers)
- ShortcutField Shift+digit records shifted key; Calendar `today` stale after midnight; TimePicker use24Hour detection with bare "a"; TimePicker edited on snapped-same value
- Sidebar empty-filter placeholder never shows; filter-expanded groups never collapse; SegmentedControl pill Behavior animates on resize/first show; no elide
- ChipGroup overwrites app focusPolicy, _restoreFocus when window inactive; FlowLayout mirroring toggle relayout, stale child connections
- NavigationStack popToRoot per-page signals, Alt+Left not mirrored, no focus after push/pop; SplitView handle not keyboard reachable
- SplitButton halves scale separately; File/FolderField drop non-file URL silently; Onboarding accessible name not overridable; ColorField applies #abc mid-typing
- FontPicker fixedOnly model reset during scan
- AtlasAutocompleteField: no textEdited/editingFinished/validator/maximumLength/inputMethodHints forwarding (additive)
#### From F1 review (Low)
- AtlasPathValidator mustExist stats on GUI thread per keystroke (documented in fix-input)
- ToolbarButton checked icon accent, SectionRow disabled 0.5 opacity: compat notes

#### From gallery ui-check
- "QQmlVMEMetaObject: Internal error - attempted to evaluate a function in an invalid context" x3 per gallery walk, page unknown (probably on page switch)
- AtlasAvatar demo's deliberate missing image prints a QQuickImage warning
- Window buttons vs real KWin unchecked (needs a WM)

#### P (from the 1.4.0 gate)
- libatlasui.so is 28 MB in Release (43 MB with no build type): .dynstr/.dynsym hold every qmlcachegen AOT symbol. Try -fvisibility=hidden / a version script exporting only the plugin entry points; measure PSS (Release 1.4.0: ~110 MB vs 114.8 budget, startup 174-193 ms vs 190).
- perf/measure.sh: first start in a run is cold and noisy (170 ms to 3 s); the median of 3 hides it. Consider 5 starts after one warm-up.
- qmllint 162 warnings (baseline 161).

#### From the reference docs
- apidump leaves out a signal that is also a NOTIFY signal (AtlasClipboard.changed()): it is public and documented; include it in api/.
- AtlasSparklineItem.color defaults to Breeze blue #3daee9 (ui/atlassparkline.h:78); AtlasSparkline sets AtlasStyle.accent, but the C++ base used directly is blue.
- Public members that look like internal helpers (permanent API now, documented plainly): AtlasButton.accent/textTint, AtlasChip.tint/showsCheck, AtlasAppCard.defaultAction, AtlasShortcuts.add/remove, AtlasPage.ensureVisible, AtlasSidebar.win, AtlasSplitButton.mirrored.
