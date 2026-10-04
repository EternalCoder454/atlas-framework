//! What every Atlas app uses. Small, with no async runtime and no Qt, so a
//! light app such as Atlas Notepad pays for nothing it doesn't use.
//!
//! - [`AppInfo`] ([`app_info!`]): who the running app is.
//! - [`settings`]: the app's own settings file, `~/.config/atlas-<app>rc`.
//! - [`log`]: the `log` crate's macros, sent to the systemd journal.
//! - [`osrelease`]: the OS name, version and logo, for About pages and reports.
//! - [`fsutil`]: appending to shared logs safely.

pub mod app;
pub mod fsutil;
pub mod log;
pub mod osrelease;
pub mod settings;

pub use app::AppInfo;
