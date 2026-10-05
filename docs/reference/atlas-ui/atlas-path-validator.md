---
title: AtlasPathValidator
summary: A validator for a file path field that can require an absolute path or an existing file or folder.
section: Validators
since: "1.4.0"
---

A validator for a text field's `validator`: a file path. `~` and `~/` stand for the home directory. NUL and control characters are never valid, text over a fixed length is Invalid, and it uses no regular expressions. Pair it with `invalidText` on [AtlasTextField](atlas-text-field.md#properties).

## Example

```qml
AtlasTextField {
    validator: AtlasPathValidator { mustExist: true; directory: true }
    invalidText: qsTr("Choose a folder that exists")
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `absolute` | `bool` | `true` | A path must start with `/` (or `~`). |
| `directory` | `bool` | `false` | With `mustExist`, the path must be a directory rather than any file. |
| `mustExist` | `bool` | `false` | The path must exist on disk. |

> [!NOTE]
> With `mustExist`, every validation (so every keystroke) stats the path on disk. Leave it off for paths on slow or network file systems.
