//! Settings migrations: `[Atlas] SchemaVersion=N`, ordered functions.

use std::error::Error;
use std::fmt;
use std::fs;
use std::io;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::PathBuf;

use super::{
    Settings, WRITERS, get_in, immutable, lock, read_text_strict, replace, resolve_link, set_in,
    sweep_temps,
};

/// Where the app's schema version lives.
pub const SCHEMA_GROUP: &str = "Atlas";
pub const SCHEMA_KEY: &str = "SchemaVersion";

/// One step: the file's whole text at version `n` in, the text at version
/// `n + 1` out. Use [`get_in`](super::get_in) and [`set_in`](super::set_in).
/// Return an error to stop: nothing is written.
pub type Migration = fn(&str) -> Result<String, Box<dyn Error + Send + Sync>>;

/// What [`Settings::migrate`] did.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Migrated {
    /// The file was already at the app's version.
    UpToDate,
    /// There was no file (or it was empty): it was created at the app's version.
    Created { to: u32 },
    /// The file was upgraded; the old one is in `<name>.bak`.
    Upgraded { from: u32, to: u32 },
}

/// Why [`Settings::migrate`] did not finish. In every case the settings file
/// is as it was.
#[derive(Debug)]
#[non_exhaustive]
pub enum MigrateError {
    /// Migration `from` to `from + 1` failed.
    Failed {
        from: u32,
        source: Box<dyn Error + Send + Sync>,
    },
    /// The file was written by a newer app (`found`) than this one knows
    /// (`known`). It is left alone: reading it still works, but do not `set`.
    Newer { found: u32, known: u32 },
    /// `SchemaVersion` is not a number.
    BadVersion(String),
    /// The file could not be read, locked or written (`InvalidData` for a
    /// file that is not UTF-8, `TimedOut` for a held lock).
    Io(io::Error),
}

impl fmt::Display for MigrateError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Failed { from, source } => write!(
                f,
                "settings migration from version {from} to {} failed: {source}",
                from + 1
            ),
            Self::Newer { found, known } => write!(
                f,
                "the settings file is version {found}, newer than this app's version {known}"
            ),
            Self::BadVersion(v) => write!(
                f,
                "the settings file's schema version is not a number: {v:?}"
            ),
            Self::Io(e) => write!(f, "settings migration: {e}"),
        }
    }
}

impl Error for MigrateError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::Failed { source, .. } => Some(source.as_ref()),
            Self::Io(e) => Some(e),
            _ => None,
        }
    }
}

impl From<io::Error> for MigrateError {
    fn from(e: io::Error) -> Self {
        Self::Io(e)
    }
}

impl Settings {
    /// Brings the file to this app's schema version, `migrations.len()`:
    /// `migrations[n]` upgrades version `n` to `n + 1`, and a file without
    /// `SchemaVersion` is version 0. Call it once at start, before reading.
    ///
    /// - Everything runs in memory under the writer lock. The old file is
    ///   copied to `<name>.bak` (atomically, with its mode) only after every
    ///   step succeeded, then the new text replaces the file atomically. A
    ///   failing step returns [`MigrateError::Failed`] naming its version and
    ///   writes nothing, not even the `.bak`.
    /// - A file newer than the app is never changed: `Err(Newer)`. Choose
    ///   what the app does: read it and keep from calling `set`, or quit with
    ///   a message.
    /// - A missing or empty file is created at the current version, so a
    ///   later start does not run the migrations on new data.
    pub fn migrate(&self, migrations: &[Migration]) -> Result<Migrated, MigrateError> {
        let known = u32::try_from(migrations.len()).unwrap_or(u32::MAX);
        if self.path.starts_with(super::NO_HOME) {
            return Err(io::Error::new(
                io::ErrorKind::NotFound,
                "no home directory to keep settings in",
            )
            .into());
        }
        let target = resolve_link(&self.path)?;
        if let Some(dir) = target.parent() {
            fs::create_dir_all(dir)?;
        }
        let _file = lock(&target)?;
        let _thread = WRITERS.lock().unwrap_or_else(|e| e.into_inner());
        sweep_temps(&target);
        let (text, meta) = match read_text_strict(&target) {
            Ok(t) => (t, Some(fs::metadata(&target)?)),
            Err(e) if e.kind() == io::ErrorKind::NotFound => (String::new(), None),
            Err(e) => return Err(e.into()),
        };
        let found = match get_in(&text, SCHEMA_GROUP, SCHEMA_KEY) {
            None => 0,
            Some(v) => v
                .trim()
                .parse::<u32>()
                .map_err(|_| MigrateError::BadVersion(v.clone()))?,
        };
        if found > known {
            log::warn!(
                "{}: schema version {found} is newer than this app's {known}; not touching it",
                target.display()
            );
            return Err(MigrateError::Newer { found, known });
        }
        let fresh = text.trim().is_empty();
        if found == known && !fresh {
            return Ok(Migrated::UpToDate);
        }
        if immutable(&text, SCHEMA_GROUP, SCHEMA_KEY) {
            return Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                format!("{SCHEMA_GROUP}/{SCHEMA_KEY} is immutable"),
            )
            .into());
        }
        let mut cur = text.clone();
        if !fresh {
            for n in found..known {
                let step = migrations[n as usize];
                let next = catch_unwind(AssertUnwindSafe(|| step(&cur)))
                    .unwrap_or_else(|_| Err("the migration panicked".into()))
                    .map_err(|source| {
                        log::error!("settings migration from version {n} failed: {source}");
                        MigrateError::Failed { from: n, source }
                    })?;
                cur = next;
            }
        }
        let out = set_in(&cur, SCHEMA_GROUP, SCHEMA_KEY, Some(&known.to_string()));
        let out = super::with_format(&text, out);
        if meta.is_some() && !fresh {
            let bak = backup_path(&target);
            replace(&bak, text.as_bytes(), meta.as_ref())?;
            log::info!(
                "settings: kept the version {found} file as {}",
                bak.display()
            );
        }
        replace(&target, out.as_bytes(), meta.as_ref())?;
        Ok(if fresh {
            Migrated::Created { to: known }
        } else {
            Migrated::Upgraded {
                from: found,
                to: known,
            }
        })
    }
}

fn backup_path(target: &std::path::Path) -> PathBuf {
    let name = target.file_name().unwrap_or_default().to_string_lossy();
    target.with_file_name(format!("{name}.bak"))
}

#[cfg(test)]
mod tests {
    use super::*;

    type R = Result<String, Box<dyn Error + Send + Sync>>;

    fn m0(t: &str) -> R {
        // 0 -> 1: rename General/Lang to General/Language
        let v = get_in(t, "General", "Lang");
        let t = set_in(t, "General", "Lang", None);
        Ok(match v {
            Some(v) => set_in(&t, "General", "Language", Some(&v)),
            None => t,
        })
    }
    fn m1(t: &str) -> R {
        Ok(set_in(t, "General", "Theme", Some("dark")))
    }
    fn bad(_: &str) -> R {
        Err("no good".into())
    }
    fn boom(_: &str) -> R {
        panic!("boom")
    }

    fn file(text: &str) -> (tempfile::TempDir, Settings) {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("atlas-xrc");
        fs::write(&p, text).unwrap();
        (d, Settings::at(p))
    }

    #[test]
    fn missing_version_is_zero_and_runs_in_order() {
        let (d, s) = file("[General]\nLang=nl\n");
        let r = s.migrate(&[m0, m1]).unwrap();
        assert_eq!(r, Migrated::Upgraded { from: 0, to: 2 });
        assert_eq!(s.get("General", "Language").as_deref(), Some("nl"));
        assert_eq!(s.get("General", "Lang"), None);
        assert_eq!(s.get("General", "Theme").as_deref(), Some("dark"));
        assert_eq!(s.get("Atlas", "SchemaVersion").as_deref(), Some("2"));
        // the backup is the old file, byte for byte
        let bak = fs::read_to_string(d.path().join("atlas-xrc.bak")).unwrap();
        assert_eq!(bak, "[General]\nLang=nl\n");
        // and a second run does nothing
        assert_eq!(s.migrate(&[m0, m1]).unwrap(), Migrated::UpToDate);
    }

    #[test]
    fn runs_only_the_missing_steps() {
        let (_d, s) = file("[Atlas]\nSchemaVersion=1\n[General]\nLang=nl\n");
        assert_eq!(
            s.migrate(&[m0, m1]).unwrap(),
            Migrated::Upgraded { from: 1, to: 2 }
        );
        // m0 did not run: Lang is still there
        assert_eq!(s.get("General", "Lang").as_deref(), Some("nl"));
        assert_eq!(s.get("General", "Theme").as_deref(), Some("dark"));
    }

    #[test]
    fn a_failure_in_the_middle_changes_nothing() {
        for steps in [&[m0, bad][..], &[m0, boom][..]] {
            let (d, s) = file("[General]\nLang=nl\n");
            let e = s.migrate(steps).unwrap_err();
            assert!(matches!(e, MigrateError::Failed { from: 1, .. }), "{e}");
            assert!(e.to_string().contains("version 1 to 2"), "{e}");
            assert_eq!(
                fs::read_to_string(s.path()).unwrap(),
                "[General]\nLang=nl\n"
            );
            assert!(!d.path().join("atlas-xrc.bak").exists());
        }
    }

    #[test]
    fn a_newer_file_is_left_alone() {
        let text = "[Atlas]\nSchemaVersion=5\n[General]\nX=1\n";
        let (d, s) = file(text);
        let e = s.migrate(&[m0, m1]).unwrap_err();
        assert!(matches!(e, MigrateError::Newer { found: 5, known: 2 }));
        assert_eq!(fs::read_to_string(s.path()).unwrap(), text);
        assert!(!d.path().join("atlas-xrc.bak").exists());
        assert_eq!(s.get("General", "X").as_deref(), Some("1")); // still readable
    }

    #[test]
    fn a_bad_version_is_an_error_and_a_missing_file_is_created() {
        let (_d, s) = file("[Atlas]\nSchemaVersion=two\n");
        assert!(matches!(
            s.migrate(&[m0]).unwrap_err(),
            MigrateError::BadVersion(_)
        ));
        let d = tempfile::tempdir().unwrap();
        let s = Settings::at(d.path().join("sub/atlas-yrc"));
        assert_eq!(s.migrate(&[m0, m1]).unwrap(), Migrated::Created { to: 2 });
        assert_eq!(s.get("Atlas", "SchemaVersion").as_deref(), Some("2"));
        assert!(!d.path().join("sub/atlas-yrc.bak").exists());
        assert_eq!(s.migrate(&[m0, m1]).unwrap(), Migrated::UpToDate);
    }

    #[test]
    fn no_steps_and_no_version_stamps_nothing_new_to_run() {
        let (d, s) = file("[General]\nA=1\n");
        // an app with no migrations yet: version 0 == known, nothing to do
        assert_eq!(s.migrate(&[]).unwrap(), Migrated::UpToDate);
        assert!(!d.path().join("atlas-xrc.bak").exists());
    }
}
