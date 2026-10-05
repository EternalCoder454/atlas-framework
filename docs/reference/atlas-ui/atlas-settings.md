---
title: AtlasSettings
summary: An app's own settings file, read and written in the format the Rust settings crate uses, with typed values, atomic batched writes and change notices.
section: Services
since: "1.4.0"
---

The app's own settings, in the file the Rust crate (`atlas_framework_core::settings`) reads and writes: `$XDG_CONFIG_HOME/<short name>rc` (default `~/.config`), in KConfig's INI format with `[Atlas] Format=1`. The short name comes from the app ID (`QGuiApplication::desktopFileName()`): its last dotted part, lower-cased, with every character other than a-z, 0-9, `_` and `-` turned into `_`, cut to 58 characters and given an `atlas-` prefix (not doubled when the part already starts with it). An empty result gives `atlas-app`. Declare one `AtlasSettings` per group. Use it for anything the app remembers between runs, such as view options, and for a split view's sizes ([AtlasSplitView](atlas-split-view.md)).

## Example

```qml
AtlasSettings {
    id: view
    group: "View"
}
AtlasSwitch {
    checked: view.value("ShowHidden", false)
    onToggled: view.setValue("ShowHidden", checked)
}
```

To save a split view's sizes (a base64 string) or a sidebar's width, use the app's own group:

```qml
AtlasSettings { id: layout; group: "Layout" }
AtlasSplitView {
    Component.onCompleted: restoreSizes(layout.value("Split", ""))
    onResizingChanged: if (!resizing) layout.setValue("Split", saveSizes())
}
AtlasSidebar {
    width: layout.value("SidebarWidth", 240)
    onWidthChanged: layout.setValue("SidebarWidth", width)
}
```

A window saves its own size with `AtlasWindow.stateKey`; see [AtlasWindow](atlas-window.md).

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `fileName` | `string` | `""` | Empty for the app's own file, or a bare file name in the config directory. Refused when it has a path separator (`/` or `\`), starts with `.`, has leading or trailing whitespace or control characters, or is over 200 characters. |
| `group` | `string` | `""` | The group (section) of the file. Required. Refused when empty, over 200 characters, with leading or trailing whitespace, starting with `#` or `;`, containing `[` or `]`, or containing control characters. |

> [!NOTE]
> Set `group` and `fileName` as literals. `value()` reads the file on first use, so a binding on a sibling that runs while the tree is built sees the saved value, but a `group` or `fileName` set by a binding is not known yet then.

## Signals

| Name | Description |
|---|---|
| `changed(string key)` | Another process (the Rust crate, KDE tools, a text editor) changed `key` of the group. |

## Methods

| Signature | Description |
|---|---|
| `contains(string key): bool` | Whether the group has `key`. |
| `flush(): bool` | Writes what is waiting now. Returns `true` when nothing is left unwritten. |
| `remove(string key): bool` | Removes `key`. Batched like `setValue`. Returns `false` (and logs) for a bad group or key, or an immutable key. |
| `setValue(string key, var value): bool` | Sets `key`. Returns `false` (and logs) for a bad group or key, a value that cannot be stored, or an immutable key. |
| `value(string key): var` | Reads `key`, or `undefined` when it is not set. |
| `value(string key, var defaultValue): var` | Reads `key`, typed by the default: a bool, int, real or string list default gives that type back (a stored value of another shape gives the default). Any other default gives a string. |

## How it reads and writes

- `setValue` and `remove` are batched (a short timer, `flush()`, or the end of the program) and written atomically: a temp file is renamed over the file.
- Writes take the same `flock` on `.<name>.lock` beside the file that the Rust crate takes, so a Rust writer and this one never lose each other's change. `flush()` waits at most 1 second for it and returns `false` if another program still holds it. The timed write never waits: while another program holds the lock the changes stay pending and are retried after 50 ms, doubling up to 1 second, and then each second until the write succeeds; after about 10 seconds one warning is logged. A failed `flush()` starts the retries too. Changing `group` or `fileName`, and quitting, write what is pending with `flush()`, so they can wait up to 1 second for the lock.
- Keys the user or an admin marked immutable (`[$i]`) are refused.
- A key marked `[$e]` (variable expansion) is dropped with a warning, so it reads as not set; `$VARIABLE` expansion is not done.
- A file that is not a regular file, or is over 4 MB, is not read (you get defaults) and not written.
- A new file is created with mode 0600.
- A settings file that is a symlink pointing out of the config directory is refused, so a planted link cannot make the app write elsewhere. This is stricter than the Rust crate on purpose.
- A change that could not be written when `group` or `fileName` changes is dropped with a warning, never moved into the other group or file.
- Every problem is logged with the file's name; nothing throws.
