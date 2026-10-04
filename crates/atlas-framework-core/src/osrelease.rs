//! The OS name, version and logo from os-release(5), for About pages and
//! crash reports. Only the system's own files are read.

use std::path::Path;

/// The fields Atlas apps show. Missing fields are empty.
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
        std::fs::read_to_string(path).ok().map(|t| Self::parse(&t))
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
            "# comment\nNAME=\"AtlasOS\"\nVERSION='44.20261003'\nID=atlasos\n\
             PRETTY_NAME=\"AtlasOS \\\"Lead\\\" \\$1\"\nLOGO=atlasos-logo\nOTHER=x\nbroken\n",
        );
        assert_eq!(r.name, "AtlasOS");
        assert_eq!(r.version, "44.20261003");
        assert_eq!(r.id, "atlasos");
        assert_eq!(r.pretty_name, "AtlasOS \"Lead\" $1");
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
            logo("NAME=Atlas\nLOGO=atlasos\n").as_deref(),
            Some("atlasos")
        );
        assert_eq!(
            logo("LOGO=\"fedora-logo-icon\"").as_deref(),
            Some("fedora-logo-icon")
        );
        assert_eq!(logo("LOGO='x'\r\n").as_deref(), Some("x"));
        assert_eq!(logo("LOGO=a\nLOGO=b\n").as_deref(), Some("b"));
        for bad in [
            "NAME=Atlas\n",
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
}
