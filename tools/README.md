# tools

Checks that keep the rules in `docs/DESIGN.md` ("Compatibility" and the design
rules) from depending on someone remembering them. CI runs all of them.

| Tool | What it does |
|---|---|
| `dev-check.sh [Type...]` | From the host: the whole local check in the dev container (build, qmllint, tests in parallel, API, gallery lint) in about 25 s; type names limit the visual and a11y tests to those demos; `--translations` rewrites the catalogue first. |
| `check-api.sh [build]` | Dumps the API of the built Atlas.Ui (`apidump`) and compares it with `api/`. A removed or changed line fails with `BREAKING: removed or renamed`; an added line fails with `API grew: run tools/update-api.sh and raise the minor version`. Also fails when `api/` changed since the last `v*` tag and `Version:` in `packaging/atlas-framework.spec` is not greater than that tag (skipped, with a notice, while there is no tag). |
| `update-api.sh [build]` | Rewrites `api/atlas-ui.api` and `api/symbols.txt`. Commit them with the change. |
| `check-app-names.sh <app-dir>...` | Fails when an app has a `.qml` file named like an Atlas.Ui type (`import Atlas.Ui` would hide it). |
| `lint-app.sh <app-dir>...` | Design rule 6: errors for QQC2/Kirigami `Button`, `ToolButton`, `RoundButton`, `DelayButton`, `Switch` and `Kirigami.ActionToolBar`; warnings for default controls Atlas.Ui now replaces (`Kirigami.PasswordField` and a `TextField` or `AtlasTextField` with a Password `echoMode` point to `AtlasPasswordField`), and an `AtlasPasswordField` that sets `echoMode` or `inputMethodHints`; also `Kirigami.PlaceholderMessage` (`AtlasEmptyState`), `Kirigami.Heading` (`AtlasLabel`), a QQC2 `ToolTip` (`AtlasToolTip`), a hand-made tinted banner (`InfoBanner`) and every name in `tools/deprecated.txt`. `tests/lint/run.sh` tests these rules (ctest `lint`). `// atlas-lint: allow <reason>` on the line or the line before silences a finding. |
| `apps.txt` | The Atlas.Ui apps (`github.com/EternalCoder454/<name>`); CI clones each and runs the two app checks. |

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
    # with: { framework-ref: main }   # a tag or commit pins the rules the app is checked against
```

The workflow checks out the app and the framework's tools, then runs
`lint-app.sh` and `check-app-names.sh` on the app. Run them by hand with
`tools/lint-app.sh path/to/app`.
