//! Who the running app is: one value names its settings file, its journal
//! entries, its crash reports and its links.

use serde::{Deserialize, Serialize};

/// Identifies an Atlas app. Build it with [`app_info!`](crate::app_info),
/// which takes the version from the app's own Cargo.toml.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppInfo {
    /// The name people see, e.g. `Atlas Updater`.
    pub name: String,
    /// Reverse-DNS app ID, e.g. `net.eterneon.atlas.updater`. It is also the
    /// desktop file name, the icon name and the single-instance D-Bus name.
    pub id: String,
    pub version: String,
    /// Repository under `github.com/EternalCoder454/`, e.g. `atlasos-updater`.
    pub repo: String,
}

/// An [`AppInfo`] with the calling crate's version:
///
/// ```
/// let app = atlas_framework_core::app_info! {
///     name: "Atlas Notepad",
///     id: "net.eterneon.atlas.notepad",
///     repo: "atlasos-notepad",
/// };
/// assert_eq!(app.short_name(), "atlas-notepad");
/// ```
#[macro_export]
macro_rules! app_info {
    (name: $name:expr, id: $id:expr, repo: $repo:expr $(,)?) => {
        $crate::AppInfo {
            name: ::std::string::String::from($name),
            id: ::std::string::String::from($id),
            version: ::std::string::String::from(env!("CARGO_PKG_VERSION")),
            repo: ::std::string::String::from($repo),
        }
    };
}

const GITHUB: &str = "https://github.com/EternalCoder454/";

impl AppInfo {
    /// `atlas-updater` for `net.eterneon.atlas.updater`: `atlas-` and the
    /// last part of the ID (without an `atlas-` of its own). Names the
    /// settings file (`atlas-updaterrc`) and the journal identifier.
    /// Characters outside `[a-z0-9_-]` become `_`, and it is at most 64
    /// characters, so the result is always a safe file name.
    pub fn short_name(&self) -> String {
        let last = self.id.rsplit('.').next().unwrap_or_default();
        let last = last.strip_prefix("atlas-").unwrap_or(last);
        let safe: String = last
            .chars()
            .take(58)
            .map(|c| match c {
                'a'..='z' | '0'..='9' | '_' | '-' => c,
                'A'..='Z' => c.to_ascii_lowercase(),
                _ => '_',
            })
            .collect();
        if safe.is_empty() {
            "atlas-app".into()
        } else {
            format!("atlas-{safe}")
        }
    }

    /// The repository's page, or `None` if `repo` isn't a plain repository
    /// name (so a bad value can't point a link somewhere else).
    pub fn source_url(&self) -> Option<String> {
        let ok = !self.repo.is_empty()
            && self.repo != "."
            && self.repo != ".."
            && self
                .repo
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'));
        ok.then(|| format!("{GITHUB}{}", self.repo))
    }

    /// Where people report problems with the app.
    pub fn issues_url(&self) -> Option<String> {
        self.source_url().map(|u| u + "/issues")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn app(id: &str, repo: &str) -> AppInfo {
        AppInfo {
            name: "X".into(),
            id: id.into(),
            version: "1".into(),
            repo: repo.into(),
        }
    }

    #[test]
    fn short_name() {
        assert_eq!(
            app("net.eterneon.atlas.updater", "").short_name(),
            "atlas-updater"
        );
        assert_eq!(
            app("net.eterneon.atlas.Monitor", "").short_name(),
            "atlas-monitor"
        );
        assert_eq!(
            app("net.eterneon.atlas.a/b c", "").short_name(),
            "atlas-a_b_c"
        );
        assert_eq!(app("", "").short_name(), "atlas-app");
        assert_eq!(app("x.atlas-notes", "").short_name(), "atlas-notes");
        assert_eq!(app(&"y".repeat(300), "").short_name().len(), 64);
    }

    #[test]
    fn urls_only_for_plain_repo_names() {
        let a = app("x", "atlasos-updater");
        assert_eq!(
            a.issues_url().as_deref(),
            Some("https://github.com/EternalCoder454/atlasos-updater/issues")
        );
        for bad in ["", "..", "a/b", "x?y", "a b", "evil.example/x"] {
            assert_eq!(app("x", bad).source_url(), None, "{bad}");
        }
    }

    #[test]
    fn macro_takes_caller_version() {
        let a = crate::app_info! { name: "N", id: "net.eterneon.atlas.n", repo: "r" };
        assert_eq!(a.version, env!("CARGO_PKG_VERSION"));
    }
}
