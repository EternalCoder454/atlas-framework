---
title: AtlasPreferencesPage
summary: One page of an AtlasPreferencesDialog: a title and symbol for the sidebar, and Sections of form entries.
section: Menus, dialogs and popups
since: "1.5.0"
---

An AtlasPreferencesPage is an [AtlasForm](atlas-form.md) that belongs to an [AtlasPreferencesDialog](atlas-preferences-dialog.md). Put [Section](section.md)s of [AtlasFormEntry](atlas-form-entry.md) rows inside, as in any form. Its `entries`, `valid` and `validate()` work for the page; the entries use the dialog's `settings` unless the page has its own.

## Example

```qml
AtlasPreferencesPage {
    title: qsTr("General")
    symbol: Symbols.Settings
    Section {
        AtlasFormEntry {
            label: qsTr("Show hidden files")
            settingKey: "ShowHidden"
            AtlasSwitch { }
        }
    }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `title` | `string` | `""` | The page's name in the dialog's sidebar and in the search results. |
| `symbol` | `int` | `0` | A [Symbols](symbols.md) value shown beside the title in the sidebar. |
