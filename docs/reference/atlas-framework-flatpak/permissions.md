---
title: Permissions
summary: new_permissions compares two Flatpak metadata files and lists what the new one grants that the old one did not, which is how an update can be held back until the user approves.
order: 20
---

`new_permissions` is what `UpdateOptions::hold_new_permissions` is built on. It compares the metadata (the `metadata` key file) of an installed app with that of its update and lists what the update grants that the installed version did not. An app with a non-empty list is held back and waits for an update the user starts.

## Example

```rust
use atlas_framework_flatpak::new_permissions;

let old = "[Application]\nname=org.example.App\n\n[Context]\nsockets=x11;\n";
let new = "[Application]\nname=org.example.App\n\n[Context]\nsockets=x11;pulseaudio;\nfilesystems=home;\n";
let asked = new_permissions(old, new);
assert!(!asked.is_empty()); // pulseaudio and home access are new
```

## How the comparison reads metadata

- Metadata is parsed with GKeyFile as flatpak parses it, so `\;` stays inside an item.
- `[Context]` lists (`filesystems=home;xdg-download;`) are compared by what they grant in the end: a later `!item` takes an item away. A `filesystems` item counts its access level (`:ro`, then `:rw` or nothing, then `:create`).
- D-Bus policies are compared by level: none, then see, then talk, then own. A level flatpak may learn later counts as the highest.
- Other values (`[Environment]`, `[Policy *]`, newer groups) are compared whole, so any change counts.
- Groups that grant nothing are ignored: what the app is (`[Application]`, apart from a change of runtime), where extensions mount, how it was built, and `[Extra Data]` (which changes with every release of an app such as Spotify or Chrome).
- An update that moves to a different runtime counts, because the runtime's own `[Context]` then applies to the app. A new branch of the same runtime is a routine update.
- A runtime update is read as strictly as an app if it grants anything. A runtime that grants nothing only reports what it would start granting, since runtimes update often, and its environment is left out either way. A runtime update that widens its own `[Context]` or bus policies is held itself.
- Metadata that cannot be parsed is reported as `UNREADABLE`, never as nothing new.

## Items

| Name | Signature or value | Description |
|---|---|---|
| `new_permissions` | `pub fn new_permissions(old: &str, new: &str) -> Vec<String>` | What `new` grants that `old` does not, as `"group: key=item"` strings. Empty when the update asks for nothing new |
| `UNREADABLE` | `"metadata that can't be read"` | Reported for metadata that cannot be read |
| `UNMATCHED` | `"a change that can't be put down to one app"` | What `hold_new_permissions` reports for everything in an update run when something in it asks for new permissions and cannot be put down to one app |
| `NEW_APP` | `"an app that wasn't installed"` | What `hold_new_permissions` reports for an app the update would install rather than update |
