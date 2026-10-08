# Native Telamon apps: bundles

A Telamon app that is not part of the OS image can be installed by Telamon Store
for one user, from the app's GitHub release, without Flatpak. The release holds
a **bundle**: the app built in a `fedora:44` container against the Telamon.Ui of
the framework, packed as a tar. Qt, KDE Frameworks and `telamon-ui` are not in
it. The binary links them from the OS image, which is the point: it was built
against the same libraries it runs on, and it starts as fast as an app of the
image does.

This page is the format (schema 1), the tools that make a bundle, and what an
app owner does to publish one. The producer side is `tools/make-bundle.sh`,
`tools/bundle.py` and `.github/workflows/bundle.yml`; the reader is Telamon
Store (`atlasos-store`).

## The release assets

A GitHub release of the tag `vX.Y.Z` carries two files:

| Asset | What it is |
|---|---|
| `<app-id>-<version>-x86_64.tar.zst` | The bundle: a zstd-compressed tar. |
| `telamon-bundle.json` | The **outer manifest**: the manifest inside the archive plus an `archive` object with the archive's name, sha256 and size. |

An archive cannot contain its own hash, so the outer manifest is the inner one
plus `archive`; a reader fetches the small JSON first, shows the app, and
checks the archive it downloads against `archive.sha256`.

## The archive

Entries are relative paths (no leading `./`, no absolute path, no `..`,
no control characters or backslashes), and only directories, regular files and
relative symlinks that stay inside the tree: no hard links, devices or fifos. Every entry
is owned by 0:0, with mode 0755 (directories, executables) or 0644 (files), and
the modification time of the commit (`SOURCE_DATE_EPOCH`). Entries are sorted
by path, and every directory has its own entry before its content.

```text
bin/                                   executables; the binary links Qt, KF6 and telamon-ui from the OS
share/applications/<app-id>.desktop   exactly one .desktop file; Exec= starts with the bare binary name
share/icons/hicolor/...               optional
share/metainfo/<app-id>.metainfo.xml  recommended: the manifest's name, summary, license and homepage come from it
share/dbus-1/services/*.service       optional; Exec= starts with the bare binary name
share/<app-id>/                       the app's data, optional (see "Data")
telamon-bundle.json                   the inner manifest, at the archive's root
```

Nothing else is at the top: there is no `lib/`, `etc/` or `libexec/`. The tool
refuses to make a bundle with a file outside `bin/` and `share/`, and a reader
must refuse to unpack one. Anything under `share/` other than the three
integration directories above stays in the app's own prefix, where the data
convention finds it.

The `.desktop` file's `Exec=` (every one: the `[Desktop Entry]` group and the
`[Desktop Action ...]` groups) starts with the name of a file in `bin/`, never
a path: `Exec=telamon-gates %U`. The `.service` files the same.

## The manifest

JSON, with the keys below in exactly this order, indented by 2 spaces, with a
trailing newline; `files` and `links` are sorted by path.

```json
{
  "schema": 1,
  "id": "net.eterneon.telamon.gates",
  "name": "Telamon Gates",
  "version": "0.1.0",
  "summary": "The AI chat of Telamon OS",
  "homepage": "https://github.com/EternalCoder454/telamon-gates",
  "license": "MIT",
  "arch": "x86_64",
  "min_telamon_ui": "2.0.2",
  "min_os_version": "44",
  "files": [
    {
      "path": "bin/telamon-gates",
      "size": 123,
      "sha256": "<hex>",
      "executable": true
    }
  ],
  "links": [],
  "archive": {
    "name": "net.eterneon.telamon.gates-0.1.0-x86_64.tar.zst",
    "sha256": "<hex>",
    "size": 456
  }
}
```

| Key | Meaning |
|---|---|
| `schema` | `1`. A reader that does not know the number refuses the bundle. |
| `id` | Reverse-DNS app ID: `[A-Za-z0-9._-]+`, starts with a letter or digit, has a dot. It is the `.desktop` file's basename and the directory name in the install layout. |
| `name`, `summary`, `license`, `homepage` | From the metainfo (`<name>`, `<summary>`, `<project_license>`, `<url type="homepage">`); without a metainfo the tool falls back to the `.desktop` file's `Name` and `Comment` and the spec's `License:` and `URL:`, and fails if one is still missing. `homepage` is an `https://` URL. |
| `version` | Dotted numbers with an optional prerelease: `0.2.0`, `1.0.0-beta.1`. The release tag without its `v`. It must agree with the numbers of `project(... VERSION)` in the app's CMake. |
| `arch` | `x86_64`, the only one. |
| `min_telamon_ui` | The oldest `telamon-ui` that runs the app: the highest `BuildRequires: telamon-ui >= X` of the app's spec (else `Requires:`), else the version of `telamon-ui` installed in the build container. QML is compiled against the types Telamon.Ui had when the app was built, so a reader refuses an OS with an older one. |
| `min_os_version` | `VERSION_ID` of the build container's `/etc/os-release` (Fedora 44: `44`). |
| `files` | Every regular file in the archive except `telamon-bundle.json`: `path`, `size`, `sha256` (lowercase hex) and `executable` (any execute bit). |
| `links` | The symlinks: `path` and the relative `target`. `[]` when there are none. |
| `archive` | In the outer manifest only: the archive's `name` (`<id>-<version>-<arch>.tar.zst`), `sha256` and `size`. |

The inner manifest in the archive is the outer one without `archive`, byte for
byte.

## Install layout (Telamon Store)

For one user, under `~/.local/share/telamon-apps/`:

```text
~/.local/share/telamon-apps/<id>/<version>/        the unpacked archive (bin/, share/, telamon-bundle.json)
~/.local/share/telamon-apps/<id>/current           symlink to <version>
```

Store then copies, from the version's directory into the user's data
directory, so Plasma, the launcher and D-Bus find the app:

- `share/applications/<id>.desktop` to `~/.local/share/applications/`, with the
  first word of every `Exec=` rewritten to the absolute path
  `~/.local/share/telamon-apps/<id>/current/bin/<name>` and `TryExec=` dropped;
- `share/icons/` to `~/.local/share/icons/`;
- `share/metainfo/` to `~/.local/share/metainfo/`;
- `share/dbus-1/services/*.service` to `~/.local/share/dbus-1/services/`, the
  `Exec=` rewritten the same way.

An update unpacks the new version beside the old one, switches `current`, and
removes the old version; a removal deletes `<id>/` and the copied files. Store
sets no environment for the app.

## Data: how an app finds its files

An app that needs files at run time (QML is compiled into the binary and
Telamon.Ui comes from the OS, so most apps need none) finds them **relative to its own
executable**: `dirname(realpath(/proc/self/exe))/../share/<app-id>/...`, and
falls back to `/usr/share/<app-id>/...` when that directory is not there (an
RPM-installed app at `/usr/bin` finds `/usr/share/<app-id>` the first way
already). Never a path fixed at build time: the build checks that the install
prefix is in no file (see below).

Rust:

```rust
fn data_dir(app_id: &str) -> Option<std::path::PathBuf> {
    let exe = std::env::current_exe().ok()?.canonicalize().ok()?;
    let bundled = exe.parent()?.join("../share").join(app_id);
    if bundled.is_dir() {
        return Some(bundled);
    }
    let system = std::path::Path::new("/usr/share").join(app_id);
    system.is_dir().then_some(system)
}
```

Qt:

```cpp
QString dataDir(const QString &appId)
{
    const QString bundled = QCoreApplication::applicationDirPath() + "/../share/" + appId;
    return QDir(bundled).exists() ? QDir::cleanPath(bundled) : "/usr/share/" + appId;
}
```

(`applicationDirPath()` is the directory of the real executable: Store starts
the app through the `current` symlink and Linux resolves it.)

## Making a bundle: `tools/make-bundle.sh`

Run it from the app's repository root **inside the `fedora:44` build container**,
with the app's build dependencies and `telamon-ui` installed. It starts no
container itself.

```sh
tools/make-bundle.sh --app-dir apps/telamon-gates --spec packaging/telamon-gates.spec --out bundle-out
```

| Option | Default |
|---|---|
| `--app-dir DIR` | The only `apps/*/CMakeLists.txt`, else `./CMakeLists.txt`. |
| `--spec FILE` | The only `packaging/*.spec`. Without a spec, `min_telamon_ui` is the installed `telamon-ui`. |
| `--out DIR` | `bundle-out`. |
| `--version V` | The CMake `project()` VERSION. With a value (a tag's `vX.Y.Z` is fine, and a prerelease `1.0.0-beta.1` of CMake's `1.0.0`) it must agree, or the tool fails before building. |
| `--stage DIR` | A new directory in `$TMPDIR`. The install prefix: new or empty. |
| `--build-dir DIR` | A temporary one. |
| `--exclude PATH` | Leaves a path (a glob, relative to the tree) out of the bundle: a legacy `.desktop` file or a renamed command's link that the RPM still installs. Repeatable. |
| `--cmake-arg ARG` | An extra `cmake` configure argument. Repeatable. |
| `--min-telamon-ui X`, `--min-os-version N` | Override what is read from the spec and the container. |
| `--keep` | Keep the temporary directories. |

What it does:

1. Resolves the version, and `SOURCE_DATE_EPOCH` (the commit time of `HEAD`, unless set).
2. Configures with CMake in Release mode with **`-DCMAKE_INSTALL_PREFIX=<stage>`** and installs
   with `cmake --install`. The prefix is the stage, not `/usr`, on purpose: a
   binary that learns its install paths at build time (`CMAKE_INSTALL_FULL_DATADIR`
   compiled in) then holds the stage path, which step 4 finds; built for `/usr` it
   would hold `/usr/share/...` and fail only on a user's computer. It fails if
   the app's CMake forces its own prefix. An app may set `/usr` only as a
   default (`if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)`, as Telamon Gates
   and Telamon Notepad do), which an explicit prefix skips.
3. Remaps the source, build and cargo directories (`--remap-path-prefix`,
   `-ffile-prefix-map`) so panic messages and `__FILE__` do not carry them. It
   does this with `CARGO_ENCODED_RUSTFLAGS`, which cargo prefers over the
   `rustflags` of `.cargo/config.toml`: put an app's own rust flags in `RUSTFLAGS`
   when it is built into a bundle.
4. Checks that **no file in the tree contains the stage path or the build directory**.
5. Packs with `tools/bundle.py pack`: the tree is validated (the layout rules
   above, exactly one `.desktop` file named like the id, every `Exec=` naming an
   existing `bin/<name>`, the metainfo's `<id>`), the inner manifest is made, the
   archive is written and compressed (`zstd -19`, one thread), the outer manifest is written.
6. **Verifies its own output** (`tools/bundle.py verify <archive> <manifest>`,
   which anyone can run): re-reads the archive, checks each entry against the rules,
   the hash and size of every file and of the archive against the manifest, that the
   inner manifest is the outer one without `archive`, and that nothing is in the
   archive that is not in `files` or `links` and the reverse. On any problem it deletes the output and fails.

It prints the two file names. The archive is reproducible: the same source
built twice in the same container gives the same bytes (entries sorted by path, times
clamped to the commit's, owner 0:0, modes 0755/0644, one zstd thread, and the
source paths remapped). `tools/test-make-bundle.sh` tests all of this on a tiny
fake app and every kind of bad bundle it must refuse; `tools/dev-check.sh` and CI run it.

## The workflow

`.github/workflows/bundle.yml` is a reusable workflow
(`on: workflow_call`). In a `registry.fedoraproject.org/fedora:44` container it:

1. fetches the framework at `framework-ref`, builds its RPMs with
   `packaging/build-rpm.sh` (cached by commit and month, like the Store's CI) and
   installs `telamon-ui`, so the app is built against that Telamon.Ui;
2. runs `dnf builddep` on the app's spec;
3. runs `tools/make-bundle.sh` (with `--version` set to the tag, so a tag that
   disagrees with CMake fails);
4. uploads the two files as the workflow artifact `telamon-bundle`, always; and
5. in a second job, for a `v*` tag, attaches them to that tag's release: it creates the release with
   generated notes when it does not exist (GitHub sometimes answers 5xx, so it
   tries again a few times), otherwise `gh release upload --clobber`.

| Input | |
|---|---|
| `framework-ref` | The full 40-character sha of the telamon-framework commit (the same convention as `app-checks.yml`), used for the tools and for the `telamon-ui` RPMs. Default `main`; pin a sha. |
| `app-dir` | As `--app-dir`. |
| `spec` | As `--spec`; also the spec `dnf builddep` installs. |
| `attach` | `true` (default): attach to the release of a `v*` tag. |

It needs no secrets. The calling job must grant `contents: write` (the workflow
itself defaults to `contents: read`: the build job keeps it, and only the final `attach` job, which runs nothing but `gh` on the two uploaded files, asks for write).
Every action is pinned by commit sha. A cache written by a tag run is read only
by that tag: run the caller by hand on the default branch (`workflow_dispatch`)
once to seed a cache that every tag can read.

## Connecting an app

Three steps for the app's owner:

**(a) Add the workflow to the app's repository**, as `.github/workflows/bundle.yml`
(`<sha>` is the full 40-character commit sha of the framework release, here v2.0.3):

```yaml
name: Telamon bundle
on:
  push:
    tags: ['v*']
  workflow_dispatch:
permissions:
  contents: read
jobs:
  bundle:
    permissions:
      contents: write
    uses: EternalCoder454/atlas-framework/.github/workflows/bundle.yml@<sha> # v2.0.3
    with:
      framework-ref: <sha>
```

The app needs a spec (`packaging/<app>.spec`) whose `BuildRequires:` build it
(the workflow installs them) and a `project(<name> VERSION x.y.z)` in its
CMake. The template (`template/`) has this workflow, a metainfo file and an icon.

**(b) Tag a release.** The version must equal the CMake project version:

```sh
git tag vX.Y.Z && git push --tags
```

The workflow builds the bundle and attaches `<id>-<version>-x86_64.tar.zst` and
`telamon-bundle.json` to the release.

**(c) Add the app to the catalog**: one entry in `catalog/native-apps.json` of
`github.com/EternalCoder454/atlasos-store`, by pull request:

```json
{ "id": "net.eterneon.telamon.gates", "repo": "EternalCoder454/telamon-gates", "channel": "releases" }
```

Store lists the app from then on and updates it when a newer release appears.

## Trying a bundle

```sh
telamon-store --install-bundle <archive.tar.zst>    # Store checks it and installs it for you
```

To look at one without Store: `python3 tools/bundle.py verify <archive> <manifest>`,
then `zstd -dc <archive> | tar -x -C /tmp/some-empty-dir` and run
`bin/<exe>` from there. It finds its data next to itself.

## Security model

- **Integrity** is HTTPS to github.com, the sha256 of the archive and of every
  file in the manifest of the same release, and a catalog that pins which
  repositories Store trusts to publish which app ID. The hashes catch a damaged or
  mismatched download, not a malicious release: whoever can publish a release
  of a pinned repository can replace both files. Trust is in the repository
  owner and in the catalog entry, which is changed by a reviewed pull request.
  The manifest's `id` must be the catalog entry's.
- **A bundle is code that runs as the user**, with the user's permissions and no
  sandbox, as any program a user installs from a trusted publisher. Nothing in a
  bundle runs as root and nothing in it is installed outside `~/.local/share`.
- **Unpacking** (Store, and `tools/bundle.py verify` the same way) accepts only the
  entries above: paths cannot leave the prefix (no `..`, no absolute path, no
  `./`), nothing is written through a symlink (every symlink is relative and
  stays inside the tree, also through the links on its way, no entry sits below one), no hard links or device
  files, and the archive is capped (50,000 entries, 2 GiB of files).
- **Later**: GitHub artifact attestations (Sigstore provenance for the workflow's
  run, which Store can check against the pinned repository) and a
  minisign signature with a key pinned in the catalog. Neither is in schema 1;
  they would be added as release assets next to the manifest.

## Changing the format

The schema number is the contract with every reader. A new key, or a new rule a
reader must enforce, raises it. The Store and `tools/bundle.py` (the reference)
are changed together with this page.
