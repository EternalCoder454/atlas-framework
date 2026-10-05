---
title: Atlas.Ui
summary: The QML module every Atlas app imports, with windows, pages, buttons, fields, lists, dialogs, charts and the style and services behind them; how to install it, check it and find a type.
order: 1
---

Atlas.Ui is the QML module of Atlas controls. Every Atlas app imports it, so they all share one look, one set of keyboard and accessibility rules and one copy on disk. It is a QML module installed next to Qt's own, like Kirigami. Its URI is `Atlas.Ui`.

## Install and import

Install the `atlas-ui` package (Fedora 44, Qt 6.11). It brings in the Material Symbols fonts (`atlas-symbols-fonts`), Kirigami, IBM Plex Sans and JetBrains Mono.

```sh
sudo dnf install atlas-ui
```

The module lives in Qt's QML directory (`/usr/lib64/qt6/qml/Atlas/Ui/`). An app writes `import Atlas.Ui` in QML and links nothing: the QML engine loads the plugin. There is no CMake package and no devel package.

```qml
import QtQuick
import Atlas.Ui

AtlasWindow {
    title: qsTr("Hello")
    visible: true

    AtlasPage {
        anchors.fill: parent
        title: qsTr("Hello")

        PrimaryButton {
            text: qsTr("Say hello")
            symbol: Symbols.WavingHand
        }
    }
}
```

> [!NOTE]
> `import Atlas.Ui` wins over the QML files in an app's own directory. An app file named like an Atlas.Ui type (say `SearchField.qml`) is hidden by it. New Atlas.Ui types are named `Atlas<Name>` to keep clear of apps' names; see [Compatibility](compatibility.md).

## Check the module at configure time

The [app template](../template/index.md) fails the CMake configure with a plain message when the module is missing. qmlcachegen and qmllint find it in Qt's QML directory by themselves, so the app's `<app>_qmllint` target checks the app's QML against it.

```cmake
if(NOT EXISTS "${QT6_INSTALL_PREFIX}/${QT6_INSTALL_QML}/Atlas/Ui/qmldir")
    message(FATAL_ERROR "Atlas.Ui is not installed: dnf install atlas-ui")
endif()
```

## Version rule

Atlas.Ui only ever adds API. An app that uses something added after 1.0.0 states the oldest version it works with in two places, and keeps them equal:

- `Requires: atlas-ui >= X.Y.Z` (and `BuildRequires`) in the app's RPM spec, so dnf installs a new enough one;
- `ui: "X.Y.Z"` in the app's `app!` call, so at startup an older Atlas.Ui, installed some other way, gives a plain error window instead of a broken one.

`AtlasApp.uiVersion` reports the installed version at run time. Each page says which version added its type (`since`).

## Guides

- [Design rules](design-rules.md): what every Atlas app does.
- [Style and theming](style-and-theming.md): colours, spacing, radii, density, blur and text scale.
- [Motion](motion.md): springs, reduced motion and the violet to sakura gradient.
- [Compatibility](compatibility.md): the API contract and what it means for an app.
- [Accessibility](accessibility.md): focus, roles, names, right-to-left and the framework's tests.

## The types

Every type has a page. The groups below are the sidebar sections.

### Windows and pages

- [AtlasWindow](atlas-window.md): The application window: blurred or opaque by the shared switch, remembers its size, and goes frameless with a header bar.
- [AtlasHeaderBar](atlas-header-bar.md): The merged header of a frameless window: window menu, title, tools and window buttons.
- [AtlasWindowButtons](atlas-window-buttons.md): Minimise, maximise and close buttons drawn like the AtlasOS window decoration.
- [AtlasWindowChrome](atlas-window-chrome.md): Singleton with the desktop's caption-button layout and whether a global menu exists.
- [AtlasPage](atlas-page.md): A scrolling page with a large bold title and centred margins.
- [AtlasAboutPage](atlas-about-page.md): A ready-made About page for any app.
- [AtlasOnboarding](atlas-onboarding.md): A setup scaffold: steps, one page at a time, Back, Skip and Next.
- [StatusBar](status-bar.md): A slim bottom bar of cells such as line, column and encoding.
- [StatusBarItem](status-bar-item.md): One cell of a status bar, optionally clickable or with a menu.

### Buttons

- [AtlasButton](atlas-button.md): The shared base of the buttons, with four variants and a busy state.
- [PrimaryButton](primary-button.md): The filled accent button for the main action.
- [SecondaryButton](secondary-button.md): The soft, tinted button for ordinary actions.
- [TextButton](text-button.md): A button that looks like a link.
- [MenuButton](menu-button.md): A button that opens a menu.
- [ToolbarButton](toolbar-button.md): A small icon button for toolbars that never takes the editor's focus.
- [AtlasSplitButton](atlas-split-button.md): A main button joined to an arrow that opens a menu of variants.
- [AtlasInstallButton](atlas-install-button.md): An install button with progress inside it and states for install, update, open and retry.
- [AtlasCopyButton](atlas-copy-button.md): An icon button that copies text and shows a check mark.
- [AtlasSwitch](atlas-switch.md): A round switch.
- [AtlasCheckBox](atlas-check-box.md): A check box with an optional partly-checked state.
- [AtlasRadioButton](atlas-radio-button.md): A radio button; siblings form a group.
- [AtlasSegmentedControl](atlas-segmented-control.md): Joined segments with one selected.
- [AtlasChip](atlas-chip.md): A small chip for a tag, filter or value.
- [AtlasChipGroup](atlas-chip-group.md): A wrapping group of chips, optionally one-of.

### Fields and pickers

- [AtlasTextField](atlas-text-field.md): A single-line text field with error, clear button, prefix, suffix and counter.
- [AtlasTextArea](atlas-text-area.md): A multi-line text field.
- [AtlasPasswordField](atlas-password-field.md): A password field with a show toggle.
- [SearchField](search-field.md): A search field with a debounced query.
- [AtlasAutocompleteField](atlas-autocomplete-field.md): A text field that suggests completions.
- [AtlasComboBox](atlas-combo-box.md): A drop-down list, optionally filterable.
- [AtlasSpinBox](atlas-spin-box.md): A whole-number field with minus and plus buttons.
- [AtlasDoubleSpinBox](atlas-double-spin-box.md): A number field with decimals.
- [AtlasSlider](atlas-slider.md): A slider with an accent track, horizontal or vertical.
- [AtlasRating](atlas-rating.md): Zero to five stars, read-only or editable.
- [AtlasDatePicker](atlas-date-picker.md): A date field that opens a calendar.
- [AtlasCalendar](atlas-calendar.md): A month grid for choosing a day.
- [AtlasTimePicker](atlas-time-picker.md): Hours and minutes, with AM/PM in 12-hour mode.
- [AtlasColorField](atlas-color-field.md): A colour chooser with a palette and a hex field.
- [AtlasFileField](atlas-file-field.md): A file chooser with a Browse button.
- [AtlasFolderField](atlas-folder-field.md): A folder chooser with a Browse button.
- [AtlasFontPicker](atlas-font-picker.md): A font chooser with a searchable list of families.
- [AtlasShortcutField](atlas-shortcut-field.md): A field that records a key combination and reports conflicts.
- [AtlasDropZone](atlas-drop-zone.md): An area that files can be dropped on.

### Lists and tables

- [AtlasListView](atlas-list-view.md): A ListView in the Atlas look with selection, type-ahead and drag reordering.
- [AtlasTreeView](atlas-tree-view.md): A tree view in the Atlas list look.
- [AtlasTreeModel](atlas-tree-model.md): A read-only tree model built from nested JavaScript objects, for the tree view.
- [DataTable](data-table.md): A sortable table that only makes the rows on screen.
- [AtlasIconGrid](atlas-icon-grid.md): A scrolling grid of icons over names.
- [AtlasDetailGrid](atlas-detail-grid.md): Names and values in aligned columns.
- [AtlasSearchResults](atlas-search-results.md): A launcher's results list with sections and shortcut hints.
- [AtlasAppCard](atlas-app-card.md): A store card for one app.
- [AtlasScreenshotCarousel](atlas-screenshot-carousel.md): Screenshots shown one at a time.

### Navigation

- [AtlasSidebar](atlas-sidebar.md): A scrolling sidebar for sidebar items and groups.
- [SidebarItem](sidebar-item.md): One sidebar entry with a live value and badge.
- [SidebarGroup](sidebar-group.md): A foldable group of sidebar entries.
- [StepItem](step-item.md): One step of a setup sidebar: done, current or to come.
- [TabBar](tab-bar.md): Document tabs with an unsaved dot and a close button.
- [AtlasViewSwitcher](atlas-view-switcher.md): Page tabs for the top of a window.
- [AtlasNavigationStack](atlas-navigation-stack.md): Drill-down pages with a Back button.
- [AtlasBreadcrumb](atlas-breadcrumb.md): A path bar that folds its middle into a menu.
- [AtlasToolbar](atlas-toolbar.md): A bar of actions that moves what does not fit into a menu.
- [AtlasFloatingToolbar](atlas-floating-toolbar.md): A capsule of icon buttons that floats over content.

### Menus, dialogs and popups

- [ContextMenu](context-menu.md): A right-click menu.
- [ContextMenuItem](context-menu-item.md): One row of a context menu.
- [ContextMenuSeparator](context-menu-separator.md): A divider line in a context menu.
- [AtlasAppMenu](atlas-app-menu.md): The app's menus for the header bar or the desktop's global menu.
- [AtlasAction](atlas-action.md): One user action shared by buttons, menus and the keyboard.
- [AtlasActionCollection](atlas-action-collection.md): The app's actions declared once, with user-changeable shortcuts.
- [AtlasDialog](atlas-dialog.md): The general modal dialog.
- [ConfirmDialog](confirm-dialog.md): A modal question with small rounded buttons.
- [AtlasPopover](atlas-popover.md): A raised card that opens next to a control.
- [AtlasToolTip](atlas-tool-tip.md): A hint on a raised card.
- [AtlasCommandPalette](atlas-command-palette.md): A searchable list of the app's actions, opened with Ctrl+K.
- [AtlasShortcutsDialog](atlas-shortcuts-dialog.md): A modal list of the app's keyboard shortcuts.

### Feedback and status

- [InfoBanner](info-banner.md): An inline info, warning or error banner with actions.
- [Toast](toast.md): A short message that goes by itself.
- [AtlasProgressBar](atlas-progress-bar.md): A progress bar with indeterminate, paused and error states.
- [AtlasSpinner](atlas-spinner.md): A busy indicator.
- [AtlasPlaceholder](atlas-placeholder.md): Skeleton bars shown while content loads.
- [AtlasEmptyState](atlas-empty-state.md): What a list shows when it has nothing.
- [AtlasStatus](atlas-status.md): Loading, Empty, NoResults and Error for lists, tables, trees and pages.
- [AtlasBadge](atlas-badge.md): A small pill label for a status or count.
- [AtlasAvatar](atlas-avatar.md): A round picture of a person, with initials as the fallback.
- [AtlasStat](atlas-stat.md): A figure with a label, a unit, a trend and a sparkline.
- [AtlasEdgeGlow](atlas-edge-glow.md): The violet-to-sakura glow for "the system is working for you now".
- [StatusHero](status-hero.md): A big centred status: icon, headline, subtitle and actions.

### Charts

- [LiveChart](live-chart.md): A live line chart.
- [LiveChartItem](live-chart-item.md): The painted item behind the live chart.
- [UsageBar](usage-bar.md): A stacked usage bar.
- [MiniBars](mini-bars.md): A row of small bars.
- [AtlasSparkline](atlas-sparkline.md): A small line chart with no axes.
- [AtlasSparklineItem](atlas-sparkline-item.md): The painted item behind the sparkline.
- [RepaintArea](repaint-area.md): An invisible item that makes a table row repaint as one rectangle.

### Text and code

- [AtlasLabel](atlas-label.md): Text in one of the Atlas looks.
- [AtlasCodeView](atlas-code-view.md): Read-only monospace text with an optional copy button.
- [AtlasShortcutLabel](atlas-shortcut-label.md): A keyboard shortcut drawn as keycaps.
- [NotesText](notes-text.md): Release notes from a safe HTML fragment.
- [FindBar](find-bar.md): A find and replace bar.

### Layout

- [Section](section.md): A rounded card of rows.
- [SectionRow](section-row.md): One row of a section: title, subtitle, value and a switch, check mark or chevron.
- [AtlasCard](atlas-card.md): A padded card with an optional header and footer.
- [AtlasExpandableSection](atlas-expandable-section.md): A header row that folds its content.
- [AtlasSplitView](atlas-split-view.md): Panes with a draggable divider.
- [AtlasFlowLayout](atlas-flow-layout.md): A wrapping row layout.
- [AtlasScrollBar](atlas-scroll-bar.md): A thin scroll bar that fades out.
- [AtlasTransparencySwitch](atlas-transparency-switch.md): A settings row with the shared Transparency and blur switch.

### Style and motion

- [AtlasStyle](atlas-style.md): The design tokens: colours, spacing, radii, fonts, motion and density.
- [Appearance](appearance.md): The look switches every app shares: transparency, colour scheme, motion and text scale.
- [AtlasSpringAnimation](atlas-spring-animation.md): The Atlas spring for movement and size.
- [AtlasFocusRing](atlas-focus-ring.md): The keyboard focus outline.

### Icons

- [Symbol](symbol.md): One Material Symbols icon.
- [Symbols](symbols.md): The singleton of every symbol's name.

### Services

- [AtlasApp](atlas-app.md): The running app's name, ID, version and the OS.
- [AtlasSettings](atlas-settings.md): The app's own settings file.
- [AtlasClipboard](atlas-clipboard.md): The system clipboard.
- [AtlasGlobalShortcut](atlas-global-shortcut.md): A system-wide shortcut through the desktop portal.
- [AtlasFormat](atlas-format.md): Formats sizes, speeds, numbers, durations and dates for the user's locale.
- [AtlasPortal](atlas-portal.md): Opens links and sends desktop notifications.
- [AtlasShortcuts](atlas-shortcuts.md): The registry of the app's actions and shortcut conflicts.
- [AccessibilityState](accessibility-state.md): Whether a screen reader is listening.

### Validators

- [AtlasEmailValidator](atlas-email-validator.md): Checks an email address.
- [AtlasUrlValidator](atlas-url-validator.md): Checks a URL and its scheme.
- [AtlasPathValidator](atlas-path-validator.md): Checks a file path.
- [AtlasNumberValidator](atlas-number-validator.md): Checks a number's range, decimals and locale format.
