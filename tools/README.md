# tools

Checks that keep the rules in `docs/DESIGN.md` ("Compatibility" and the design
rules) from depending on someone remembering them. CI runs all of them.

| Tool | What it does |
|---|---|
| `dev-check.sh [Type...]` | From the host: the whole local check in the dev container (build, qmllint, tests in parallel, API, gallery lint) in about 25 s; type names limit the visual and a11y tests to those demos; `--translations` rewrites the catalogue first. It needs an absolute `ATLAS_DEV_BUILD_DIR`, holds a lock on the build directory, and does not run the Rust crates. |
| `check-api.sh [build]` | Dumps the API of the built Atlas.Ui (`apidump`) and compares it with `api/`. A removed or changed line fails with `BREAKING: removed or renamed`; an added line fails with `API grew: run tools/update-api.sh and raise the minor version`. Also fails when `api/` changed since the last `v*` tag and `Version:` in `packaging/atlas-framework.spec` is not greater than that tag (skipped, with a notice, while there is no tag). |
| `update-api.sh [build]` | Rewrites `api/atlas-ui.api` and `api/symbols.txt`. Commit them with the change. |
| `check-app-names.sh <app-dir>...` | Fails when an app has a `.qml` file named like an Atlas.Ui type (`import Atlas.Ui` would hide it). |
| `lint-app.sh [--allow-empty] [--strict] <app-dir>...` | Design rule 6: errors for QQC2/Kirigami `Button`, `ToolButton`, `RoundButton`, `DelayButton`, `Switch` and `Kirigami.ActionToolBar`; warnings for default controls Atlas.Ui now replaces (`Kirigami.PasswordField` and a `TextField` or `AtlasTextField` with a Password `echoMode` point to `AtlasPasswordField`), and an `AtlasPasswordField` that sets `echoMode` or `inputMethodHints`; also `Kirigami.PlaceholderMessage` (`AtlasEmptyState`), `Kirigami.Heading` (`AtlasLabel`), a QQC2 `ToolTip` (`AtlasToolTip`), a hand-made tinted banner (`InfoBanner`) and every name in `tools/deprecated.txt`. Also warns on raw values where AtlasStyle has a token: colour strings (`"#rgb"`, `"#rrggbb"`, `"#aarrggbb"`, a named colour such as `"red"` in a `color:` binding, `Qt.rgba`/`Qt.hsla`/`Qt.hsva` with literal numbers) point to an `AtlasStyle` colour, a literal `duration:` in an animation to `AtlasStyle.durationShort`, `duration` or `durationLong`, and a literal `radius:` other than 0 to `AtlasStyle.radiusSmall`, `radius`, `radiusLarge` or `radiusPill`. Warnings never change the exit code (only an error, or no QML file, exits 1) unless `--strict` is given, which makes any warning exit 1 too; CI uses it on the gallery and the template. `tests/lint/run.sh` tests these rules (ctest `lint`). `// atlas-lint: allow <reason>` on the line or the line before silences a finding; `// atlas-lint: allow-raw` does the same for the raw-value rules. |
| `atlas-preview <file.qml> --out <dir> [--size WxH] [-I <path>]...` | Installed with Atlas.Ui (`/usr/bin/atlas-preview`; `build/atlas-preview` in a build tree). Loads an app's page or component offscreen in the visual-test matrix (light, dark, accent, opaque, rtl, text200, compact, contrast) and writes `<dir>/<name>-<variant>.png` for each, plus `<dir>/<name>-warnings.txt` when QML warned. Exit 0: clean; 1: pictures written but QML warned (the warnings are on stderr, once each with the variants that raised them); 2: a bad argument or a file that would not load. `--size` is the picture's size (default 900x700; a window root keeps its own); `-I` adds a QML import path, and `QML_IMPORT_PATH` works as for any Qt app. A page that is an `Item` is put on the theme's background; a `Window` is grabbed as it is. Needs `dbus-run-session` and the org.kde.desktop style (`kf6-qqc2-desktop-style`; exit 2 without it). Every variant runs on a private session bus of its own with no service directories, so a page cannot reach the user's notifications, shortcuts or portal; the contrast variant adds a settings-portal stand-in on it. `--size` is at most 4096x4096. It refuses to write a picture or warnings file through a symbolic link, creates a new `--out` with mode 0700, replaces control characters in messages with `?`, and stops its children when it gets SIGINT or SIGTERM. The `--internal-*` options are private to the tool (it runs them itself, and they refuse to run without a random token it sets in the environment); don't use them. It uses the offscreen platform unless `QT_QPA_PLATFORM` is set, so it never opens a window on a desktop. About 2 s for a small page (8 renders, a few at a time). `tests/preview/run.sh` tests it (ctest `preview`); the variants' code is shared with `tests/visual` in `tools/preview/variant.cpp`. |
| `docs.py check` / `docs.py build <dir>` | The reference docs in `docs/reference` (published on atlasos.eterneon.net/framework; `docs/reference/README.md` is the contract). `check` also fails when a type in `api/atlas-ui.api` has no page or a public member is not in a table's first cell, a heading or a list item's start on its page (`--root` skips this unless `--api FILE` is given): the pages are the single source for the API, so change the page in the same commit as the API. It fails on missing or over-long frontmatter, raw HTML, a `#` heading, a code fence without a language, a broken relative link or anchor, an image without alt text or outside `<library>/images/`, and the site's size limits. `build` also writes the pages, images and `index.json` that CI force-pushes to the `docs-published` branch from main. Standard library only. |
| `apps.txt` | The Atlas.Ui apps (`github.com/EternalCoder454/<name>`); CI clones each and runs the two app checks. |
| `../packaging/build-rpm.sh <out dir>` | The RPMs, inside `fedora:44` as root. Built from `HEAD` with `git archive` (spec included): a dirty tree is refused unless `ATLAS_ALLOW_DIRTY=1`, and then its changes are not built. From a git worktree, also mount `git rev-parse --path-format=absolute --git-common-dir` read-only at the same path. |

`check-api.sh` and `update-api.sh` need a build with `-DATLAS_UI_TESTS=ON`
(in the dev container):

```sh
cmake -S . -B build -G Ninja -DATLAS_UI_TESTS=ON && cmake --build build
tools/check-api.sh build
```

## Checking an app

An app calls the reusable workflow. Put this in `.github/workflows/atlas.yml`:

```yaml
name: Atlas checks
on: [push, pull_request]
jobs:
  atlas:
    uses: EternalCoder454/atlas-framework/.github/workflows/app-checks.yml@main
    # with: { framework-ref: main }   # a tag or a full 40-character commit sha pins the rules
```

The workflow checks out the app and the framework's tools, then runs
`lint-app.sh` and `check-app-names.sh` on the app. `framework-ref` is a
branch, a tag or a full 40-character sha: the workflow fetches that exact ref,
and GitHub does not serve a short sha. Run them by hand with
`tools/lint-app.sh path/to/app` (`--allow-empty` for an app with no QML; an
empty directory otherwise fails).

## Previewing an app's pages in CI

`atlas-preview` needs a Qt platform that can render; under `xvfb-run` it also
works with `QT_QPA_PLATFORM=xcb`. An example step for an app's workflow (the
pictures are uploaded so a reviewer can look; the step fails on QML warnings):

```yaml
      - name: Preview the pages
        run: |
          for page in qml/MainPage.qml qml/SettingsPage.qml; do
            xvfb-run -a -s "-screen 0 1920x1080x24" \
              atlas-preview "$page" --out preview -I build/qml || rc=$?
          done
          exit "${rc:-0}"
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: preview, path: preview }
```

Exit 1 means QML warnings and 2 a page that did not load; the loop keeps the
last non-zero code. There is no reference page for the tools: `docs/reference`
holds the libraries only, so `tools/README.md` is where they are described.
