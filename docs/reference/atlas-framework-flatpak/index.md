---
title: atlas-framework-flatpak
summary: The Rust crate for Flatpak updates through libflatpak, used by Atlas Updater and the future Atlas Store, with update listing, update runs and a check for newly requested permissions.
order: 6
---

`atlas-framework-flatpak` lists and runs Flatpak updates through libflatpak. It exists for Atlas Updater and the future Atlas Store; an app that does not manage Flatpaks does not need it.

System installations go through flatpak's own system helper, which asks polkit itself, so the Atlas system helper is not involved. The calls block, so run them on a worker thread, never on a UI thread.

## Add it

```toml
atlas-framework-flatpak = { git = "https://github.com/EternalCoder454/atlas-framework", rev = "7a114a112bd1fff4fe3d6facc81b0a81e5d2db30" }
```

The commit is the one tagged `v1.4.0`. Pin apps to a commit or a release tag and build with `cargo build --locked`. It needs `flatpak-devel` to build (the `libflatpak` 0.7 bindings link libflatpak), so a build container needs that package.

## Features

None.

## Pages

| Page | What it covers |
|---|---|
| [Updates](updates.md) | Listing updates, running them, options, progress, outcome and errors |
| [Permissions](permissions.md) | `new_permissions` and the strings that report held-back apps |

## Crate root

| Name | Kind | Description |
|---|---|---|
| `InstallationKind`, `AppUpdate`, `Progress`, `Updated`, `Held`, `Outcome`, `UpdateOptions` | types | See [Updates](updates.md) |
| `Error`, `Result` | types | See [Updates](updates.md#errors-and-text-from-remotes) |
| `list_updates`, `list_updates_with`, `update_all`, `update` | functions | See [Updates](updates.md) |
| `clean`, `clean_to` | functions | Make text from a remote safe to show |
| `new_permissions`, `UNREADABLE`, `UNMATCHED`, `NEW_APP` | function and constants | See [Permissions](permissions.md) |
