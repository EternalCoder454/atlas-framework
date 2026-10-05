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
The work runs as for 1.4.0 (above): bug batches first, since they change no
API, while the new API is sketched in `docs/api-1.5.0.md` and reviewed once.
Every new member gets its line on its docs/reference page in the same commit
(`tools/docs.py check` fails otherwise). Versions are bumped at release.

### B0: bugs the apps hit on 1.4.0

- [ ] AtlasSidebar: `priv.watch()` connects the bare `updateTarget` to
  `selectedChanged` and `visibleChanged`, so it runs without scope: "TypeError:
  Property 'findSelected' of object [null] is not a function" at every Atlas
  Monitor start, and the highlight doesn't follow when the selected entry is
  hidden. (Monitor)
- [ ] AtlasSidebar: the scroll bar shows in compact (icons-only) mode and takes
  about 14 px of a 64 px sidebar; it is the stock bar, not AtlasScrollBar. A
  focused entry's ring may be clipped next to it. (Monitor)
- [ ] SidebarItem: the compact tooltip leaves out `badgeText`. (Monitor)
- [x] AtlasDialog: with nothing focusable in the body, `onOpened` focus wraps
  to the header's Back or Close, so Return right after opening closes the
  dialog. Focus only an item inside the body, else the dialog. (Monitor)
- [x] ToolbarButton: its tooltip stays up while the menu it opened is open.
  (Monitor)
- [x] ConfirmDialog: `destructive` drew the accept button violet since the
  1.4.0 restyle; it uses the Destructive look again (fixed on main, 7dc2806).

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

### Release

- [ ] `APP_UPDATE_TOKEN` is not set in the "release" environment, so the
  v1.4.0 Release run opened no app PRs. The user adds the secret.

### Follow-ups from the 1.4.0 gates

Non-blocking findings (Medium and Low) filed while shipping 1.4.0.

#### S gate (C++ and file/drop QML)
- AtlasTreeModel: node() trusts internalPointer; add checkIndex()/model()==this. Document "small trees" (no node cap, items kept twice).
- AtlasDropZone: compile nameFilters once per change, cap URLs examined (~10k), collapse repeated `*` (backtracking); say in docs that folders named *.png pass.
- AtlasFileField/AtlasFolderField toUrl/fromUrl: reject control chars and lone surrogates; require file:/// in fromUrl; show an error when decode fails.
- AtlasPathValidator.mustExist: stat on every keystroke can hang on a stale NFS/FUSE mount; check on commit or debounce; docs: not a containment check.
- AtlasUrlValidator: consider rejecting userinfo (https://good@evil); docs: apps must check acceptableInput.
- AtlasShortcuts::toSequence: range-check StandardKey ints, isfinite on doubles; conflicts() recomputes and emits from the getter.
- Appearance.textScale: clamp to 0.5..4.

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
