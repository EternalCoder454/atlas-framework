---
title: atlas-framework-core
summary: The small Rust crate every Atlas app uses, with app identity, the settings file, journal logging, os-release and a safe append helper, and no Qt or async runtime.
order: 3
---

`atlas-framework-core` is what every Atlas app shares at the Rust level. It has no Qt and no async runtime, so a light app pays for nothing it does not use.

An app rarely adds it by hand. [atlas-framework-ui](../atlas-framework-ui/index.md) depends on it and re-exports it as `atlas_framework_ui::atlas_framework_core` (and `AppInfo` directly), so a GUI app gets it through that crate. Add it directly only for a command-line tool or a service that has no GUI.

## Add it

```toml
atlas-framework-core = { git = "https://github.com/EternalCoder454/atlas-framework", rev = "7a114a112bd1fff4fe3d6facc81b0a81e5d2db30" }
```

The commit is the one tagged `v1.4.0`. Pin apps to a commit or a release tag, and build with `cargo build --locked`.

## Features

None. Its dependencies are `serde`, `libc` and `log`.

## Pages

| Page | What it covers |
|---|---|
| [AppInfo and app_info!](app-info.md) | Who the running app is: name, ID, version, repository |
| [settings](settings.md) | The app's own `atlas-<app>rc` file in KConfig format |
| [log](log.md) | The `log` macros sent to the systemd journal |
| [osrelease](osrelease.md) | The OS name, version and logo from os-release |
| [fsutil](fsutil.md) | Appending to shared log files safely |

## Crate root

| Name | Kind | Description |
|---|---|---|
| `AppInfo` | struct | Re-exported from the `app` module |
| `app_info!` | macro | Builds an `AppInfo` with the calling crate's version |
| `app`, `fsutil`, `log`, `osrelease`, `settings` | modules | All public |
