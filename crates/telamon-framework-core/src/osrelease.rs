//! The OS name, version and logo from os-release(5), for About pages and
//! crash reports. Only the system's own files are read.

use std::path::Path;

/// The fields Telamon apps show. Missing fields are empty.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct OsRelease {
    pub id: String,
    pub name: String,
    pub version: String,
    pub version_id: String,
    pub pretty_name: String,
    /// An icon name (`LOGO=`), e.g. `atlasos-logo`.
    pub logo: String,
    pub home_url: String,
    pub bug_report_url: String,
}

impl OsRelease {
    /// `/etc/os-release`, else `/usr/lib/os-release`, else all empty.
    pub fn load() -> OsRelease {
        ["/etc/os-release", "/usr/lib/os-release"]
            .iter()
            .find_map(|p| Self::load_from(Path::new(p)))
            .unwrap_or_default()
    }

    pub fn load_from(path: &Path) -> Option<OsRelease> {
        // regular files only, at most 1 MB, bad UTF-8 replaced
        let bytes = crate::fsutil::read_capped(path, 1024 * 1024).ok()?;
        Some(Self::parse(&String::from_utf8_lossy(&bytes)))
    }

    pub fn parse(text: &str) -> OsRelease {
        let mut r = OsRelease::default();
        for line in text.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let Some((key, raw)) = line.split_once('=') else {
                continue;
            };
            let field = match key.trim() {
                "ID" => &mut r.id,
                "NAME" => &mut r.name,
                "VERSION" => &mut r.version,
                "VERSION_ID" => &mut r.version_id,
                "PRETTY_NAME" => &mut r.pretty_name,
                "LOGO" => &mut r.logo,
                "HOME_URL" => &mut r.home_url,
                "BUG_REPORT_URL" => &mut r.bug_report_url,
                _ => continue,
            };
            *field = unquote(raw.trim());
        }
        r
    }

    /// `PRETTY_NAME`, else `NAME VERSION`, else `Linux` (the os-release(5)
    /// default).
    pub fn display_name(&self) -> String {
        if !self.pretty_name.is_empty() {
            return self.pretty_name.clone();
        }
        let name = if self.name.is_empty() {
            "Linux"
        } else {
            &self.name
        };
        let version = if self.version.is_empty() {
            &self.version_id
        } else {
            &self.version
        };
        if version.is_empty() {
            name.to_string()
        } else {
            format!("{name} {version}")
        }
    }
}

impl OsRelease {
    /// `LOGO=` if it is a plain icon name; a path or an empty value counts
    /// as missing.
    pub fn logo_icon(&self) -> Option<String> {
        let v = self.logo.as_str();
        let ok = !v.is_empty()
            && v.chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | '+'));
        ok.then(|| v.to_string())
    }
}

/// The OS logo's icon name (`LOGO=`), if the system names a plain one.
pub fn logo_icon() -> Option<String> {
    OsRelease::load().logo_icon()
}

/// os-release values are shell-style: optionally single- or double-quoted;
/// inside double quotes `\` escapes `"`, `\`, `$` and `` ` ``.
fn unquote(v: &str) -> String {
    if let Some(inner) = v.strip_prefix('\'').and_then(|s| s.strip_suffix('\'')) {
        return inner.to_string();
    }
    let Some(inner) = v.strip_prefix('"').and_then(|s| s.strip_suffix('"')) else {
        return v.to_string();
    };
    let mut out = String::with_capacity(inner.len());
    let mut chars = inner.chars();
    while let Some(c) = chars.next() {
        if c == '\\' {
            match chars.next() {
                Some(n @ ('"' | '\\' | '$' | '`')) => out.push(n),
                Some(n) => {
                    out.push('\\');
                    out.push(n);
                }
                None => out.push('\\'),
            }
        } else {
            out.push(c);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_quoted_and_plain() {
        let r = OsRelease::parse(
            "# comment\nNAME=\"Telamon OS\"\nVERSION='44.20261003'\nID=atlasos\n\
             PRETTY_NAME=\"Telamon OS \\\"Lead\\\" \\$1\"\nLOGO=atlasos-logo\nOTHER=x\nbroken\n",
        );
        assert_eq!(r.name, "Telamon OS");
        assert_eq!(r.version, "44.20261003");
        assert_eq!(r.id, "atlasos");
        assert_eq!(r.pretty_name, "Telamon OS \"Lead\" $1");
        assert_eq!(r.logo, "atlasos-logo");
    }

    #[test]
    fn display_name_falls_back() {
        assert_eq!(OsRelease::default().display_name(), "Linux");
        let r = OsRelease::parse("NAME=Fedora\nVERSION_ID=44\n");
        assert_eq!(r.display_name(), "Fedora 44");
    }

    #[test]
    fn logo_must_be_a_plain_icon_name() {
        let logo = |t: &str| OsRelease::parse(t).logo_icon();
        assert_eq!(
            logo("NAME=Telamon\nLOGO=atlasos\n").as_deref(),
            Some("atlasos")
        );
        assert_eq!(
            logo("LOGO=\"fedora-logo-icon\"").as_deref(),
            Some("fedora-logo-icon")
        );
        assert_eq!(logo("LOGO='x'\r\n").as_deref(), Some("x"));
        assert_eq!(logo("LOGO=a\nLOGO=b\n").as_deref(), Some("b"));
        for bad in [
            "NAME=Telamon\n",
            "LOGO=\n",
            "LOGO=/usr/share/x.svg\n",
            "#LOGO=atlasos\n",
            "PRETTY_LOGO=atlasos\n",
        ] {
            assert_eq!(logo(bad), None, "{bad:?}");
        }
    }

    #[test]
    fn missing_file_is_none() {
        assert_eq!(
            OsRelease::load_from(Path::new("/nonexistent/os-release")),
            None
        );
    }

    #[test]
    fn load_from_refuses_big_files_and_fifos() {
        let d = tempfile::tempdir().unwrap();
        let big = d.path().join("big");
        std::fs::write(&big, vec![b'#'; 1024 * 1024 + 1]).unwrap();
        assert_eq!(OsRelease::load_from(&big), None);
        let fifo = d.path().join("fifo");
        let c = std::ffi::CString::new(fifo.to_str().unwrap()).unwrap();
        // SAFETY: a NUL-terminated path.
        assert_eq!(unsafe { libc::mkfifo(c.as_ptr(), 0o600) }, 0);
        assert_eq!(OsRelease::load_from(&fifo), None); // and does not block
        let dir = d.path().join("dir");
        std::fs::create_dir(&dir).unwrap();
        assert_eq!(OsRelease::load_from(&dir), None);
    }

    mod props {
        use super::*;
        use proptest::prelude::*;

        proptest! {
            #[test]
            fn prop_parse_never_panics_and_fields_come_from_the_text(t in any::<String>()) {
                let r = OsRelease::parse(&t);
                for f in [&r.id, &r.name, &r.version, &r.version_id, &r.pretty_name,
                          &r.logo, &r.home_url, &r.bug_report_url] {
                    prop_assert!(f.len() <= t.len());
                }
                prop_assert!(!r.display_name().is_empty());
                if let Some(icon) = r.logo_icon() {
                    prop_assert!(!icon.is_empty());
                    prop_assert!(icon.chars().all(|c| c.is_ascii_alphanumeric()
                        || matches!(c, '-' | '_' | '.' | '+')));
                }
            }

            #[test]
            fn prop_parse_survives_os_release_shaped_text(
                lines in proptest::collection::vec(
                    ("[A-Z_]{0,16}", prop_oneof!["[ -~]{0,24}", "\"[ -~]{0,16}\"?", "'[ -~]{0,16}'?"]),
                    0..12
                )
            ) {
                let t: String = lines.iter().map(|(k, v)| format!("{k}={v}\n")).collect();
                let r = OsRelease::parse(&t);
                prop_assert!(!r.display_name().is_empty());
                // the last LOGO= line decides, the way a shell source would
                let logo = lines.iter().rev().find(|(k, _)| k == "LOGO").map(|(_, v)| v);
                prop_assert_eq!(logo.is_some() && !r.logo.is_empty(), logo.is_some_and(|v| !unquote(v.trim()).is_empty()));
            }

            #[test]
            fn prop_unquote_never_panics(v in any::<String>()) {
                let u = unquote(&v);
                prop_assert!(u.len() <= v.len());
            }
        }
    }
}
