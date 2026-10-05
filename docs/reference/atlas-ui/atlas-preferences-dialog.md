---
title: AtlasPreferencesDialog
summary: A preferences dialog of pages with a sidebar, a search over every setting's label and help, and entries that save themselves.
section: Menus, dialogs and popups
since: "1.5.0"
---

AtlasPreferencesDialog is an [AtlasDialog](atlas-dialog.md) of [AtlasPreferencesPage](atlas-preferences-page.md)s. With one page it shows alone; with two or more it gets an [AtlasSidebar](atlas-sidebar.md) of the page titles and symbols (icons only when the dialog is narrower than 36 grid units). It is up to 50 grid units wide (`preferredWidth`), and its page area has a fixed height and scrolls.

The search field (`searchable`) looks through the `label` and `help` of every [AtlasFormEntry](atlas-form-entry.md) on every page, ignoring case. Entries that are disabled or hidden by the app (`visible: false`), on any page, are left out. The matches are listed as rows of "label" with the page title under it; no match shows an [AtlasEmptyState](atlas-empty-state.md). Choosing a row leaves the search, shows the entry's page, scrolls the entry into view, gives its control the keyboard focus and flashes the row once (no flash under reduced motion). Escape clears the search first and closes the dialog only when the search is already empty.

Entries with a `settingKey` save to `settings`. See [AtlasFormEntry](atlas-form-entry.md).

## Example

```qml
AtlasPreferencesDialog {
    id: prefs
    title: qsTr("Preferences")
    settings: AtlasSettings { group: "General" }

    AtlasPreferencesPage {
        title: qsTr("General")
        symbol: Symbols.Settings
        Section {
            AtlasFormEntry {
                label: qsTr("Show hidden files")
                help: qsTr("Dotfiles too")
                settingKey: "ShowHidden"
                AtlasSwitch { }
            }
        }
    }
    AtlasPreferencesPage {
        title: qsTr("Network")
        symbol: Symbols.Language
        Section {
            AtlasFormEntry {
                label: qsTr("Proxy port")
                settingKey: "ProxyPort"
                AtlasSpinBox { from: 1; to: 65535 }
            }
        }
    }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `pages` | `list<AtlasPreferencesPage>` (default, read-only) | — | The pages, in order. They are taken once, when the dialog is created. |
| `settings` | `AtlasSettings` | `null` | Used by every entry with a `settingKey` (a page's own `settings` win). |
| `searchable` | `bool` | `true` | Shows the search field. |
| `currentIndex` | `int` | `0` | The page shown. A page the user chooses does not end an app binding on it: if the app does not take the choice, `currentIndex` goes back one turn later. |
| `stateKey` | `string` | `""` | When set, the page shown is saved under `AtlasPreferencesDialog-<stateKey>` in the app's settings file and restored when the dialog is created. The dialog is not resizable, so no size is saved. |

The inherited properties of [AtlasDialog](atlas-dialog.md) work as usual; `title` is "Preferences" and `preferredWidth` is 50 grid units by default.

## Keyboard

Tab goes through the sidebar, the search field and the controls of the page. Escape clears the search, then closes. Return on a search result chooses it.

## Accessibility

The sidebar is named "Pages" and the search field "Search settings". A result row is named by its label and described by its page title. The controls are named by their entries.
