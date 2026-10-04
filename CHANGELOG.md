# Changelog

What each atlas-framework release brings to apps. One version covers the whole
repository: Atlas.Ui (`atlas-ui`), the fonts, the gallery and the Rust crates.
Apps pin a release tag (`tag = "vX.Y.Z"` on the crates) and require the same
Atlas.Ui (`Requires: atlas-ui >= X.Y.Z`, `ui: "X.Y.Z"` in `app!`) once they use
something it added. The packaging spec's `%changelog` repeats the package side.

## 1.3.0 (unreleased)

## 1.2.0

- Atlas.Ui: TabBar, FindBar, StatusBar, StatusBarItem, InfoBanner, Toast and
  ToolbarButton (from Atlas Notepad).
- ContextMenuItem: a check mark for checked checkable rows, `icon.source`, a
  submenu arrow; hidden rows and separators take no room.
- Crates: `bootc::utc_second` and `bootc::TRANSPORTS` are public; crash
  report scrubbing handles `::` paths, quoted values and secrets in more forms.

## 1.1.0

- Atlas.Ui: AtlasApp and AtlasAboutPage.
- atlas-ui ships `/usr/share/atlas/crash-reporting.toml`: crash reports go to
  the AtlasOS relay, which posts them as GitHub issues.

## 1.0.0

- First release: Atlas.Ui, atlas-symbols-fonts and Atlas Symbols, moved out of
  atlasos-updater, and the atlas-framework crates (startup, settings, logging,
  crash reports, polkit, Flatpak).
