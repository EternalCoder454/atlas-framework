#!/bin/bash
# Moves an app from Atlas.Ui 1.x (the atlas-framework crates, atlas-ui) to
# Telamon.Ui 2.0.0 (the telamon-framework crates, telamon-ui). Run it in the
# app's repository:
#
#   path/to/migrate-app-to-telamon.sh [options] [app dir]
#
#   -n, --dry-run     print what would change, change nothing
#   --rev <sha>       pin the framework crates to this commit (`rev = "<sha>"`)
#                     instead of `tag = "v2.0.0"`, for an app whose CI wants revs
#   --no-pin          leave the framework pins (`tag`/`rev`/`branch`) alone
#   --allow-dirty     also run on a tree with uncommitted changes, or one that
#                     is not a git repository (no way back: copy it first)
#   -h, --help        this text
#
# It rewrites only names the framework itself had, as whole words (never the
# middle of a longer word), and prints every file it touched and what kind of
# change it made:
#
#   QML/C++   `import Atlas.Ui` (also `Atlas.Ui 1.0`, `as X`) -> `import
#             Telamon.Ui`; every Atlas<Name> type and singleton the
#             framework had (AtlasWindow, AtlasStyle, AtlasSettings,
#             AtlasTextView, ... 111 names; the app's own AtlasFoo stays);
#             the interface IDs net.eterneon.Atlas.TextView/1 and friends;
#             the logging categories atlas.ui.*; the property "atlasRepo"
#   Rust      the crates atlas-framework-{core,ui,system,flatpak} in
#             Cargo.toml and atlas_framework_* in `use` paths, `app!` and
#             Rust code; the app!'s `ui: "x.y.z"` below 2.0.0 -> "2.0.0"
#   Cargo     the pin of those crates to `tag = "v2.0.0"` (or `--rev`),
#             on one line or in a [dependencies.<crate>] table; Cargo.lock
#             is not touched: run the `cargo fetch` line printed at the end
#   C         include/atlas/app.h (also textview.h, textsnapshot.h) ->
#             telamon/..., atlas_app_{init,ready,require_ui,run} and
#             atlas_backend_new (the template's backend factory) -> telamon_*,
#             ATLAS_TEXTVIEW_INTERFACE_VERSION, ATLAS_TEXTSNAPSHOT_ABI_VERSION
#   CMake     the check for the module's directory `.../qml/Atlas/Ui/qmldir`
#             -> `.../Telamon/Ui/qmldir`, the package names in messages
#   RPM spec  Requires:/BuildRequires: atlas-ui, atlas-symbols-fonts,
#             atlas-symbols-fonts-extra, atlas-symbols (with or without a
#             version) -> telamon-... >= 2.0.0 ; %changelog is not touched
#   CI/shell  atlas-preview -> telamon-preview, `atlas-lint:` comments ->
#             `telamon-lint:`, app-checks.yml@v1.x.y and framework-ref: v1.x.y
#             -> v2.0.0 (a pin to a commit is only reported), the package
#             names above anywhere else (dnf install lines, Containerfiles),
#             the variables ATLAS_SOFTWARE_RENDERING, ATLAS_REDUCED_MOTION,
#             ATLAS_LOG, ATLAS_KF6_INCLUDEDIR, ATLAS_UI_SYMBOLS_DIR,
#             ATLAS_UI_TRANSLATIONS_DIR, ATLAS_LINT_DEPRECATED,
#             ATLAS_TARGET, ATLAS_UI_DEV_PATHS
#   Fonts     the family names "Material Symbols Rounded|Outlined|Sharp" in
#             QML, JavaScript and C++ -> "Telamon Symbols ..." (the same glyphs)
#   Files     atlas-<x>.notifyrc -> telamon-<x>.notifyrc (git mv), and its
#             mentions: the framework names the notification component and the
#             settings file after the app (`telamon-<x>`) now
#
# Not touched: CHANGELOG*, NEWS*, LICENSE, Cargo.lock, an RPM spec's %changelog,
# binary files, files over 2 MB, .git, build and target directories, and
# anything not named above: the app's own names (AtlasOS, atlasos-<app>
# repositories, its desktop file and app ID, its own AtlasFoo.qml), which
# change when the app itself is renamed. At the end it lists what still says
# "atlas" so you can look at it. Running it again changes nothing.
#
# Afterwards: build in the app's container with the telamon-ui 2.0.0 packages
# installed, run its tests, and look at `git diff`.
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    echo "migrate-app-to-telamon: python3 is needed" >&2
    exit 2
fi
exec python3 - "$@" <<'PYTHON'
import os
import re
import subprocess
import sys

TARGET = "2.0.0"
TAG = "v" + TARGET
MAX_BYTES = 2 * 1024 * 1024
SKIP_DIRS = {".git", "node_modules", "target", "_build", ".cache", ".ccache", ".cargo-registry"}
SKIP_NAMES = ("CHANGELOG", "ChangeLog", "NEWS", "LICENSE", "COPYING", "Cargo.lock")

# The Atlas<Name> names the framework had (types, singletons, C++ classes,
# interfaces): Atlas.Ui 1.6.1. The app's own names are not on this list.
KNOWN = """
AboutPage AccentPicker Action ActionCollection App AppCard AppMenu AutocompleteField
Avatar Badge Breadcrumb Button Calendar Card CheckBox Chip ChipGroup ChoiceCard
Clipboard CodeView ColorField ColorsPrivate ComboBox CommandPalette CopyButton
DatePicker DetailGrid Dialog DoubleSpinBox DropZone EdgeGlow EmailValidator
EmptyState ExpandableSection FileField FloatingToolbar FlowLayout FocusRing
FolderField FontPicker Form FormEntry Format GlobalShortcut HeaderBar IconGrid
InstallButton Label ListView NavigationStack NumberValidator Onboarding Page
PasswordField PasswordStrength PathValidator Placeholder Popover Portal
PreferencesDialog PreferencesPage ProgressBar RadioButton Rating ScreenshotCarousel
ScrollBar SearchResults SegmentedControl Settings Shelf ShortcutField ShortcutLabel
Shortcuts ShortcutsDialog Sidebar Slider Sparkline SparklineItem SpinBox Spinner
SplitButton SplitView SpringAnimation Stat Status StatusView Style Switch Text
TextArea TextChunk TextDetail TextField TextHighlighterInterface TextScale
TextSnapshot TextSnapshotInterface TextView TextViewDetail TextViewInterface
TimePicker ToolTip Toolbar TransparencySwitch TreeModel TreeView UrlValidator
ViewSwitcher Window WindowButtons WindowChrome
""".split()
KNOWN_TYPES = "|".join(sorted(KNOWN, key=len, reverse=True))

CRATES = "core|ui|system|flatpak"
PACKAGES = ["atlas-symbols-fonts-extra", "atlas-symbols-fonts", "atlas-symbols", "atlas-ui"]
ENV = ["ATLAS_SOFTWARE_RENDERING", "ATLAS_REDUCED_MOTION", "ATLAS_LOG", "ATLAS_KF6_INCLUDEDIR",
       "ATLAS_UI_SYMBOLS_DIR", "ATLAS_UI_TRANSLATIONS_DIR", "ATLAS_LINT_DEPRECATED",
       "ATLAS_TARGET", "ATLAS_UI_DEV_PATHS", "ATLAS_TEXTVIEW_INTERFACE_VERSION",
       "ATLAS_TEXTSNAPSHOT_ABI_VERSION"]
C_FUNCS = ["atlas_app_init", "atlas_app_ready", "atlas_app_require_ui", "atlas_app_run", "atlas_backend_new"]
# A word: not preceded or followed by a letter, digit or underscore.
W_BEFORE = r"(?<![A-Za-z0-9_])"
W_AFTER = r"(?![A-Za-z0-9_])"


def word(pattern):
    return re.compile(W_BEFORE + "(?:" + pattern + ")" + W_AFTER)


# (kind, compiled pattern, replacement) applied to every text file.
RULES = [
    ("import", word(r"Atlas\.Ui"), "Telamon.Ui"),
    ("import", re.compile(W_BEFORE + r"Atlas/Ui" + W_AFTER), "Telamon/Ui"),
    ("import", word(r"qml_register_types_Atlas_Ui"), "qml_register_types_Telamon_Ui"),
    ("type", word(r"Atlas(" + KNOWN_TYPES + ")"), r"Telamon\1"),
    ("interface id", re.compile(r"net\.eterneon\.Atlas\.(TextView|TextSnapshot|TextHighlighter)/"),
     r"net.eterneon.Telamon.\1/"),
    ("logging category", re.compile(W_BEFORE + r"atlas\.ui(?=[.*\"' ,;:]|$)"), "telamon.ui"),
    ("property", re.compile(r"([\"'])atlasRepo\1"), r"\1telamonRepo\1"),
    ("crate", re.compile(r"(?<![A-Za-z0-9_])atlas-framework-(" + CRATES + ")" + W_AFTER), r"telamon-framework-\1"),
    ("crate", re.compile(r"(?<![A-Za-z0-9_])atlas_framework_(" + CRATES + ")(?![A-Za-z0-9])"), r"telamon_framework_\1"),
    ("c include", re.compile(r"(?<![A-Za-z0-9_])atlas/(app|textview|textsnapshot)\.h"), r"telamon/\1.h"),
    ("c function", word("|".join(C_FUNCS)), lambda m: "telamon_" + m.group(0)[len("atlas_"):]),
    ("variable", word("|".join(ENV)), lambda m: "TELAMON_" + m.group(0)[len("ATLAS_"):]),
    ("tool", word(r"atlas-preview"), "telamon-preview"),
    ("lint comment", re.compile(r"(?<![A-Za-z0-9_-])atlas-lint:"), "telamon-lint:"),
    ("ci pin", re.compile(r"(EternalCoder454/atlas-framework/\.github/workflows/app-checks\.yml@)v?1\.\d+\.\d+"), r"\g<1>" + TAG),
    ("ci pin", re.compile(r"(framework-ref:\s*[\"']?)v?1\.\d+\.\d+"), r"\g<1>" + TAG),
    ("package", re.compile(W_BEFORE + "(?:" + "|".join(re.escape(p) for p in PACKAGES) + r")(?![A-Za-z0-9_]|-fonts)"),
     lambda m: "telamon-" + m.group(0)[len("atlas-"):]),
    ("notifyrc", re.compile(W_BEFORE + r"atlas-([a-z0-9_-]+)\.notifyrc"), r"telamon-\1.notifyrc"),
    # "an Atlas.Ui type" was right; "an Telamon.Ui type" is not.
    ("grammar", re.compile(r"(?<![A-Za-z])([Aa])n (Telamon[A-Z.])"), r"\1 \2"),
]
FONT_RULE = ("font family", re.compile(r"(?<![A-Za-z0-9_])Material Symbols (Rounded|Outlined|Sharp)" + W_AFTER), r"Telamon Symbols \1")
FONT_EXT = (".qml", ".js", ".mjs", ".cpp", ".cc", ".h", ".hpp", ".rs", ".ui")

VERSION = re.compile(r"[0-9]+(?:\.[0-9]+){0,2}")


def vkey(text):
    parts = [int(p) for p in text.split(".")]
    return tuple(parts + [0] * (3 - len(parts)))


class Report:
    def __init__(self):
        self.files = {}      # path -> {kind: count}
        self.renamed = []
        self.notes = []

    def add(self, path, kind, n=1):
        if n:
            kinds = self.files.setdefault(path, {})
            kinds[kind] = kinds.get(kind, 0) + n


HELP = """usage: migrate-app-to-telamon.sh [-n|--dry-run] [--rev <sha>] [--no-pin] [--allow-dirty] [app dir]
Moves an app from Atlas.Ui 1.x to Telamon.Ui 2.0.0 (names, crates, spec, pins).
See the comment at the top of the script for what it changes and what it leaves."""


def parse_args(argv):
    opts = {"dry": False, "rev": None, "pin": True, "dirty": False, "dir": "."}
    i = 0
    dir_seen = False
    while i < len(argv):
        a = argv[i]
        if a in ("-n", "--dry-run"):
            opts["dry"] = True
        elif a == "--rev":
            i += 1
            if i >= len(argv) or not re.fullmatch(r"[0-9a-f]{7,40}", argv[i]):
                print("migrate-app-to-telamon: --rev needs a commit id (hex)", file=sys.stderr)
                sys.exit(2)
            opts["rev"] = argv[i]
        elif a == "--no-pin":
            opts["pin"] = False
        elif a == "--allow-dirty":
            opts["dirty"] = True
        elif a in ("-h", "--help"):
            print(HELP)
            sys.exit(0)
        elif a.startswith("-"):
            print(f"migrate-app-to-telamon: unknown option {a}", file=sys.stderr)
            sys.exit(2)
        elif not dir_seen:
            opts["dir"] = a
            dir_seen = True
        else:
            print("migrate-app-to-telamon: one directory only", file=sys.stderr)
            sys.exit(2)
        i += 1
    return opts


def git(root, *args):
    return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)


def list_files(root, in_git):
    if in_git:
        r = subprocess.run(["git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                           capture_output=True)
        names = [n for n in r.stdout.decode("utf-8", "surrogateescape").split("\0") if n]
        return [n for n in names if os.path.isfile(os.path.join(root, n)) and not os.path.islink(os.path.join(root, n))]
    out = []
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and d != "build" and not d.startswith("build-")]
        for f in files:
            p = os.path.join(base, f)
            if not os.path.islink(p):
                out.append(os.path.relpath(p, root))
    return out


def skipped(rel):
    parts = rel.split("/")
    if any(p in SKIP_DIRS or p == "build" or p.startswith("build-") for p in parts[:-1]):
        return True
    base = parts[-1]
    return base.startswith(SKIP_NAMES)


def apply_rules(rel, text, report):
    for kind, rx, rep in RULES:
        text, n = rx.subn(rep, text)
        report.add(rel, kind, n)
    if rel.endswith(FONT_EXT):
        kind, rx, rep = FONT_RULE
        text, n = rx.subn(rep, text)
        report.add(rel, kind, n)
    return text


def spec_requires(rel, text, report):
    """Requires/BuildRequires of the four packages: renamed, and at least 2.0.0."""
    pkgs = "|".join(re.escape(p) for p in PACKAGES)
    rx = re.compile(r"^(\s*(?:Build)?Requires(?:\([^)]*\))?:\s*)(?:" + pkgs + r")"
                    r"(?![A-Za-z0-9_]|-fonts)(?:\s*(?:>=|<=|=|>|<)\s*[0-9][^\s,]*)?", re.M | re.I)
    head, sep, tail = text.partition("\n%changelog")

    def fix(m):
        name = re.search("|".join(re.escape(p) for p in PACKAGES), m.group(0)).group(0)
        return m.group(1) + "telamon-" + name[len("atlas-"):] + " >= " + TARGET

    new, n = rx.subn(fix, head)
    report.add(rel, "spec requires", n)
    return new + sep + tail


def spec_apply(rel, text, report):
    """Rules for a spec outside its %changelog; then the Requires lines."""
    head, sep, tail = text.partition("\n%changelog")
    # The Requires lines first, so the package rule does not rename them without the version.
    head = spec_requires(rel, head, report)
    head = apply_rules(rel, head, report)
    return head + sep + tail


def raise_ui(rel, text, report):
    """`ui: "x.y.z"` inside an app! { ... } below 2.0.0 becomes "2.0.0"."""
    out = []
    pos = 0
    for m in re.finditer(r"(?<![A-Za-z0-9_])app!\s*\{", text):
        start = m.end()
        depth = 1
        i = start
        while i < len(text) and depth:
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            i += 1
        block = text[start:i]

        def fix(v):
            if VERSION.fullmatch(v.group(2)) and vkey(v.group(2)) < vkey(TARGET):
                report.add(rel, "app! ui version")
                return v.group(1) + TARGET + v.group(3)
            return v.group(0)

        new = re.sub(r'(\bui\s*:\s*")([^"]*)(")', fix, block)
        out.append(text[pos:start])
        out.append(new)
        pos = i
    out.append(text[pos:])
    return "".join(out)


FRAMEWORK_URL = re.compile(r"github\.com/EternalCoder454/atlas-framework")
PIN = re.compile(r"\b(tag|rev|branch)(\s*=\s*)\"[^\"]*\"")


def pin_value(opts):
    return ('rev = "%s"' % opts["rev"]) if opts["rev"] else ('tag = "%s"' % TAG)


FW_HEADER = re.compile(r"\[(?:[^\]]*\.)?telamon-framework-(?:%s)\]\s*(?:#.*)?$" % CRATES)
FW_INLINE = re.compile(r"telamon-framework-(?:%s)\s*=\s*\{" % CRATES)


def repin(rel, text, report, opts):
    """Pins of the framework crates: on the dependency's own line, or in a
    [dependencies.<crate>] table. Only a dependency whose `git` is the framework."""
    lines = text.split("\n")
    changed = 0
    was_rev = 0
    unpinned = []
    tables = []   # (first line index, last line index) of each framework table
    i = 0
    while i < len(lines):
        if FW_HEADER.match(lines[i].strip()):
            j = i + 1
            while j < len(lines) and not lines[j].strip().startswith("["):
                j += 1
            tables.append((i, j))
            i = j
        else:
            i += 1

    def pin(index):
        nonlocal changed, was_rev
        m = PIN.search(lines[index])
        if not m:
            return False
        if m.group(1) == "rev" and not opts["rev"]:
            was_rev += 1
        new = PIN.sub(lambda _: pin_value(opts), lines[index], count=1)
        if new != lines[index]:
            lines[index] = new
            changed += 1
        return True

    for index, line in enumerate(lines):
        if FW_INLINE.match(line.strip()) and FRAMEWORK_URL.search(line):
            if not pin(index):
                unpinned.append(index + 1)
    for first, last in tables:
        if not any(FRAMEWORK_URL.search(lines[k]) for k in range(first, last)):
            continue
        if not any(pin(k) for k in range(first, last)):
            unpinned.append(first + 1)
    report.add(rel, "framework pin", changed)
    if was_rev:
        report.notes.append(f"{rel}: {was_rev} rev pin(s) became tag = \"{TAG}\" (use --rev <sha> to keep a rev)")
    for n in unpinned:
        report.notes.append(f"{rel}:{n}: a framework dependency with no tag, rev or branch: pin it by hand")
    return "\n".join(lines)


def main():
    opts = parse_args(sys.argv[1:])
    root = os.path.abspath(opts["dir"])
    if not os.path.isdir(root):
        print(f"migrate-app-to-telamon: not a directory: {opts['dir']}", file=sys.stderr)
        sys.exit(2)
    top = git(root, "rev-parse", "--show-toplevel")
    in_git = top.returncode == 0
    if in_git and os.path.realpath(top.stdout.strip()) != os.path.realpath(root):
        print(f"migrate-app-to-telamon: {root} is inside the repository {top.stdout.strip()}: run it in the top directory", file=sys.stderr)
        sys.exit(2)
    if not opts["dry"] and not opts["dirty"]:
        if not in_git:
            print("migrate-app-to-telamon: this is not a git repository, so there is no way back: copy it first, then use --allow-dirty", file=sys.stderr)
            sys.exit(2)
        status = git(root, "status", "--porcelain", "--untracked-files=no")
        if status.stdout.strip():
            print("migrate-app-to-telamon: the working tree has uncommitted changes; commit or stash them first (or --allow-dirty):", file=sys.stderr)
            print(status.stdout.rstrip(), file=sys.stderr)
            sys.exit(2)

    report = Report()
    left = []   # (path, line number, text) of what still says atlas
    for rel in sorted(list_files(root, in_git)):
        if skipped(rel):
            continue
        path = os.path.join(root, rel)
        try:
            if os.path.getsize(path) > MAX_BYTES:
                continue
            raw = open(path, "rb").read()
            if b"\0" in raw:
                continue
            text = raw.decode("utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        new = spec_apply(rel, text, report) if rel.endswith(".spec") else apply_rules(rel, text, report)
        for m in re.finditer(r"app-checks\.yml@([0-9a-f]{40})", new):
            report.notes.append(f"{rel}: app-checks.yml is pinned to the commit {m.group(1)[:12]}: move it to the commit of {TAG} (git ls-remote https://github.com/EternalCoder454/atlas-framework refs/tags/{TAG}) and keep framework-ref: {TAG}")
        if "app!" in new:
            new = raise_ui(rel, new, report)
        if rel.endswith(".toml") and "telamon-framework-" in new:
            if opts["pin"]:
                new = repin(rel, new, report, opts)
        if new != text and not opts["dry"]:
            tmp = path + ".migrate-tmp"
            mode = os.stat(path).st_mode & 0o7777
            with open(tmp, "w", encoding="utf-8", newline="") as f:
                f.write(new)
            os.chmod(tmp, mode)
            os.replace(tmp, path)
        for n, line in enumerate(new.split("\n"), 1):
            if re.search(r"atlas", line, re.I):
                left.append((rel, n, line.strip()))

    # Files: atlas-<x>.notifyrc -> telamon-<x>.notifyrc
    for rel in sorted(list_files(root, in_git)):
        base = os.path.basename(rel)
        m = re.fullmatch(r"atlas-([a-z0-9_-]+)\.notifyrc", base)
        if m and not skipped(rel):
            dst = os.path.join(os.path.dirname(rel), "telamon-" + m.group(1) + ".notifyrc")
            report.renamed.append((rel, dst))
            if not opts["dry"]:
                if os.path.exists(os.path.join(root, dst)):
                    print(f"migrate-app-to-telamon: {dst} exists already; not renaming {rel}", file=sys.stderr)
                elif in_git and git(root, "mv", rel, dst).returncode == 0:
                    pass
                else:
                    os.rename(os.path.join(root, rel), os.path.join(root, dst))

    verb = "would change" if opts["dry"] else "changed"
    total = 0
    for rel in sorted(report.files):
        kinds = ", ".join(f"{k} x{n}" for k, n in sorted(report.files[rel].items()))
        print(f"{rel}: {kinds}")
        total += sum(report.files[rel].values())
    for src, dst in report.renamed:
        print(f"{src}: {'would be renamed' if opts['dry'] else 'renamed'} to {dst}")
    print(f"migrate-app-to-telamon: {verb} {total} place(s) in {len(report.files)} file(s), renamed {len(report.renamed)} file(s)")

    for note in report.notes:
        print("note: " + note)

    # What still says atlas: the app's own names, mostly. Not an error.
    tokens = {}
    for f, n, t in left:
        for tok in re.findall(r"[A-Za-z0-9_./~-]*[Aa][Tt][Ll][Aa][Ss][A-Za-z0-9_./-]*", t):
            if tok.rstrip("./-").lower() in ("atlas", "atlas-framework", "atlasos", "atlas-framework-rpms"):
                tok = tok.rstrip("./-")
            entry = tokens.setdefault(tok, [0, f, n])
            entry[0] += 1
    if tokens:
        print("\nStill says \"atlas\" (names of the app itself stay until it is renamed; the repository name\n"
              "atlas-framework stays until GitHub renames it; look at the rest):")
        for tok, (count, f, n) in sorted(tokens.items(), key=lambda kv: (-kv[1][0], kv[0]))[:30]:
            print(f"  {tok}  x{count}  (first: {f}:{n})")
        if len(tokens) > 30:
            print(f"  ... and {len(tokens) - 30} more names")

    frameworks = any("framework pin" in k or "crate" in k for k in (kk for v in report.files.values() for kk in v))
    print("\nNext:")
    if frameworks:
        print("  cargo fetch   # no --locked: Cargo.lock still names the atlas-framework crates; this swaps them for the new ones")
        print("  (if cargo says \"failed to select a version for X\": cargo update -p X, and again. Then build with --locked.)")
    print("  install telamon-ui 2.0.0 (and telamon-symbols-fonts) in the app's container, build, run the tests")
    print("  git diff   # look at every change")
    if opts["dry"]:
        print("(dry run: nothing was changed)")


main()
PYTHON
