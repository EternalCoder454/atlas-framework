---
title: AtlasForm
summary: A form of Sections and AtlasFormEntry rows that knows when it is valid, shows every error with validate() and gives its entries the settings they save to.
section: Layout
since: "1.5.0"
---

An AtlasForm holds [Section](section.md)s of [AtlasFormEntry](atlas-form-entry.md) rows. It is a Qt Quick Layouts `ColumnLayout`, so anything else can sit beside the Sections (a button row, an [InfoBanner](info-banner.md)). The form does not draw anything of its own: it collects its entries (they register when they are created and leave when they are destroyed) and answers for all of them. A page of an [AtlasPreferencesDialog](atlas-preferences-dialog.md) is an AtlasForm.

## Example

```qml
AtlasForm {
    id: form
    settings: AtlasSettings { group: "Account" }
    onAccepted: save()

    Section {
        title: qsTr("Account")
        AtlasFormEntry {
            label: qsTr("Name")
            required: true
            settingKey: "Name"
            AtlasTextField { }
        }
        AtlasFormEntry {
            label: qsTr("Email")
            AtlasTextField { validator: AtlasEmailValidator { } }
        }
    }
    PrimaryButton {
        text: qsTr("Save")
        enabled: form.valid
        onClicked: save()
    }
}
```

Bind a primary button to `enabled: form.valid`, or leave it enabled and call `form.validate()` when it is clicked: `validate()` shows what is wrong and moves the focus there.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `entries` | `var` (read-only) | `[]` | The entries inside, as an array, in the order they were created. |
| `settings` | `AtlasSettings` | `null` | Where the entries with a `settingKey` save. On a page of an AtlasPreferencesDialog the dialog's `settings` are used when the page has none. |
| `valid` | `bool` (read-only) | — | True when every entry is valid. An entry that is disabled or not visible counts as valid (so does one on a page that is not shown), and `validate()` never focuses it. |

## Signals

| Name | Description |
|---|---|
| `accepted()` | Return was pressed in a single-line field while the form is valid. When the form is not valid Return does what `validate()` does. |

## Methods

| Signature | Description |
|---|---|
| `validate()` | Shows the error of every entry (not only those the user has left), moves the keyboard focus to the first invalid entry in reading order and returns `valid`. |

## Accessibility

The form adds no accessible item. Each entry gives its control an accessible name (its `label`) and description (its `help` and error); see [AtlasFormEntry](atlas-form-entry.md).
