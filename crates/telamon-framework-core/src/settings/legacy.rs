//! Files from before 2.0.0, when the framework was called Atlas.
//!
//! `atlas-<app>rc` became `telamon-<app>rc`, and the `[Atlas]` group of
//! `Format` and `SchemaVersion` became `[Telamon]`. The first time an app asks
//! for its settings ([`Settings::for_app`](super::Settings::for_app)) and the
//! new file is not there yet, the old one is copied to the new name with its
//! `[Atlas]` group renamed. The old file stays where it is: an app that has
//! not moved to 2.0.0 yet keeps reading and writing it, and the two do not
//! follow each other from then on.

use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::Path;

/// The group name before 2.0.0.
pub(super) const LEGACY_GROUP: &str = "Atlas";

/// `text` with every `[Atlas]` group header (also `[Atlas][$i]` and
/// `[Atlas][Sub]`) renamed to `[Telamon]`; every other byte unchanged.
pub(super) fn rename_group(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 16);
    for line in text.split_inclusive('\n') {
        match line.strip_prefix("[Atlas]") {
            Some(rest) if rest.trim_end().is_empty() || rest.starts_with('[') => {
                out.push_str("[Telamon]");
                out.push_str(rest);
            }
            _ => out.push_str(line),
        }
    }
    out
}

/// Copies `old` to `new` when `new` does not exist (not even as a link) and
/// `old` is a regular file (or a link to one) of a size settings files have.
/// The copy keeps the mode, is complete before it appears under its name
/// and never replaces a file another process made in the meantime.
/// Returns whether a file was made.
pub(super) fn adopt(new: &Path, old: &Path) -> io::Result<bool> {
    if fs::symlink_metadata(new).is_ok() {
        return Ok(false);
    }
    let Ok(meta) = fs::metadata(old) else {
        return Ok(false);
    };
    if !meta.is_file() {
        return Ok(false);
    }
    // Too large or not readable: the app starts with defaults, as it would
    // have for any other file it cannot use.
    let Ok(bytes) = crate::fsutil::read_capped(old, super::MAX_BYTES) else {
        return Ok(false);
    };
    let bytes = match String::from_utf8(bytes) {
        Ok(text) => rename_group(&text).into_bytes(),
        Err(e) => e.into_bytes(),
    };
    let Some(dir) = new.parent() else {
        return Ok(false);
    };
    crate::fsutil::create_private_dir_all(dir)?;
    let name = new.file_name().unwrap_or_default().to_string_lossy();
    let tmp = dir.join(format!(".{name}.adopt{}", std::process::id()));
    let mode = meta.mode() & 0o777;
    let write = || -> io::Result<()> {
        let mut f = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(mode)
            .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
            .open(&tmp)?;
        // The umask may have taken bits off.
        f.set_permissions(fs::Permissions::from_mode(mode))?;
        f.write_all(&bytes)?;
        f.sync_all()
    };
    let _ = fs::remove_file(&tmp);
    if let Err(e) = write() {
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    // A hard link appears whole, and fails when the name is taken. Where the
    // file system has no links, fall back to creating the name exclusively.
    let linked = match fs::hard_link(&tmp, new) {
        Ok(()) => Ok(true),
        Err(e) if e.kind() == io::ErrorKind::AlreadyExists => Ok(false),
        Err(_) => OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(mode)
            .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
            .open(new)
            .and_then(|mut f| {
                f.set_permissions(fs::Permissions::from_mode(mode))?;
                f.write_all(&bytes)?;
                f.sync_all()
            })
            .map(|()| true)
            .or_else(|e| {
                if e.kind() == io::ErrorKind::AlreadyExists {
                    Ok(false)
                } else {
                    Err(e)
                }
            }),
    };
    let _ = fs::remove_file(&tmp);
    linked
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_atlas_group_header_changes() {
        let t = "# [Atlas] in a comment\n[Atlas]\nFormat=1\n[Atlas][$i]\nA=1\n[Atlas][Sub]\nB=2\n\
                 [AtlasX]\nC=3\n[General]\nName=[Atlas]\n[Atlas] \r\nD=4\r\n[Atlas]";
        assert_eq!(
            rename_group(t),
            "# [Atlas] in a comment\n[Telamon]\nFormat=1\n[Telamon][$i]\nA=1\n[Telamon][Sub]\nB=2\n\
             [AtlasX]\nC=3\n[General]\nName=[Atlas]\n[Telamon] \r\nD=4\r\n[Telamon]"
        );
        assert_eq!(rename_group(""), "");
    }

    #[test]
    fn copies_once_with_mode_and_leaves_the_old_file() {
        let d = tempfile::tempdir().unwrap();
        let old = d.path().join("atlas-xrc");
        let new = d.path().join("telamon-xrc");
        fs::write(&old, "[Atlas]\nFormat=1\n\n[View]\nSide=left\n").unwrap();
        fs::set_permissions(&old, fs::Permissions::from_mode(0o600)).unwrap();

        assert!(adopt(&new, &old).unwrap());
        assert_eq!(
            fs::read_to_string(&new).unwrap(),
            "[Telamon]\nFormat=1\n\n[View]\nSide=left\n"
        );
        assert_eq!(fs::metadata(&new).unwrap().mode() & 0o777, 0o600);
        assert!(old.exists(), "the old file stays for apps not moved yet");
        // No temp file left behind.
        let names: Vec<_> = fs::read_dir(d.path())
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(names.len(), 2, "{names:?}");

        // The new file is the app's now: a later change to the old one, or a
        // second call, does not touch it.
        fs::write(&new, "[View]\nSide=right\n").unwrap();
        fs::write(&old, "[View]\nSide=top\n").unwrap();
        assert!(!adopt(&new, &old).unwrap());
        assert_eq!(fs::read_to_string(&new).unwrap(), "[View]\nSide=right\n");
    }

    #[test]
    fn nothing_to_copy_means_no_file() {
        let d = tempfile::tempdir().unwrap();
        let new = d.path().join("telamon-xrc");
        // No old file.
        assert!(!adopt(&new, &d.path().join("atlas-xrc")).unwrap());
        assert!(!new.exists());
        // A directory, a broken link, an oversized file and a fifo are not
        // settings files.
        fs::create_dir(d.path().join("atlas-dir")).unwrap();
        assert!(!adopt(&new, &d.path().join("atlas-dir")).unwrap());
        std::os::unix::fs::symlink("nowhere", d.path().join("atlas-link")).unwrap();
        assert!(!adopt(&new, &d.path().join("atlas-link")).unwrap());
        let big = d.path().join("atlas-big");
        fs::write(&big, vec![b'#'; super::super::MAX_BYTES as usize + 1]).unwrap();
        assert!(!adopt(&new, &big).unwrap());
        assert!(!new.exists());
    }

    #[test]
    fn follows_a_dotfiles_link_and_keeps_bytes_that_are_not_utf8() {
        let d = tempfile::tempdir().unwrap();
        let real = d.path().join("dotfiles-rc");
        fs::write(&real, b"[Atlas]\nFormat=1\n# \xff\xfe\n").unwrap();
        let old = d.path().join("atlas-xrc");
        std::os::unix::fs::symlink(&real, &old).unwrap();
        let new = d.path().join("telamon-xrc");
        assert!(adopt(&new, &old).unwrap());
        // Not valid UTF-8: copied as it is, the old group name included.
        assert_eq!(fs::read(&new).unwrap(), b"[Atlas]\nFormat=1\n# \xff\xfe\n");
        assert!(!fs::symlink_metadata(&new).unwrap().file_type().is_symlink());
    }

    #[test]
    fn a_link_at_the_new_name_counts_as_present() {
        let d = tempfile::tempdir().unwrap();
        let new = d.path().join("telamon-xrc");
        std::os::unix::fs::symlink("elsewhere", &new).unwrap();
        let old = d.path().join("atlas-xrc");
        fs::write(&old, "[G]\nK=1\n").unwrap();
        assert!(!adopt(&new, &old).unwrap());
    }

    mod props {
        use super::*;
        use proptest::prelude::*;

        fn text() -> impl Strategy<Value = String> {
            prop_oneof![
                1 => any::<String>(),
                3 => proptest::collection::vec(
                    prop_oneof![
                        Just("[Atlas]".to_string()),
                        Just("[Atlas][$i]".to_string()),
                        Just("[Atlas][Sub]".to_string()),
                        Just("[AtlasX]".to_string()),
                        Just("[Atlas] ".to_string()),
                        Just("# [Atlas]".to_string()),
                        "[ -~]{0,12}",
                    ],
                    0..8
                )
                .prop_map(|l| l.join("\n")),
            ]
        }

        proptest! {
            #[test]
            fn prop_only_atlas_headers_change_and_nothing_else_moves(t in text()) {
                let out = rename_group(&t);
                prop_assert_eq!(out.lines().count(), t.lines().count());
                prop_assert_eq!(out.matches('\n').count(), t.matches('\n').count());
                // 7 bytes become 9: the length only grows, by 2 per header
                prop_assert!(out.len() >= t.len());
                for (a, b) in t.lines().zip(out.lines()) {
                    if a != b {
                        prop_assert!(a.starts_with("[Atlas]"));
                        prop_assert!(b.starts_with("[Telamon]"));
                        prop_assert_eq!(&a["[Atlas]".len()..], &b["[Telamon]".len()..]);
                    }
                }
                // renaming is idempotent: no [Atlas] header is left
                prop_assert_eq!(rename_group(&out), out);
            }
        }
    }
}
