---
title: Start a new app
summary: Copy the template into a new repository and rename the crate, QML module, app ID, desktop file, notification file and binary.
order: 10
---

1. Copy the template directory to the new app's repository.
2. Rename, by search and replace in every file, and rename the files that carry the name:

   | What | Template value | Where |
   |---|---|---|
   | Crate and library | `atlas-app-template`, `atlas_app_template` | `Cargo.toml`, `CMakeLists.txt` |
   | QML module URI | `net.eterneon.atlas.apptemplate` | `CMakeLists.txt`, `main.cpp` |
   | App ID, desktop file | `net.eterneon.atlas.apptemplate` | `main.cpp`, `src/lib.rs`, `data/` |
   | Name and repository | `name: "Atlas App"`, `repo: "atlas-framework"` | `app!` in `src/lib.rs` |
   | Notification file | `data/atlas-apptemplate.notifyrc` | named `atlas-` plus the last part of the app ID; its `DesktopEntry=` and `IconName=` are the app ID |
   | Binary name | `atlas-app-template` | `CMakeLists.txt`, `main.cpp` |
   | Optional | `atlas_backend_new`, the `atlas_app` C++ namespace | `src/lib.rs`, `main.cpp`, `src/backend.rs` |

3. In `Cargo.toml`, take `atlas-framework-ui` from git, pinned to a release tag (the comment there shows the line), and add [atlas-framework-system](../atlas-framework-system/index.md) or [atlas-framework-flatpak](../atlas-framework-flatpak/index.md) only if the app needs them:

   ```toml
   atlas-framework-ui = { git = "https://github.com/EternalCoder454/atlas-framework", tag = "v1.4.0" }
   ```

   The template's own `Cargo.toml` uses `path = "../crates/..."` dependencies, because it sits in the framework's checkout; replace them.
4. Give the app's RPM `Requires: atlas-ui` and `BuildRequires: atlas-ui` with `>= X.Y.Z`, the same version as `ui:` in the `app!` call in `src/lib.rs` (the template says `1.3.0`). Keep the two equal. See [Compatibility](../atlas-ui/compatibility.md).
5. Add properties and invokables to `src/backend.rs`, pages to `qml/`, and list each page in `QML_FILES` in `CMakeLists.txt`.
6. Run the framework's checks in the app's CI: `tools/lint-app.sh <app dir>` and `tools/check-app-names.sh <app dir>`.
