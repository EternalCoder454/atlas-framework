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
- [ ] Section's fold header toggles on Return and Enter, not only Space
- [ ] LiveChart.setValues/setValues2 skip the repaint when nothing changed
- [ ] AtlasSwitch reports the Switch accessible role

### F1: foundations

- [ ] `AtlasStyle` singleton: colours by role (accent, surface, text, success,
      warning, error; from Kirigami.Theme), spacing, radii (today 6, 8 and 10
      are hard-coded), font sizes, durations; controls read it
- [ ] `Appearance` gains the system's colour scheme, high contrast, reduced
      motion and text scale (one place for system preferences)
- [ ] Global density: `AtlasStyle.density` (normal, compact) read by TabBar,
      StatusBar, SectionRow and the rows of lists; one reduced-motion flag
      every animation reads
- [ ] `AtlasLabel { textStyle: Title | Heading | Body | Caption | Mono }`
      (replaces the planned AtlasHeading and AtlasCaption)
- [ ] `AtlasAction` on Qt's `Action`: text, symbol, shortcut, enabled,
      checkable, toolTip. ToolbarButton, ContextMenuItem, MenuButton,
      AtlasFloatingToolbar and AtlasCommandPalette take one; an icon-only
      button gets its tooltip from the action's text
- [ ] Shortcut registry (collects actions' shortcuts, warns on conflicts),
      `AtlasShortcutsDialog`, `AtlasShortcutLabel`
- [ ] Slots: SectionRow `leading`, `trailing` (any control) and `content`;
      `SectionRow.busy` (replaces the planned AtlasBusyRow); AtlasPage
      `headerTrailing` and writable `maxContentWidth`
- [ ] The state contract in DESIGN.md (enabled, readOnly, error, busy,
      hover, pressed, focus) and a test that walks every demo for it
- [ ] Changes to existing types: ToolbarButton `symbol`, checkable style,
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

- [ ] `AtlasValidators` (C++ validators): url(schemes), email, path, number;
      replaces the planned AtlasUrlField
- [ ] `AtlasDoubleSpinBox` on Qt 6.11's DoubleSpinBox (decimals); with
      `AtlasSpinBox.showButtons: false` it replaces the planned AtlasNumberField
- [ ] `AtlasSegmentedControl`
- [ ] `AtlasTimePicker` (minuteStep, optional day, 12/24 h from the locale)
- [ ] `AtlasDatePicker` and `AtlasCalendar`
- [ ] `AtlasColorField`, `AtlasFileField`, `AtlasFolderField` (the file
      chooser portal through QtQuick.Dialogs)
- [ ] `AtlasShortcutField` (records a key combination)
- [ ] `AtlasSplitButton`
- [ ] `AtlasChip`, `AtlasChipGroup`
- [ ] `AtlasAutocompleteField`
- [ ] `AtlasFontPicker`

### F3: surfaces, layout and navigation

- [ ] `AtlasSidebar`: scrolls the focused item into view
      (`positionViewAtChild`), filtering, an empty placeholder, item context
      menus, drop targets, focus lands on the selected row
- [ ] Width classes on AtlasWindow (compact, medium, wide); sidebars collapse
      the same way everywhere
- [ ] `AtlasSplitView` (remembers its sizes), `AtlasNavigationStack`
      (push, pop, Back), `AtlasViewSwitcher` (page tabs)
- [ ] `AtlasToolbar` (overflows into a "more" menu), `AtlasFloatingToolbar`
      (Notepad's ToolCapsule), `AtlasFlowLayout`
- [ ] `AtlasPopover`, `AtlasScrollBar`, `AtlasDialog` (title, Back and Close,
      scrolling body, slots), `AtlasCard` (padded body, slots),
      `AtlasExpandableSection`
- [ ] `AtlasDropZone`, an onboarding scaffold on StepItem (Back, Next, Skip)

### F4: lists and display

- [ ] `AtlasTreeView`
- [ ] `AtlasListView` (single and multi-select, type-ahead, context menu,
      drag to reorder)
- [ ] DataTable: column resize, show and hide columns, multi-select, row
      context menu, sticky header
- [ ] `AtlasStat` (value, label, unit, trend; replaces AtlasBigStat),
      `AtlasDetailGrid`, `AtlasSparkline` (C++; NaN gaps, auto-scale with a
      minimum, no repaint when equal)
- [ ] `AtlasAvatar`, `AtlasRating`, `AtlasBadge`
- [ ] `AtlasCodeView` (read-only monospace, framed or not, max height,
      optional copy), `AtlasCopyButton`
- [ ] `AtlasCommandPalette` (AtlasSearchResults fed by AtlasAction)

### F5: services, checks and lint

- [ ] `AtlasFormat`: bytes, percentages, durations, numbers and dates (long,
      short, date-time, at a time, relative); Atlas.Ui owns the strings
- [ ] `AtlasClipboard`: text, rich text and images
- [ ] `AtlasSettings` in QML on the existing settings file: typed values with
      defaults; restores window size, sidebar width and split sizes
- [ ] Portal helpers: open a URL; notification actions from QML (the crate
      has them); a second launch raises the running window (check what the
      single-instance name already does)
- [ ] Visual test variants: high contrast, right-to-left, compact, 200% text
- [ ] a11y: a tab-order test per demo
- [ ] Deprecation rule in DESIGN.md (one more minor version, with a
      lint-app.sh warning)
- [ ] lint-app.sh: Kirigami.PlaceholderMessage, a hand-made tinted banner,
      QQC2.ToolTip, Kirigami.Heading (use AtlasLabel)

Dropped: AtlasCoreGrid (AtlasCard and MiniBars cover it), AtlasHeading,
AtlasCaption, AtlasBusyRow, AtlasNumberField, AtlasUrlField, AtlasBigStat.
