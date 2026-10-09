//! Programs that keep out of crash reporting.
//!
//! An app that says `crash: false` (telamon-framework-ui) installs no panic
//! hook, but a native crash (SIGSEGV, the abort after a Qt fatal) still lands
//! in the journal through systemd-coredump, where [`collect_coredumps`] of any
//! other Telamon app would find it and build a report from the package name or
//! the Flatpak ID. [`opt_out`] writes the program down in the user's state
//! directory so that collection leaves its crashes alone. The core dump itself
//! stays with systemd (`coredumpctl`): only the report is never made.
//!
//! The file is the user's own (0600 in a 0700 directory), at most 64 entries,
//! one per line: `exe <absolute path>` or `app <app ID>`.

use super::*;

const FILE: &str = "crash-optout";
const MAX_BYTES: u64 = 64 * 1024;
const MAX_ENTRIES: usize = 64;

fn path() -> Option<PathBuf> {
    Some(state_dir()?.join(FILE))
}

fn app_id_ok(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 255
        && id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
}

/// Records `app` as keeping out of crash reporting: its program path and its
/// app ID. Called by `telamon_framework_ui::start()` for an app whose `app!` says
/// `crash: false`; safe to call again (an entry is written once). Failures are
/// logged and otherwise ignored.
pub fn opt_out(app: &AppInfo) {
    let mut wanted = Vec::new();
    if let Ok(exe) = std::env::current_exe().and_then(fs::canonicalize) {
        // a deleted-and-replaced binary reads as "<path> (deleted)" in /proc
        if let Some(exe) = exe.to_str().filter(|e| valid_exe(e)) {
            wanted.push(format!("exe {exe}"));
        }
    }
    if app_id_ok(&app.id) {
        wanted.push(format!("app {}", app.id));
    }
    let Some(p) = path() else { return };
    if let Err(e) = record_in(&p, &wanted) {
        eprintln!("telamon-framework: could not record the crash reporting opt-out: {e}");
    }
}

/// Adds the lines of `wanted` that `file` does not have yet.
fn record_in(file: &Path, wanted: &[String]) -> io::Result<()> {
    let mut lines: Vec<String> = read_small_text(file, MAX_BYTES, true)
        .map(|t| t.lines().map(str::to_string).collect())
        .unwrap_or_default();
    let before = lines.len();
    for w in wanted {
        if !lines.contains(w) && lines.len() < MAX_ENTRIES {
            lines.push(w.clone());
        }
    }
    if lines.len() == before {
        return Ok(());
    }
    let mut text = lines.join("\n");
    text.push('\n');
    write_private(file, text.as_bytes(), true)
}

/// The programs that opted out, as read from the state directory.
pub(super) struct OptOut {
    exes: Vec<String>,
    apps: Vec<String>,
}

impl OptOut {
    pub(super) fn load() -> OptOut {
        path().map_or_else(|| OptOut::parse(""), |p| OptOut::load_from(&p))
    }

    fn load_from(file: &Path) -> OptOut {
        OptOut::parse(&read_small_text(file, MAX_BYTES, true).unwrap_or_default())
    }

    pub(super) fn parse(text: &str) -> OptOut {
        let mut out = OptOut {
            exes: Vec::new(),
            apps: Vec::new(),
        };
        for line in text.lines().take(MAX_ENTRIES) {
            match line.split_once(' ') {
                Some(("exe", e)) if valid_exe(e) => out.exes.push(e.to_string()),
                Some(("app", id)) if app_id_ok(id) => out.apps.push(id.to_string()),
                _ => {}
            }
        }
        out
    }

    /// Whether this crash is one of a program that opted out: its program path
    /// is on the list, or it is a Flatpak app whose ID is.
    pub(super) fn matches(&self, dump: &Coredump) -> bool {
        (!dump.exe.is_empty() && self.exes.contains(&dump.exe))
            || matches!(&dump.origin, Origin::Flatpak(id) if self.apps.contains(id))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dump(exe: &str, origin: Origin) -> Coredump {
        Coredump {
            ts: 1,
            exe: exe.into(),
            comm: "pong".into(),
            signal: "SIGSEGV".into(),
            origin,
        }
    }

    #[test]
    fn a_program_on_the_list_is_matched_by_path_or_flatpak_id() {
        let o = OptOut::parse("exe /usr/bin/pong\napp net.example.Pong\n");
        assert!(o.matches(&dump("/usr/bin/pong", Origin::Host)));
        assert!(o.matches(&dump(
            "/app/bin/x",
            Origin::Flatpak("net.example.Pong".into())
        )));
        assert!(!o.matches(&dump("/usr/bin/other", Origin::Host)));
        assert!(!o.matches(&dump("", Origin::Host)));
        assert!(!o.matches(&dump(
            "/app/bin/x",
            Origin::Flatpak("net.example.Other".into())
        )));
    }

    #[test]
    fn odd_lines_are_ignored() {
        let o = OptOut::parse("exe relative\nexe /a/../b\napp bad id\napp \nnonsense\nexe /ok\n");
        assert_eq!(o.exes, vec!["/ok".to_string()]);
        assert!(o.apps.is_empty());
    }

    #[test]
    fn the_list_is_written_once_per_program_privately_and_read_back() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("telamon/crash-optout");
        let wanted = vec![
            "exe /usr/bin/pong".to_string(),
            "app net.example.pong".to_string(),
        ];
        record_in(&file, &wanted).unwrap();
        record_in(&file, &wanted).unwrap();
        assert_eq!(
            fs::read_to_string(&file).unwrap(),
            "exe /usr/bin/pong\napp net.example.pong\n"
        );
        assert_eq!(fs::metadata(&file).unwrap().permissions().mode() & 0o077, 0);
        let o = OptOut::load_from(&file);
        assert!(o.matches(&dump("/usr/bin/pong", Origin::Host)));
        assert!(o.matches(&dump("", Origin::Flatpak("net.example.pong".into()))));
    }

    #[test]
    fn the_list_is_bounded() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("o");
        let many: Vec<String> = (0..200).map(|i| format!("app a{i}")).collect();
        record_in(&file, &many).unwrap();
        assert_eq!(
            fs::read_to_string(&file).unwrap().lines().count(),
            MAX_ENTRIES
        );
        // a file over the cap, or a FIFO, is not read: nothing matches
        fs::write(&file, vec![b'a'; MAX_BYTES as usize + 1]).unwrap();
        assert!(OptOut::load_from(&file).apps.is_empty());
    }

    #[test]
    fn collection_skips_an_opted_out_program() {
        // coredump_report is the same for every caller; the check sits in the
        // collection loop, on Coredump::parse of the entry.
        let o = OptOut::parse("exe /usr/bin/foo\n");
        let d = Coredump::parse(&super::secure_tests::trusted_entry(), "1000").unwrap();
        assert!(o.matches(&d));
        assert!(!OptOut::parse("exe /usr/bin/bar\n").matches(&d));
    }
}
