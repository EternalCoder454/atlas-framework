#!/usr/bin/env python3
"""Telamon native app bundles: make one from an installed tree, and verify one.

    bundle.py version --app-dir DIR [--version V]
    bundle.py pack    --tree DIR --out DIR --epoch N --version V [options]
    bundle.py verify  ARCHIVE MANIFEST

tools/make-bundle.sh builds and installs an app, then calls `pack`. The format
is described in docs/BUNDLES.md; this file is its reference implementation
(the Store reads the same rules). Standard library only, plus the `zstd` program.

`verify` reads hostile input (a bundle may come from anywhere, and the signing job of
.github/workflows/bundle.yml runs it on whatever an app's build made), so it never
extracts: the archive is streamed through `zstd -dc` into `scan_tar`, every entry is
only looked at and hashed, and nothing is written to disk.
"""

import argparse
import hashlib
import io
import json
import os
import posixpath
import re
import shlex
import stat
import subprocess
import sys
import tarfile
import unicodedata
import xml.etree.ElementTree as ET

SCHEMA = 1
ARCH = "x86_64"
MANIFEST = "telamon-bundle.json"
TOP_DIRS = ("bin", "share")
KEY_ORDER = ["schema", "id", "name", "version", "summary", "homepage", "license",
             "arch", "min_telamon_ui", "min_os_version", "files", "links"]
FILE_KEYS = ["path", "size", "sha256", "executable"]
LINK_KEYS = ["path", "target"]
ARCHIVE_KEYS = ["name", "sha256", "size"]

ID_RE = re.compile(r"[A-Za-z0-9._-]+")
NUM = r"(?:0|[1-9][0-9]{0,8})"
# up to 6 numbers of at most 9 digits, no leading zeros; a prerelease of dot-separated [0-9A-Za-z-] (the Store's rule)
VERSION_RE = re.compile(rf"{NUM}(?:\.{NUM}){{1,5}}(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?")
MIN_UI_RE = re.compile(rf"{NUM}(?:\.{NUM}){{0,5}}")
OSVER_RE = re.compile(r"[0-9]{1,4}")
SHA_RE = re.compile(r"[0-9a-f]{64}")
BARE_RE = re.compile(r"[A-Za-z0-9._+-]{1,100}")

# The Store's caps (telamon-store-core, native/manifest.rs and desktop.rs).
MAX_FILES = 20000                 # files, and links, each
MAX_ENTRIES = 2 * MAX_FILES       # every entry of the archive, directories too
MAX_FILE = 512 * 1024 ** 2
MAX_TOTAL = 1024 ** 3             # unpacked
MAX_ARCHIVE = 256 * 1024 ** 2
MAX_ICONS = 64
MAX_EXPORTS = 200                 # exported files in all
MAX_EXPORT = 1024 * 1024          # one exported file
MAX_KEYFILE = 64 * 1024           # a .desktop or .service file
MAX_KEYFILE_LINES = 1000
MAX_PATH = 1024                   # bytes, a whole path
MAX_FOLLOWS = 40                  # symlinks followed to resolve one link (Linux's own limit)
SMALL = MAX_EXPORT                # files read whole: desktop, service, metainfo, manifest
MAX_MANIFEST = 1024 * 1024        # telamon-store-core native/manifest.rs MAX_MANIFEST
MAX_PAX = 64 * 1024               # the one pax header before an entry (path, linkpath): nothing else is written
# archive.rs `unpack`: the decompressor is cut off after MAX_UNPACKED plus 1536 bytes of headers
# for each of the (2 * MAX_FILES + 16) entries a bundle may hold. A "zip bomb" ends there.
MAX_DECOMPRESSED = MAX_TOTAL + (MAX_FILES * 2 + 16) * 1536
MAX_NAME, MAX_SUMMARY, MAX_LICENSE = 80, 300, 100   # manifest.rs `check`: the Store cuts the texts shown at these


def valid_version(v):
    return len(v) <= 64 and VERSION_RE.fullmatch(v) is not None


def valid_min_ui(v):
    return len(v) <= 64 and MIN_UI_RE.fullmatch(v) is not None


def valid_app_id(i):
    """The Store's rule, and at least three dot-separated parts."""
    parts = i.split(".")
    return (len(i.encode("utf-8")) <= 128 and ID_RE.fullmatch(i) is not None and len(parts) >= 3
            and all(p and not p.startswith("-") for p in parts))


def hidden(c):
    """The Store's `hidden` characters (telamon-store-core, launch.rs `hidden`: control, invisible, bidi, filler),
    plus any other format, control or line/paragraph separator."""
    o = ord(c)
    return (unicodedata.category(c)[0] == "C" or unicodedata.category(c) in ("Zl", "Zp") or o in (
        0xAD, 0x34F, 0x61C, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x200B, 0x200E, 0x200F, 0x3164, 0xFEFF, 0xFFA0)
        or 0x180B <= o <= 0x180F or 0x2028 <= o <= 0x202E or 0x2060 <= o <= 0x206F
        or 0xFE00 <= o <= 0xFE0F or 0xFFF9 <= o <= 0xFFFB or 0x1BCA0 <= o <= 0x1BCA3
        or 0x1D173 <= o <= 0x1D17A or 0xE0000 <= o <= 0xE007F or 0xE0100 <= o <= 0xE01EF)


# telamon-store-core text.rs `class` / `LineBuf`: the Store cleans every text it shows (drops controls and
# invisible characters, collapses white space, cuts at a cap). A bundle's name, summary and license must
# already be what that leaves, so the page shows exactly what the manifest says.
_STORE_SPACE = frozenset("\t\n\x0b\x0c\r \x85\xa0\u1680\u2028\u2029\u202f\u205f\u3000") | frozenset(map(chr, range(0x2000, 0x200B)))


def _store_dropped(c):
    o = ord(c)
    return (unicodedata.category(c) in ("Cc", "Cs") or o in (0xAD, 0x34F, 0x61C, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x200B, 0x3164, 0xFEFF, 0xFFA0)
            or 0x180B <= o <= 0x180F or 0x202A <= o <= 0x202E or 0x2060 <= o <= 0x206F or 0xFE00 <= o <= 0xFE0F
            or 0xFFF9 <= o <= 0xFFFC or 0x1BCA0 <= o <= 0x1BCA3 or 0x1D173 <= o <= 0x1D17A or 0xE0000 <= o <= 0xE007F
            or 0xE0100 <= o <= 0xE01EF or 0xFDD0 <= o <= 0xFDEF or (o & 0xFFFE) == 0xFFFE)


def store_clean(s, max_chars):
    """What the Store's `text::clean(s, max_chars)` leaves of `s`."""
    out, pending, n = [], False, 0
    for c in s:
        if c in _STORE_SPACE:
            pending = n > 0
        elif not _store_dropped(c):
            extra = 2 if pending else 1
            if n + extra > max_chars:
                break
            if pending:
                out.append(" ")
                pending = False
            out.append(c)
            n += extra
    return "".join(out)


_BAD_TLDS = {"local", "localhost", "localdomain", "lan", "home", "internal", "intranet", "private", "corp",
             "arpa", "test", "example", "invalid", "onion", "alt"}


def https_url(s):
    """The Store's normalised https address (launch.rs `https_url`), or None."""
    if len(s) > 4096 or not all(0x21 <= ord(c) <= 0x7e for c in s) or any(c in '\\"<>`{}|^' for c in s):
        return None
    if s[:8].lower() != "https://":
        return None
    rest = s[8:]
    cut = min([i for i in (rest.find(c) for c in "/?#") if i >= 0], default=len(rest))
    authority, tail = rest[:cut], rest[cut:]
    host = authority
    if ":" in authority:
        host, port = authority.split(":", 1)
        if port != "443":
            return None
    path = re.split(r"[?#]", tail, maxsplit=1)[0]
    if any(seg in (".", "..") for seg in path.lower().replace("%2e", ".").split("/")):
        return None
    host = host.lower()
    labels = host.split(".")
    if not (len(host) <= 253 and len(labels) >= 2
            and all(1 <= len(lb) <= 63 and re.fullmatch(r"[a-z0-9-]+", lb) and not lb.startswith("-") and not lb.endswith("-")
                    for lb in labels)
            and re.fullmatch(r"[a-z]+", labels[-1]) and labels[-1] not in _BAD_TLDS):
        return None
    return f"https://{host}{tail}"


class BundleError(Exception):
    """One or more problems; each line is a message."""

    def __init__(self, problems):
        if isinstance(problems, str):
            problems = [problems]
        self.problems = list(problems)
        super().__init__("\n".join(self.problems))


class Entry:
    __slots__ = ("path", "kind", "mode", "uid", "gid", "mtime", "size", "sha256", "target")

    def __init__(self, path, kind, mode=0, uid=0, gid=0, mtime=0, size=0, sha256="", target=""):
        self.path, self.kind, self.mode = path, kind, mode
        self.uid, self.gid, self.mtime = uid, gid, mtime
        self.size, self.sha256, self.target = size, sha256, target


def dump(obj):
    """The one JSON form: insertion order, 2-space indent, trailing newline."""
    return json.dumps(obj, indent=2, ensure_ascii=False, allow_nan=False) + "\n"


def printable(text):
    """`text` with control, hidden and non-printing characters written as \\uXXXX, for messages:
    a file name must not be able to start a line of its own in a log (GitHub Actions reads
    `::workflow-command::` lines) or move the cursor in a terminal."""
    return "".join(c if c.isprintable() and not hidden(c) else
                   (f"\\u{ord(c):04x}" if ord(c) <= 0xFFFF else f"\\U{ord(c):08x}") for c in text)


def open_regular(path):
    """Opens a regular file for reading without following a symlink at `path`
    (a file swapped for a link while the tree is read is refused)."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK)
    except OSError as exc:
        raise BundleError(f"cannot read {printable(path)}: {exc.strerror}") from None
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise BundleError(f"{printable(path)}: not a regular file")
    return os.fdopen(fd, "rb")


# ---------------------------------------------------------------- path rules

def path_problem(p):
    """Why a tree path is not allowed, or None. The Store's rule is `valid_rel_path` (telamon-store-core,
    native/manifest.rs: non-empty, at most 1,024 bytes, not absolute, every part non-empty, not `.` or `..`, at most 255
    bytes, no `hidden` character) applied by native/archive.rs `entry_path` to each member name (it also
    tolerates a leading `./` and a directory's trailing `/`, which this tool never writes and refuses). More
    here: no backslash, and every other control, format or separator character, not only the Store's list."""
    if p == "" or p.startswith("/"):
        return "empty or absolute path"
    if "\\" in p:
        return "backslash in path"
    try:
        raw = p.encode("utf-8")
    except UnicodeEncodeError:
        return "path is not valid UTF-8"
    if len(raw) > MAX_PATH:
        return f"path longer than {MAX_PATH} bytes"
    for c in p.split("/"):
        if c in ("", ".", ".."):
            return "path has an empty, '.' or '..' component (no './' prefix, no '..')"
        if len(c.encode("utf-8")) > 255:
            return "path component longer than 255 bytes"
        if any(hidden(ch) for ch in c):
            return "control, format (bidi, zero-width) or other hidden character in path"
    return None


def link_target_ok(path, target):
    """The Store's lexical rule for a link target (native/manifest.rs `link_target_ok`, checked again on the real
    folders by archive.rs `unpack`): relative, plain names and `..`, no empty or `.` part, no hidden
    character, at most 1,024 bytes, never above the root."""
    if not target or len(target.encode("utf-8", "replace")) > 1024 or target.startswith("/") or any(hidden(c) for c in target):
        return False
    depth = path.count("/")
    for part in target.split("/"):
        if part in ("", "."):
            return False
        if part == "..":
            depth -= 1
            if depth < 0:
                return False
        else:
            depth += 1
    return True


def resolve_link(path, target, by_path=None):
    """The tree path a symlink at `path` points to, or None if it leaves the tree.
    With `by_path` (every entry), links on the way are followed too, so `d/..`
    through a link to a directory cannot climb out."""
    if target == "" or target.startswith("/") or "\\" in target:
        return None
    if by_path is None:
        joined = posixpath.normpath(posixpath.join(posixpath.dirname(path), target))
        if joined == "." or joined == ".." or joined.startswith("../"):
            return None
        return joined
    # Like the kernel, at most MAX_FOLLOWS links are followed to resolve one path (ELOOP):
    # without it a few links that name each other many times over take for ever.
    parts = _walk(by_path, posixpath.dirname(path).split("/") if "/" in path else [], target, [MAX_FOLLOWS])
    return "/".join(parts) if parts else None


def _walk(by_path, start, rel, budget):
    parts = list(start)
    for comp in rel.split("/"):
        if comp in ("", "."):
            continue
        if comp == "..":
            if not parts:
                return None
            parts.pop()
            continue
        parts.append(comp)
        e = by_path.get("/".join(parts))
        if e is not None and e.kind == "link":
            budget[0] -= 1
            if budget[0] < 0 or e.target == "" or e.target.startswith("/") or "\\" in e.target:
                return None
            parts = _walk(by_path, parts[:-1], e.target, budget)
            if parts is None:
                return None
    return parts


def validate(entries, archive):
    """Layout rules shared by `pack` (on the staged tree) and `verify` (on the archive)."""
    errs = []
    by_path = {}
    total = 0
    if len(entries) > MAX_ENTRIES:
        errs.append(f"{len(entries)} entries: more than {MAX_ENTRIES}")
    for e in entries:
        bad = path_problem(e.path)
        if bad:
            errs.append(f"{e.path!r}: {bad}")
            continue
        if e.path in by_path:
            errs.append(f"{e.path}: listed twice")
            continue
        by_path[e.path] = e
        total += e.size
    if total > MAX_TOTAL:
        errs.append(f"{total} bytes of files: more than {MAX_TOTAL} (1 GiB unpacked)")
    nfiles = sum(1 for e in by_path.values() if e.kind == "file")
    nlinks = sum(1 for e in by_path.values() if e.kind == "link")
    if nfiles > MAX_FILES or nlinks > MAX_FILES:
        errs.append(f"{nfiles} files and {nlinks} links: at most {MAX_FILES} of each")

    # every directory some entry is below, to tell a link to a missing directory in O(1)
    dirs = {p.rsplit("/", i)[0] for p in by_path for i in range(1, p.count("/") + 1)}
    for e in by_path.values():
        top = e.path.split("/", 1)[0]
        if "/" not in e.path and e.kind != "dir":
            if not (archive and e.kind == "file" and e.path == MANIFEST):
                errs.append(f"{e.path}: only {', '.join(TOP_DIRS)}" + (f" and {MANIFEST}" if archive else "")
                            + " may be at the top; install into bin/ and share/")
                continue
        elif top not in TOP_DIRS:
            errs.append(f"{e.path}: outside bin/ and share/ (no lib/, etc/ or libexec/: a bundle links Qt, KF6 and telamon-ui from the OS)")
            continue
        parent = posixpath.dirname(e.path)
        if parent:
            p = by_path.get(parent)
            if p is None:
                errs.append(f"{e.path}: its directory {parent} is not in the archive")
            elif p.kind != "dir":
                errs.append(f"{e.path}: inside {parent}, which is a {p.kind}, not a directory")
        if archive:
            if e.uid != 0 or e.gid != 0:
                errs.append(f"{e.path}: owner {e.uid}:{e.gid}, expected 0:0")
        if e.kind == "dir":
            if archive and e.mode & 0o7777 != 0o755:
                errs.append(f"{e.path}: directory mode {e.mode & 0o7777:04o}, expected 0755")
        elif e.kind == "file":
            if e.size > MAX_FILE:
                errs.append(f"{e.path}: {e.size} bytes, more than {MAX_FILE} (512 MiB)")
            if archive and e.mode & 0o7777 not in (0o755, 0o644):
                errs.append(f"{e.path}: mode {e.mode & 0o7777:04o}, expected 0755 or 0644")
            if e.path.startswith("bin/") and not e.mode & 0o111:
                errs.append(f"{e.path}: in bin/ but not executable")
            if e.path.startswith("bin/") and e.path.count("/") > 1:
                errs.append(f"{e.path}: bin/ holds no subdirectories")
        elif e.kind == "link":
            dest = resolve_link(e.path, e.target, by_path) if link_target_ok(e.path, e.target) else None
            if archive and e.mode & 0o7777 != 0o777:
                errs.append(f"{e.path}: symlink mode {e.mode & 0o7777:04o}, expected 0777")
            if dest is None:
                errs.append(f"{e.path}: symlink to {e.target!r}, which is not a relative path inside the tree "
                            "(plain names and '..', no empty or '.' part, no hidden character)")
            elif dest not in by_path and dest not in dirs:
                errs.append(f"{e.path}: symlink to {e.target!r}, which is not in the archive")
            if e.path.startswith("bin/") and e.path.count("/") > 1:
                errs.append(f"{e.path}: bin/ holds no subdirectories")
    if archive:
        paths = [e.path for e in entries]
        if paths != sorted(paths):
            errs.append("entries are not sorted by path (a directory must come before its content)")
        mt = {e.mtime for e in entries}
        if len(mt) > 1:
            errs.append(f"entries have {len(mt)} different modification times; they must all be the commit time")
    if errs:
        raise BundleError(errs)
    return by_path


# ------------------------------------------------------- semantic (file contents)

# What Telamon Store copies out of a bundle (docs/BUNDLES.md, "What the Store
# copies out of a bundle"): only these, only as regular files. The rest of
# share/ and bin/ stays in the app's own prefix.
EXPORT_DIRS = ("share/applications", "share/icons", "share/metainfo", "share/dbus-1", "share/knotifications6")
ICON_RE = re.compile(r"share/icons/hicolor/(?:scalable|[0-9]+x[0-9]+)/apps/([^/]+)")


def in_export_zone(path):
    return any(path == d or path.startswith(d + "/") for d in EXPORT_DIRS)


def notifyrc_ok(path, app_id):
    """share/knotifications6/telamon-<last part of the app id>[-_<suffix>].notifyrc"""
    last = app_id.rsplit(".", 1)[-1]
    return re.fullmatch(rf"share/knotifications6/telamon-{re.escape(last)}(?:[-_][A-Za-z0-9._+-]*)?\.notifyrc", path) is not None


def _glib_space(c):
    return c in " \t\n\x0b\x0c\r"


def parse_keyfile(data, what):
    """A .desktop or D-Bus .service file, read as strictly as the Store reads it
    (GLib's key-file rules plus its limits). Returns [(group, [(key, value)])] in
    order of first appearance (a repeated group merges). Raises BundleError."""
    if len(data) > MAX_KEYFILE:
        raise BundleError(f"{what}: larger than {MAX_KEYFILE // 1024} KiB")
    if b"\0" in data:
        raise BundleError(f"{what}: contains a NUL byte")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        raise BundleError(f"{what}: not UTF-8 text") from None
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if len(lines) > MAX_KEYFILE_LINES:
        raise BundleError(f"{what}: more than {MAX_KEYFILE_LINES} lines")
    groups, cur, nkeys = [], None, 0
    for n, line in enumerate(lines, 1):
        if line.endswith("\r"):
            line = line[:-1]
        line = line.lstrip(" \t\n\x0b\x0c\r")
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            end = line.find("]", 1)
            if end < 0 or line[end + 1:].strip(" \t"):
                raise BundleError(f"{what}: line {n} is not a group, a key or a comment")
            name = line[1:end]
            if not name or any(c in "[]" or unicodedata.category(c) == "Cc" for c in name):
                raise BundleError(f"{what}: line {n}: a group name is not valid")
            cur = next((g for g in groups if g[0] == name), None)
            if cur is None:
                if len(groups) >= 32:
                    raise BundleError(f"{what}: more than 32 groups")
                cur = (name, [])
                groups.append(cur)
            continue
        if "=" not in line:
            raise BundleError(f"{what}: line {n} is not a group, a key or a comment")
        if cur is None:
            raise BundleError(f"{what}: line {n}: a key before the first group")
        key, value = line.split("=", 1)
        key = key.rstrip(" \t\n\x0b\x0c\r")
        base, _, loc = key.partition("[")
        if not base or base.startswith(" ") or any(c in "=[]" or unicodedata.category(c) == "Cc" for c in base) or \
                (loc and (not loc.endswith("]") or not loc[:-1] or any(c in "[]" or unicodedata.category(c) == "Cc" for c in loc[:-1]))):
            raise BundleError(f"{what}: line {n}: a key name is not valid")
        value = value.lstrip(" \t\n\x0b\x0c\r")
        if len(value.encode("utf-8")) > 8192:
            raise BundleError(f"{what}: line {n}: a value is longer than 8192 bytes")
        nkeys += 1
        if nkeys > 400:
            raise BundleError(f"{what}: more than 400 keys")
        cur[1].append((key, value.rstrip(" \t\r")))
    return groups


def group_get(groups, group, key):
    """The last value of `key` in `group`, as GLib reads it."""
    val = None
    for name, items in groups:
        if name == group:
            for k, v in items:
                if k == key:
                    val = v
    return val


def parse_ini_group(text, group):
    """Keys of one group (a later duplicate wins), for text parse_keyfile accepted."""
    return {k: v for name, items in parse_keyfile(text.encode("utf-8"), "file") if name == group for k, v in items}


def exec_name(value):
    """The bare program name an Exec= line starts with, or raise ValueError:
    no path, no quotes, no `env`, [A-Za-z0-9._+-] at most 100, not starting with a dot."""
    if value[:1] in ("'", '"'):
        raise ValueError(f"Exec={value!r} starts with a quote: start it with the bare program name")
    cut = min([i for i in (value.find(" "), value.find("\t")) if i >= 0], default=len(value))
    first = value[:cut]
    if not first:
        raise ValueError("Exec= is empty")
    if "/" in first:
        raise ValueError(f"Exec starts with {first!r}: use the bare binary name (the Store fills in the path)")
    if first == "env":
        raise ValueError("Exec starts with `env`: start it with the app's own program (the Store sets no environment)")
    if not BARE_RE.fullmatch(first) or first.startswith("."):
        raise ValueError(f"Exec starts with {first!r}: a program name is [A-Za-z0-9._+-], at most 100, not starting with a dot")
    return first


def check_exec(by_path, where, value):
    try:
        name = exec_name(value)
    except ValueError as exc:
        return f"{where}: {exc}"
    e = by_path.get(f"bin/{name}")
    if e is None or e.kind != "file" or not e.mode & 0o111:
        return f"{where}: Exec={name!r}, but bin/{name} is not an executable file in the bundle (a regular file directly in bin/)"
    return None


def exec_errors(groups, where, by_path):
    """Problems with every Exec= of a parsed .desktop file (and the localised launcher keys)."""
    errs = []
    execs = []
    for name, items in groups:
        for k, v in items:
            if k.startswith(("Exec[", "TryExec[", "Path[")):
                errs.append(f"{where} [{name}]: {k} is a localised launcher key, which the Store does not copy")
            elif k == "Exec":
                execs.append((name, v))
    names = [g for g, _ in execs]
    if "Desktop Entry" not in names:
        errs.append(f"{where}: no Exec= in [Desktop Entry]")
    for g in sorted({g for g in names if names.count(g) > 1}):
        errs.append(f"{where} [{g}]: Exec= twice")
    for g, v in execs:
        bad = check_exec(by_path, f"{where} [{g}]", v)
        if bad:
            errs.append(bad)
    return errs


def check_semantics(by_path, read):
    """The rules for what the Store copies out: .desktop, icons, metainfo, D-Bus
    services and notification files. `read(path)` returns bytes.
    Returns (app id, metainfo dict)."""
    errs = []
    apps = sorted(p for p, e in by_path.items() if p.startswith("share/applications/") or
                  (p == "share/applications" and e.kind != "dir"))
    if len(apps) != 1 or not apps[0].endswith(".desktop") or apps[0].count("/") != 2:
        raise BundleError([f"share/applications must hold exactly one file, <app id>.desktop: found {len(apps)}: "
                           f"{', '.join(apps) or 'none'} (leave a legacy file out with --exclude)"])
    dpath = apps[0]
    app_id = posixpath.basename(dpath)[: -len(".desktop")]
    if not valid_app_id(app_id):
        errs.append(f"{dpath}: the app id {app_id!r} must be reverse-DNS with at least three parts: letters, digits, '.', '_' and '-', "
                    "no empty part, no part starting with '-', at most 128 bytes")

    exported = 0
    icons = 0

    def too_big(p, limit):
        return by_path[p].size > limit

    if by_path[dpath].kind != "file":
        errs.append(f"{dpath}: must be a regular file")
    elif too_big(dpath, MAX_KEYFILE):
        errs.append(f"{dpath}: larger than {MAX_KEYFILE // 1024} KiB")
    else:
        try:
            groups = parse_keyfile(read(dpath), dpath)
        except BundleError as exc:
            errs.extend(exc.problems)
        else:
            if not groups or groups[0][0] != "Desktop Entry":
                errs.append(f"{dpath}: the first group must be [Desktop Entry]")
            if group_get(groups, "Desktop Entry", "Type") != "Application":
                errs.append(f"{dpath}: Type must be Application")
            errs.extend(exec_errors(groups, dpath, by_path))

    for p, e in sorted(by_path.items()):
        if not in_export_zone(p) or (e.kind == "dir" and p in EXPORT_DIRS):
            continue
        if e.kind == "link":
            errs.append(f"{p}: the Store copies this directory's files out: a symlink here is not allowed (a regular file)")
            continue
        if e.kind == "file":
            exported += 1
            if e.size > MAX_EXPORT:
                errs.append(f"{p}: larger than {MAX_EXPORT // 1024 // 1024} MiB, too large to copy out")
        if p.startswith("share/applications"):
            if e.kind == "dir" and p != "share/applications":
                errs.append(f"{p}: share/applications holds no directories")
        elif p.startswith("share/icons"):
            if e.kind != "file":
                continue
            m = ICON_RE.fullmatch(p)
            name = m.group(1) if m else ""
            if not (m and name.endswith((".png", ".svg")) and
                    (name[:-4] == app_id or name.startswith((app_id + "-", app_id + "_")))):
                errs.append(f"{p}: icons are only share/icons/hicolor/<WxH or scalable>/apps/<file>, a .png or .svg named "
                            f"{app_id}.<ext> or starting {app_id}- or {app_id}_ (a bundle cannot shadow theme icons)")
            icons += 1
        elif p.startswith("share/metainfo"):
            if e.kind == "dir" or posixpath.basename(p) not in (f"{app_id}.metainfo.xml", f"{app_id}.appdata.xml") \
                    or posixpath.dirname(p) != "share/metainfo":
                errs.append(f"{p}: share/metainfo holds only {app_id}.metainfo.xml (or {app_id}.appdata.xml)")
        elif p.startswith("share/dbus-1"):
            if e.kind == "dir":
                if p not in ("share/dbus-1", "share/dbus-1/services"):
                    errs.append(f"{p}: share/dbus-1 holds only services/")
                continue
            if posixpath.dirname(p) != "share/dbus-1/services" or not p.endswith(".service"):
                errs.append(f"{p}: share/dbus-1 holds only services/<name>.service")
                continue
            if too_big(p, MAX_KEYFILE):
                errs.append(f"{p}: larger than {MAX_KEYFILE // 1024} KiB")
                continue
            try:
                groups = parse_keyfile(read(p), p)
            except BundleError as exc:
                errs.extend(exc.problems)
                continue
            name = group_get(groups, "D-BUS Service", "Name") or ""
            if not groups or groups[0][0] != "D-BUS Service":
                errs.append(f"{p}: the first group must be [D-BUS Service]")
            elif not (name == app_id or name.startswith(app_id + ".")) or posixpath.basename(p) != name + ".service":
                errs.append(f"{p}: Name={name!r} must be {app_id} or {app_id}.<more>, and the file named <Name>.service")
            execv = group_get(groups, "D-BUS Service", "Exec")
            if execv is None:
                errs.append(f"{p}: no Exec=")
            else:
                bad = check_exec(by_path, p, execv)
                if bad:
                    errs.append(bad)
        elif p.startswith("share/knotifications6"):
            if e.kind == "dir" or not notifyrc_ok(p, app_id):
                errs.append(f"{p}: share/knotifications6 holds only telamon-{app_id.rsplit('.', 1)[-1]}.notifyrc "
                            "(or with a - or _ suffix before .notifyrc)")
    if icons > MAX_ICONS:
        errs.append(f"{icons} icons: at most {MAX_ICONS}")
    if exported > MAX_EXPORTS:
        errs.append(f"{exported} files the Store copies out: at most {MAX_EXPORTS}")

    # A link may not lead to a file the Store exports.
    for p, e in by_path.items():
        if e.kind == "link":
            dest = resolve_link(p, e.target, by_path) if link_target_ok(p, e.target) else None
            if dest is not None and in_export_zone(dest):
                errs.append(f"{p}: symlink to {e.target!r}, a file the Store copies out")

    meta = {}
    mpaths = [f"share/metainfo/{app_id}.metainfo.xml", f"share/metainfo/{app_id}.appdata.xml"]
    found = [m for m in mpaths if m in by_path and by_path[m].kind == "file"]
    if found:
        try:
            meta = parse_metainfo(read(found[0]), app_id)
        except BundleError as exc:
            errs.extend(f"{found[0]}: {m}" for m in exc.problems)
    if errs:
        raise BundleError(errs)
    return app_id, meta


XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"


def parse_metainfo(data, app_id):
    # No entity or DOCTYPE tricks: a metainfo file has neither.
    if b"<!DOCTYPE" in data or b"<!ENTITY" in data or b"\x00" in data or not data.lstrip(b"\xef\xbb\xbf \t\r\n").startswith(b"<"):
        raise BundleError("must be UTF-8 XML without a DOCTYPE or ENTITY declaration")
    # Another declared encoding would hide a DOCTYPE from the check above (the rest of the
    # file is then in that encoding, EBCDIC for example).
    declared = re.match(rb"\s*<\?xml[^>]*?\bencoding\s*=\s*[\"']([^\"']*)[\"']", data.lstrip(b"\xef\xbb\xbf"))
    if declared and declared.group(1).lower().replace(b"_", b"-") not in (b"utf-8", b"utf8"):
        raise BundleError(f"declares the encoding {printable(declared.group(1).decode('latin-1'))}: it must be UTF-8")
    try:
        root = ET.fromstring(data)
    except ET.ParseError as exc:
        raise BundleError(f"not well-formed XML: {exc}") from None
    if root.tag != "component":
        raise BundleError("the root element is not <component>")

    def text(tag):
        for child in root.findall(tag):
            if XML_LANG not in child.attrib and child.text and child.text.strip():
                return " ".join(child.text.split())
        return ""

    cid = text("id")
    if cid and cid not in (app_id, app_id + ".desktop"):
        raise BundleError(f"<id>{cid}</id> is not the app id {app_id}")
    homepage = ""
    for url in root.findall("url"):
        if url.get("type") == "homepage" and url.text and url.text.strip():
            homepage = url.text.strip()
    return {"name": text("name"), "summary": text("summary"),
            "license": text("project_license"), "homepage": homepage}


# --------------------------------------------------------- app metadata sources

def cmake_version(app_dir):
    path = os.path.join(app_dir, "CMakeLists.txt")
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError as exc:
        raise BundleError(f"cannot read {path}: {exc}") from None
    text = re.sub(r"#[^\n]*", "", text)
    m = re.search(r"\bproject\s*\(\s*[^\s)]+[^)]*?\bVERSION\s+([0-9]+(?:\.[0-9]+)*)", text, re.I | re.S)
    if m is None and re.search(r"\bproject\s*\([^)]*\bVERSION\b", text, re.I | re.S):
        raise BundleError(f"project(... VERSION ...) in {path} is not literal numbers (a variable?): the bundle version cannot be checked against it")
    return m.group(1) if m else None


def resolve_version(app_dir, wanted):
    cm = cmake_version(app_dir)
    if wanted:
        wanted = wanted[1:] if wanted.startswith("v") else wanted
        if not valid_version(wanted):
            raise BundleError(f"version {wanted!r}: dotted numbers with an optional -prerelease (0.2.0, 1.0.0-beta.1)")
        core = wanted.split("-", 1)[0]
        if cm is None:
            raise BundleError(f"no project(... VERSION x.y.z) in {app_dir}/CMakeLists.txt: the version {wanted} cannot be checked against it; add a VERSION")
        if core != cm:
            raise BundleError(f"version {wanted} does not match project(... VERSION {cm}) in {app_dir}/CMakeLists.txt: "
                              "set the CMake version to the release's before tagging")
        return wanted
    if cm is None:
        raise BundleError(f"no project(... VERSION x.y.z) in {app_dir}/CMakeLists.txt: add a VERSION")
    if not valid_version(cm):
        raise BundleError(f"project VERSION {cm} needs at least major.minor")
    return cm


def vkey(v):
    return [int(x) for x in v.split(".")]


def spec_min_ui(spec):
    found = {"BuildRequires": [], "Requires": []}
    try:
        lines = open(spec, encoding="utf-8", errors="replace").read().splitlines()
    except OSError as exc:
        raise BundleError(f"cannot read {spec}: {exc}") from None
    for line in lines:
        m = re.match(r"^\s*(BuildRequires|Requires):\s*telamon-ui\s*>=\s*([0-9]+(?:\.[0-9]+)*)", line)
        if m:
            found[m.group(1)].append(m.group(2))
    for key in ("BuildRequires", "Requires"):
        if found[key]:
            return max(found[key], key=vkey)
    return None


def installed_ui():
    r = subprocess.run(["rpm", "-q", "--qf", "%{VERSION}", "telamon-ui"], capture_output=True, text=True)
    if r.returncode == 0 and re.fullmatch(r"[0-9]+(\.[0-9]+)*", r.stdout.strip()):
        return r.stdout.strip()
    return None


def os_version_id():
    try:
        for line in open("/etc/os-release", encoding="utf-8"):
            if line.startswith("VERSION_ID="):
                return line.split("=", 1)[1].strip().strip("\"'")
    except OSError:
        pass
    return None


def spec_field(spec, field):
    if not spec:
        return ""
    for line in open(spec, encoding="utf-8", errors="replace"):
        m = re.match(rf"^{field}:\s*(\S.*?)\s*$", line)
        if m and "%{" not in m.group(1):
            return m.group(1)
    return ""


# ------------------------------------------------------------------- tree / pack

def read_small(tree, rel):
    """At most SMALL + 1 bytes of a file of the tree (more means it is too large)."""
    with open_regular(os.path.join(tree, rel)) as f:
        return f.read(SMALL + 1)


def sha256_file(path):
    h = hashlib.sha256()
    with open_regular(path) as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def scan_tree(tree):
    entries = []

    def walk(rel):
        full = os.path.join(tree, rel) if rel else tree
        for name in sorted(os.listdir(full)):
            r = f"{rel}/{name}" if rel else name
            p = os.path.join(tree, r)
            st = os.lstat(p)
            if stat.S_ISDIR(st.st_mode):
                entries.append(Entry(r, "dir", 0o755))
                walk(r)
            elif stat.S_ISLNK(st.st_mode):
                entries.append(Entry(r, "link", 0o777, target=os.readlink(p)))
            elif stat.S_ISREG(st.st_mode):
                if st.st_mode & 0o7000:
                    raise BundleError(f"{printable(r)}: mode {st.st_mode & 0o7777:04o} has a setuid, setgid or sticky bit: "
                                      "nothing in a bundle runs with another identity; install it with mode 0755 or 0644")
                mode = 0o755 if st.st_mode & 0o111 else 0o644
                entries.append(Entry(r, "file", mode, size=st.st_size, sha256=sha256_file(p)))
            else:
                raise BundleError(f"{printable(r)}: not a directory, file or symlink (a device, fifo or socket)")

    walk("")
    return entries


def build_manifest(meta, entries):
    files = [{"path": e.path, "size": e.size, "sha256": e.sha256, "executable": bool(e.mode & 0o111)}
             for e in sorted(entries, key=lambda x: x.path) if e.kind == "file" and e.path != MANIFEST]
    links = [{"path": e.path, "target": e.target}
             for e in sorted(entries, key=lambda x: x.path) if e.kind == "link"]
    m = {"schema": SCHEMA}
    for k in KEY_ORDER[1:-2]:
        m[k] = meta[k]
    m["files"] = files
    m["links"] = links
    return m


def _create(path):
    """A new file, mode 0644: never written through a link someone left at the name."""
    if os.path.lexists(path):
        os.unlink(path)
    return os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0), 0o644), "wb")


def cmd_pack(a):
    tree = os.path.abspath(a.tree)
    out = os.path.abspath(a.out)
    if not 0 <= a.epoch < 8 ** 11:       # an octal mtime field of a ustar header: no pax `mtime` record
        raise BundleError(f"SOURCE_DATE_EPOCH {a.epoch} is not a time between 1970 and 2242")
    entries = scan_tree(tree)
    if not entries:
        raise BundleError("the install produced no files")
    by_path = validate(entries, archive=False)
    app_id, mi = check_semantics(by_path, lambda p: read_small(tree, p))

    desktop = parse_ini_group(read_small(tree, f"share/applications/{app_id}.desktop").decode("utf-8", "replace"), "Desktop Entry")
    meta = {
        "id": app_id,
        "name": a.name or mi.get("name") or desktop.get("Name", ""),
        "version": a.version,
        "summary": a.summary or mi.get("summary") or desktop.get("Comment", ""),
        "homepage": a.homepage or mi.get("homepage") or spec_field(a.spec, "URL"),
        "license": a.license or mi.get("license") or spec_field(a.spec, "License"),
        "arch": ARCH,
        "min_telamon_ui": a.min_telamon_ui or (spec_min_ui(a.spec) if a.spec else None) or installed_ui() or "",
        "min_os_version": a.min_os_version or os_version_id() or "",
    }
    missing = [k for k, v in meta.items() if not v]
    if missing:
        hints = {"name": "a metainfo <name>", "summary": "a metainfo <summary>", "homepage": "a metainfo <url type=\"homepage\">",
                 "license": "a metainfo <project_license>", "min_telamon_ui": "`BuildRequires: telamon-ui >= X` in the spec, or telamon-ui installed",
                 "min_os_version": "VERSION_ID in /etc/os-release"}
        raise BundleError([f"no {k}: needs {hints.get(k, '--' + k.replace('_', '-'))}" for k in missing])
    if not valid_app_id(meta["id"]):
        raise BundleError(f"id {meta['id']!r} is not valid")
    if not valid_version(meta["version"]):
        raise BundleError(f"version {meta['version']!r} is not valid")
    if not OSVER_RE.fullmatch(meta["min_os_version"]):
        raise BundleError(f"os version {meta['min_os_version']!r} is not valid")
    if not valid_min_ui(meta["min_telamon_ui"]):
        raise BundleError(f"min_telamon_ui {meta['min_telamon_ui']!r} is not a dotted number (up to 6 numbers of at most 9 digits)")
    if https_url(meta["homepage"]) != meta["homepage"]:
        raise BundleError(f"homepage {meta['homepage']!r} is not the plain https address the Store accepts "
                          f"(https only, no port, lowercase public host with a letters-only TLD, no . or .. path part, "
                          f"none of \\ \" < > ` {{ }} | ^); it would be {https_url(meta['homepage'])!r}")

    inner = build_manifest(meta, entries)
    inner_bytes = dump(inner).encode("utf-8")
    entries.append(Entry(MANIFEST, "file", 0o644, size=len(inner_bytes)))
    name = f"{meta['id']}-{meta['version']}-{ARCH}.tar.zst"
    os.makedirs(out, exist_ok=True)
    archive_path = os.path.join(out, name)
    manifest_path = os.path.join(out, MANIFEST)
    tmp = archive_path + ".part"

    # Deterministic: one thread, a fixed level, a fixed tar format with the names written as UTF-8
    # whatever the locale, and the time from SOURCE_DATE_EPOCH. The same tree and the same zstd give
    # the same bytes.
    try:
        with _create(tmp) as outf:
            z = subprocess.Popen(["zstd", "-19", "-T1", "-q", "-c"], stdin=subprocess.PIPE, stdout=outf)
            try:
                with tarfile.open(fileobj=z.stdin, mode="w|", format=tarfile.PAX_FORMAT, encoding="utf-8", errors="strict") as tf:
                    for e in sorted(entries, key=lambda x: x.path):
                        ti = tarfile.TarInfo(e.path)
                        ti.mtime, ti.uid, ti.gid, ti.uname, ti.gname = a.epoch, 0, 0, "", ""
                        ti.mode = e.mode
                        if e.kind == "dir":
                            ti.type = tarfile.DIRTYPE
                            tf.addfile(ti)
                        elif e.kind == "link":
                            ti.type, ti.linkname = tarfile.SYMTYPE, e.target
                            tf.addfile(ti)
                        elif e.path == MANIFEST:
                            ti.size = len(inner_bytes)
                            tf.addfile(ti, io.BytesIO(inner_bytes))
                        else:
                            ti.size = e.size
                            with open_regular(os.path.join(tree, e.path)) as f:
                                tf.addfile(ti, f)
            finally:
                z.stdin.close()
                rc = z.wait()
            if rc != 0:
                raise BundleError(f"zstd failed ({rc})")
        os.replace(tmp, archive_path)
    finally:
        if os.path.lexists(tmp):
            os.unlink(tmp)

    outer = dict(inner)
    outer["archive"] = {"name": name, "sha256": sha256_file(archive_path), "size": os.path.getsize(archive_path)}
    mtmp = manifest_path + ".part"
    try:
        with _create(mtmp) as f:
            f.write(dump(outer).encode("utf-8"))
        os.replace(mtmp, manifest_path)
    finally:
        if os.path.lexists(mtmp):
            os.unlink(mtmp)
    try:
        verify(archive_path, manifest_path, epoch=a.epoch)
    except BundleError:
        os.unlink(archive_path)
        os.unlink(manifest_path)
        raise
    print(archive_path)
    print(manifest_path)
    print(f"sha256 {outer['archive']['sha256']}  {name}", file=sys.stderr)


# ------------------------------------------------------------------------ verify

BLOCK = 512
_ZERO = bytes(BLOCK)
_TYPES = {b"0": "file", b"2": "link", b"5": "dir"}
_REFUSED = {b"1": "hard link", b"3": "device or fifo", b"4": "device or fifo", b"6": "device or fifo",
            b"7": "contiguous file", b"g": "global pax header", b"S": "sparse file",
            b"L": "GNU long name entry", b"K": "GNU long link entry", b"\0": "old-style file entry"}


def tarfile_type(flag):
    return _REFUSED.get(flag, "special entry")


def _octal(field, what):
    """A tar number: octal digits, then NUL or spaces. No base-256, no sign, no letters:
    the readers of a tar disagree about everything else."""
    digits = bytes(field).split(b"\0", 1)[0].split(b" ", 1)[0]
    rest = bytes(field)[len(digits):]
    if not digits or not all(0x30 <= b <= 0x37 for b in digits) or rest.strip(b"\0 "):
        raise BundleError(f"tar header: {what} is not a plain octal number")
    return int(digits, 8)


def _cstr(field, what):
    raw = bytes(field)
    text, _, rest = raw.partition(b"\0")
    if rest.strip(b"\0"):
        raise BundleError(f"tar header: {what} has bytes after its end")
    return text


def _utf8(raw, what):
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise BundleError(f"{what}: not valid UTF-8") from None
    if "\0" in text:
        raise BundleError(f"{what}: NUL in a name")
    return text


def parse_pax(data):
    """The one extended header an entry may have: `path` and `linkpath` records, each at most once.
    Anything else (size, uid, mtime, comments, ...) is how two readers come to read one archive two ways."""
    out, i = {}, 0
    while i < len(data):
        sp = data.find(b" ", i)
        if sp < 0 or not 0 < sp - i <= 7 or not data[i:sp].isdigit():
            raise BundleError("pax header: a record does not start with its length")
        n = int(data[i:sp])
        rec = data[i:i + n]
        if n < sp - i + 4 or len(rec) != n or not rec.endswith(b"\n"):
            raise BundleError("pax header: a record's length is wrong")
        key, eq, value = rec[sp + 1:-1].partition(b"=")
        if not eq or key not in (b"path", b"linkpath") or key in out:
            raise BundleError("pax header: only one `path` and one `linkpath` record are written")
        out[key] = _utf8(value, f"pax {key.decode()}")
        i += n
    return out


def scan_tar(stream, want_small=False):
    """Reads an uncompressed tar from `stream` as strictly as the Store's unpacker does and more:
    one canonical form (POSIX ustar headers, `path`/`linkpath` pax headers for long or non-ASCII
    names; octal numbers; no GNU, sparse, global, hard link, device or fifo entries; no data after
    the end marker; every header checksummed). Returns ([Entry], {name: bytes of the small files}).

    The archive.rs reader (the `tar` crate) and any other reader then see the same entries; a
    tar this function accepts has no second reading."""
    entries, small, used = [], {}, 0
    pending = None

    def take(n):
        nonlocal used
        used += n
        if used > MAX_DECOMPRESSED:
            raise BundleError("the archive is larger than the limits (entries or bytes)")
        data = stream.read(n)
        if len(data) != n:
            raise BundleError("the tar archive ends in the middle of an entry")
        return data

    def padding(n):
        if n and take(n).strip(b"\0"):
            raise BundleError("tar: the padding after an entry's data is not zeros")

    while True:
        hdr = take(BLOCK)
        if hdr == _ZERO:
            if pending is not None:
                raise BundleError("tar: a pax header with no entry after it")
            break
        if hdr[257:263] != b"ustar\0" or hdr[263:265] != b"00":
            raise BundleError("tar header: not a POSIX ustar header (GNU and old formats are not accepted)")
        if sum(hdr[:148]) + 8 * 32 + sum(hdr[156:]) != _octal(hdr[148:156], "the checksum"):
            raise BundleError("tar header: the checksum is wrong")
        flag = hdr[156:157]
        size = _octal(hdr[124:136], "the size")
        mode, uid, gid = (_octal(hdr[a:b], w) for a, b, w in ((100, 108, "the mode"), (108, 116, "the uid"), (116, 124, "the gid")))
        mtime = _octal(hdr[136:148], "the modification time")
        if _cstr(hdr[265:329], "the owner names") or _cstr(hdr[345:500], "the name prefix"):
            raise BundleError("tar header: owner names and the ustar name prefix are not written; a long name is a pax `path`")
        if any(f.strip(b"\0") and _octal(f, "a device number") for f in (hdr[329:337], hdr[337:345])):
            raise BundleError("tar header: device numbers on an entry that is not a device")
        name_raw = _cstr(hdr[0:100], "the name")
        link_raw = _cstr(hdr[157:257], "the link name")
        if flag == b"x":
            if pending is not None or size == 0 or size > MAX_PAX:
                raise BundleError("tar: a pax header that is empty, too large or follows another")
            data = take(size)
            padding(-size % BLOCK)
            pending = parse_pax(data)
            continue
        px, pending = pending or {}, None
        name = px[b"path"] if b"path" in px else _utf8(name_raw, "a file name")
        if flag not in _TYPES:
            raise BundleError(f"{name}: a {tarfile_type(flag)}: only directories, files and symlinks are allowed")
        if len(entries) >= MAX_ENTRIES:
            raise BundleError("the archive is larger than the limits (entries or bytes)")
        kind = _TYPES[flag]
        if kind != "link" and (link_raw or b"linkpath" in px):
            raise BundleError(f"{name}: a link name on an entry that is not a link")
        if kind == "dir":
            name = name[:-1] if name.endswith("/") else name
        e = Entry(name, kind, mode)
        e.uid, e.gid, e.mtime = uid, gid, mtime
        if kind == "link":
            e.target = px[b"linkpath"] if b"linkpath" in px else _utf8(link_raw, "a link target")
            if size:
                raise BundleError(f"{name}: a link with data")
        elif kind == "dir":
            if size:
                raise BundleError(f"{name}: a directory with data")
        else:
            if size > MAX_FILE:
                raise BundleError(f"{name}: {size} bytes, more than {MAX_FILE} (512 MiB)")
            # Kept whole: the manifest and the few files check_semantics reads, each only up to the size
            # the Store reads of it (a bigger one is refused there by its size, not by its content).
            limit = (MAX_MANIFEST if name == MANIFEST else
                     MAX_KEYFILE if name.endswith((".desktop", ".service")) and in_export_zone(name) else
                     SMALL if name.endswith((".metainfo.xml", ".appdata.xml")) and in_export_zone(name) else -1)
            h, keep, buf, left = hashlib.sha256(), want_small and size <= limit, bytearray(), size
            while left:
                chunk = take(min(left, 1 << 20))
                left -= len(chunk)
                h.update(chunk)
                if keep:
                    buf += chunk
            padding(-size % BLOCK)
            e.size, e.sha256 = size, h.hexdigest()
            if keep:
                small[name] = bytes(buf)
        entries.append(e)
    # The end: nothing but zeros after it (no archive hidden behind the marker), and the second zero block.
    tail = 0
    while True:
        chunk = stream.read(1 << 20)
        if not chunk:
            break
        used += len(chunk)
        if used > MAX_DECOMPRESSED or chunk.strip(b"\0"):
            raise BundleError("the tar archive has data after its end marker")
        tail += len(chunk)
    if tail < BLOCK:
        raise BundleError("the tar archive has no end marker")
    return entries, small


def read_archive(path):
    """(entries, {path: bytes} for the small files)."""
    try:
        with open(path, "rb") as f:
            magic = f.read(4)
    except OSError as exc:
        raise BundleError(f"cannot read {printable(path)}: {exc.strerror}") from None
    if magic != b"\x28\xb5\x2f\xfd":
        # `zstd -d` also unpacks gzip, xz and lz4 when built with them: a bundle is zstd.
        raise BundleError("the archive is not zstd-compressed")
    try:
        z = subprocess.Popen(["zstd", "-dc", "-qq", "--memory=128MiB", "--", path], stdout=subprocess.PIPE)
    except FileNotFoundError:
        raise BundleError("zstd is not installed") from None
    ok = False
    try:
        entries, small = scan_tar(z.stdout, want_small=True)
        ok = True
    finally:
        if not ok:
            z.kill()
        z.stdout.close()
        rc = z.wait()
    if rc != 0:
        raise BundleError(f"zstd could not decompress the archive ({rc})")
    return entries, small


def _dup_keys(pairs):
    d = {}
    for k, v in pairs:
        if k in d:
            raise ValueError(f"the key {k!r} is given twice")
        d[k] = v
    return d


def _refuse_constant(name):
    raise ValueError(f"{name} is not JSON a manifest may hold")


def _refuse_float(text):
    raise ValueError(f"the number {text} has a fraction or an exponent: a manifest holds whole numbers only")


def _whole(text):
    if len(text) > 20:       # the Store reads u64: at most 20 digits
        raise ValueError("a number longer than 20 digits")
    return int(text)


def load_json_ordered(data, what):
    """Strict JSON, as serde_json reads it and more: UTF-8 without a byte order mark, at most
    MAX_MANIFEST bytes, no duplicate keys, no NaN or Infinity, no fractions or exponents, whole
    numbers of at most 20 digits, no lone surrogates. Key order is kept (dicts keep insertion order)."""
    if len(data) > MAX_MANIFEST:
        raise BundleError(f"{what} is larger than {MAX_MANIFEST // 1024} KiB")
    if data.startswith(b"\xef\xbb\xbf"):
        raise BundleError(f"{what} starts with a byte order mark")
    try:
        text = data.decode("utf-8")
        obj = json.loads(text, object_pairs_hook=_dup_keys, parse_constant=_refuse_constant,
                         parse_float=_refuse_float, parse_int=_whole)
        dump(obj).encode("utf-8")   # a lone surrogate (\ud800) parses, and cannot be written
    except (ValueError, RecursionError) as exc:       # UnicodeError is a ValueError
        raise BundleError(f"{what} is not valid JSON: {exc}") from None
    return obj


def _is_int(v):
    return type(v) is int          # not a bool, not a float


def _text_problem(k, v, limit):
    if not isinstance(v, str) or (not v and k != "homepage"):
        return f"{k} must be a non-empty string"
    if k in ("name", "summary", "license") and store_clean(v, limit) != v:
        return (f"{k} {v!r} is not what the Store shows of it (it drops control and invisible characters, collapses "
                f"white space and cuts at {limit} characters): write it that way")
    return None


def check_manifest_shape(m, with_archive):
    """The manifest's keys, types and values: the Store's `Manifest::check` (native/manifest.rs)
    and more (exact keys in one order, sorted lists). Returns a list of problems."""
    errs = []
    want = KEY_ORDER + (["archive"] if with_archive else [])
    if list(m.keys()) != want:
        errs.append(f"manifest keys are {list(m.keys())}, expected exactly {want} in that order")
        return errs
    if not _is_int(m["schema"]) or m["schema"] != SCHEMA:
        errs.append(f"schema is {m['schema']!r}, this tool reads {SCHEMA}")
    limits = {"name": MAX_NAME, "summary": MAX_SUMMARY, "license": MAX_LICENSE}
    for k in ("id", "name", "version", "summary", "homepage", "license", "arch", "min_telamon_ui", "min_os_version"):
        bad = _text_problem(k, m[k], limits.get(k, 0))
        if bad:
            errs.append(bad)
    if errs:
        return errs
    if not valid_app_id(m["id"]):
        errs.append(f"id {m['id']!r} is not reverse-DNS with three parts or more")
    if not valid_version(m["version"]):
        errs.append(f"version {m['version']!r} is not up to 6 numbers (at most 9 digits, no leading zero) with an optional -prerelease, 64 characters at most")
    if m["arch"] != ARCH:
        errs.append(f"arch is {m['arch']!r}, expected {ARCH}")
    if not valid_min_ui(m["min_telamon_ui"]):
        errs.append(f"min_telamon_ui {m['min_telamon_ui']!r} is not a dotted number")
    if not OSVER_RE.fullmatch(m["min_os_version"]):
        errs.append(f"min_os_version {m['min_os_version']!r} is not a number")
    if m["homepage"] and https_url(m["homepage"]) != m["homepage"]:
        errs.append("homepage must be a plain https address as the Store normalises it (no port, lowercase public host)")
    if not isinstance(m["files"], list) or not isinstance(m["links"], list):
        errs.append("files and links must be arrays")
        return errs
    if not m["files"]:
        errs.append("files is empty: a bundle holds at least its program")
    if len(m["files"]) > MAX_FILES or len(m["links"]) > MAX_FILES:
        errs.append(f"{len(m['files'])} files and {len(m['links'])} links: at most {MAX_FILES} of each")
        return errs
    for f in m["files"]:
        if not isinstance(f, dict) or list(f.keys()) != FILE_KEYS:
            errs.append(f"a files entry must have exactly {FILE_KEYS}: {f!r}")
        elif (not isinstance(f["path"], str) or not _is_int(f["size"]) or not 0 <= f["size"] <= MAX_FILE
              or not isinstance(f["sha256"], str) or not SHA_RE.fullmatch(f["sha256"]) or not isinstance(f["executable"], bool)):
            errs.append(f"a files entry has a wrong type, size or hash: {f!r}")
    for ln in m["links"]:
        if not isinstance(ln, dict) or list(ln.keys()) != LINK_KEYS or not all(isinstance(v, str) for v in ln.values()):
            errs.append(f"a links entry must have exactly {LINK_KEYS}: {ln!r}")
    if errs:
        return errs
    for f in m["files"]:
        bad = path_problem(f["path"]) or (f"{MANIFEST} lists itself" if f["path"] == MANIFEST else None)
        if bad:
            errs.append(f"{f['path']!r}: {bad}")
    for ln in m["links"]:
        bad = path_problem(ln["path"]) or (None if link_target_ok(ln["path"], ln["target"]) else "a link target that leaves the tree")
        if bad:
            errs.append(f"{ln['path']!r}: {bad}")
    if sum(f["size"] for f in m["files"]) > MAX_TOTAL:
        errs.append(f"files add up to more than {MAX_TOTAL} bytes (1 GiB unpacked)")
    if errs:
        return errs
    for key in ("files", "links"):
        paths = [x["path"] for x in m[key]]
        if paths != sorted(paths) or len(set(paths)) != len(paths):
            errs.append(f"{key} must be sorted by path, with no duplicates")
    both = [x["path"] for x in m["files"]] + [x["path"] for x in m["links"]]
    if len(set(both)) != len(both):
        errs.append("a path is both a file and a link")
    if with_archive:
        ar = m["archive"]
        if not isinstance(ar, dict) or list(ar.keys()) != ARCHIVE_KEYS:
            errs.append(f"archive must have exactly {ARCHIVE_KEYS}")
        elif (not isinstance(ar["name"], str) or not isinstance(ar["sha256"], str) or not SHA_RE.fullmatch(ar["sha256"])
              or not _is_int(ar["size"]) or not 0 < ar["size"] <= MAX_ARCHIVE):
            errs.append(f"archive has a wrong type, hash or size (1 to {MAX_ARCHIVE} bytes)")
        elif ar["name"] != f"{m['id']}-{m['version']}-{m['arch']}.tar.zst":
            errs.append(f"archive.name {ar['name']!r} is not <id>-<version>-<arch>.tar.zst")
    return errs


def parse_manifest(data, what, with_archive):
    """Bytes of a manifest to its dict, or a BundleError naming every problem."""
    obj = load_json_ordered(data, what)
    if not isinstance(obj, dict):
        raise BundleError(f"{what} is not a JSON object")
    errs = check_manifest_shape(obj, with_archive)
    if errs:
        raise BundleError(errs)
    if data != dump(obj).encode("utf-8"):
        raise BundleError(f"{what} is not in the canonical form (2-space indent, trailing newline)")
    return obj


def verify(archive_path, manifest_path, epoch=None):
    errs = []
    try:
        with open(manifest_path, "rb") as f:
            outer_raw = f.read(MAX_MANIFEST + 1)
    except OSError as exc:
        raise BundleError(f"cannot read {manifest_path}: {exc}") from None
    outer = parse_manifest(outer_raw, str(manifest_path), with_archive=True)

    ar = outer["archive"]
    if not os.path.isfile(archive_path):
        raise BundleError(f"cannot read {archive_path}")
    if os.path.basename(archive_path) != ar["name"]:
        errs.append(f"the archive file is {os.path.basename(archive_path)}, the manifest names {ar['name']}")
    if not 0 < os.path.getsize(archive_path) <= MAX_ARCHIVE:
        raise BundleError(errs + [f"the archive is {os.path.getsize(archive_path)} bytes: at most {MAX_ARCHIVE} (256 MiB)"])
    if os.path.getsize(archive_path) != ar["size"]:
        errs.append(f"archive size {os.path.getsize(archive_path)}, the manifest says {ar['size']}")
    if sha256_file(archive_path) != ar["sha256"]:
        errs.append("archive sha256 differs from the manifest's archive.sha256")

    entries, small = read_archive(archive_path)
    try:
        by_path = validate(entries, archive=True)
    except BundleError as exc:
        raise BundleError(errs + exc.problems) from None
    if epoch is not None and entries and entries[0].mtime != epoch:
        errs.append(f"modification time {entries[0].mtime}, expected SOURCE_DATE_EPOCH {epoch}")

    inner_raw = small.get(MANIFEST)
    if inner_raw is None:
        errs.append(f"{MANIFEST} is not in the archive")
    else:
        inner = load_json_ordered(inner_raw, f"{MANIFEST} in the archive")
        expect = {k: v for k, v in outer.items() if k != "archive"}
        if inner != expect or inner_raw != dump(expect).encode("utf-8"):
            errs.append("the manifest inside the archive is not the outer manifest without `archive`")

    listed = {f["path"]: f for f in outer["files"]}
    actual = {p: e for p, e in by_path.items() if e.kind == "file" and p != MANIFEST}
    for p in sorted(set(listed) - set(actual)):
        errs.append(f"{p}: in the manifest, not in the archive")
    for p in sorted(set(actual) - set(listed)):
        errs.append(f"{p}: in the archive, not in the manifest")
    for p in sorted(set(listed) & set(actual)):
        f, e = listed[p], actual[p]
        if f["sha256"] != e.sha256:
            errs.append(f"{p}: sha256 differs from the manifest")
        if f["size"] != e.size:
            errs.append(f"{p}: size {e.size}, the manifest says {f['size']}")
        if f["executable"] != bool(e.mode & 0o111):
            errs.append(f"{p}: executable bit differs from the manifest")
    links = {x["path"]: x["target"] for x in outer["links"]}
    real_links = {p: e.target for p, e in by_path.items() if e.kind == "link"}
    if links != real_links:
        errs.append("links in the manifest and in the archive differ")

    try:
        app_id, mi = check_semantics(by_path, lambda p: small[p] if p in small else b"")
    except BundleError as exc:
        errs.extend(exc.problems)
    else:
        if app_id != outer["id"]:
            errs.append(f"the manifest id is {outer['id']}, the .desktop file is {app_id}.desktop")
        for key in ("name", "summary", "license", "homepage"):
            if mi.get(key) and mi[key] != outer[key]:
                errs.append(f"{key}: the manifest says {outer[key]!r}, the metainfo {mi[key]!r}")
    if errs:
        raise BundleError(errs)
    return outer


# ---------------------------------------------------------------------------- CLI

def main(argv):
    ap = argparse.ArgumentParser(prog="bundle.py", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    v = sub.add_parser("version", help="print the bundle version, checked against CMake's project VERSION")
    v.add_argument("--app-dir", required=True)
    v.add_argument("--version")

    p = sub.add_parser("pack", help="make the archive and both manifests from an installed tree")
    p.add_argument("--tree", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--epoch", type=int, required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--spec")
    for opt in ("name", "summary", "homepage", "license", "min-telamon-ui", "min-os-version"):
        p.add_argument(f"--{opt}")

    c = sub.add_parser("verify", help="check an archive against its manifest and the layout rules")
    c.add_argument("archive")
    c.add_argument("manifest")

    a = ap.parse_args(argv)
    try:
        if a.cmd == "version":
            print(resolve_version(a.app_dir, a.version))
        elif a.cmd == "pack":
            cmd_pack(a)
        else:
            m = verify(a.archive, a.manifest)
            print(f"ok: {m['id']} {m['version']}, {len(m['files'])} files, {len(m['links'])} links")
    except BundleError as exc:
        for line in exc.problems:
            print(f"bundle: {printable(line)}", file=sys.stderr)
        return 1
    except OSError as exc:      # an unreadable file, a full disk: a message, not a traceback
        print(f"bundle: {printable(str(exc))}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
