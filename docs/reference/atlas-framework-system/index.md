---
title: atlas-framework-system
summary: The Rust crate for Atlas system apps, with opt-in crash reports, AtlasOS state (bootc status, boot history, update events), polkit checks for root helpers and desktop notifications.
order: 5
---

`atlas-framework-system` is for apps that work with the AtlasOS system: Atlas Updater, Atlas Monitor and the root helper behind them. It holds opt-in crash reports (the only telemetry an Atlas app may have), the types and files that describe the AtlasOS image state, a polkit check for root D-Bus helpers, and desktop notifications.

A light app can use [`crash`](crash.md) alone: only the `polkit` and `notify` features bring in D-Bus. [atlas-framework-ui](../atlas-framework-ui/index.md) already depends on this crate (without the features) for the crash hooks, so a GUI app gets `crash` without adding anything.

## Add it

```toml
atlas-framework-system = { git = "https://github.com/EternalCoder454/atlas-framework", rev = "7a114a112bd1fff4fe3d6facc81b0a81e5d2db30", features = ["notify"] }
```

The commit is the one tagged `v1.4.0`. Pin apps to a commit or a release tag and build with `cargo build --locked`. Leave out `features` if the app needs neither feature.

## Features

| Feature | Default | What it adds |
|---|---|---|
| `polkit` | off | The [`polkit`](polkit.md) module: the authorization check for a root helper. Pulls in `zbus` and `tokio` |
| `notify` | off | The [`notify`](notify.md) module: desktop notifications over `org.freedesktop.Notifications`. Pulls in `zbus` and `tokio` |

## Pages

| Page | What it covers |
|---|---|
| [crash](crash.md) | Opt-in crash reports: settings, endpoint, scrubbing, collecting, sending |
| [history](history.md) | The versions this machine has booted |
| [bootc](bootc.md) | Types for `bootc status --json` and the channel tag rewrite |
| [events](events.md) | Update and rollback events the system helper records |
| [polkit](polkit.md) | The authorization check for a root D-Bus helper (feature `polkit`) |
| [notify](notify.md) | Desktop notifications the way KNotification sends them (feature `notify`) |
| [On-disk formats](formats.md) | Every file these modules read or write, with paths and fields |

## Crate root

| Name | Kind | Description |
|---|---|---|
| `bootc`, `crash`, `events`, `history` | modules | Always available |
| `notify` | module | Feature `notify` |
| `polkit` | module | Feature `polkit` |
