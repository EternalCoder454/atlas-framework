---
title: TelamonPreferencesPage
summary: One page of a TelamonPreferencesDialog: a title and symbol for the sidebar, and Sections of form entries.
section: Menus, dialogs and popups
since: "1.5.0"
---

A TelamonPreferencesPage is a [TelamonForm](telamon-form.md) that belongs to a [TelamonPreferencesDialog](telamon-preferences-dialog.md). Put [Section](section.md)s of [TelamonFormEntry](telamon-form-entry.md) rows inside, as in any form. Its `entries`, `valid` and `validate()` work for the page; the entries use the dialog's `settings` unless the page has its own.

## Example

```qml
TelamonPreferencesPage {
    title: qsTr("General")
    symbol: Symbols.Settings
    Section {
        TelamonFormEntry {
            label: qsTr("Show hidden files")
            settingKey: "ShowHidden"
            TelamonSwitch { }
        }
    }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `title` | `string` | `""` | The page's name in the dialog's sidebar and in the search results. |
| `symbol` | `int` | `0` | A [Symbols](symbols.md) value shown beside the title in the sidebar. |
