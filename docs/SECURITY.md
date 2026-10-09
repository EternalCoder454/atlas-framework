# telamon-framework: security

The threat model of the Telamon framework: what it protects, who it defends
against, the rule each entry point follows, and the test that keeps the rule
true. Every Telamon app links Telamon.Ui and the crates, so a bug here is in
every app: the rules below are the ones apps inherit. Change this file together
with the code it describes; some of the tests named below read the QML, the
workflows and the tools and fail when a rule here is skipped.

Report a vulnerability privately to the maintainer through GitHub's "Report a
vulnerability" on the repository (Security tab), not in a public issue.

## What the framework is, security-wise

- **Code that runs inside every app.** Telamon.Ui (a QML plugin plus C++) and
  the Rust crates run with the app's privileges, in the user's session. System
  apps (Updater, the root helper) also use `telamon-framework-system` as root.
  The framework has no setuid file, no service and no polkit action of its own.
- **It shows and reads text it did not write.** File names, D-Bus values,
  release notes, journal and crash text, Flatpak metadata, image labels, and
  whatever an app puts in a model row.
- **It talks to the network in two places only:** the crash relay (an explicit,
  user-confirmed send over `curl`) and what an app asks Telamon.Ui to load (a
  picture URL). Neither is automatic.
- **It is also the build and release machinery of every app:** the reusable
  workflows (`app-checks.yml`, `bundle.yml`), the bundle tools and the release
  workflow, which has a token that can open a pull request in every app.

## Who we defend against

| Attacker | What they can reach | Defended? |
|---|---|---|
| **Another program in the user's session** (a sandboxed Flatpak with a bus name, a compromised app) | Files it can write in the user's folders, the session bus, the journal fields it logs, the strings an app displays from it | Yes: the main model. Everything arriving from it is bounded, validated and shown as plain text |
| **Another local user** | The system journal (their own crashes), shared folders, root-owned state is out of reach | Yes: only the signed-in user's own crashes are collected; state files are 0600 in 0700 directories |
| **Remote data** | Release notes, Flatpak permission lists, image labels, the crash relay's answers, picture URLs | Yes: length, control and bidi characters, plain text, https only, no fetch without opt-in |
| **A hostile app repository** (the release workflow clones every app) | An app's `Cargo.toml`, `Cargo.lock`, `.cargo/config.toml`, CMake files and QML | Yes: the lock step runs with no secret and the publish step validates its output (see "App update pull requests") |
| **A hostile pull request or fork** | The workflows' triggers, caches, artifacts | Yes: no `pull_request_target`, read-only tokens, caches written only by main (see "GitHub workflows") |
| **The supply chain** | crates.io, GitHub Actions, the Fedora packages in the build container | Partly: locked builds, `cargo-deny`, `cargo-audit`, actions pinned by commit, Dependabot |

Out of scope, because it is not the framework's to stop: code running as the
same user outside any sandbox (it can already do everything the app can); a
compromised OS image or a compromised maintainer account; physical access; bugs
in Qt, KDE, libflatpak, zbus, curl and the services the crates call.

## Untrusted text in the UI (Telamon.Ui)

- **Text is plain.** Every `Text`, `Label`, `Heading`, `TextEdit` and `TextArea`
  in Telamon.Ui says `textFormat: Text.PlainText`. `TelamonLabel` and
  `TelamonTextArea` are plain by default. Without it, Qt's `AutoText` reads a
  string that starts with `<` as HTML, and `<img src="http://...">` fetches.
  Rich text exists in two places, both documented: `NotesText` (release notes;
  one pass rebuilds each tag from an allow-list, and keeps only `href` on a
  link) and the autocomplete drawing (it escapes `&`, `<` and `>` and adds only
  `<b>`).
- **Mnemonics.** A data row of `TelamonAppMenu` (file and recent names) has its
  `&` doubled, so a name cannot become an Alt shortcut. An action keeps its own.
- **Links open in one place.** Only `TelamonPortal.openUrl` opens a URL: http or
  https with a host, `mailto` (subject and body only), a safe local file; it
  refuses control characters and over-long URLs. `Qt.openUrlExternally` is not
  used. A `linkActivated` handler only forwards the link to the app, which must
  check it before opening it.
- **Pictures.** `TelamonAvatar`, `TelamonChoiceCard` and the screenshot carousel
  take a local file, `qrc:` or `image:` source; `https` only with the opt-in
  `allowRemote` (default off). Every QML engine that loads Telamon.Ui gets a
  network access manager (`ui/telamonnetwork.cpp`) that refuses cleartext
  `http:` and `ftp:` (loopback excepted), limits redirects to 5 and sets a
  transfer timeout, so `Kirigami.Icon` cannot be pointed at a cleartext server;
  an app's own factory is kept.
- **No text is run as code, and QML fetches nothing by itself.** No `eval`,
  `Function`, `Qt.include`, `XMLHttpRequest`, WebSocket, WebView, non-literal
  `createQmlObject`, `Loader` source or template literal in Telamon.Ui.
- **Config files.** `Telamon.Ui` reads settings with a 4 MB cap, regular files
  only (a FIFO never blocks it), writes atomically under a lock with
  `O_NOFOLLOW`, new files 0600; a copied 1.x settings file never keeps group or
  other write. D-Bus replies (portal, global shortcuts) are type-checked and
  size-capped, signals are filtered by owner, ids, paths and icons validated.
  Development-only paths and variables (`TELAMON_UI_SYMBOLS_DIR`,
  `TELAMON_UI_TRANSLATIONS_DIR`) are compiled out of packaged builds; the spec's
  `%check` fails if they are there. Log text goes through `logSafe`.

**Guards.** `crates/telamon-framework-ui/tests/qml_text.rs` (runs in
`cargo test --workspace`, so CI fails) reads the QML and fails when a text
control is not plain (including derived types: a type in `ui/` whose root is a
text control may not switch away from plain), when rich-text tokens appear
outside the counted allow-list, when a URL is opened outside the listed places
or an image source is not vetted, when QML evaluates text or fetches, when a
password field does not clear itself. It has self-tests with must-pass and
must-fail snippets and evasion cases, so it cannot silently rot. Plus
`tests/network` (the access manager), `tests/fields/tst_text_safety.qml`
(hostile strings through the controls) and the app-menu and legacy-config tests.
Apps: write the same `textFormat: Text.PlainText` on your own `Text`; the
template's `MainPage.qml` does, and the lint covers the template.

## Files and configuration (core, system)

The crates run as the signed-in user (apps) or as root (the system helper). They
read the user's settings and notifyrc files (writable by anything with access to
the config folder), `/etc/os-release`, the helper's `history.jsonl` and
`events.jsonl`, `bootc status` JSON (strings from whoever built the image) and
Flatpak metadata (written by publishers).

- **Reads are bounded and regular-only.** `fsutil::read_capped` opens with
  `O_NONBLOCK`, requires a regular file and fails over its cap (settings 4 MB,
  os-release 1 MB, history and events 16 MB). A FIFO, device or directory never
  blocks or is slurped. A line over 64 KiB is dropped undecoded. `bootc` status
  JSON is capped at 4 MiB (`bootc::MAX_JSON_BYTES`); serde_json's depth limit is
  128. Crash state files (markers, the crash id, the ledger) are read with 64 KiB
  (ledger 1 MiB) caps and `O_NOFOLLOW`.
- **Writes are atomic and private.** A temp file (`O_EXCL|O_NOFOLLOW`, 0600) in
  the same directory, then rename; directories the crates create are 0700
  (`fsutil::create_private_dir_all`). Appends (`append_line`) refuse symlinks and
  anything but a regular file; lock files open with `open_lock_file`
  (`O_NOFOLLOW|O_NONBLOCK`, regular, 0600) and waits are bounded, so a planted
  FIFO or link cannot hang or redirect a writer. Settings files are followed
  when they are symlinks on purpose (dotfiles); state files are not.
- **No injection through values.** Settings values are escaped to one line and
  read back as written (the round trip is property-tested); a group or key name
  that could forge lines or groups (control characters, brackets, `=`, a leading
  `#` or `;`, a group starting with `$`) is refused by `set` and `set_in`. App ids
  only ever become `[a-z0-9_-]` file names (`short_name`). Log text from outside
  cannot forge entries: the journal path is length-prefixed, the stderr fallback
  prefixes every line.
- **State from images and logs is cut and cleaned** before it is written:
  `history::record_boot` limits version, image, digest and time and removes
  control characters; a line over 8 KB is refused.
- **No program is run by the core and system crates** except `/usr/bin/journalctl`,
  `rpm` and `curl` in the crash module (below), all by absolute path, with a
  cleared environment and fixed arguments.

## Crash reports

`telamon-framework-system::crash` collects crashes of the user's own programs
and, only when the user says so, sends one report.

- **Consent.** Off by default: only `enabled = true` in the user's
  `crash-reporting.toml` turns it on. Every collector and `send` re-checks it,
  turning it off deletes pending and quarantined reports, and the first opt-in
  starts the markers at "now". Each send is a separate user action: the app
  shows the exact payload first.
- **An app can keep out of it entirely.** `crash: false` in `app!` (or the C++
  call `telamon_app_set_crash_reporting(false)` before `telamon_app_init`)
  installs no panic hook and only logs a fatal Qt message, whatever the user
  chose for Telamon apps. For an app that is not part of Telamon OS and must
  never feed the Telamon relay. Tests: `crates/telamon-framework-ui/tests/crash_off.rs`,
  `crash_cpp_switch.rs`, and `crash_on.rs` for the default.
- **Which crashes count.** An entry counts only if journald itself says
  systemd-coredump wrote it (`_COMM`, `_SYSTEMD_UNIT=systemd-coredump@*.service`)
  for our uid (`_UID` and `COREDUMP_UID`, filtered before `-n 500`). Container
  crashes and programs outside `/usr`, `/bin`, `/sbin`, `/lib`, `/lib64`, `/opt`,
  `/app` and `/var/lib/flatpak` are ignored. A program path that is present but
  odd (control or bidi characters, `..`, relative, over 4096 bytes) is ignored: it
  used to fall back to `COREDUMP_COMM`, which the crashing process sets freely.
  Process-controlled text is capped, stripped of control and bidi characters and
  scrubbed; it is never used in a file name, command or URL path.
- **Reading the journal.** `/usr/bin/journalctl` by absolute path, `PATH=/usr/bin`,
  fixed arguments (no user text), 10 s limit, 16 MiB output cap, its own process
  group killed on timeout. `rpm -qf --` takes the program path after `--`.
- **The report.** Telamon OS version and channel, app name and version, category,
  scrubbed message and frames, kernel, GPU model and driver, CPU model, coarse RAM
  and uptime, a timestamp. Never a host name, user name, machine-id, boot-id, IP,
  MAC, home path, command line, environment or core dump. A test pins the allowed
  field set, so a new field forces a privacy review. The scrubber, the 64 KiB
  payload cap and the safe reading of report files are in 2.0.8.
- **Transport.** `/usr/bin/curl` with a cleared environment, `-q`, `--proto
  =https` (plain http only for a loopback DSN from `/etc`), `--tlsv1.2`,
  certificate checks on, no proxy, no redirects, 30 s, 64 KiB answer. A report
  counts as sent only on a 2xx answer (a 3xx used to count). The key is a public
  key in a header, never in the URL. Only an `https://github.com/EternalCoder454/AtlasOS/issues/<n>`
  link from the answer is kept. curl's error text is one clean line in the log.
- **Endpoint pinning.** The endpoint comes only from root-owned files
  (`/etc/telamon`, `/etc/atlas`, `/usr/share/telamon`, `/usr/share/atlas`); no
  user-writable file or environment variable can redirect reports (an admin can
  override it, or set `dsn = ""`). A test pins the shipped DSN to
  `https://telamon.eterneon.net/`.
- **State and the marker.** Files 0600 in 0700 directories, created with
  `O_NOFOLLOW`/`create_new` and linked or renamed over the target, never written
  through; report file names come from a validated time (a time such as `.` used
  to make a hidden file that could never be sent or discarded); the 1.x state
  directory is chmod 0700 when adopted.
- **Residual risk.** A process of the same user can fill the newest 500 journal
  slots of its own user journal, or forge a Flatpak scope name (it only mislabels
  its own report). It already controls the user's session.

## D-Bus helpers

- **Notifications.** Title, labels, action keys, icon and body are validated and
  capped before they reach `org.freedesktop.Notifications`: the title is one line
  of at most 256 characters, labels 64, at most 8 actions with plain-word keys,
  icons are names or absolute paths (`.` and `..` refused), and the body keeps
  only `b`, `i`, `u`, `br` and `a href="https://..."` (`sanitize_body`); every
  other tag becomes text. Callers still `escape()` outside text; the allow-list
  is the second layer. Every call has a 10 s timeout.
- **polkit.** The subject is always `system-bus-name` of the message's sender,
  never a pid or uid from the caller. The name must be a unique bus name and the
  action a valid action id (`unique_name_ok`, `action_id_ok`) or polkit is not
  asked. Any error, timeout (25 s; 120 s interactive) or vanished caller is a
  refusal, with `CancelCheck`. Nothing is cached between callers.

## Flatpak helpers

No entry point takes a URL, remote, ref or `.flatpakref` from outside: the crate
lists and updates existing installations. Error text, names and versions are
cleaned (control, invisible and direction characters, length).
`new_permissions` entries come from publisher metadata: cleaned, deduplicated,
at most 64 plus `MORE_PERMISSIONS`; metadata over 1 MiB (`MAX_METADATA_BYTES`) is
unreadable, which counts as new permissions. A UI must show them as plain text.
No `Command::new` exists outside the crash module.

## GitHub workflows

`tools/check-workflows.py` (tests in `tools/test_check_workflows.py`; run by
`.github/workflows/security.yml` on every change to a workflow and weekly) fails
the build when a workflow:

- is triggered by `pull_request_target` or `workflow_run`;
- has no top-level `permissions:`, a writable one, or a job that asks for write
  access without an entry (with its reason) in the checker's `WRITERS` list:
  today `publish-docs` (force-pushes `docs-published` from main and tags),
  `release` (creates the release), `attach` (attaches the bundle; runs nothing
  but `gh`) and the `checks: write` of the audit jobs;
- uses an action or reusable workflow not pinned to a full commit sha with its
  version in a comment, or a `docker://` action (the template's placeholders
  `<FRAMEWORK_SHA>` and `vX.Y.Z` are allowed only under `template/`);
- checks out without `persist-credentials: false`;
- puts an attacker-influenced expression (inputs, ref and branch names, step
  outputs, matrix values, event fields) in a `run:` or `script:`: it goes through
  `env:`;
- uses a secret other than `GITHUB_TOKEN` outside a job with an `environment:`
  (a reviewer gate), puts one in a script, or says `secrets: inherit`;
- pipes a download into a shell, or saves a cache from a step a pull request can
  reach (the exception, `bundle.yml`'s framework RPM cache, is listed with its
  reason: it is saved before any of the app's code runs).

The pins were checked against the actions' tags. The reusable `app-checks.yml`
validates `framework-ref` (a name, no option) and verifies that a full sha
fetched is the sha asked for; `bundle.yml` insists on a full sha, checks its
inputs, builds with a read-only token and uploads to a second job that can write
and runs nothing but `gh` on exactly two files (an archive named
`<id>-<version>-x86_64.tar.zst` and `telamon-bundle.json`). Dependabot
(`.github/dependabot.yml`) moves the pins.

Repository settings that complete this (checked, not changed here): the default
workflow token is read-only and cannot approve pull requests; the `release`
environment has a required reviewer and a deployment rule; a ruleset protects
`v*` tags; secret scanning and push protection are on. **Not on, and worth
turning on:** a ruleset for `main` (no direct pushes, CI required), Dependabot
security updates, and "require actions to be pinned to a full-length commit sha".

### App update pull requests (release.yml)

A release opens a pull request in every app (`tools/apps.txt`) that moves the
framework tag. The app's checkout is not trusted (cargo runs what its
`.cargo/config.toml` names) and the token can push to every app, so it is two
jobs:

- **`update-locks`** has `contents: read` and no secret; `GH_TOKEN`,
  `GITHUB_TOKEN` and the Actions tokens are unset before cargo runs. It moves the
  pins and runs `cargo update` on the untrusted tree and uploads `base`, `locks`
  and `files/`: all untrusted text.
- **`update-apps`** (`environment: release`) holds `APP_UPDATE_TOKEN` and never
  checks the app out or runs anything from it. It fetches one commit into its own
  bare repository (hooks off, its own config) and builds the commit from git
  objects. `Cargo.toml` is never taken from the lock job: it is rewritten from the
  base's blobs. A `Cargo.lock` from the lock job is accepted only if its path is a
  plain `Cargo.lock` blob of the base tree, the file is a plain file of at most
  8 MiB, printable ASCII, written exactly as cargo writes one with at least one
  package, every new or changed package is a `telamon-framework-*` crate at
  exactly the tag's commit or a crates.io package the app or the framework lock
  already had, no existing checksum changed, `base` is the app's HEAD now, and
  the repository is an `EternalCoder454` one. Names from the app reach the log
  only after the workflow-command characters are replaced.
- **Net effect.** A hostile lock job can at most get a pull request whose
  `Cargo.lock` differs by allowed changes, or nothing. It can still choose any
  published crates.io version of a crate already in the lock (the registry vouches
  for it by checksum; the pull request is reviewed and built `--locked`). It
  cannot add a source, touch another file, repo or the default branch, or read
  the token.
- **Tests.** `tools/test-open-update-pr.sh` (about 120 checks; about 50 forged lock
  job outputs, none accepted: git sources for other crates, altered registries,
  path dependencies, comment-hidden packages, tabs and CR, `..` and absolute paths
  in the listing, forged `::set-output` lines, links, FIFOs, oversize files, a
  stale base, odd branch and repository names). The pure checks live in
  `tools/lib/update-pr-lib.sh` and are tested directly, under gawk, mawk and awk.

## Bundles (tools/bundle.py, tools/make-bundle.sh)

The native bundle (`<id>-<version>-x86_64.tar.zst` and `telamon-bundle.json`) is
read by Telamon Store, which re-checks everything; `bundle.py verify` is the
producer-side gate and mirrors the Store's rules (`telamon-store-core`
`native/archive.rs`, `native/manifest.rs`, `launch.rs`, `text.rs`, cited in the
code).

- **One strict tar reader**, not `tarfile`: POSIX ustar, checksummed headers,
  octal numbers, zero padding, only file, directory and symlink entries, a pax
  header only for `path` and `linkpath`, nothing after the end marker. Refused:
  GNU and sparse formats, global headers, hard links, devices, FIFOs, `size`,
  `uid` and `mtime` pax keys, owner names, name prefixes.
- **Caps are the Store's:** 40,000 entries, 20,000 files and links, 512 MiB per
  file, 1 GiB unpacked, 256 MiB archive, 1 MiB manifest, 1,024-byte paths, a
  decompression cut-off (zip bomb) and a 128 MiB zstd window.
- **Paths** are relative, plain, unique, with no `..`, `.`, empty part,
  backslash, or hidden or bidi character; links stay inside the tree, also
  through other links; modes are exactly 0755 or 0644 (setuid and world-writable
  are refused, not stripped); owner 0:0, one mtime, sorted names.
- **The manifest** is strict JSON (no BOM, duplicate key, NaN, fraction, huge
  number or lone surrogate), exact keys and types, hashes and sizes matching the
  archive, and `name`, `summary` and `license` equal to the Store's cleaned text.
- **Reproducible and offline.** `make-bundle.sh` fixes `LC_ALL=C`, `TZ=UTC`,
  `umask 022`, `SOURCE_DATE_EPOCH` from the commit and removes `ZSTD_*`. The only
  download is `cargo fetch --locked` (the lock may not change); everything after
  runs with `CARGO_NET_OFFLINE`, FetchContent disconnected, a dead proxy and, where
  `unshare` allows, no network namespace. A CMake file that downloads
  (`FetchContent`, `ExternalProject`, `file(DOWNLOAD)`, curl, wget, `git clone`,
  `pip install`) is refused unless `--allow-network`. A build from another path,
  locale, time zone, umask or `ZSTD_CLEVEL` gives a byte-identical bundle (tested).
- **Tests:** `tools/test-make-bundle.sh` (96 checks), `tools/test_bundle_rules.py`
  (the Store's rules as a reference port plus a seeded fuzzer; CI runs 20,000
  cases), `tools/test-tool-scripts.sh`.
- **Other scripts that read other people's trees** (`migrate-app-to-telamon.sh`,
  `lint-app.sh`, `check-app-names.sh`, `docs.py`) write through a fresh temp file,
  never follow links, skip pipes, run git without `core.fsmonitor` and print file
  names with control characters replaced.

## Template defaults

What a copied app inherits (`template/`): `CMakeLists.txt` builds with the
hardening flags of Fedora's packages whatever the build (stack protector strong,
stack clash protection, `_FORTIFY_SOURCE=3`, `_GLIBCXX_ASSERTIONS`, `-fcf-protection`,
PIE, full RELRO, `BIND_NOW`, no executable stack; `-DTELAMON_HARDENING=OFF` for a
sanitizer build); the release profile checks overflow; `publish = false`;
`deny.toml`, `.github/workflows/security.yml` (cargo-deny, cargo-audit, weekly)
and `.github/dependabot.yml`; the framework workflow pinned by commit
(`<FRAMEWORK_SHA>`) like `bundle.yml`; read-only tokens and
`persist-credentials: false`; plain-text labels; and the commented `crash: false`
switch in `src/lib.rs`. An app's RPM should also run `check-hardening.sh`.

## Build hardening and supply chain

- **RPM flags.** The spec builds with Fedora's `%build_cflags`, `%build_cxxflags`
  and `%build_ldflags` (through `%cmake`). `packaging/check-hardening.sh`, run by
  `%check` on `libtelamonui.so` (as a shared object), `telamon-preview` and
  `telamon-symbols`, reads the ELF files back and fails the package build without
  position independence (programs), `GNU_RELRO` with `BIND_NOW`, a non-executable
  stack, no RPATH, RUNPATH or TEXTREL, stack protectors (the C++), and without
  the development-only strings. CI tests the check itself against programs and
  libraries built with and without each protection
  (`packaging/test-check-hardening.sh`), and `annocheck` is a build dependency.
  *Not met:* Intel CET's IBT marking is reported, not required (`--require-cet`).
- **Locked and pinned.** CI builds with `--locked`; every action is pinned by
  commit; the build image is `fedora:44` with its current updates (a digest would
  freeze security fixes out; the one exception in the checker says so).
- **`cargo-deny`** (`deny.toml`: advisories, licences, sources, bans of OpenSSL and
  native-tls) and **`cargo-audit`** run on the workspace and on the template in
  CI on every change to the dependencies and weekly, so a new advisory against a
  lock file is seen without a commit.

## Fuzzing and property tests

`proptest` property tests (`prop_*`) cover the parsers of what other programs
send: the settings escape and INI round trip (injection, no panic), os-release,
log entries, history and events lines, bootc JSON and the channel rewrite, the
polkit and notify validators, permission lists from Flatpak metadata, the crash
module's journal-field parser, report file names and log lines. A local run is
256 cases; CI runs `PROPTEST_CASES=20000 cargo test --workspace -- prop_`.
`tools/test_bundle_rules.py` fuzzes the bundle verifier against the Store's rules
the same way (stdlib only; 20,000 cases in CI). Regressions found are kept under
`proptest-regressions/`.

## What is left

- **Repository settings** noted above (a ruleset for `main`, Dependabot security
  updates, requiring pinned actions) are the owner's to switch on.
- **The framework RPM cache** in `bundle.yml` is verified against a checksum file
  stored in the same cache: that catches corruption, not an attacker who can
  write the cache, which needs a run on the app's default branch.
- **Redirects in QML.** A loopback `http:` server that redirects to another
  computer's `http:` is followed (only the first request is checked); `Kirigami.Icon`,
  `icon.source` and `Loader` assignments are covered by the network policy but not
  by a source lint.
- **Same-user attackers** can flood their own journal slots and forge their own
  report's labels (see "Crash reports").
- **No certificate-validation test** for the crash sender (the image has no
  `openssl` to make a certificate); the tests show that https to a plain-http
  server fails and sends nothing in clear text.
- **Not audited:** `tools/preview` and `tools/apidump` (C++), and `check_semantics`
  of the bundle verifier (desktop, service and metainfo rules) beyond crash-fuzzing.
- **Fuzzing is property testing** (stable Rust, no coverage guidance);
  `cargo-fuzz` targets are a possible next step.
- **Apps** still have to write `textFormat: Text.PlainText` on their own text,
  check a link before opening one from `linkActivated`, and show Flatpak
  permission entries as plain text; the framework can only lint its own QML and
  the template.
