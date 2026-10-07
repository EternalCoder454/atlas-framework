---
title: TelamonFormEntry
summary: One labelled row of a form: a label and help text, one control, its validation and an optional settings key that loads and saves the control by itself.
section: Layout
since: "1.5.0"
---

A TelamonFormEntry is one row in a [Section](section.md) of a [TelamonForm](telamon-form.md): the label (and `help` under it) on the leading side, the control on the trailing side. The control is the one item declared inside the entry; any Telamon.Ui control works, and so does a plain `Item`. In a narrow row (less than 22 grid units), for a tall control (a text area), and for a control too wide to fit beside the label, the control goes under the label (`stacked`).

An entry is valid when it has no `errorText`, is not `required` and empty, and its control's `acceptableInput` is not false (the Telamon validators and `TextField.validator` set it; an optional field that is empty is never unacceptable). The error shows under the row, with an error symbol, and the control gets a red outline (a control that draws its own error, such as TelamonTextField, keeps its own):

- the app's `errorText` shows at once, as `TelamonTextField.errorText` does;
- the `requiredText` and `invalidText` errors show only after the user has left the control once (focus moving to something else; a combo box's open list is not leaving), or after `TelamonForm.validate()`. After that they follow the control live and go as soon as it is fine.

Each error is announced with `Accessible.announce()` when it appears. Clicking the label focuses the control.

The entry gives the control its accessible name (`label`; the control's own name stays when the label is empty) and description (`help`, then the error shown). Empty means: no text, not checked, index -1, no path, no shortcut. A colour is never empty.

## Example

```qml
TelamonFormEntry {
    label: qsTr("Port")
    help: qsTr("1 to 65535")
    required: true
    settingKey: "Port"
    TelamonSpinBox { from: 1; to: 65535 }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `content` | `list<QtObject>` (default, read-only) | — | The control: one item. |
| `label` | `string` | `""` | The row's label, and the control's accessible name. |
| `help` | `string` | `""` | A muted line under the row, and the control's accessible description. |
| `errorText` | `string` | `""` | The app's own error. Non-empty makes the entry invalid and shows at once. |
| `required` | `bool` | `false` | An empty control is invalid. |
| `requiredText` | `string` | `qsTr("Required")` | Shown when `required` fails. |
| `invalidText` | `string` | `qsTr("Check this value")` | Shown when the control's `acceptableInput` is false. |
| `valid` | `bool` (read-only) | — | No error of any kind, shown or not. An entry that is disabled, or that the app hid with `visible: false`, is valid, so it never blocks a form. One on a page that is not shown still counts. |
| `shownError` | `string` (read-only) | — | The error on screen, or `""`. |
| `stacked` | `bool` | automatic | The control under the label. On in a narrow row, for a tall control and for one too wide to fit beside the label; set it to force either. |
| `settingKey` | `string` | `""` | The key in the form's `settings` the control is bound to; see below. |
| `settingProperty` | `string` | `""` | The control's property to save, for a control that is not in the table below. |
| `telamonRow` | `bool` (read-only) | `true` | Marks the entry as a row of a Section, as [SectionRow](section-row.md) does. |
| `isFirst` | `bool` (read-only) | — | True for the first visible row of its Section, which draws no separator above itself. |

## Settings that save themselves

With a `settingKey` the control takes the stored value when the entry is created (the control's own value is the default when the key is missing) and every user edit is written with `TelamonSettings.setValue()`. The edit is detected with the control's own edit signal. A change of the key made by another writer (`TelamonSettings.changed(key)`) updates the control.

| Control | Property saved | Edit signal |
|---|---|---|
| [TelamonSwitch](telamon-switch.md), [TelamonCheckBox](telamon-check-box.md) | `checked` | `toggled` |
| [TelamonSlider](telamon-slider.md), [TelamonSpinBox](telamon-spin-box.md), [TelamonDoubleSpinBox](telamon-double-spin-box.md), [TelamonRating](telamon-rating.md) | `value` | `moved`, `valueModified`, `edited` |
| [TelamonComboBox](telamon-combo-box.md), [TelamonSegmentedControl](telamon-segmented-control.md) | `currentIndex` | `activated` |
| [TelamonTextField](telamon-text-field.md), [TelamonTextArea](telamon-text-area.md) | `text` | `textEdited` (`textChanged` for a text area) |
| [TelamonColorField](telamon-color-field.md) | `color` (as `#rrggbb` or `#aarrggbb`) | `edited` |
| [TelamonFileField](telamon-file-field.md), [TelamonFolderField](telamon-folder-field.md) | `path` | `edited` |
| [TelamonShortcutField](telamon-shortcut-field.md) | `sequence` (the portable form) | `edited` |
| [TelamonPasswordField](telamon-password-field.md) | none: a password is not a setting | |
| other | the property named by `settingProperty` | its change signal |

Only a valid value is saved: while the entry is invalid (an unacceptable text, a required control that is empty) an edit is not written. A string over 64 KiB is not saved (one warning), and a stored string over 64 KiB is ignored, so a huge paste cannot make the settings file unreadable. A key that TelamonSettings would refuse (brackets, `=`, a leading `#` or `;`, control characters, over 200 characters) warns once and is ignored. A stored shortcut is read back through its portable form. A loaded `path` is untrusted text: validate it before use.

A stored value that does not fit the property (text for a switch) is ignored with a warning that names the key. A password is never loaded or saved, whatever `settingProperty` says: the control, or anything inside it (a field in a wrapper `Item`), counts as a password when it is a TelamonPasswordField, hides what is typed (`echoMode` other than `Normal`), sets `Qt.ImhSensitiveData` or reports `Accessible.passwordEdit`. One warning names the key. A field switched to a password later may already have saved what was typed before. An entry with a `settingKey` and no settings (the form has none, and it is not on a page of a dialog that has) warns.

> [!NOTE]
> The stored value is applied like a user edit: held for one turn, then released. A control with an app binding on the property (`checked: app.flag`) goes back to the app's value after that turn, so the app stays in charge; the user's edits are still saved and the binding stays intact. See "App bindings" in [TelamonSegmentedControl](telamon-segmented-control.md).

## Keyboard

The entry takes no Tab stop; the control inside does. Return in a single-line field emits `TelamonForm.accepted()` while the form is valid.

## Accessibility

The control has the accessible name `label` and the description `help` followed by the error shown. Errors are announced when they appear.
