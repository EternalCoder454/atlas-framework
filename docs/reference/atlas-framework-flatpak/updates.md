---
title: Updates
summary: Listing the Flatpak updates available in the system and user installations, running them with progress, and the types that describe the result.
order: 10
---

The crate works on both Flatpak installations at once: every system installation and the user installation. All functions block, so call them from a worker thread. The progress callback runs on the calling thread, from inside the call.

## Example

```rust
use atlas_framework_flatpak as flatpak;

// What is available (refresh = true updates remote summaries and appstream data first, over the network).
for u in flatpak::list_updates(true)? {
    println!("{} {} ({} bytes)", u.name, u.branch, u.download_size);
}

// Run the updates, holding back apps that ask for new permissions.
let opts = flatpak::UpdateOptions { hold_new_permissions: true, ..Default::default() };
let outcome = flatpak::update(&opts, |p| eprintln!("{}: {}%", p.reference, p.percent));
for h in &outcome.held_back {
    println!("{} wants: {:?}", h.app.name, h.permissions);
}
if let Some(e) = outcome.error {
    eprintln!("an update failed: {e}");
}
```

## Functions

| Name | Signature | Description |
|---|---|---|
| `list_updates` | `pub fn list_updates(refresh: bool) -> Result<Vec<AppUpdate>>` | Updates available, apps and runtimes. With `refresh`, appstream data and remote summaries are updated first (network); without it only cached metadata is read. `download_size` is only looked up with `refresh` (the lookup reads the remote's summary, which flatpak downloads when it is not cached), so without it every size is `0`. A remote that fails to refresh is skipped and logged. An installation that fails (an unmounted extra one) does not fail the call: the others are returned, and only when every installation failed is it an error |
| `list_updates_with` | `pub fn list_updates_with(refresh: bool, no_interaction: bool) -> Result<Vec<AppUpdate>>` | `list_updates` for a check nobody is watching: with `no_interaction` nothing asks for a password |
| `list_updates_report` | `pub fn list_updates_report(opts: &ListOptions) -> ListOutcome` | `list_updates` that also reports the installations that failed, and can be cancelled and bounded in time |
| `update_all` | `pub fn update_all(progress: impl FnMut(Progress) + 'static) -> Result<()>` | Updates everything that has an update, one transaction per installation. Returns the first error; the other installations are still updated |
| `update` | `pub fn update(opts: &UpdateOptions, progress: impl FnMut(Progress) + 'static) -> Outcome` | Like `update_all`, with options, and says what changed even when an installation failed part way |
| `update_cancellable` | `pub fn update_cancellable(opts: &UpdateOptions, cancel: Option<&CancelToken>, progress: impl FnMut(Progress) + 'static) -> Outcome` | `update` that stops when the token is cancelled: the running transaction is cancelled, the rest are not started, and `Outcome::error` is `cancelled`. It has no deadline, as an update may rightly take long |

## UpdateOptions

`#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]`. All fields default to `false`.

| Field | Description |
|---|---|
| `no_interaction` | Never ask for a password: a step that would need one fails instead. For updates nobody is watching |
| `hold_new_permissions` | Leave out apps whose new version asks for more permissions than the installed one (new files, devices, sockets, D-Bus names and so on). They are listed in `Outcome::held_back` and wait for an update the user starts. See [Permissions](permissions.md) |
| `check_only` | Only look: `Outcome::held_back` says what `hold_new_permissions` would leave out, and nothing is downloaded or installed. For showing what an update asks for before the user starts it |

## Cancellation and time limits

libflatpak has no timeouts of its own, so a stalled remote would hold the worker for good. `CancelToken` (`Debug, Clone, Default`; `new()`, `cancel()`, `is_cancelled()`) stops a running call from another thread within about 50 ms. `ListOptions` (`Debug, Clone`) has `refresh: bool` and `no_interaction: bool` (both default `false`), `cancel: Option<CancelToken>` (default `None`) and `call_timeout: Option<Duration>` (default `Some(DEFAULT_CALL_TIMEOUT)`, 60 seconds; `None` waits for ever) and `deadline: Option<Duration>` (the whole run, default `None`; calls are cut to what is left of it). A remote that failed to refresh, or timed out sizing a ref, gets no more size lookups in that run (those sizes are `0`). The timeout is per libflatpak call (refreshing a remote, its appstream data, listing, sizing a ref): a call over it fails with `timed out after N s`, is logged and the run goes on with the next.

`ListOutcome` (`Debug, Clone, Default, PartialEq, Eq`) has `updates: Vec<AppUpdate>`, `errors: Vec<InstallationError>` and `checked: usize` (installations checked without error) and `cancelled: bool` (stopped by the token; `into_result()` is then an error); `into_result()` is the updates, or the first error when nothing could be checked. `InstallationError` has `installation: InstallationKind`, `id: String` (flatpak's id for it, empty when listing the system installations itself failed) and `error: Error`. `Error` also derives `Clone, PartialEq, Eq`.

## Types

All derive `Debug, Clone, PartialEq, Eq` unless noted.

| Type | Fields | Description |
|---|---|---|
| `InstallationKind` | `System`, `User` (also `Copy` and `Hash`) | Which installation an update belongs to |
| `AppUpdate` | `id: String` (Flatpak ID, such as `org.kde.kate`), `name: String` (display name from the metadata, else the ID), `branch: String`, `installation: InstallationKind`, `download_size: u64` (bytes, `0` when flatpak cannot tell), `current_version: Option<String>`, `new_version: Option<String>` (not known without downloading metadata: always `None` for now), `is_runtime: bool` | An app or runtime with an update available |
| `Progress` | `installation: InstallationKind`, `reference: String` (such as `app/org.kde.kate/x86_64/stable`), `percent: u32` (0 to 100 for the current operation), `status: String` (flatpak's status line, such as "Downloading") | Progress of the running transaction |
| `Updated` | `id`, `name`, `branch`, `installation`, `is_runtime`, `old_version: Option<String>` (`None` for a new dependency or no version), `new_version: Option<String>` | An app or runtime that was updated, or installed as a new dependency |
| `Held` | `app: AppUpdate`, `permissions: Vec<String>` | An app left out by `hold_new_permissions`, and what it asks for |
| `Outcome` (`Debug` and `Default` only: not `Clone`, `PartialEq` or `Eq`) | `updated: Vec<Updated>`, `held_back: Vec<Held>`, `error: Option<Error>` (the first error; the other installations were still tried) | What `update` did |

## Errors and text from remotes

`pub struct Error(pub String)` implements `Debug`, `Display` and `std::error::Error`, and converts from a glib error. The message is cleaned and cut to 300 characters, because flatpak's messages can carry text from a remote. `pub type Result<T> = std::result::Result<T, Error>`.

Text from a remote (app names, versions, permission items) should be made safe before it is shown or logged:

| Name | Signature | Description |
|---|---|---|
| `clean` | `pub fn clean(s: &str) -> String` | Control characters become spaces, invisible and direction-changing characters (format characters, the soft hyphen, line and paragraph separators, blank-looking letters) go, more than three combining marks in a row are dropped, and the text is trimmed and cut to 80 characters (ending with `…`) |
| `clean_to` | `pub fn clean_to(s: &str, max: usize) -> String` | `clean` with another length limit |
