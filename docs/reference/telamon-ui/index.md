---
title: Telamon.Ui
summary: The QML module every Telamon app imports, with windows, pages, buttons, fields, lists, dialogs, charts and the style and services behind them; how to install it, check it and find a type.
order: 1
---

Telamon.Ui is the QML module of Telamon controls. Every Telamon app imports it, so they all share one look, one set of keyboard and accessibility rules and one copy on disk. It is a QML module installed next to Qt's own, like Kirigami. Its URI is `Telamon.Ui`.

## Install and import

Install the `telamon-ui` package (Fedora 44, Qt 6.11). It brings in the Material Symbols fonts (`telamon-symbols-fonts`), Kirigami, IBM Plex Sans and JetBrains Mono.

```sh
sudo dnf install telamon-ui
```

The module lives in Qt's QML directory (`/usr/lib64/qt6/qml/Telamon/Ui/`). An app writes `import Telamon.Ui` in QML and links nothing: the QML engine loads the plugin. There is no CMake package and no devel package.

```qml
import QtQuick
import Telamon.Ui

TelamonWindow {
    title: qsTr("Hello")
    visible: true

    TelamonPage {
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
> `import Telamon.Ui` wins over the QML files in an app's own directory. An app file named like a Telamon.Ui type (say `SearchField.qml`) is hidden by it. New Telamon.Ui types are named `Telamon<Name>` to keep clear of apps' names; see [Compatibility](compatibility.md).

## Check the module at configure time

The [app template](../template/index.md) fails the CMake configure with a plain message when the module is missing. qmlcachegen and qmllint find it in Qt's QML directory by themselves, so the app's `<app>_qmllint` target checks the app's QML against it.

```cmake
if(NOT EXISTS "${QT6_INSTALL_PREFIX}/${QT6_INSTALL_QML}/Telamon/Ui/qmldir")
    message(FATAL_ERROR "Telamon.Ui is not installed: dnf install telamon-ui")
endif()
```

## Version rule

Telamon.Ui only ever adds API. An app that uses something added after 1.0.0 states the oldest version it works with in two places, and keeps them equal:

- `Requires: telamon-ui >= X.Y.Z` (and `BuildRequires`) in the app's RPM spec, so dnf installs a new enough one;
- `ui: "X.Y.Z"` in the app's `app!` call, so at startup an older Telamon.Ui, installed some other way, gives a plain error window instead of a broken one.

`TelamonApp.uiVersion` reports the installed version at run time. Each page says which version added its type (`since`).

## Guides

- [Design rules](design-rules.md): what every Telamon app does.
- [Style and theming](style-and-theming.md): colours, spacing, radii, density, blur and text scale.
- [Motion](motion.md): springs, reduced motion and the violet to sakura gradient.
- [Compatibility](compatibility.md): the API contract and what it means for an app.
- [Accessibility](accessibility.md): focus, roles, names, right-to-left and the framework's tests.

## The types

Every type has a page. The groups below are the sidebar sections.

### Windows and pages

- [TelamonWindow](telamon-window.md): The application window: blurred or opaque by the shared switch, remembers its size, and goes frameless with a header bar.
- [TelamonHeaderBar](telamon-header-bar.md): The merged header of a frameless window: window menu, title, tools and window buttons.
- [TelamonWindowButtons](telamon-window-buttons.md): Minimise, maximise and close buttons drawn like the Telamon OS window decoration.
- [TelamonWindowChrome](telamon-window-chrome.md): Singleton with the desktop's caption-button layout and whether a global menu exists.
- [TelamonPage](telamon-page.md): A scrolling page with a large bold title and centred margins.
- [TelamonAboutPage](telamon-about-page.md): A ready-made About page for any app.
- [TelamonOnboarding](telamon-onboarding.md): A setup scaffold: steps, one page at a time, Back, Skip and Next.
- [StatusBar](status-bar.md): A slim bottom bar of cells such as line, column and encoding.
- [StatusBarItem](status-bar-item.md): One cell of a status bar, optionally clickable or with a menu.

### Buttons

- [TelamonButton](telamon-button.md): The shared base of the buttons, with four variants and a busy state.
- [PrimaryButton](primary-button.md): The filled accent button for the main action.
- [SecondaryButton](secondary-button.md): The soft, tinted button for ordinary actions.
- [TextButton](text-button.md): A button that looks like a link.
- [MenuButton](menu-button.md): A button that opens a menu.
- [ToolbarButton](toolbar-button.md): A small icon button for toolbars that never takes the editor's focus.
- [TelamonSplitButton](telamon-split-button.md): A main button joined to an arrow that opens a menu of variants.
- [TelamonInstallButton](telamon-install-button.md): An install button with progress inside it and states for install, update, open and retry.
- [TelamonCopyButton](telamon-copy-button.md): An icon button that copies text and shows a check mark.
- [TelamonSwitch](telamon-switch.md): A round switch.
- [TelamonCheckBox](telamon-check-box.md): A check box with an optional partly-checked state.
- [TelamonRadioButton](telamon-radio-button.md): A radio button; siblings form a group.
- [TelamonSegmentedControl](telamon-segmented-control.md): Joined segments with one selected.
- [TelamonChip](telamon-chip.md): A small chip for a tag, filter or value.
- [TelamonChoiceCard](telamon-choice-card.md): One of a few choices as a picture with its name and a check circle.
- [TelamonAccentPicker](telamon-accent-picker.md): A row of round colour swatches, one chosen.
- [TelamonChipGroup](telamon-chip-group.md): A wrapping group of chips, optionally one-of.

### Fields and pickers

- [TelamonTextField](telamon-text-field.md): A single-line text field with error, clear button, prefix, suffix and counter.
- [TelamonTextArea](telamon-text-area.md): A multi-line text field.
- [TelamonPasswordField](telamon-password-field.md): A password field with a show toggle.
- [TelamonPasswordStrength](telamon-password-strength.md): A strength bar and label for a password.
- [SearchField](search-field.md): A search field with a debounced query.
- [TelamonAutocompleteField](telamon-autocomplete-field.md): A text field that suggests completions.
- [TelamonComboBox](telamon-combo-box.md): A drop-down list, optionally filterable.
- [TelamonSpinBox](telamon-spin-box.md): A whole-number field with minus and plus buttons.
- [TelamonDoubleSpinBox](telamon-double-spin-box.md): A number field with decimals.
- [TelamonSlider](telamon-slider.md): A slider with an accent track, horizontal or vertical.
- [TelamonRating](telamon-rating.md): Zero to five stars, read-only or editable.
- [TelamonDatePicker](telamon-date-picker.md): A date field that opens a calendar.
- [TelamonCalendar](telamon-calendar.md): A month grid for choosing a day.
- [TelamonTimePicker](telamon-time-picker.md): Hours and minutes, with AM/PM in 12-hour mode.
- [TelamonColorField](telamon-color-field.md): A colour chooser with a palette and a hex field.
- [TelamonFileField](telamon-file-field.md): A file chooser with a Browse button.
- [TelamonFolderField](telamon-folder-field.md): A folder chooser with a Browse button.
- [TelamonFontPicker](telamon-font-picker.md): A font chooser with a searchable list of families.
- [TelamonShortcutField](telamon-shortcut-field.md): A field that records a key combination and reports conflicts.
- [TelamonDropZone](telamon-drop-zone.md): An area that files can be dropped on.

### Lists and tables

- [TelamonListView](telamon-list-view.md): A ListView in the Telamon look with selection, type-ahead and drag reordering.
- [TelamonTreeView](telamon-tree-view.md): A tree view in the Telamon list look.
- [TelamonTreeModel](telamon-tree-model.md): A read-only tree model built from nested JavaScript objects, for the tree view.
- [DataTable](data-table.md): A sortable table that only makes the rows on screen.
- [TelamonIconGrid](telamon-icon-grid.md): A scrolling grid of icons over names.
- [TelamonDetailGrid](telamon-detail-grid.md): Names and values in aligned columns.
- [TelamonSearchResults](telamon-search-results.md): A launcher's results list with sections and shortcut hints.
- [TelamonAppCard](telamon-app-card.md): A store card for one app.
- [TelamonScreenshotCarousel](telamon-screenshot-carousel.md): Screenshots shown one at a time.
- [TelamonShelf](telamon-shelf.md): A titled horizontal row of cards with scroll buttons.

### Navigation

- [TelamonSidebar](telamon-sidebar.md): A scrolling sidebar for sidebar items and groups.
- [SidebarItem](sidebar-item.md): One sidebar entry with a live value and badge.
- [SidebarGroup](sidebar-group.md): A foldable group of sidebar entries.
- [StepItem](step-item.md): One step of a setup sidebar: done, current or to come.
- [TabBar](tab-bar.md): Document tabs with an unsaved dot and a close button.
- [TelamonViewSwitcher](telamon-view-switcher.md): Page tabs for the top of a window.
- [TelamonNavigationStack](telamon-navigation-stack.md): Drill-down pages with a Back button.
- [TelamonBreadcrumb](telamon-breadcrumb.md): A path bar that folds its middle into a menu.
- [TelamonToolbar](telamon-toolbar.md): A bar of actions that moves what does not fit into a menu.
- [TelamonFloatingToolbar](telamon-floating-toolbar.md): A capsule of icon buttons that floats over content.

### Menus, dialogs and popups

- [ContextMenu](context-menu.md): A right-click menu.
- [ContextMenuItem](context-menu-item.md): One row of a context menu.
- [ContextMenuSeparator](context-menu-separator.md): A divider line in a context menu.
- [TelamonAppMenu](telamon-app-menu.md): The app's menus for the header bar or the desktop's global menu.
- [TelamonAction](telamon-action.md): One user action shared by buttons, menus and the keyboard.
- [TelamonActionCollection](telamon-action-collection.md): The app's actions declared once, with user-changeable shortcuts.
- [TelamonDialog](telamon-dialog.md): The general modal dialog.
- [TelamonPreferencesDialog](telamon-preferences-dialog.md): A preferences dialog of pages, with search.
- [TelamonPreferencesPage](telamon-preferences-page.md): One page of a preferences dialog.
- [ConfirmDialog](confirm-dialog.md): A modal question with small rounded buttons.
- [TelamonPopover](telamon-popover.md): A raised card that opens next to a control.
- [TelamonToolTip](telamon-tool-tip.md): A hint on a raised card.
- [TelamonCommandPalette](telamon-command-palette.md): A searchable list of the app's actions, opened with Ctrl+K.
- [TelamonShortcutsDialog](telamon-shortcuts-dialog.md): A modal list of the app's keyboard shortcuts.

### Feedback and status

- [InfoBanner](info-banner.md): An inline info, warning or error banner with actions.
- [Toast](toast.md): A short message that goes by itself.
- [TelamonProgressBar](telamon-progress-bar.md): A progress bar with indeterminate, paused and error states.
- [TelamonSpinner](telamon-spinner.md): A busy indicator.
- [TelamonPlaceholder](telamon-placeholder.md): Skeleton bars shown while content loads.
- [TelamonEmptyState](telamon-empty-state.md): What a list shows when it has nothing.
- [TelamonStatus](telamon-status.md): Loading, Empty, NoResults and Error for lists, tables, trees and pages.
- [TelamonBadge](telamon-badge.md): A small pill label for a status or count.
- [TelamonAvatar](telamon-avatar.md): A round picture of a person, with initials as the fallback.
- [TelamonStat](telamon-stat.md): A figure with a label, a unit, a trend and a sparkline.
- [TelamonEdgeGlow](telamon-edge-glow.md): The violet-to-sakura glow for "the system is working for you now".
- [StatusHero](status-hero.md): A big centred status: icon, headline, subtitle and actions.

### Charts

- [LiveChart](live-chart.md): A live line chart.
- [LiveChartItem](live-chart-item.md): The painted item behind the live chart.
- [UsageBar](usage-bar.md): A stacked usage bar.
- [MiniBars](mini-bars.md): A row of small bars.
- [TelamonSparkline](telamon-sparkline.md): A small line chart with no axes.
- [TelamonSparklineItem](telamon-sparkline-item.md): The painted item behind the sparkline.
- [RepaintArea](repaint-area.md): An invisible item that makes a table row repaint as one rectangle.

### Text and code

- [TelamonLabel](telamon-label.md): Text in one of the Telamon looks.
- [TelamonCodeView](telamon-code-view.md): Read-only monospace text with an optional copy button.
- [TelamonCodeEditor](telamon-code-editor.md): An editable code editor with syntax highlighting, line numbers, marks and edits from outside that keep the caret and the view.
- [TelamonConsoleView](telamon-console-view.md): Read-only monospace view for a command's streaming output, with ANSI colours and follow-tail.
- [TelamonShortcutLabel](telamon-shortcut-label.md): A keyboard shortcut drawn as keycaps.
- [NotesText](notes-text.md): Release notes from a safe HTML fragment.
- [FindBar](find-bar.md): A find and replace bar.

### Layout

- [Section](section.md): A rounded card of rows.
- [SectionRow](section-row.md): One row of a section: title, subtitle, value and a switch, check mark or chevron.
- [TelamonForm](telamon-form.md): A form of sections and entries that knows when it is valid.
- [TelamonFormEntry](telamon-form-entry.md): One labelled form row with validation and a settings key.
- [TelamonCard](telamon-card.md): A padded card with an optional header and footer.
- [TelamonExpandableSection](telamon-expandable-section.md): A header row that folds its content.
- [TelamonSplitView](telamon-split-view.md): Panes with a draggable divider.
- [TelamonFlowLayout](telamon-flow-layout.md): A wrapping row layout.
- [TelamonScrollBar](telamon-scroll-bar.md): A thin scroll bar that fades out.
- [TelamonTransparencySwitch](telamon-transparency-switch.md): A settings row with the shared Transparency and blur switch.

### Style and motion

- [TelamonStyle](telamon-style.md): The design tokens: colours, spacing, radii, fonts, motion and density.
- [Appearance](appearance.md): The look switches every app shares: transparency, colour scheme, motion and text scale.
- [TelamonSpringAnimation](telamon-spring-animation.md): The Telamon spring for movement and size.
- [TelamonFocusRing](telamon-focus-ring.md): The keyboard focus outline.

### Icons

- [Symbol](symbol.md): One Material Symbols icon.
- [TelamonIcon](telamon-icon.md): A theme icon that stays under dialogs and menus.
- [Symbols](symbols.md): The singleton of every symbol's name.

### Services

- [TelamonApp](telamon-app.md): The running app's name, ID, version and the OS.
- [TelamonSettings](telamon-settings.md): The app's own settings file.
- [TelamonClipboard](telamon-clipboard.md): The system clipboard.
- [TelamonGlobalShortcut](telamon-global-shortcut.md): A system-wide shortcut through the desktop portal.
- [TelamonFormat](telamon-format.md): Formats sizes, speeds, numbers, durations and dates for the user's locale.
- [TelamonPortal](telamon-portal.md): Opens links and sends desktop notifications.
- [TelamonShortcuts](telamon-shortcuts.md): The registry of the app's actions and shortcut conflicts.
- [AccessibilityState](accessibility-state.md): Whether a screen reader is listening.

### Validators

- [TelamonEmailValidator](telamon-email-validator.md): Checks an email address.
- [TelamonUrlValidator](telamon-url-validator.md): Checks a URL and its scheme.
- [TelamonPathValidator](telamon-path-validator.md): Checks a file path.
- [TelamonNumberValidator](telamon-number-validator.md): Checks a number's range, decimals and locale format.
