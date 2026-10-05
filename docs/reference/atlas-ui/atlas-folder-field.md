---
title: AtlasFolderField
summary: A folder chooser: a path field and a Browse button that opens the system folder dialog.
section: Fields and pickers
since: "1.4.0"
---

AtlasFolderField is a text field with the path and a Browse button that opens the system folder dialog (through the file chooser portal under Plasma). `path` is the text; `url` is the same as a file URL. `~` and `~/...` mean the home folder, and a path that is not absolute gives an empty `url`. See [AtlasFileField](atlas-file-field.md) for a file.

## Example

```qml
AtlasFolderField {
    placeholderText: qsTr("Choose a folder")
    onEdited: settings.backupFolder = path
    Accessible.name: qsTr("Backup folder")
}
```

> [!NOTE]
> Nothing is run through a shell. The dialog is made on first use.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `editable` | `bool` | `true` | `false` leaves only the button: the path cannot be typed, only chosen. |
| `path` | `string` | `""` | The path as text. |
| `placeholderText` | `string` | `""` | Hint shown while the field is empty. |
| `title` | `string` | `""` | The dialog's title; empty for the system's own. |
| `url` | `url` (read-only) | — | `path` as a file URL; empty when `path` is empty or not absolute. |

## Signals

| Name | Description |
|---|---|
| `edited()` | The user typed a path or chose one. Not emitted when the app sets `path`. |

> [!NOTE]
> A user edit keeps your binding. `path: model.x` stays bound: if your handler takes the edit it follows the model, and if it ignores it the value springs back after the handler. With a plain value or no binding the edit stays. `edited()` and `on<Property>Changed` see the edit at once, as before.
