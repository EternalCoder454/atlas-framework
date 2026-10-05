//! Flatpak updates through libflatpak: for Atlas Updater and the future Atlas Store.
//!
//! System installations go through flatpak's own system helper, which asks
//! polkit itself; the Atlas system helper is not involved. The calls block, so
//! run them on a worker thread, not on a UI thread.

use std::cell::RefCell;
use std::fmt;
use std::rc::Rc;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use libflatpak::gio::Cancellable;
use libflatpak::glib::{KeyFile, KeyFileFlags};
use libflatpak::prelude::*;
use libflatpak::{
    Installation, InstalledRef, RefKind, Transaction, TransactionOperation,
    TransactionOperationType,
};

/// Which installation an update belongs to.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum InstallationKind {
    System,
    User,
}

/// An app or runtime with an update available.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppUpdate {
    /// Flatpak ID, e.g. `org.kde.kate`.
    pub id: String,
    /// Display name from the app's metadata; the ID when there is none.
    pub name: String,
    pub branch: String,
    pub installation: InstallationKind,
    /// Bytes to download; 0 when flatpak cannot tell.
    pub download_size: u64,
    pub current_version: Option<String>,
    /// Not known without downloading metadata; always `None` for now.
    pub new_version: Option<String>,
    /// True for runtimes, false for apps.
    pub is_runtime: bool,
}

/// Progress of the running transaction.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Progress {
    pub installation: InstallationKind,
    /// The ref being updated, e.g. `app/org.kde.kate/x86_64/stable`.
    pub reference: String,
    /// 0 to 100 for the current operation.
    pub percent: u32,
    /// Flatpak's status line, e.g. "Downloading".
    pub status: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error(pub String);

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for Error {}

impl From<libflatpak::glib::Error> for Error {
    fn from(e: libflatpak::glib::Error) -> Self {
        // Flatpak's messages can carry text from a remote.
        Error(clean_to(e.message(), ERROR_MAX))
    }
}

pub type Result<T> = std::result::Result<T, Error>;

/// A flag that stops a running call from another thread: clone it, hand the
/// clone to a `*_cancellable` function or [`ListOptions`], and call
/// [`CancelToken::cancel`] from anywhere. A cancelled call returns an error
/// that says so (or what it has done so far, for [`list_updates_report`]).
#[derive(Debug, Clone)]
pub struct CancelToken(Cancellable);

impl CancelToken {
    pub fn new() -> CancelToken {
        CancelToken(Cancellable::new())
    }

    /// Stop the calls using this token. Takes effect within about 50 ms.
    pub fn cancel(&self) {
        self.0.cancel();
    }

    pub fn is_cancelled(&self) -> bool {
        self.0.is_cancelled()
    }
}

impl Default for CancelToken {
    fn default() -> Self {
        CancelToken::new()
    }
}

/// How long one libflatpak call that may use the network (refreshing a
/// remote, its appstream data, sizing a ref) may take unless
/// [`ListOptions::call_timeout`] says otherwise.
pub const DEFAULT_CALL_TIMEOUT: Duration = Duration::from_secs(60);

/// How often a running call looks at its [`CancelToken`].
const CANCEL_POLL: Duration = Duration::from_millis(50);

/// Runs `f` with a fresh `Cancellable` that a watcher thread cancels when
/// `cancel` is cancelled or `limit` has passed. The thread ends when the
/// call returns. libflatpak has no timeouts of its own: this is the only
/// way a stalled remote does not hold the worker for good.
fn guarded<T>(
    cancel: Option<&CancelToken>,
    limit: Option<Duration>,
    f: impl FnOnce(&Cancellable) -> std::result::Result<T, libflatpak::glib::Error>,
) -> Result<T> {
    if cancel.is_some_and(CancelToken::is_cancelled) {
        return Err(Error("cancelled".into()));
    }
    let c = Cancellable::new();
    let expired = Arc::new(AtomicBool::new(false));
    // Dropping the sender (when this function returns) ends the watcher.
    let mut _done = None;
    if cancel.is_some() || limit.is_some() {
        let (tx, rx) = mpsc::channel::<()>();
        let (c, token, expired) = (c.clone(), cancel.cloned(), expired.clone());
        let end = limit.map(|l| Instant::now() + l);
        let spawned = std::thread::Builder::new()
            .name("flatpak-watch".into())
            .spawn(move || {
                while let Err(mpsc::RecvTimeoutError::Timeout) = rx.recv_timeout(CANCEL_POLL) {
                    if token.as_ref().is_some_and(CancelToken::is_cancelled) {
                        c.cancel();
                        return;
                    }
                    if end.is_some_and(|e| Instant::now() >= e) {
                        expired.store(true, Ordering::SeqCst);
                        c.cancel();
                        return;
                    }
                }
            });
        match spawned {
            Ok(_) => _done = Some(tx),
            Err(e) => log::warn!("flatpak: no watcher thread, this call cannot be stopped: {e}"),
        }
    }
    f(&c).map_err(|e| {
        // Only an error that really is "cancelled" is put down to our stop.
        if !e.matches(libflatpak::gio::IOErrorEnum::Cancelled) {
            e.into()
        } else if expired.load(Ordering::SeqCst) {
            Error(format!(
                "timed out after {} s",
                limit.map_or(0, |l| l.as_secs())
            ))
        } else if cancel.is_some_and(CancelToken::is_cancelled) {
            Error("cancelled".into())
        } else {
            e.into()
        }
    })
}

/// The installations that could be opened, and what went wrong with the
/// others (one failing must not hide the rest).
/// `no_interaction`: calls through flatpak's system helper (refreshing a
/// system remote, say) fail rather than raise a password prompt.
fn installations(
    no_interaction: bool,
    cancel: Option<&CancelToken>,
) -> (
    Vec<(InstallationKind, Installation)>,
    Vec<InstallationError>,
) {
    let mut v = Vec::new();
    let mut errors = Vec::new();
    match guarded(cancel, Some(DEFAULT_CALL_TIMEOUT), |c| {
        libflatpak::functions::system_installations(Some(c))
    }) {
        Ok(list) => v.extend(list.into_iter().map(|i| (InstallationKind::System, i))),
        Err(error) => errors.push(InstallationError {
            installation: InstallationKind::System,
            id: String::new(),
            error,
        }),
    }
    match guarded(cancel, Some(DEFAULT_CALL_TIMEOUT), |c| {
        Installation::new_user(Some(c))
    }) {
        Ok(i) => v.push((InstallationKind::User, i)),
        Err(error) => errors.push(InstallationError {
            installation: InstallationKind::User,
            id: "user".into(),
            error,
        }),
    }
    for (_, i) in &v {
        i.set_no_interaction(no_interaction);
    }
    (v, errors)
}

/// The installation's id (`default`, `user`, an extra one's name).
fn inst_id(inst: &Installation) -> String {
    inst.id().map(|s| s.to_string()).unwrap_or_default()
}

/// The longest error text passed on.
const ERROR_MAX: usize = 300;

/// Characters that are invisible or reorder text: format characters (Cf:
/// direction marks and isolates, zero-width ones, the soft hyphen, tags)
/// and the line and paragraph separators (Zl, Zp).
fn hidden(c: char) -> bool {
    matches!(c,
        '\u{00AD}' | '\u{0600}'..='\u{0605}' | '\u{061C}' | '\u{06DD}' | '\u{070F}'
        | '\u{0890}'..='\u{0891}' | '\u{08E2}' | '\u{180E}' | '\u{200B}'..='\u{200F}'
        | '\u{2028}'..='\u{202E}' | '\u{2060}'..='\u{2064}' | '\u{2066}'..='\u{206F}'
        | '\u{FEFF}' | '\u{FFF9}'..='\u{FFFB}' | '\u{110BD}' | '\u{110CD}'
        | '\u{13430}'..='\u{1343F}' | '\u{1BCA0}'..='\u{1BCA3}' | '\u{1D173}'..='\u{1D17A}'
        | '\u{E0001}' | '\u{E0020}'..='\u{E007F}'
        // Blank-looking letters and the grapheme joiner.
        | '\u{034F}' | '\u{115F}' | '\u{1160}' | '\u{17B4}' | '\u{17B5}' | '\u{2800}'
        | '\u{3164}' | '\u{FFA0}')
}

/// Combining marks: a few in a row make an accent, dozens make a smear.
fn combining(c: char) -> bool {
    matches!(c,
        '\u{0300}'..='\u{036F}' | '\u{0483}'..='\u{0489}' | '\u{0591}'..='\u{05C7}'
        | '\u{0610}'..='\u{061A}' | '\u{064B}'..='\u{065F}' | '\u{0670}'
        | '\u{06D6}'..='\u{06ED}' | '\u{0900}'..='\u{0903}' | '\u{093A}'..='\u{094F}'
        | '\u{0E31}' | '\u{0E34}'..='\u{0E3A}' | '\u{0E47}'..='\u{0E4E}'
        | '\u{1AB0}'..='\u{1AFF}' | '\u{1DC0}'..='\u{1DFF}' | '\u{20D0}'..='\u{20FF}'
        | '\u{FE20}'..='\u{FE2F}')
}

/// Text from a remote (app names, versions, permission items) made safe to
/// show and log: control characters become spaces, invisible and
/// direction-changing ones go, at most 80 characters.
pub fn clean(s: &str) -> String {
    clean_to(s, 80)
}

/// [`clean`] with another length limit.
pub fn clean_to(s: &str, max: usize) -> String {
    let mut marks = 0;
    let s: String = s
        .chars()
        .filter(|c| !hidden(*c))
        .filter(|c| {
            marks = if combining(*c) { marks + 1 } else { 0 };
            marks <= 3
        })
        .map(|c| if c.is_control() { ' ' } else { c })
        .collect();
    let s = s.trim();
    if s.chars().count() > max {
        let mut t: String = s.chars().take(max.saturating_sub(1)).collect();
        t.push('…');
        t
    } else {
        s.to_string()
    }
}

fn clean_opt(s: Option<impl AsRef<str>>) -> Option<String> {
    s.map(|s| clean(s.as_ref())).filter(|s| !s.is_empty())
}

/// Updates available in the system and user installations, apps and
/// runtimes. With `refresh`, appstream data and remote summaries are updated
/// first (network) and download sizes are looked up; without it only cached
/// metadata is read and `download_size` is `0`. A remote that fails to
/// refresh is skipped (and logged). An installation that fails does not fail
/// the call: the others are returned; only when every installation failed is
/// it an error, and a run that was cancelled is an error too. The result can
/// therefore be partial: failures are logged at warn level, and
/// [`list_updates_report`] returns them.
pub fn list_updates(refresh: bool) -> Result<Vec<AppUpdate>> {
    list_updates_with(refresh, false)
}

/// [`list_updates`] for a check nobody is watching: with `no_interaction`
/// nothing asks for a password (see [`UpdateOptions::no_interaction`]).
pub fn list_updates_with(refresh: bool, no_interaction: bool) -> Result<Vec<AppUpdate>> {
    let out = list_updates_report(&ListOptions {
        refresh,
        no_interaction,
        ..ListOptions::default()
    });
    if !out.errors.is_empty() {
        log::warn!(
            "flatpak: {} installation(s) could not be checked; the list is partial",
            out.errors.len()
        );
    }
    out.into_result()
}

/// How [`list_updates_report`] runs.
#[derive(Debug, Clone)]
pub struct ListOptions {
    /// Update remote summaries and appstream data first, and look up
    /// download sizes (network). Default `false`.
    pub refresh: bool,
    /// Never ask for a password. Default `false`.
    pub no_interaction: bool,
    /// Stops the run when cancelled. Default none.
    pub cancel: Option<CancelToken>,
    /// The longest one libflatpak call may take (refreshing a remote,
    /// listing, sizing a ref); a call over it fails and the run goes on with
    /// the next. Default [`DEFAULT_CALL_TIMEOUT`]; `None` waits for ever.
    pub call_timeout: Option<Duration>,
    /// The longest the whole run may take. When it has passed, the call in
    /// progress is cut short and the rest is not started: the installation
    /// in progress is reported as an error. Default `None`.
    pub deadline: Option<Duration>,
}

impl Default for ListOptions {
    fn default() -> Self {
        ListOptions {
            refresh: false,
            no_interaction: false,
            cancel: None,
            call_timeout: Some(DEFAULT_CALL_TIMEOUT),
            deadline: None,
        }
    }
}

/// An installation that could not be checked.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstallationError {
    pub installation: InstallationKind,
    /// flatpak's id for it (`default`, `user`, an extra one's name); empty
    /// when the list of system installations itself failed.
    pub id: String,
    pub error: Error,
}

/// What [`list_updates_report`] found.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ListOutcome {
    /// Updates from every installation that could be checked.
    pub updates: Vec<AppUpdate>,
    /// The installations that could not (an unmounted extra one, say), and a
    /// run stopped by its cancel token.
    pub errors: Vec<InstallationError>,
    /// How many installations were checked without error.
    pub checked: usize,
    /// The run was stopped by its cancel token.
    pub cancelled: bool,
}

impl ListOutcome {
    /// The updates, unless the run was cancelled, or nothing could be checked
    /// at all: then the first error (`cancelled` for a cancelled run).
    pub fn into_result(self) -> Result<Vec<AppUpdate>> {
        if self.cancelled {
            return Err(Error("cancelled".into()));
        }
        match self.errors.into_iter().next() {
            Some(e) if self.checked == 0 => Err(e.error),
            _ => Ok(self.updates),
        }
    }
}

/// [`list_updates`] that says which installations failed, and can be
/// cancelled and bounded in time (see [`ListOptions`]).
pub fn list_updates_report(opts: &ListOptions) -> ListOutcome {
    let cancel = opts.cancel.as_ref();
    let end = opts.deadline.map(|d| Instant::now() + d);
    let arch = libflatpak::functions::default_arch();
    let (insts, errors) = installations(opts.no_interaction, cancel);
    let mut out = ListOutcome {
        errors,
        ..ListOutcome::default()
    };
    for (kind, inst) in insts {
        let id = inst_id(&inst);
        match list_installation(&inst, kind, &id, opts, arch.as_deref(), end) {
            Ok(mut v) => {
                out.updates.append(&mut v);
                out.checked += 1;
            }
            Err(error) => {
                log::warn!("flatpak: cannot check installation {id}: {error}");
                out.errors.push(InstallationError {
                    installation: kind,
                    id,
                    error,
                });
            }
        }
        if cancel.is_some_and(CancelToken::is_cancelled) {
            out.cancelled = true;
            break;
        }
    }
    out
}

/// The limit for the next call: the per-call one, cut to what is left of the
/// overall deadline; `None` when that has passed.
fn next_limit(call: Option<Duration>, end: Option<Instant>) -> Option<Option<Duration>> {
    let Some(end) = end else {
        return Some(call);
    };
    let left = end
        .checked_duration_since(Instant::now())
        .filter(|d| !d.is_zero())?;
    Some(Some(call.map_or(left, |c| c.min(left))))
}

fn list_installation(
    inst: &Installation,
    kind: InstallationKind,
    id: &str,
    opts: &ListOptions,
    arch: Option<&str>,
    end: Option<Instant>,
) -> Result<Vec<AppUpdate>> {
    let cancel = opts.cancel.as_ref();
    let call = opts.call_timeout;
    let over = || Error("the time limit for the whole check has passed".into());
    // Remotes that failed to refresh or to size a ref in this run: asking
    // again would only wait for the same timeout once per ref.
    let mut dead: std::collections::HashSet<String> = std::collections::HashSet::new();
    if opts.refresh {
        let limit = next_limit(call, end).ok_or_else(over)?;
        for remote in guarded(cancel, limit, |c| inst.list_remotes(Some(c)))? {
            let Some(name) = remote.name() else {
                log::warn!("flatpak: installation {id} has a remote without a name; skipped");
                continue;
            };
            let limit = next_limit(call, end).ok_or_else(over)?;
            if let Err(e) = guarded(cancel, limit, |c| inst.update_remote_sync(&name, Some(c))) {
                log::warn!(
                    "flatpak: cannot refresh remote {name} in {id}: {e}; its sizes are skipped"
                );
                dead.insert(name.to_string());
            }
            if cancel.is_some_and(CancelToken::is_cancelled) {
                return Err(Error("cancelled".into()));
            }
            let limit = next_limit(call, end).ok_or_else(over)?;
            if let Err(e) = guarded(cancel, limit, |c| {
                inst.update_appstream_sync(&name, arch, Some(c))
            }) {
                log::warn!("flatpak: cannot refresh the appstream data of {name} in {id}: {e}");
            }
            if cancel.is_some_and(CancelToken::is_cancelled) {
                return Err(Error("cancelled".into()));
            }
        }
    }
    let limit = next_limit(call, end).ok_or_else(over)?;
    let refs = guarded(cancel, limit, |c| {
        inst.list_installed_refs_for_update(Some(c))
    })?;
    let mut out = Vec::with_capacity(refs.len());
    for r in &refs {
        if cancel.is_some_and(CancelToken::is_cancelled) {
            return Err(Error("cancelled".into()));
        }
        // Past the deadline the sizes are dropped, the list is kept.
        let limit = if opts.refresh {
            next_limit(call, end)
        } else {
            None
        };
        out.push(to_update(inst, kind, r, limit, cancel, &mut dead));
    }
    Ok(out)
}

/// `size_limit`: `Some` looks up the download size with that limit. `fetch_remote_size_sync` reads the
/// remote's summary, which flatpak downloads when it is not cached, so it
/// is only asked after a refresh (then the summary is cached and the lookup
/// is quick); without one the size is `0`.
fn to_update(
    inst: &Installation,
    kind: InstallationKind,
    r: &InstalledRef,
    size_limit: Option<Option<Duration>>,
    cancel: Option<&CancelToken>,
    dead: &mut std::collections::HashSet<String>,
) -> AppUpdate {
    let id = r.name().map(|s| s.to_string()).unwrap_or_default();
    let name = clean_opt(r.appdata_name()).unwrap_or_else(|| id.clone());
    let origin = r.origin().map(|o| o.to_string());
    let download_size = match (size_limit, origin) {
        (Some(limit), Some(o)) if !dead.contains(&o) => {
            match guarded(cancel, limit, |c| {
                inst.fetch_remote_size_sync(&o, r, Some(c))
            }) {
                Ok((download, _installed)) => download,
                Err(e) => {
                    log::warn!("flatpak: no size for {id}: {e}");
                    if e.0.starts_with("timed out") {
                        log::warn!("flatpak: remote {o} timed out; no more sizes from it");
                        dead.insert(o);
                    }
                    0
                }
            }
        }
        _ => 0,
    };
    AppUpdate {
        name,
        branch: r.branch().map(|s| s.to_string()).unwrap_or_default(),
        installation: kind,
        download_size,
        current_version: clean_opt(r.appdata_version()),
        new_version: None,
        is_runtime: r.kind() == RefKind::Runtime,
        id,
    }
}

/// Update everything that has an update: one transaction per installation.
/// `progress` is called as operations advance (flatpak calls it from inside
/// `update_all`, on the calling thread). Returns the first error; the other
/// installations are still updated.
pub fn update_all(progress: impl FnMut(Progress) + 'static) -> Result<()> {
    match update(&UpdateOptions::default(), progress).error {
        Some(e) => Err(e),
        None => Ok(()),
    }
}

/// How [`update`] runs.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct UpdateOptions {
    /// Never ask for a password: a step that would need one fails instead.
    /// For updates nobody is watching.
    pub no_interaction: bool,
    /// Leave out apps whose new version asks for more permissions than the
    /// installed one (new files, devices, sockets, D-Bus names...). They are
    /// listed in [`Outcome::held_back`] and wait for an update the user starts.
    pub hold_new_permissions: bool,
    /// Only look: [`Outcome::held_back`] says what `hold_new_permissions`
    /// would leave out, and nothing is downloaded or installed (each run
    /// stops before it would start). For showing what an update asks for
    /// before the user starts it.
    pub check_only: bool,
}

/// An app or runtime that was updated (or installed as a new dependency).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Updated {
    pub id: String,
    /// Display name; the ID when there is none.
    pub name: String,
    pub branch: String,
    pub installation: InstallationKind,
    pub is_runtime: bool,
    /// The version before; `None` for a new dependency or no version.
    pub old_version: Option<String>,
    pub new_version: Option<String>,
}

/// An app left out by [`UpdateOptions::hold_new_permissions`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Held {
    pub app: AppUpdate,
    /// What it asks for, from [`new_permissions`].
    pub permissions: Vec<String>,
}

/// What [`update`] did.
#[derive(Debug, Default)]
pub struct Outcome {
    pub updated: Vec<Updated>,
    /// Apps left out because they ask for new permissions.
    pub held_back: Vec<Held>,
    /// The first error; the other installations were still tried.
    pub error: Option<Error>,
}

/// Like [`update_all`], with options, and says what changed even when an
/// installation failed part way.
pub fn update(opts: &UpdateOptions, progress: impl FnMut(Progress) + 'static) -> Outcome {
    update_cancellable(opts, None, progress)
}

/// [`update`] that stops when `cancel` is cancelled: the running transaction
/// is cancelled, the rest are not started, and `Outcome::error` says so.
/// There is no deadline: an update may rightly take long.
pub fn update_cancellable(
    opts: &UpdateOptions,
    cancel: Option<&CancelToken>,
    progress: impl FnMut(Progress) + 'static,
) -> Outcome {
    let progress: Rc<RefCell<dyn FnMut(Progress)>> = Rc::new(RefCell::new(progress));
    let mut out = Outcome::default();
    let (insts, errors) = installations(opts.no_interaction, cancel);
    // An installation that cannot be opened does not stop the others.
    for e in errors {
        out.error.get_or_insert(e.error);
    }
    for (kind, inst) in insts {
        if cancel.is_some_and(CancelToken::is_cancelled) {
            out.error.get_or_insert(Error("cancelled".into()));
            break;
        }
        if let Err(e) = update_installation(&inst, kind, opts, cancel, &progress, &mut out) {
            out.error.get_or_insert(e);
        }
    }
    out
}

/// A ref left out, and the permissions it asks for.
type HeldRef = (String, Vec<String>);

fn update_installation(
    inst: &Installation,
    kind: InstallationKind,
    opts: &UpdateOptions,
    cancel: Option<&CancelToken>,
    progress: &Rc<RefCell<dyn FnMut(Progress)>>,
    out: &mut Outcome,
) -> Result<()> {
    let none = None::<&Cancellable>;
    let refs = guarded(cancel, None, |c| {
        inst.list_installed_refs_for_update(Some(c))
    })?;
    // What each ref was before, by its full ref string.
    let mut before = std::collections::HashMap::new();
    for r in &refs {
        if let Some(spec) = r.format_ref() {
            before.insert(spec.to_string(), to_update_offline(kind, r));
        }
    }
    // Ref → the permissions it asks for.
    let mut held: Vec<HeldRef> = Vec::new();
    let mut error = None;
    // Each pass that finds an app asking for new permissions is aborted
    // before anything is downloaded, and run again without it.
    for _ in 0..=refs.len() {
        let wanted: Vec<String> = before
            .keys()
            .filter(|s| !held.iter().any(|(h, _)| h == *s))
            .cloned()
            .collect();
        if wanted.is_empty() {
            break;
        }
        // A failure here still reports what earlier passes held back.
        let made = (|| -> Result<Transaction> {
            let tx = Transaction::for_installation(inst, none)?;
            tx.set_no_interaction(opts.no_interaction);
            // A user app's runtime may be in the system installation; the
            // flatpak command adds these too.
            tx.add_default_dependency_sources();
            for spec in &wanted {
                tx.add_update(spec, &[], None)?;
            }
            Ok(tx)
        })();
        let tx = match made {
            Ok(tx) => tx,
            Err(e) => {
                error = Some(e);
                break;
            }
        };
        // Updates asked for in this pass → what they ask for. An operation
        // flatpak added itself is put down to the update that brought it.
        let found: Rc<RefCell<Vec<HeldRef>>> = Rc::default();
        // Whether the check ran (so a check-only run stopped on purpose).
        let checked: Rc<std::cell::Cell<bool>> = Rc::default();
        if opts.hold_new_permissions || opts.check_only {
            let check_only = opts.check_only;
            let found = found.clone();
            let checked = checked.clone();
            let asked: std::collections::HashSet<String> = wanted.iter().cloned().collect();
            tx.connect_ready_pre_auth(move |tx| {
                checked.set(true);
                let ops = tx.operations();
                for op in &ops {
                    let Some(r) = op.get_ref().map(|r| r.to_string()) else {
                        continue;
                    };
                    let app = r.starts_with("app/");
                    let more = match (op.operation_type(), app) {
                        // An app installed as part of an update (an
                        // end-of-life rename) is new: it waits for the user.
                        (TransactionOperationType::Install, true) => vec![NEW_APP.to_string()],
                        (TransactionOperationType::Update, true) => {
                            // Metadata we can't read counts as new permissions.
                            match (op.old_metadata(), op.metadata()) {
                                (Some(old), Some(new)) => key_file_permissions(&old, &new),
                                _ => vec![UNREADABLE.to_string()],
                            }
                        }
                        // A runtime's own permissions apply to its apps. A
                        // runtime installed for an update (a new branch an
                        // app moved to) is measured against none at all.
                        (t, false) if r.starts_with("runtime/") => {
                            let old = match t {
                                TransactionOperationType::Update => op.old_metadata(),
                                TransactionOperationType::Install => None,
                                _ => continue,
                            };
                            match op.metadata() {
                                Some(new) => runtime_permissions(old.as_ref(), &new),
                                None => continue,
                            }
                        }
                        _ => continue,
                    };
                    if more.is_empty() {
                        continue;
                    }
                    let mut owners: Vec<String> = Vec::new();
                    if asked.contains(&r) {
                        owners.push(r.clone());
                    } else {
                        let ours = |o: &TransactionOperation| {
                            o.get_ref()
                                .map(|x| x.to_string())
                                .filter(|x| asked.contains(x))
                        };
                        owners.extend(op.related_to_ops().iter().filter_map(ours));
                        if owners.is_empty() {
                            // A rename uninstalls the app it replaces.
                            owners.extend(
                                ops.iter()
                                    .filter(|o| {
                                        o.operation_type() == TransactionOperationType::Uninstall
                                    })
                                    .filter_map(ours)
                                    .filter(|x| x.starts_with("app/")),
                            );
                        }
                        if owners.is_empty() {
                            // Nobody to put it down to: the pass is held below.
                            owners.push(r.clone());
                        }
                    }
                    let mut found = found.borrow_mut();
                    for o in owners {
                        found.push((o, more.clone()));
                    }
                }
                !check_only && found.borrow().is_empty()
            });
        }
        if opts.check_only {
            // A second stop before any operation runs, should a flatpak ever
            // not emit ready-pre-auth (the run then reports an error).
            tx.connect_ready(|_| false);
        }
        let done: Rc<RefCell<Vec<String>>> = Rc::default();
        {
            let done = done.clone();
            tx.connect_operation_done(move |_tx, op, _commit, result| {
                let t = op.operation_type();
                // gir names FLATPAK_TRANSACTION_RESULT_NO_CHANGE "CHANGE".
                let unchanged = result.contains(libflatpak::TransactionResult::CHANGE);
                if (t == TransactionOperationType::Update || t == TransactionOperationType::Install)
                    && !unchanged
                    && let Some(r) = op.get_ref()
                {
                    done.borrow_mut().push(r.to_string());
                }
            });
        }
        // One app that fails (a removed remote, a full disk) must not stop
        // the others: note the first error and go on.
        let failed: Rc<RefCell<Option<Error>>> = Rc::default();
        {
            let failed = failed.clone();
            tx.connect_operation_error(move |_tx, op, err, _details| {
                let what = op.get_ref().map(|s| s.to_string()).unwrap_or_default();
                failed.borrow_mut().get_or_insert_with(|| {
                    Error(clean_to(&format!("{what}: {}", err.message()), ERROR_MAX))
                });
                true
            });
        }
        let cb = progress.clone();
        tx.connect_new_operation(move |_tx, op, prog| {
            let reference = op.get_ref().map(|s| s.to_string()).unwrap_or_default();
            let cb = cb.clone();
            prog.connect_changed(move |p| {
                (cb.borrow_mut())(Progress {
                    installation: kind,
                    reference: reference.clone(),
                    percent: p.progress().clamp(0, 100) as u32,
                    status: p.status().map(|s| s.to_string()).unwrap_or_default(),
                });
            });
        });
        let res = guarded(cancel, None, |c| tx.run(Some(c)));
        for spec in done.borrow().iter() {
            out.updated
                .push(updated(inst, kind, spec, before.get(spec)));
        }
        // One entry per app, with everything it asks for.
        let mut newly: Vec<HeldRef> = Vec::new();
        for (s, more) in found.borrow().iter() {
            if !before.contains_key(s) || held.iter().any(|(h, _)| h == s) {
                continue;
            }
            match newly.iter_mut().find(|(n, _)| n == s) {
                Some((_, all)) => {
                    for m in more {
                        if !all.contains(m) {
                            all.push(m.clone());
                        }
                    }
                }
                None => newly.push((s.clone(), more.clone())),
            }
        }
        if newly.is_empty() && !found.borrow().is_empty() {
            // Something asks for new permissions and can't be put down to
            // one update: hold this pass's apps rather than install it
            // unchecked or stop every update. Runtimes go on, unless only
            // runtimes are left.
            let apps: Vec<&String> = wanted.iter().filter(|s| s.starts_with("app/")).collect();
            let hold = if apps.is_empty() {
                wanted.iter().collect()
            } else {
                apps
            };
            newly = hold
                .into_iter()
                .map(|s| (s.clone(), vec![UNMATCHED.to_string()]))
                .collect();
        }
        if opts.check_only {
            // Stopped on purpose before anything ran: one pass saw every
            // operation, and its "aborted" is not an error. A run that
            // failed before the check (no network, say) is.
            held.extend(newly);
            if !checked.get()
                && let Err(e) = res
            {
                error = Some(e);
            }
            break;
        }
        if !newly.is_empty() {
            // Aborted on purpose before anything ran: try the rest.
            held.extend(newly);
            continue;
        }
        if let Some(e) = failed.borrow_mut().take() {
            error = Some(e);
        } else if let Err(e) = res {
            error = Some(e);
        }
        break;
    }
    for (spec, permissions) in held {
        if let Some(u) = before.get(&spec) {
            out.held_back.push(Held {
                app: u.clone(),
                permissions,
            });
        }
    }
    error.map_or(Ok(()), Err)
}

/// [`AppUpdate`] without the download size (which needs the network).
fn to_update_offline(kind: InstallationKind, r: &InstalledRef) -> AppUpdate {
    let id = r.name().map(|s| s.to_string()).unwrap_or_default();
    AppUpdate {
        name: clean_opt(r.appdata_name()).unwrap_or_else(|| id.clone()),
        branch: r.branch().map(|s| s.to_string()).unwrap_or_default(),
        installation: kind,
        download_size: 0,
        current_version: clean_opt(r.appdata_version()),
        new_version: None,
        is_runtime: r.kind() == RefKind::Runtime,
        id,
    }
}

/// `app/org.kde.kate/x86_64/stable` → kind, name, arch, branch.
fn split_ref(spec: &str) -> Option<(RefKind, &str, &str, &str)> {
    let mut it = spec.splitn(4, '/');
    let kind = match it.next()? {
        "app" => RefKind::App,
        "runtime" => RefKind::Runtime,
        _ => return None,
    };
    Some((kind, it.next()?, it.next()?, it.next()?))
}

fn updated(
    inst: &Installation,
    kind: InstallationKind,
    spec: &str,
    before: Option<&AppUpdate>,
) -> Updated {
    let parts = split_ref(spec);
    let now = parts.and_then(|(k, name, arch, branch)| {
        inst.installed_ref(k, name, Some(arch), Some(branch), None::<&Cancellable>)
            .ok()
    });
    let id = parts
        .map(|p| p.1.to_string())
        .unwrap_or_else(|| spec.to_string());
    let name = before
        .map(|b| b.name.clone())
        .or_else(|| now.as_ref().and_then(|r| clean_opt(r.appdata_name())))
        .unwrap_or_else(|| id.clone());
    Updated {
        name,
        branch: parts.map(|p| p.3.to_string()).unwrap_or_default(),
        installation: kind,
        is_runtime: parts.is_some_and(|p| p.0 == RefKind::Runtime),
        old_version: before.and_then(|b| b.current_version.clone()),
        new_version: now.and_then(|r| clean_opt(r.appdata_version())),
        id,
    }
}

/// What [`new_permissions`] reports for metadata it cannot read.
pub const UNREADABLE: &str = "metadata that can't be read";
/// What [`UpdateOptions::hold_new_permissions`] reports for everything in
/// an update run when something in it asks for new permissions and can't be
/// put down to one app.
pub const UNMATCHED: &str = "a change that can't be put down to one app";
/// What [`UpdateOptions::hold_new_permissions`] reports for an app the
/// update would install rather than update.
pub const NEW_APP: &str = "an app that wasn't installed";

/// Groups of a Flatpak metadata file that grant nothing: what the app is,
/// where extensions mount, how it was built, what it downloads when it is
/// installed (`[Extra Data]`, which changes with every release of an app
/// like Spotify or Chrome). Every other group (Context, bus
/// policies, Environment, USB devices, `Policy *`, anything newer) counts.
/// `[Application]` is checked for a change of runtime separately.
fn harmless_group(g: &str) -> bool {
    matches!(
        g,
        "Application" | "Runtime" | "ExtensionOf" | "Build" | "Extra Data"
    ) || g.starts_with("Extension ")
}

/// Whether a runtime's metadata has a group that could grant something:
/// anything but what it is, where extensions mount and its environment
/// (Flathub's and Fedora's runtimes have nothing else).
fn grants_any(k: &KeyFile) -> bool {
    k.groups()
        .iter()
        .any(|g| !harmless_group(g) && g.as_str() != "Environment")
}

/// What a runtime update asks for. `old` is `None` for a runtime installed
/// for the update, or one whose installed metadata can't be found: it is
/// then measured against nothing. A runtime that grants anything is read as
/// strictly as an app; one that grants nothing only reports what it would
/// start granting, as runtimes update often and routinely. Its environment
/// is left out either way.
fn runtime_permissions(old: Option<&KeyFile>, new: &KeyFile) -> Vec<String> {
    let strict = grants_any(new);
    let nothing;
    let old = match old {
        Some(old) => old,
        None if strict => {
            nothing = KeyFile::new();
            &nothing
        }
        None => return Vec::new(),
    };
    key_file_permissions(old, new)
        .into_iter()
        .filter(|p| !p.starts_with("Environment: "))
        .filter(|p| strict || p != UNREADABLE)
        .collect()
}

/// A metadata value, the way flatpak reads it.
#[derive(Debug, PartialEq)]
enum Value {
    /// A `[Context]` list folded in order (`x` grants, a later `!x` takes
    /// it away): what is granted in the end, by name → (how much, as
    /// written).
    Granted(std::collections::BTreeMap<String, (u8, String)>),
    /// A D-Bus policy: its level and text.
    Level(u8, String),
    /// Anything else (`[Environment]`, `[Policy *]`, newer groups): the
    /// whole value, compared as is.
    Text(String),
    /// GKeyFile could not read it.
    Unreadable,
}

/// A `filesystems` item as flatpak resolves it: the path without trailing
/// or doubled slashes, and how much access (`:ro` 1, `:rw` or nothing 2,
/// `:create` 3). `None` for what we don't read the way flatpak does: a
/// `:reset`, or a backslash escape.
fn fs_item(i: &str) -> Option<(String, u8)> {
    if i.contains('\\') {
        return None;
    }
    let (path, rank) = match i.rsplit_once(':') {
        Some((p, "ro")) => (p, 1),
        Some((p, "rw")) => (p, 2),
        Some((p, "create")) => (p, 3),
        Some((_, "reset")) => return None,
        _ => (i, 2),
    };
    let mut p = path.to_string();
    while p.contains("//") {
        p = p.replace("//", "/");
    }
    let p = p.trim_end_matches('/');
    Some((if p.is_empty() { "/" } else { p }.to_string(), rank))
}

/// A `[Context]` list folded in order. `None` when an item could be read
/// more than one way (the caller then counts it as unreadable): only a
/// plain `!item` takes a grant away.
fn granted<'a>(
    key: &str,
    items: impl Iterator<Item = &'a str>,
) -> Option<std::collections::BTreeMap<String, (u8, String)>> {
    let fs = key == "filesystems";
    let mut set = std::collections::BTreeMap::new();
    for i in items.filter(|i| !i.is_empty()) {
        // Flatpak keeps the spaces (" home" is no place it knows): don't
        // read it as "home".
        if i.trim() != i {
            return None;
        }
        match i.strip_prefix('!') {
            Some(gone) if fs => {
                let (n, rank) = fs_item(gone)?;
                // `!home:ro` isn't a plain removal.
                if rank != 2 || gone.contains(':') {
                    return None;
                }
                set.remove(&n);
            }
            Some(gone) => {
                set.remove(gone);
            }
            None if fs => {
                let (n, rank) = fs_item(i)?;
                set.insert(n, (rank, i.to_string()));
            }
            None => {
                set.insert(i.to_string(), (1, i.to_string()));
            }
        }
    }
    Some(set)
}

/// (group, key) → value, for every group that can grant something, parsed
/// with GKeyFile as flatpak parses it (so `\;` stays inside an item). A
/// group whose keys can't be listed is one [`Value::Unreadable`] entry.
fn permission_entries(k: &KeyFile) -> std::collections::BTreeMap<(String, String), Value> {
    let mut out = std::collections::BTreeMap::new();
    for g in k.groups().iter() {
        let g = g.as_str();
        if harmless_group(g) {
            continue;
        }
        let Ok(keys) = k.keys(g) else {
            out.insert((g.to_string(), String::new()), Value::Unreadable);
            continue;
        };
        for key in keys.iter() {
            let key = key.as_str();
            let v = if g == "Context" {
                k.string_list(g, key)
                    .ok()
                    .and_then(|l| granted(key, l.iter().map(|i| i.as_str())))
                    .map(Value::Granted)
            } else if g.ends_with("Bus Policy") {
                k.string(g, key)
                    .ok()
                    .map(|v| Value::Level(bus_level(&v), v.to_string()))
            } else {
                k.string(g, key).ok().map(|v| Value::Text(v.to_string()))
            };
            out.insert(
                (g.to_string(), key.to_string()),
                v.unwrap_or(Value::Unreadable),
            );
        }
    }
    out
}

/// How much a D-Bus policy grants: none < see < talk < own. A value flatpak
/// may learn later counts as the most.
fn bus_level(v: &str) -> u8 {
    match v.trim() {
        "none" => 0,
        "see" => 1,
        "talk" => 2,
        "own" => 3,
        _ => 4,
    }
}

/// The runtime's ID without arch and branch: `org.kde.Platform/x86_64/6.9`
/// → `org.kde.Platform`. A new branch is a routine update, a different
/// runtime is not (its own `[Context]` applies to the app). A runtime
/// update that widens its own `[Context]` or bus policies is held itself.
fn runtime_id(k: &KeyFile, key: &str) -> Option<String> {
    let v = k.string("Application", key).ok()?;
    Some(v.split('/').next().unwrap_or_default().trim().to_string())
}

fn key_file_permissions(old: &KeyFile, new: &KeyFile) -> Vec<String> {
    let mut out = Vec::new();
    for key in ["runtime", "sdk"] {
        let n = runtime_id(new, key);
        if let Some(id) = &n
            && n != runtime_id(old, key)
        {
            out.push(format!("Application: {key}={id}"));
        }
    }
    let old = permission_entries(old);
    for ((group, key), value) in permission_entries(new) {
        let had = old.get(&(group.clone(), key.clone()));
        match value {
            Value::Unreadable => {
                if !out.iter().any(|o| o == UNREADABLE) {
                    out.push(UNREADABLE.to_string());
                }
            }
            Value::Granted(items) => {
                for (name, (rank, item)) in items {
                    let before = match had {
                        Some(Value::Granted(h)) => h.get(&name).map_or(0, |(r, _)| *r),
                        _ => 0,
                    };
                    if rank > before {
                        out.push(format!("{group}: {key}={item}"));
                    }
                }
            }
            Value::Level(level, text) => {
                let before = match had {
                    Some(Value::Level(l, _)) => *l,
                    _ => 0,
                };
                if level > before {
                    out.push(format!("{group}: {key}={text}"));
                }
            }
            Value::Text(text) => {
                if !matches!(had, Some(Value::Text(t)) if *t == text) {
                    out.push(format!("{group}: {key}={}", text.trim_end_matches(';')));
                }
            }
        }
    }
    out
}

/// What `new` (a metadata key file) grants that `old` does not, as
/// "group: key=item" strings. Empty when the update asks for nothing new.
/// `[Context]` lists (`filesystems=home;xdg-download;`) are compared by
/// what they grant in the end (a `!item` takes an item away); D-Bus
/// policies by level; other values whole, so any change counts. Metadata that
/// can't be parsed is reported as [`UNREADABLE`], never as nothing new.
pub fn new_permissions(old: &str, new: &str) -> Vec<String> {
    let load = |t: &str| {
        let k = KeyFile::new();
        k.load_from_data(t, KeyFileFlags::NONE).ok().map(|_| k)
    };
    match (load(old), load(new)) {
        (Some(o), Some(n)) => key_file_permissions(&o, &n),
        _ => vec![UNREADABLE.to_string()],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const OLD: &str = "[Application]\nname=org.example.App\nruntime=org.kde.Platform/x86_64/6.9\n\n[Context]\nshared=network;ipc;\nsockets=x11;wayland;\nfilesystems=xdg-download;\n\n[Session Bus Policy]\norg.kde.StatusNotifierWatcher=talk\n";

    #[test]
    fn same_permissions_are_nothing_new() {
        assert!(new_permissions(OLD, OLD).is_empty());
        // A new runtime version alone is not a permission.
        let new = OLD.replace("6.9", "6.10");
        assert!(new_permissions(OLD, &new).is_empty());
    }

    #[test]
    fn new_filesystem_and_device_count() {
        let new = OLD
            .replace(
                "filesystems=xdg-download;",
                "filesystems=xdg-download;home;",
            )
            .replace("[Session", "devices=all;\n\n[Session");
        assert_eq!(
            new_permissions(OLD, &new),
            vec!["Context: devices=all", "Context: filesystems=home"]
        );
    }

    #[test]
    fn taking_away_is_not_new() {
        let new = OLD
            .replace("sockets=x11;wayland;", "sockets=wayland;!x11;")
            .replace("network;ipc;", "ipc;");
        assert!(new_permissions(OLD, &new).is_empty());
    }

    #[test]
    fn bus_names_compare_by_level() {
        let talk_to_own = OLD.replace("Watcher=talk", "Watcher=own");
        assert_eq!(
            new_permissions(OLD, &talk_to_own),
            vec!["Session Bus Policy: org.kde.StatusNotifierWatcher=own"]
        );
        let own_to_see = talk_to_own.replace("=own", "=see");
        assert!(new_permissions(&talk_to_own, &own_to_see).is_empty());
        let system = format!("{OLD}\n[System Bus Policy]\norg.freedesktop.login1=talk\n");
        assert_eq!(
            new_permissions(OLD, &system),
            vec!["System Bus Policy: org.freedesktop.login1=talk"]
        );
    }

    #[test]
    fn generic_policies_count() {
        let new = format!("{OLD}\n[Policy Telepathy]\nsubsystems=org.example.Foo;\n");
        assert_eq!(
            new_permissions(OLD, &new),
            vec!["Policy Telepathy: subsystems=org.example.Foo"]
        );
    }

    #[test]
    fn harmless_groups_are_ignored() {
        let new = format!(
            "{OLD}\n[Extension org.example.App.Locale]\ndirectory=share/runtime/locale\n\n[Build]\nbuilt-extensions=x;\n\n[Extra Data]\nname=app.deb\nchecksum=ab12\nsize=1\nuri=https://example.org/2.deb\n"
        )
        .replace("name=org.example.App", "name=org.example.App\ncommand=app");
        assert!(new_permissions(OLD, &new).is_empty());
    }

    #[test]
    fn unknown_groups_and_environment_count() {
        let new =
            format!("{OLD}\n[Environment]\nLD_PRELOAD=/tmp/x.so\n\n[Future Thing]\nallow=all;\n");
        assert_eq!(
            new_permissions(OLD, &new),
            vec![
                "Environment: LD_PRELOAD=/tmp/x.so",
                "Future Thing: allow=all"
            ]
        );
    }

    #[test]
    fn another_runtime_counts() {
        let new = OLD.replace("org.kde.Platform", "com.example.Platform");
        assert_eq!(
            new_permissions(OLD, &new),
            vec!["Application: runtime=com.example.Platform"]
        );
    }

    #[test]
    fn unknown_bus_values_count_as_the_most() {
        let new = OLD.replace("Watcher=talk", "Watcher=everything");
        assert_eq!(new_permissions(OLD, &new).len(), 1);
        let none = OLD.replace("Watcher=talk", "Watcher=none");
        assert!(new_permissions(OLD, &none).is_empty());
    }

    #[test]
    fn escaped_separators_stay_in_one_item() {
        // GKeyFile reads `x\;home` as one item "x;home", so `home` is new.
        let old = OLD.replace("filesystems=xdg-download;", "filesystems=x\\;home;");
        let new = OLD.replace("filesystems=xdg-download;", "filesystems=x\\;home;home;");
        assert_eq!(
            new_permissions(&old, &new),
            vec!["Context: filesystems=home"]
        );
    }

    #[test]
    fn environment_values_compare_whole() {
        let old = format!("{OLD}\n[Environment]\nPATH=/app/bin\n");
        let new = old.replace("PATH=/app/bin", "PATH=!/x:/app/bin");
        assert_eq!(
            new_permissions(&old, &new),
            vec!["Environment: PATH=!/x:/app/bin"]
        );
        let preload = format!("{OLD}\n[Environment]\nLD_PRELOAD=!x /app/lib/evil.so\n");
        assert_eq!(new_permissions(OLD, &preload).len(), 1);
        assert!(new_permissions(&old, &old).is_empty());
    }

    #[test]
    fn context_lists_count_what_they_grant_in_the_end() {
        let denied = OLD.replace("sockets=x11;wayland;", "sockets=wayland;x11;!x11;");
        let granted = OLD.replace("sockets=x11;wayland;", "sockets=wayland;!x11;x11;");
        assert_eq!(
            new_permissions(&denied, &granted),
            vec!["Context: sockets=x11"]
        );
        assert!(new_permissions(&granted, &denied).is_empty());
    }

    #[test]
    fn filesystems_compare_by_path_and_access() {
        let with = |fs: &str| OLD.replace("filesystems=xdg-download;", fs);
        // Spelled differently, same access: nothing new.
        assert!(new_permissions(&with("filesystems=~/x/;"), &with("filesystems=~/x;")).is_empty());
        // More access to the same place counts.
        assert_eq!(
            new_permissions(&with("filesystems=home:ro;"), &with("filesystems=home;")),
            vec!["Context: filesystems=home"]
        );
        // What could be read more than one way holds the update.
        for odd in [
            "home;!home:ro;",
            "home;home:reset;",
            "a\\:rw;",
            "xdg-download; home;",
        ] {
            assert_eq!(
                new_permissions(OLD, &with(&format!("filesystems={odd}"))),
                vec![UNREADABLE]
            );
        }
    }

    #[test]
    fn only_granting_metadata_counts_as_granting() {
        let k = |t: &str| {
            let k = KeyFile::new();
            k.load_from_data(t, KeyFileFlags::NONE).unwrap();
            k
        };
        assert!(!grants_any(&k(
            "[Runtime]\nname=org.example.Platform\n[Environment]\nA=b\n"
        )));
        assert!(grants_any(&k(
            "[Runtime]\nname=x\n[Context]\nshared=network;\n"
        )));
        assert!(grants_any(&k(
            "[Runtime]\nname=x\n[Policy Tracker3]\ndbus=x;\n"
        )));
        assert!(grants_any(&k(
            "[Runtime]\nname=x\n[System Bus Policy]\norg.x=talk\n"
        )));
        // Anything newer counts too.
        assert!(grants_any(&k(
            "[Runtime]\nname=x\n[USB Devices]\nenumerable-devices=all;\n"
        )));
        assert!(!grants_any(&k(
            "[Runtime]\nname=x\n[Extension org.x.GL]\ndirectory=lib/GL\n"
        )));
    }

    #[test]
    fn runtimes_that_grant_are_read_like_apps() {
        let k = |t: &str| {
            let k = KeyFile::new();
            k.load_from_data(t, KeyFileFlags::NONE).unwrap();
            k
        };
        let plain = k("[Runtime]\nname=x\n[Environment]\nA=b\n");
        let moved = k("[Runtime]\nname=x\n[Environment]\nA=c\\q\n");
        // A runtime that grants nothing: its environment and what can't be
        // read go on, with or without the old metadata.
        assert!(runtime_permissions(Some(&plain), &moved).is_empty());
        assert!(runtime_permissions(None, &moved).is_empty());
        // One that grants anything is held for what can't be read.
        let odd = k("[Runtime]\nname=x\n[USB Devices]\nenumerable-devices=all;\\q\n");
        assert_eq!(runtime_permissions(Some(&plain), &odd), vec![UNREADABLE]);
        // A new grant with no old metadata to go by is measured against none.
        let net = k("[Runtime]\nname=x\n[Context]\nshared=network;\n");
        assert_eq!(
            runtime_permissions(None, &net),
            vec!["Context: shared=network"]
        );
        assert!(runtime_permissions(Some(&net), &net).is_empty());
    }

    #[test]
    fn unreadable_metadata_is_never_nothing_new() {
        assert_eq!(new_permissions(OLD, "[broken"), vec![UNREADABLE]);
    }

    #[test]
    fn remote_text_is_cleaned() {
        assert_eq!(clean("Kate\n2\u{202E}x"), "Kate 2x");
        assert_eq!(
            clean("a\u{200B}b\u{2028}c\u{FEFF}\u{E0041}d\u{00AD}"),
            "abcd"
        );
        assert_eq!(clean_to("abcdef", 4), "abc…");
        assert_eq!(clean("a\u{3164}\u{2800}b"), "ab");
        let smear = format!("e{}", "\u{0301}".repeat(30));
        assert_eq!(clean(&smear).chars().count(), 4);
        assert_eq!(clean(&"a".repeat(200)).chars().count(), 80);
        assert_eq!(clean_opt(Some("  ")), None);
    }

    /// Serialises the tests that set environment variables.
    static ENV: std::sync::Mutex<()> = std::sync::Mutex::new(());

    #[test]
    fn a_cancelled_run_is_an_error_and_the_deadline_is_split() {
        let o = ListOutcome {
            checked: 1,
            cancelled: true,
            ..ListOutcome::default()
        };
        assert_eq!(o.into_result().unwrap_err().0, "cancelled");
        assert_eq!(
            next_limit(Some(Duration::from_secs(60)), None),
            Some(Some(Duration::from_secs(60)))
        );
        let end = Instant::now() + Duration::from_secs(5);
        let l = next_limit(Some(Duration::from_secs(60)), Some(end))
            .unwrap()
            .unwrap();
        assert!(l <= Duration::from_secs(5));
        assert_eq!(
            next_limit(None, Some(Instant::now() - Duration::from_secs(1))),
            None
        );
    }

    #[test]
    fn an_unrelated_error_is_not_called_cancelled() {
        let token = CancelToken::new();
        let t2 = token.clone();
        let e = guarded(Some(&token), None, |_| {
            t2.cancel();
            Err::<(), _>(libflatpak::glib::Error::new(
                libflatpak::gio::IOErrorEnum::NotFound,
                "no such remote",
            ))
        })
        .unwrap_err();
        assert_eq!(e.0, "no such remote");
    }

    fn wait_for_cancel(c: &Cancellable) -> std::result::Result<(), libflatpak::glib::Error> {
        while !c.is_cancelled() {
            std::thread::sleep(Duration::from_millis(5));
        }
        Err(libflatpak::glib::Error::new(
            libflatpak::gio::IOErrorEnum::Cancelled,
            "cancelled",
        ))
    }

    #[test]
    fn a_stalled_call_times_out() {
        let t = Instant::now();
        let e = guarded(None, Some(Duration::from_millis(150)), wait_for_cancel).unwrap_err();
        assert!(e.0.starts_with("timed out"), "{e}");
        assert!(t.elapsed() < Duration::from_secs(5));
    }

    #[test]
    fn a_token_stops_a_running_call() {
        let token = CancelToken::new();
        let t2 = token.clone();
        let h = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(100));
            t2.cancel();
        });
        let e = guarded(Some(&token), None, wait_for_cancel).unwrap_err();
        h.join().unwrap();
        assert_eq!(e.0, "cancelled");
        // already cancelled: the call never starts
        let mut ran = false;
        let e = guarded(Some(&token), None, |_| {
            ran = true;
            Ok(())
        })
        .unwrap_err();
        assert!(!ran && e.0 == "cancelled");
    }

    #[test]
    fn a_quick_call_is_not_cut_and_leaves_no_thread_behind() {
        let r = guarded(None, Some(Duration::from_secs(30)), |_| Ok(7)).unwrap();
        assert_eq!(r, 7);
    }

    #[test]
    fn a_report_checks_what_it_can_and_stops_on_cancel() {
        // An empty private user installation, no network: refresh is off.
        let _env = ENV.lock().unwrap_or_else(|e| e.into_inner());
        let d = tempfile::tempdir().unwrap();
        // SAFETY: tests that touch the environment hold ENV.
        unsafe { std::env::set_var("FLATPAK_USER_DIR", d.path()) };
        let o = list_updates_report(&ListOptions::default());
        assert!(o.updates.is_empty());
        assert!(o.checked >= 1, "{o:?}");
        let token = CancelToken::new();
        token.cancel();
        let o = list_updates_report(&ListOptions {
            cancel: Some(token),
            ..ListOptions::default()
        });
        assert_eq!(o.checked, 0);
        // SAFETY: as above.
        unsafe { std::env::remove_var("FLATPAK_USER_DIR") };
        assert!(o.errors.iter().all(|e| e.error.0 == "cancelled"));
        assert!(!o.errors.is_empty());
        assert!(o.into_result().is_err());
    }

    #[test]
    fn some_failures_still_give_the_successes() {
        let fail = InstallationError {
            installation: InstallationKind::System,
            id: "extra".into(),
            error: Error("not mounted".into()),
        };
        let o = ListOutcome {
            updates: Vec::new(),
            errors: vec![fail.clone()],
            checked: 1,
            cancelled: false,
        };
        assert!(o.into_result().unwrap().is_empty());
        let o = ListOutcome {
            errors: vec![fail],
            ..ListOutcome::default()
        };
        assert_eq!(o.into_result().unwrap_err().0, "not mounted");
    }

    #[test]
    fn refs_split() {
        assert_eq!(
            split_ref("app/org.kde.kate/x86_64/stable"),
            Some((RefKind::App, "org.kde.kate", "x86_64", "stable"))
        );
        assert_eq!(
            split_ref("runtime/org.kde.Platform/x86_64/6.9").map(|p| p.0),
            Some(RefKind::Runtime)
        );
        assert_eq!(split_ref("bogus"), None);
    }
}
