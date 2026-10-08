# tools

Checks that keep the rules in `docs/DESIGN.md` ("Compatibility" and the design
rules) from depending on someone remembering them. CI runs all of them.

| Tool | What it does |
|---|---|
| `dev-check.sh [Type...]` | From the host: the whole local check in the dev container (build, qmllint, tests in parallel, API, gallery lint) in about 25 s; type names limit the visual and a11y tests to those demos; `--translations` rewrites the catalogue first. It needs an absolute `TELAMON_DEV_BUILD_DIR`, holds a lock on the build directory, and does not run the Rust crates. |
| `check-api.sh [build]` | Dumps the API of the built Telamon.Ui (`apidump`) and compares it with `api/`. A removed or changed line fails with `BREAKING: removed or renamed`; an added line fails with `API grew: run tools/update-api.sh and raise the minor version`. Also fails when `api/` changed since the last `v*` tag and `Version:` in `packaging/telamon-framework.spec` is not greater than that tag (skipped, with a notice, while there is no tag). |
| `update-api.sh [build]` | Rewrites `api/telamon-ui.api` and `api/symbols.txt`. Commit them with the change. |
| `check-app-names.sh <app-dir>...` | Fails when an app has a `.qml` file named like a Telamon.Ui type (`import Telamon.Ui` would hide it). |
| `lint-app.sh [--allow-empty] [--strict] <app-dir>...` | (An app that still imports Atlas.Ui 1.x is read with the new names, so these rules apply to it too.) Design rule 6: errors for QQC2/Kirigami `Button`, `ToolButton`, `RoundButton`, `DelayButton`, `Switch` and `Kirigami.ActionToolBar`; warnings for default controls Telamon.Ui now replaces (`Kirigami.PasswordField` and a `TextField` or `TelamonTextField` with a Password `echoMode` point to `TelamonPasswordField`), and a `TelamonPasswordField` that sets `echoMode` or `inputMethodHints`; also `Kirigami.PlaceholderMessage` (`TelamonEmptyState`), `Kirigami.Heading` (`TelamonLabel`), a QQC2 `ToolTip` (`TelamonToolTip`), a hand-made tinted banner (`InfoBanner`) and every name in `tools/deprecated.txt`. Also warns on raw values where TelamonStyle has a token: colour strings (`"#rgb"`, `"#rrggbb"`, `"#aarrggbb"`, a named colour such as `"red"` in a `color:` binding, `Qt.rgba`/`Qt.hsla`/`Qt.hsva` with literal numbers) point to a `TelamonStyle` colour, a literal `duration:` in an animation to `TelamonStyle.durationShort`, `duration` or `durationLong`, and a literal `radius:` other than 0 to `TelamonStyle.radiusSmall`, `radius`, `radiusLarge` or `radiusPill`. Warnings never change the exit code (only an error, or no QML file, exits 1) unless `--strict` is given, which makes any warning exit 1 too; CI uses it on the gallery and the template. `tests/lint/run.sh` tests these rules (ctest `lint`). `// telamon-lint: allow <reason>` (`atlas-lint:` before 2.0.0) on the line or the line before silences a finding; `// telamon-lint: allow-raw` does the same for the raw-value rules. |
| `telamon-preview <file.qml> --out <dir> [--size WxH] [-I <path>]...` | Installed with Telamon.Ui (`/usr/bin/telamon-preview`; `build/telamon-preview` in a build tree). Loads an app's page or component offscreen in the visual-test matrix (light, dark, accent, opaque, rtl, text200, compact, contrast) and writes `<dir>/<name>-<variant>.png` for each, plus `<dir>/<name>-warnings.txt` when QML warned. Exit 0: clean; 1: pictures written but QML warned (the warnings are on stderr, once each with the variants that raised them); 2: a bad argument or a file that would not load. `--size` is the picture's size (default 900x700; a window root keeps its own); `-I` adds a QML import path, and `QML_IMPORT_PATH` works as for any Qt app. A page that is an `Item` is put on the theme's background; a `Window` is grabbed as it is. Needs `dbus-daemon` and the org.kde.desktop style (`kf6-qqc2-desktop-style`; exit 2 without it). Every variant runs on a private session bus of its own with no service directories, so a page cannot reach the user's notifications, shortcuts or portal; the contrast variant adds a settings-portal stand-in on it. `--size` is at most 4096x4096. It writes each file next to its name and renames it into place (a symbolic link at the name is replaced, never written through), refuses an `--out` that is a link, is not yours or that others can write to (exit 2), creates a new `--out` with mode 0700, replaces control characters in messages with `?` (continuation lines start with `  | `), and stops its helpers on SIGINT, SIGTERM or SIGHUP. Its helpers (the bus, the portal stand-in, the renders) end with it even when it is killed with SIGKILL. The `--internal-*` options are private to the tool (it runs them itself, and they refuse to run without a random token it sets in the environment); don't use them. It uses the offscreen platform unless `QT_QPA_PLATFORM` is set, so it never opens a window on a desktop. About 2 s for a small page (8 renders, a few at a time). `tests/preview/run.sh` tests it (ctest `preview`); the variants' code is shared with `tests/visual` in `tools/preview/variant.cpp`. |
| `docs.py check` / `docs.py build <dir>` | The reference docs in `docs/reference` (published on telamon.eterneon.net/framework; `docs/reference/README.md` is the contract). `check` also fails when a type in `api/telamon-ui.api` has no page or a public member is not in a table's first cell, a heading or a list item's start on its page (`--root` skips this unless `--api FILE` is given): the pages are the single source for the API, so change the page in the same commit as the API. It fails on missing or over-long frontmatter, raw HTML, a `#` heading, a code fence without a language, a broken relative link or anchor, an image without alt text or outside `<library>/images/`, and the site's size limits. `build` also writes the pages, images and `index.json` that CI force-pushes to the `docs-published` branch from main. Standard library only. |
| `migrate-app-to-telamon.sh [--dry-run] [--rev <sha>] [--no-pin] [--allow-dirty] [app dir]` | Run in an app's repository: moves it from Atlas.Ui 1.x to Telamon.Ui 2.0.0. Rewrites, as whole words and only names the framework had, `import Atlas.Ui` and the `Atlas<Name>` types, the crates and their `use` paths, the framework pin (`tag = "v2.0.0"`, or `--rev`), C includes and functions, CMake's module check, the spec's `Requires:`/`BuildRequires:` (to `>= 2.0.0`), CI references, environment variables, font family strings, and renames `atlas-<x>.notifyrc`. Prints each file and what it changed, what still says "atlas" and what to do by hand; refuses a dirty tree; a second run changes nothing. See "Migrating from Atlas.Ui 1.x" in `CHANGELOG.md`. |
| `check-coexistence.sh <atlas rpm dir> <telamon rpm dir>` | In a `fedora:44` container: the Atlas.Ui 1.x RPMs and these ones share no file path, install together with dnf with no conflict, and a QML file importing each module loads (needs `podman`). |
| `make-bundle.sh [--app-dir D] [--spec S] [--out DIR] [--version V] [--stage DIR]` | In an app's repository, inside the `fedora:44` build container with `telamon-ui` installed: builds the app with CMake (Release, the stage as prefix), checks that nothing in the install holds the stage or build path, packs `<id>-<version>-x86_64.tar.zst` and `telamon-bundle.json` (a reproducible tar, sha256 of every file) for Telamon Store and verifies them again from the archive. `--exclude PATH` leaves a legacy file out. The format, the install layout and the three steps that connect an app are in [`docs/BUNDLES.md`](../docs/BUNDLES.md). |
| `bundle.py version / pack / verify` | What `make-bundle.sh` calls: `pack` makes the archive and manifests from an installed tree, `verify <archive> <manifest>` checks a bundle against the format (the reference for readers). Standard library and `zstd` only. |
| `test-make-bundle.sh` | Tests the two on a tiny fake app: layout, manifest, hashes, a byte-identical second build, and every kind of bad bundle refused (about 10 s; needs `cmake`, `python3`, `zstd`; `dev-check.sh` and CI run it). |
| `apps.txt` | The Telamon.Ui apps (`github.com/EternalCoder454/<name>`); CI clones each and runs the two app checks. |
| `../packaging/build-rpm.sh <out dir>` | The RPMs, inside `fedora:44` as root. Built from `HEAD` with `git archive` (spec included): a dirty tree is refused unless `TELAMON_ALLOW_DIRTY=1`, and then its changes are not built. From a git worktree, also mount `git rev-parse --path-format=absolute --git-common-dir` read-only at the same path. |

`check-api.sh` and `update-api.sh` need a build with `-DTELAMON_UI_TESTS=ON`
(in the dev container):

```sh
cmake -S . -B build -G Ninja -DTELAMON_UI_TESTS=ON && cmake --build build
tools/check-api.sh build
```

## Checking an app

An app calls the reusable workflow. Put this in `.github/workflows/telamon.yml`:

```yaml
name: Telamon checks
on: [push, pull_request]
jobs:
  telamon:
    uses: EternalCoder454/atlas-framework/.github/workflows/app-checks.yml@main
    # with: { framework-ref: main }   # a tag or a full 40-character commit sha pins the rules
```

The workflow checks out the app and the framework's tools, then runs
`lint-app.sh` and `check-app-names.sh` on the app. `framework-ref` is a
branch, a tag or a full 40-character sha: the workflow fetches that exact ref,
and GitHub does not serve a short sha. Run them by hand with
`tools/lint-app.sh path/to/app` (`--allow-empty` for an app with no QML; an
empty directory otherwise fails).

## Shipping an app as a native bundle

An app that is not in the OS image calls the reusable `bundle.yml` from a `v*`
tag; it builds the app against this framework's `telamon-ui` in `fedora:44`,
and attaches the bundle to the release, where Telamon Store finds it. The
caller's file and the other two steps are in
[`docs/BUNDLES.md`](../docs/BUNDLES.md#connecting-an-app).

## Previewing an app's pages in CI

`telamon-preview` needs a Qt platform that can render; under `xvfb-run` it also
works with `QT_QPA_PLATFORM=xcb`. An example step for an app's workflow (the
pictures are uploaded so a reviewer can look; the step fails on QML warnings):

```yaml
      - name: Preview the pages
        run: |
          for page in qml/MainPage.qml qml/SettingsPage.qml; do
            xvfb-run -a -s "-screen 0 1920x1080x24" \
              telamon-preview "$page" --out preview -I build/qml || rc=$?
          done
          exit "${rc:-0}"
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: preview, path: preview }
```

Exit 1 means QML warnings and 2 a page that did not load; the loop keeps the
last non-zero code. There is no reference page for the tools: `docs/reference`
holds the libraries only, so `tools/README.md` is where they are described.
