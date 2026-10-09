# Native Telamon apps: bundles

A Telamon app that is not part of the OS image can be installed by Telamon Store
for one user, from the app's GitHub release, without Flatpak. The release holds
a **bundle**: the app built in a `fedora:44` container against the Telamon.Ui of
the framework, packed as a tar. Qt, KDE Frameworks and `telamon-ui` are not in
it. The binary links them from the OS image, which is the point: it was built
against the same libraries it runs on, and it starts as fast as an app of the
image does.

This page is the format (schema 1), the tools that make and sign a bundle, and
what an app owner does to publish one. The producer side is `tools/make-bundle.sh`,
`tools/bundle.py`, `tools/sign-bundle.sh` and `.github/workflows/bundle.yml`; the
reader is Telamon Store (`atlasos-store`), which uses a release only when it
is signed ("Signing" below).

## The release assets

A GitHub release of the tag `vX.Y.Z` carries three files:

| Asset | What it is |
|---|---|
| `<app-id>-<version>-x86_64.tar.zst` | The bundle: a zstd-compressed tar. |
| `telamon-bundle.json` | The **outer manifest**: the manifest inside the archive plus an `archive` object with the archive's name, sha256 and size. |
| `telamon-bundle.json.minisig` | The [minisign](https://jedisct1.github.io/minisign/) signature over the exact bytes of `telamon-bundle.json`. Telamon Store offers a release only when it is there and verifies with a key the catalog lists for the app. |

An archive cannot contain its own hash, so the outer manifest is the inner one
plus `archive`; a reader fetches the small JSON first, checks its signature,
shows the app, and checks the archive it downloads against `archive.sha256`.
The signature covers the archive through that hash and size.

## The archive

Entries are UTF-8 relative paths (no leading `./` (a reader tolerates it; the tool never writes it), no absolute path, no `.` or `..` or empty component,
no backslash, and no control, hidden, zero-width or bidi characters), and only directories, regular files and
relative symlinks that stay inside the tree: no hard links, devices or fifos. Every entry
is owned by 0:0, with mode 0755 (directories, executables) or 0644 (files), and
the modification time of the commit (`SOURCE_DATE_EPOCH`); symlinks are mode 0777.
A setuid, setgid or sticky bit is an error when the tool packs a file and when it reads one. Entries
are sorted by path (compared without the trailing `/` that a directory's name is written
with in the tar header), and every directory has its own entry before its content. A tar
header too small for a long or non-ASCII name is followed by a PAX `x` extended header
that carries it; a reader must read both.

The tar itself is written in one form, and `bundle.py verify` accepts only that form,
so that no reader (the Store's, `tar`, Python) can read a different archive out of the
same bytes: POSIX ustar headers (magic `ustar\0`, version `00`), every number octal (no
base-256, no sign), a correct checksum, zero padding after each entry's data, no ustar
name prefix and no owner names, entry types `0` (file), `2` (symlink) and `5` (directory)
only (no hard link, device, fifo, sparse, contiguous, GNU long name or global pax
entry), a pax `x` header only for a `path` and a `linkpath` record (at most once each, 64 KiB at most;
no `size`, `uid`, `mtime` or any other key), a link name only on a symlink, and nothing
but zeros after the end marker. The zstd stream is read with the decoder's default
128 MiB window limit, and unpacking stops after 1 GiB plus 1,536 bytes of header for
each of the 40,016 entries a bundle may hold (the Store's cut-off for a "zip bomb").

Limits, the Store's: 20,000 files and 20,000 links, 40,000 entries in all, 512 MiB for
one file, 1 GiB unpacked, a 256 MiB archive, a manifest of 1 MiB, a path of 1,024 bytes
(255 in a name), and for what is copied out: at most 64 icons and 200 files in all, a
`.desktop` or `.service` file of 64 KiB and 1,000 lines at most (400 keys, 32 groups),
any other copied file 1 MiB.

```text
bin/                                   executables; the binary links Qt, KF6 and telamon-ui from the OS
share/applications/<app-id>.desktop   exactly one file; Exec= starts with the bare binary name
share/icons/hicolor/<size>/apps/...   optional
share/metainfo/<app-id>.metainfo.xml  recommended: the manifest's name, summary, license and homepage come from it
share/dbus-1/services/*.service       optional; Exec= starts with the bare binary name
share/knotifications6/telamon-*.notifyrc  optional
share/<app-id>/                       the app's data, optional (see "Data")
telamon-bundle.json                   the inner manifest, at the archive's root
```

Nothing else is at the top: there is no `lib/`, `etc/` or `libexec/`. The tool
refuses to make a bundle with a file outside `bin/` and `share/`, and a reader
must refuse to unpack one. Anything under `share/` other than the five
directories above stays in the app's own prefix, where the data convention finds it.

What the Store copies out of the tree, and the rules it enforces, are below
("What the Store copies out of a bundle"); `tools/bundle.py` enforces the same
rules when it makes a bundle, so a bundle that passes `make-bundle.sh` is
accepted by the Store.

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
| `id` | Reverse-DNS app ID: `[A-Za-z0-9._-]`, **at least three** dot-separated parts, none empty, none starting with `-`, at most 128 bytes (`net.eterneon.telamon.gates`). It is the `.desktop` file's basename and the directory name in the install layout. |
| `name`, `summary`, `license`, `homepage` | From the metainfo (`<name>`, `<summary>`, `<project_license>`, `<url type="homepage">`); without a metainfo the tool falls back to the `.desktop` file's `Name` and `Comment` and the spec's `License:` and `URL:`, and fails if one is still missing. `homepage` is the plain https address **as the Store normalises it**, or empty for a reader (this tool requires one): `https://` only, no port, a lowercase public DNS name of two labels or more with a letters-only TLD (not `.local`, `.lan`, `.internal`, `.test`, `.example`, `.localhost`, ...), printable ASCII without `\ " < > ` { } | ^`, and no `.` or `..` path segment (also as `%2e`). `https://GitHub.com/x` is refused: write `https://github.com/x`. |
| `version` | Up to 6 numbers of at most 9 digits with no leading zero (at least two with this tool), then an optional `-prerelease` of dot-separated parts of `[0-9A-Za-z-]`, 64 characters in all: `0.2.0`, `1.0.0-beta.1`. The release tag without its `v`; no `v`, no `+build`. It must agree with the numbers of `project(... VERSION)` in the app's CMake, which must have one. |
| `arch` | `x86_64`, the only one. |
| `min_telamon_ui` | Up to 6 numbers as in `version`, no prerelease. The oldest `telamon-ui` that runs the app: the highest `BuildRequires: telamon-ui >= X` of the app's spec (else `Requires:`), else the version of `telamon-ui` installed in the build container. QML is compiled against the types Telamon.Ui had when the app was built, so a reader refuses an OS with an older one. |
| `min_os_version` | `VERSION_ID` of the build container's `/etc/os-release` (Fedora 44: `44`). |
| `files` | Every regular file in the archive except `telamon-bundle.json`: `path`, `size`, `sha256` (lowercase hex) and `executable` (any execute bit). |
| `links` | The symlinks: `path` and the relative `target`. `[]` when there are none. |
| `archive` | In the outer manifest only: the archive's `name` (`<id>-<version>-<arch>.tar.zst`), `sha256` and `size`. |

The inner manifest in the archive is the outer one without `archive`, byte for
byte.

The JSON is read strictly (the Store uses serde, which is strict about types and
duplicate keys, and the tool refuses more): UTF-8 without a byte order mark and
at most 1 MiB; no duplicate key, `NaN`, `Infinity`, fraction or exponent; whole numbers
of at most 20 digits (`schema`, `size`, `archive.size` are exact integers, not `1.0`
and not `true`); no lone surrogate escape; exactly the keys above in that order, no
others (the Store ignores unknown keys, this tool does not write them); every `path`
the same plain relative path as in the archive; `telamon-bundle.json` is not listed in `files`;
no path is both a file and a link; `files` is not empty. `name`, `summary` and `license`
are what the Store shows of them: it drops control and invisible characters, collapses white
space, and cuts at 80, 300 and 100 characters, so a manifest holding anything the cleaning
would change is refused (otherwise the page would say something the manifest does not).

## What the Store copies out of a bundle

The Store unpacks the whole bundle into the app's prefix and copies only the
files below into the user's data directory (`~/.local/share`). Everything else
stays in the prefix: the rest of `share/` (for example `share/<app-id>/`) and `bin/`.
`tools/bundle.py` fails the build with the file and the rule when one is broken.

| Under | Allowed | Notes |
|---|---|---|
| `share/applications/` | exactly one file, `<app-id>.desktop` | `Type=Application`, the first group is `[Desktop Entry]`. Every `Exec=` (the `[Desktop Action ...]` groups too) starts with a **bare program name**: no path, no quotes, no `env`; that program is a regular file directly in `bin/` with `"executable": true` in the manifest. The Store drops `TryExec=` and `Path=` and any `X-Telamon-Native-*` key (it writes its own). |
| `share/icons/` | `share/icons/hicolor/<W>x<H or scalable>/apps/<file>`, where `<file>` is a `.png` or `.svg` named `<app-id>.<ext>` or starting with `<app-id>-` or `<app-id>_` | Any other file under `share/icons/` is an error, so a bundle cannot shadow a theme icon. |
| `share/metainfo/` | `<app-id>.metainfo.xml` (or `<app-id>.appdata.xml`) only | UTF-8 XML, no DOCTYPE; its `<id>` is the app ID. |
| `share/dbus-1/services/` | `<Name>.service`, where `[D-BUS Service] Name=` is `<app-id>` or `<app-id>.<more>` and the file is named `<Name>.service` | The Store keeps only `Name` and `Exec`; `Exec` starts with a bare `bin/` program as above. Nothing else under `share/dbus-1/`. |
| `share/knotifications6/` | `telamon-<last part of the app ID>.notifyrc` only, or with a `-` or `_` and a suffix before `.notifyrc` (`telamon-gates-alerts.notifyrc`) | The template installs one. |

Everything copied out is a regular file: a symlink in one of those directories is an
error, and so is a symlink anywhere that leads to one of them. Symlinks
elsewhere are allowed only as relative links that resolve inside the tree,
also through the links on their way (`bin/atlas-notepad -> telamon-notepad`).

## Install layout (Telamon Store)

For one user, under `~/.local/share/telamon-apps/`:

```text
~/.local/share/telamon-apps/<id>/<version>/        the unpacked archive (bin/, share/, telamon-bundle.json)
~/.local/share/telamon-apps/<id>/current           symlink to <version>
```

Store then copies the files named above, from the version's directory into the user's data
directory, so Plasma, the launcher and D-Bus find the app:

- `share/applications/<id>.desktop` to `~/.local/share/applications/`, with the
  first word of every `Exec=` rewritten to the absolute path
  `~/.local/share/telamon-apps/<id>/current/bin/<name>`, `TryExec=` and `Path=` dropped;
- `share/icons/` to `~/.local/share/icons/`;
- `share/metainfo/` to `~/.local/share/metainfo/`;
- `share/dbus-1/services/*.service` to `~/.local/share/dbus-1/services/`, the
  `Exec=` rewritten the same way;
- `share/knotifications6/*.notifyrc` to `~/.local/share/knotifications6/`.

An update unpacks the new version beside the old one, switches `current`, and
removes the old version; a removal deletes `<id>/` and the copied files. Store
sets no environment for the app.

## Data: how an app finds its files

An app that needs files at run time (QML is compiled into the binary and
Telamon.Ui comes from the OS, so most apps need none) finds them **relative to its own
executable**: `dirname(realpath(/proc/self/exe))/../share/<app-id>/...`, and
falls back to `/usr/share/<app-id>/...` when that directory is not there (an
RPM-installed app at `/usr/bin` finds `/usr/share/<app-id>` the first way
already). Resolve the directory **once, at startup**: an update replaces the files
under a running app (the old version's directory is removed once the new one is
current), so a path found later, or a file opened lazily, may be gone. Never a
path fixed at build time: the build checks that the install
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
| `--exclude PATH` | Leaves a path (a glob, relative to the tree) out of the bundle: a legacy `.desktop` file or a renamed command's link that the RPM still installs. Repeatable. It removes only what is inside the install: a match whose directory leads out of it (a symlink in the tree) is an error. |
| `--cmake-arg ARG` | An extra `cmake` configure argument. Repeatable. |
| `--min-telamon-ui X`, `--min-os-version N` | Override what is read from the spec and the container. |
| `--keep` | Keep the temporary directories. |
| `--allow-network` | Let the build use the network (see "No network after the one declared download" below). |

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
clamped to the commit's, owner 0:0, modes 0755/0644, one zstd thread at a fixed level, and the
source paths remapped), whoever builds it and wherever: the script fixes `LC_ALL=C`, `TZ=UTC`,
`umask 022` and drops the `ZSTD_*` and Python settings of the environment, and the
tar names are written as UTF-8 whatever the locale.

**No network after the one declared download.** The only step that uses the network is
`cargo fetch --locked` for an app with a `Cargo.toml` (every crate is pinned by
`Cargo.lock`, by checksum or by commit; a stale lock fails the build, and so does a build that
changes the lock). Configure, build and install then run with `CARGO_NET_OFFLINE=true`,
`FETCHCONTENT_FULLY_DISCONNECTED=ON` and a dead proxy, and, where the kernel lets a user make
a network namespace (`unshare -rn`; hosted CI runners often do not, and the script says so),
in a namespace with no network at all. A CMake file that downloads (`FetchContent`,
`ExternalProject`, `file(DOWNLOAD)`, `curl`, `wget`, `git clone`, `pip install`...) is refused before
anything is configured; `--allow-network` lifts both, and the bundle is then not
guaranteed to be reproducible. `tools/test-make-bundle.sh` tests all of this on a tiny
fake app and every kind of bad bundle it must refuse, `tools/test_bundle_rules.py` holds the
Store's rules as a reference and fuzzes the verifier against them
(`--cases N --seed S`; CI runs 20,000 cases), and `tools/dev-check.sh` runs the first two.

## The workflow

`.github/workflows/bundle.yml` is a reusable workflow
(`on: workflow_call`) of three jobs. The first, `bundle`, runs in a
`registry.fedoraproject.org/fedora:44` container and is the only one that runs
the app's code:

1. fetches the framework at `framework-ref`, builds its RPMs with
   `packaging/build-rpm.sh` (cached by commit and month, like the Store's CI) and
   installs `telamon-ui`, so the app is built against that Telamon.Ui;
2. runs `dnf builddep` on the app's spec;
3. runs `tools/make-bundle.sh` (with `--version` set to the tag, so a tag that
   disagrees with CMake fails) and checks that the tag is `v` + the manifest's `version`;
4. uploads the two files as the workflow artifact `telamon-bundle`, always.

For a `v*` tag two more jobs follow:

5. `sign` (a `fedora:44` container, no token): runs only the framework's own tools,
   fetched by commit sha, in two steps through `tools/sign-bundle.sh` ("Signing" below).
   Step A downloads `telamon-bundle` and **verifies it again** (`tools/bundle.py verify`:
   the archive against the manifest and the layout rules; a directory with anything
   else in it is refused) with no secret in its environment. Step B has the optional
   secret `minisign-key` and parses nothing: it checks that the manifest is the file
   step A verified (its sha256) and that the directory holds only the archive and the
   manifest, then signs `telamon-bundle.json` with `minisign`. So the key is never in the
   environment of anything that parses the bundle. It uploads `telamon-bundle.json.minisig`
   as the artifact `telamon-bundle-signature`. Without the secret nothing is signed, and
   the release is left a draft (next item).
6. `attach` (the only job with a write token; it runs nothing but `gh`, `jq` and
   `sha256sum`): downloads both artifacts and checks that the manifest is the file
   `sign` verified (its sha256), that the archive is the one the manifest names, and
   that the directory holds exactly those files and the signature. When there is no
   release for the tag it creates a **draft** with generated notes, uploads the files, and only then
   publishes it (`gh release edit --draft=false`), so Store never sees a release
   without its bundle; a draft it made is deleted if the upload fails. It stops at the
   draft, with an `::error` annotation that says how to sign offline and publish, when
   `publish` is `false` **or when there is no signature** (unless `allow-unsigned` is
   `true`): a missing or misspelled secret, or a fork that gets none, cannot publish an
   unsigned release by mistake. An existing release just
   gets the files (`gh release upload --clobber`). GitHub sometimes answers 5xx, so each
   call is tried again a few times.

| Input | |
|---|---|
| `framework-ref` | **Required**: the full 40-character sha of the telamon-framework commit, used for the tools and for the `telamon-ui` RPMs. A branch, a tag or a short sha fails the run, because they name something that moves (or cannot be fetched). Use a commit from 2.0.10 on to get the signing job. |
| `app-dir` | As `--app-dir`. |
| `spec` | As `--spec`; also the spec `dnf builddep` installs. |
| `attach` | `true` (default): sign and attach to the release of a `v*` tag. |
| `publish` | `true` (default): publish a release this run created, when it is signed. `false`: leave it a **draft** whatever happens, so its owner can sign `telamon-bundle.json` offline and publish it by hand ("Signing"). |
| `allow-unsigned` | `false` (default): a release with no signature stays a draft. `true`: publish it as a normal release anyway; Telamon Store will not offer it until `telamon-bundle.json.minisig` is added. |
| `minisign-public-key` | Optional: the catalog's public key for the app (`RW...`). When given, the signature made with the secret must verify with it, so a wrong key in the secret fails the run and not the users, and **the run fails when the secret is empty or missing**. Set it next to the secret. |

| Secret | |
|---|---|
| `minisign-key` | Optional: the **content of the minisign secret key file** (both lines). Without it the release is attached unsigned and left a draft. It is read by one step of the `sign` job, which parses nothing, and by nothing that runs the app's code. |
| `minisign-password` | Optional: the key's password, if it has one. |

The calling job must grant `contents: write` (the workflow itself defaults to
`contents: read`: the build job keeps it, the sign job has no token, and only the final
`attach` job asks for write) and passes the secrets by name: `secrets: inherit` hands over all of
the repository's, which is more than the workflow needs.
No job asks for an OIDC token (`id-token`).
Every action is pinned by commit sha. The tag is checked against
`^v[0-9]+(\.[0-9]+)+(-[0-9A-Za-z.-]+)?$` before any job uses it, and every input and the
tag reach a script only through an environment variable, quoted. A cache written by a tag run is read only
by that tag: run the caller by hand on the default branch (`workflow_dispatch`)
once to seed a cache that every tag can read.

## Signing

Telamon Store installs or offers a release only when its `telamon-bundle.json`
has a valid minisign signature by a key that its catalog lists **for that app**.
The signature is the release asset `telamon-bundle.json.minisig`: the output
of `minisign -S` in its default form (Ed25519 over the BLAKE2b-512 hash of the
file, which minisign marks `ED`; the legacy kind that `-l` writes, `Ed`, is
refused), over the exact bytes of `telamon-bundle.json`. The trusted comment
is signed but means nothing to the Store. There is no separate signature of
the archive: the manifest holds its sha256 and size.

**The key.** One key pair per app, made once, off the repository:

```sh
mkdir -p ~/.minisign
minisign -G -p telamon-gates.pub -s ~/.minisign/telamon-gates.key     # asks for a password: give one
minisign -G -W -p telamon-gates.pub -s ~/.minisign/telamon-gates.key  # -W: no password, for a key that CI holds
```

`minisign -G` prints the public key (`RW` and 54 more characters, also the second
line of the `.pub` file). The secret key never goes into a repository or a chat; keep a backup.

**The catalog entry** pins the public key for the app, in `catalog/native-apps.json`
of the Store (a reviewed pull request):

```json
{
  "id": "net.eterneon.telamon.gates",
  "repo": "EternalCoder454/telamon-gates",
  "channel": "releases",
  "signers": [ { "type": "minisign", "key": "RWQ..." } ]
}
```

Up to four signers; a release signed by any other key, or with the legacy
kind, is refused. **Rotating a key:** add the new public key beside the old one
(pull request), sign the next release with the new key, and remove the old one
in a second pull request when it is no longer needed or when it leaks. While
both are listed either may sign. Stores refetch the catalog within 6 hours;
what is installed stays installed.

There are two ways to make the signature.

**Offline (recommended).** The key stays on the owner's computer. The workflow
is called with `publish: false`: it builds, verifies and attaches the archive
and the manifest to a **draft** release and stops. The owner then signs and
publishes (the run's summary lists the sha256 of both files, to compare):

```sh
tag=v0.2.0 repo=EternalCoder454/telamon-gates
mkdir bundle && cd bundle
gh release download "$tag" --repo "$repo"
python3 /path/to/telamon-framework/tools/bundle.py verify *.tar.zst telamon-bundle.json
minisign -Sm telamon-bundle.json -s ~/.minisign/telamon-gates.key     # writes telamon-bundle.json.minisig
minisign -Vm telamon-bundle.json -P RWQ...                            # against the key in the catalog
gh release upload "$tag" telamon-bundle.json.minisig --repo "$repo"
gh release edit "$tag" --draft=false --repo "$repo"
```

**In CI.** The key file's content is a repository secret and the caller passes
it. The `sign` job puts the key in a file on tmpfs (umask 077), runs `minisign -S`
with it, shreds the file and removes it whatever happens; the key and the password
are never an argument, never printed (tracing is off), and not in the environment of
`minisign`. The step that has them parses nothing; the step before it parses the bundle with
no secret in its environment, so the key is never in the environment of anything that parses
the bundle. The job checks the form of the signature (`ED`, four lines), and with
`minisign-public-key` that it verifies with the catalog's key. It runs none
of the app's code, and only signs a bundle that passes `tools/bundle.py verify`.

**What CI signing does not protect.** The job signs what the app's build
made, after checking that it is a *valid* bundle (the archive matches its
manifest and the layout rules; an arbitrary file cannot be signed). That is all
the check can say: whoever controls the app's build controls what is signed.
That is everyone who can get code into the build of a tag, push a tag, or change
the workflow in that repository, and also a compromised dependency of the
build. A repository secret can be read by anyone who can change the workflow
that is run with it. **For an app whose repository has more than one writer,
sign offline.** A key kept in CI suits a repository with one trusted owner who
accepts that a stolen account or token can sign a release.

Without a key the run is not an error, but the release is **not published**: the archive
and the manifest are attached to a draft, the run prints an `::error` annotation that says how
to sign offline and publish, and the owner adds `telamon-bundle.json.minisig` and publishes, as
above. `allow-unsigned: true` publishes it as a normal release instead; Telamon Store will not
offer it. (With `minisign-public-key` set and no key, the run fails.)

**The runtime of the signing job** is a `fedora:44` container with `minisign` from `dnf`
(and git, python3, zstd), both mutable: whatever those repositories serve that day runs
next to the key. The framework's tools are pinned by sha, the runtime is not. For a
high-value app, sign offline.

## Connecting an app

Four steps for the app's owner:

**(a) Make the app's signing key** (once, "Signing" above): `minisign -G -p
telamon-<app>.pub -s ~/.minisign/telamon-<app>.key`. The public key is what the
catalog pins.

**(b) Add the workflow to the app's repository**, as `.github/workflows/bundle.yml`
(`<sha>` is the full 40-character commit sha of the framework release, here v2.0.10):

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
    uses: EternalCoder454/atlas-framework/.github/workflows/bundle.yml@<sha> # v2.0.10
    with:
      framework-ref: <sha>
      publish: false   # leave the release a draft and sign it offline (recommended)
    # To sign in CI instead (read "What CI signing does not protect"): drop `publish`, and
    # pass the key file's content as a repository secret:
    # secrets:
    #   minisign-key: ${{ secrets.MINISIGN_KEY }}
    #   minisign-password: ${{ secrets.MINISIGN_PASSWORD }}   # only if the key has a password
    # and, with `with:`, minisign-public-key: RWQ...   # the catalog's key: the run fails when the secret is missing or another key
```

An unsigned release (no secret, a misspelled one, a fork) is left a draft; `allow-unsigned: true`
publishes it anyway, and Telamon Store will not offer it.

The app needs a spec (`packaging/<app>.spec`) whose `BuildRequires:` build it
(the workflow installs them) and a `project(<name> VERSION x.y.z)` in its
CMake. The template (`template/`) has this workflow, a metainfo file and an icon.

**(c) Tag a release.** The version must equal the CMake project version:

```sh
git tag vX.Y.Z && git push --tags
```

The workflow builds the bundle and attaches `<id>-<version>-x86_64.tar.zst`,
`telamon-bundle.json` and (signing in CI) `telamon-bundle.json.minisig` to the
release; offline, sign the draft and publish it as under "Signing".

**(d) Add the app to the catalog**: one entry in `catalog/native-apps.json` of
`github.com/EternalCoder454/atlasos-store`, by pull request, with the public
key:

```json
{ "id": "net.eterneon.telamon.gates", "repo": "EternalCoder454/telamon-gates", "channel": "releases",
  "signers": [ { "type": "minisign", "key": "RWQ..." } ] }
```

Store lists the app from then on and updates it when a newer signed release appears.

## Trying a bundle

```sh
telamon-store --install-bundle <archive.tar.zst>    # Store checks it and installs it for you
```

To look at one without Store: `python3 tools/bundle.py verify <archive> <manifest>`
(it reads the archive without unpacking it anywhere, and refuses what the Store would),
`minisign -Vm telamon-bundle.json -P <the catalog's key>` for the signature, then `zstd -dc <archive> | tar -x -C /tmp/some-empty-dir` and run
`bin/<exe>` from there. It finds its data next to itself.

## Security model

Enforced today:

- **Authenticity is a signature pinned in the catalog.** Store uses a release only when
  `telamon-bundle.json` carries a valid minisign signature by a key listed for
  that app in its catalog entry (a reviewed pull request, "Signing"). It is verified over the
  manifest's exact bytes as downloaded, before the manifest is read for anything; a
  missing, oversize or edited signature, the legacy `Ed` kind, and a good signature by
  a key the entry does not list are all refusals. The manifest's `id` must be the
  catalog entry's and the tag must be `v` + its `version`. Whoever can publish a
  release of the repository, or replace its assets, without the signing key can only
  make Store refuse the release.
- **A hash chain from the signature to every byte.** The signature covers the manifest;
  the manifest holds the archive's sha256, size and name, and the sha256 and size
  of every file in it; Store checks each as it downloads and unpacks. HTTPS to
  github.com carries them.
- **No downgrade.** Store never offers or installs a release older than the installed
  version, so a validly signed old release served as "latest" does not roll an app back.
- **A bundle is code that runs as the user**, with the user's permissions and no
  sandbox, as any program a user installs from a trusted publisher. Nothing in a
  bundle runs as root and nothing in it is installed outside `~/.local/share`.
- **Unpacking** (Store, and `tools/bundle.py verify` the same way, which does not
  extract anything: it streams the tar and hashes) accepts only the
  entries above: paths cannot leave the prefix (no `..`, no absolute path, no
  `./`), nothing is written through a symlink (every symlink is relative and
  stays inside the tree, also through the links on its way, no entry sits below one), no hard links,
  device files, setuid, setgid or sticky bits, and the archive is capped (the limits under "The archive",
  and `verify` stops reading a decompressed stream that is longer than they allow).
- **The producer's workflow** keeps the secret away from the app's code: the job
  that builds the app has a read-only token and no secret; the job that holds the key
  runs the framework's own tools (by commit sha) on a bundle it has verified, and the key
  is never in the environment of anything that parses the bundle; a release without a signature
  stays a draft; the job that writes the release runs only `gh` on files whose hashes it has checked. The tag
  and the inputs never reach a shell as code, actions are pinned by sha, and no job
  asks for an OIDC token.

What remains:

- **A stolen signing key signs anything** that installs on every computer whose
  catalog lists it, until the owner removes the key from the catalog (a pull request;
  Stores stop accepting it when they refetch, at most 6 hours). Nothing installed
  before is removed. Keep the key off the repository, with a password; offline
  signing exposes it least.
- **In the secret-key-in-CI model a malicious build gets a bundle signed.** The `sign`
  job verifies that the bundle is valid, not that it is what the owner meant to
  ship: whoever controls the app's build, the workflow or a tag in that repository
  controls what is signed, and can read the secret. This is why offline signing
  (`publish: false`) is the recommended model for any app whose repository has
  several writers.
- **The signing job's runtime is mutable.** It is a `fedora:44` container with `minisign`
  from `dnf`; the framework's tools are pinned by sha, the packages are not. For a
  high-value app, sign offline.
- **No freshness.** A signature does not expire: an attacker who can block or
  replay GitHub's answers can keep a computer on an older signed release, and a
  validly signed old release that is still the latest can be offered to a computer
  that has none installed.
- **Sigstore and GitHub artifact attestations are not verified.** Store does not
  check build provenance (which workflow of which repository made the archive). The
  catalog's `signers` list is typed, so `sigstore` entries can be added later without a new
  schema, and the workflow can then also publish an attestation for the archive (it
  would ask for `id-token: write` and `attestations: write`, which no job does today).
- The archive is not signed by itself, only through the manifest's hash: this is
  complete as long as the manifest's `archive.sha256` and `size` are checked, which
  both Store and `bundle.py verify` do.

## Changing the format

The schema number is the contract with every reader. A new key, or a new rule a
reader must enforce, raises it. The Store and `tools/bundle.py` (the reference)
are changed together with this page.
