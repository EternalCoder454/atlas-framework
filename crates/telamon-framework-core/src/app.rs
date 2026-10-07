//! Who the running app is: one value names its settings file, its journal
//! entries, its crash reports and its links.

use serde::{Deserialize, Serialize};

/// Identifies a Telamon app. Build it with [`app_info!`](crate::app_info),
/// which takes the version from the app's own Cargo.toml.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppInfo {
    /// The name people see, e.g. `Telamon Updater`.
    pub name: String,
    /// Reverse-DNS app ID, e.g. `net.eterneon.telamon.updater`. It is also the
    /// desktop file name, the icon name and the single-instance D-Bus name.
    pub id: String,
    pub version: String,
    /// Repository under `github.com/EternalCoder454/`, e.g. `atlasos-updater`.
    pub repo: String,
}

/// An [`AppInfo`] with the calling crate's version:
///
/// ```
/// let app = telamon_framework_core::app_info! {
///     name: "Telamon Notepad",
///     id: "net.eterneon.telamon.notepad",
///     repo: "atlasos-notepad",
/// };
/// assert_eq!(app.short_name(), "telamon-notepad");
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
const BRAND_PREFIX: &str = "telamon-";
const LEGACY_PREFIX: &str = "atlas-";

impl AppInfo {
    /// `telamon-updater` for `net.eterneon.telamon.updater`: `telamon-` and the
    /// last part of the ID (without a `telamon-` or `atlas-` of its own). Names
    /// the settings file (`telamon-updaterrc`) and the journal identifier.
    /// Characters outside `[a-z0-9_-]` become `_`, and it is at most 64
    /// characters, so the result is always a safe file name.
    pub fn short_name(&self) -> String {
        self.name_with(BRAND_PREFIX, "telamon-app")
    }

    /// What [`short_name`](Self::short_name) was before 2.0.0, when the
    /// framework was called Atlas: `atlas-updater` for
    /// `net.eterneon.atlas.updater` (and for `net.eterneon.telamon.updater`).
    /// Only for finding files an earlier version wrote, such as
    /// `atlas-updaterrc`, which [`Settings::for_app`](crate::settings::Settings::for_app)
    /// copies to the new name the first time.
    pub fn legacy_short_name(&self) -> String {
        self.name_with(LEGACY_PREFIX, "atlas-app")
    }

    fn name_with(&self, prefix: &str, empty: &str) -> String {
        let last = self.id.rsplit('.').next().unwrap_or_default();
        let last = [BRAND_PREFIX, LEGACY_PREFIX]
            .iter()
            .find_map(|p| {
                last.get(..p.len())
                    .filter(|head| head.eq_ignore_ascii_case(p))
                    .map(|_| &last[p.len()..])
            })
            .unwrap_or(last);
        let safe: String = last
            .chars()
            .take(64 - prefix.len())
            .map(|c| match c {
                'a'..='z' | '0'..='9' | '_' | '-' => c,
                'A'..='Z' => c.to_ascii_lowercase(),
                _ => '_',
            })
            .collect();
        if safe.is_empty() {
            empty.into()
        } else {
            format!("{prefix}{safe}")
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
            app("net.eterneon.telamon.updater", "").short_name(),
            "telamon-updater"
        );
        assert_eq!(
            app("net.eterneon.telamon.Monitor", "").short_name(),
            "telamon-monitor"
        );
        assert_eq!(
            app("net.eterneon.telamon.a/b c", "").short_name(),
            "telamon-a_b_c"
        );
        assert_eq!(app("", "").short_name(), "telamon-app");
        assert_eq!(app("x.telamon-notes", "").short_name(), "telamon-notes");
        assert_eq!(app("x.Telamon-Notes", "").short_name(), "telamon-notes");
        assert_eq!(app(&"y".repeat(300), "").short_name().len(), 64);
        // An ID that still has the old brand names the same file as before,
        // under the new prefix.
        assert_eq!(
            app("net.eterneon.atlas.updater", "").short_name(),
            "telamon-updater"
        );
        assert_eq!(app("x.atlas-notes", "").short_name(), "telamon-notes");
        assert_eq!(app("x.Atlas-Notes", "").short_name(), "telamon-notes");
    }

    #[test]
    fn legacy_short_name_is_what_1_x_made() {
        let l = |id: &str| app(id, "").legacy_short_name();
        assert_eq!(l("net.eterneon.atlas.updater"), "atlas-updater");
        assert_eq!(l("net.eterneon.telamon.updater"), "atlas-updater");
        assert_eq!(l("net.eterneon.atlas.Monitor"), "atlas-monitor");
        assert_eq!(l("net.eterneon.atlas.a/b c"), "atlas-a_b_c");
        assert_eq!(l(""), "atlas-app");
        assert_eq!(l("x.atlas-notes"), "atlas-notes");
        assert_eq!(l("x.Atlas-Notes"), "atlas-notes");
        assert_eq!(l(&"y".repeat(300)).len(), 64);
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
        let a = crate::app_info! { name: "N", id: "net.eterneon.telamon.n", repo: "r" };
        assert_eq!(a.version, env!("CARGO_PKG_VERSION"));
    }
}
