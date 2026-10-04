//! For Atlas system apps (Atlas Updater, Atlas Monitor): crash reports and the
//! AtlasOS state they describe. A light app can use [`crash`] too: only the
//! `polkit` feature brings in D-Bus.
//!
//! - [`crash`]: opt-in crash reports, the only telemetry Atlas apps may have.
//! - [`bootc`]: types for `bootc status --json` and the channel tag rewrite.
//! - [`history`]: the versions this machine has booted.
//! - [`events`]: update and rollback events the system helper records.
//! - `polkit` (feature `polkit`): the authorization check for a root D-Bus
//!   helper's admin actions.
//! - `notify` (feature `notify`): desktop notifications the way KNotification
//!   sends them, for the app's own events.

pub mod bootc;
pub mod crash;
pub mod events;
pub mod history;
#[cfg(feature = "notify")]
pub mod notify;
#[cfg(feature = "polkit")]
pub mod polkit;

// The history and events writers use these.
pub(crate) use atlas_framework_core::fsutil;
