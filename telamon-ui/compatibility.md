---
title: Compatibility
summary: Telamon.Ui's API is a contract with every Telamon app: it only grows, and what that means for the app's version requirements and names.
section: Guides
order: 40
---

Telamon.Ui's API is a contract with every Telamon app: its type names, their properties, signals, functions and enum values, the singletons and `Symbols.<Name>`. Apps are built separately and updated separately, so a change that breaks an app breaks it on users' machines.

## What an app can count on

- **Additions only.** A type, property, signal, function, enum value or symbol name is never renamed or removed in a later minor version. A new property has a default that keeps the old look.
- **Versions.** A release that adds something raises the minor version (2.0.0 to 2.1.0). Telamon.Ui starts at 2.0.0, the first release after the rename from Atlas.Ui; a `since` below 2.0.0 names the Atlas.Ui release that added the subject. Each page here says which version added its subject (`since`); a page without `since` has been there since 1.0.0.
- **The rename.** 2.0.0 renamed every `Atlas<Name>` type to `Telamon<Name>` and the module to `Telamon.Ui`, and nothing else; the migration is in `CHANGELOG.md`, and `tools/migrate-app-to-telamon.sh` does it for an app. The old and the new packages install side by side while apps move.
- **A rename or removal** needs every Telamon app updated first, in the same Telamon OS build, and a new major version. The old name is kept working when it can be.
- **Deprecation.** Something can be deprecated for one more minor version before it is removed in the next major. It keeps working, its page says what to use instead, and `tools/lint-app.sh` warns (not errors) when an app uses it.
- **The look can change.** Colours, spacing and radii may change when the change follows the [design rules](design-rules.md). Every app changes with it, which is the point. This is why apps take colours and sizes from [TelamonStyle](telamon-style.md) and never hard-code them.

## What an app does

An app that uses something added after 1.0.0 says so twice, with the same version in both:

| Where | What | What it does |
|---|---|---|
| The app's RPM spec | `Requires: telamon-ui >= X.Y.Z` and `BuildRequires: telamon-ui >= X.Y.Z` | dnf installs a new enough Telamon.Ui |
| `app!` in `src/lib.rs` | `ui: "X.Y.Z"` | at startup an older Telamon.Ui, installed some other way, gives a plain error and exit code 1 |

C++ apps without `app!` call `telamon_app_require_ui("X.Y.Z")`. `TelamonApp.uiVersion` is the installed version, the project version in Telamon.Ui's `CMakeLists.txt`.

## Names that clash

`import Telamon.Ui` wins over the QML files in an app's own directory. A Telamon.Ui type named like an app's local type replaces it in that app, which then breaks. For that reason new Telamon.Ui types are named `Telamon<Name>` (`TelamonAboutPage`, not `AboutPage`) and checked against every Telamon app before they are added. If an app has a file named like an older Telamon.Ui type, `tools/check-app-names.sh <app dir>` finds it.

## Qt minor versions

Telamon.Ui is built against Qt's private API for ahead-of-time compiled QML, so it needs the exact Qt minor version it was built with (Qt 6.11 now). A Qt minor update (6.11 to 6.12) means rebuilding `telamon-ui`, then the apps, in the same Telamon OS build.

## Symbols

`Symbols.<Name>` is part of the contract too. When the fonts are updated and Google renames an icon, the old name stays as an alias for `Symbol.name`, and removed `Symbols.<Name>` values are treated as a break. See [Symbols](../symbols/index.md).

## The Rust crates and on-disk formats

The framework's Rust crates follow semver and an app moves to a new one by changing its `rev` or tag, so a break shows up in the app's own build. Two things are fixed across versions because separately built programs share them: the C functions in `include/telamon/app.h` (they are only added to), and anything on disk or on D-Bus (the settings file format, crash report and history files, polkit action IDs). New code reads the old form forever.
