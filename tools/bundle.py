#!/usr/bin/env python3
"""Telamon native app bundles: make one from an installed tree, and verify one.

    bundle.py version --app-dir DIR [--version V]
    bundle.py pack    --tree DIR --out DIR --epoch N --version V [options]
    bundle.py verify  ARCHIVE MANIFEST

tools/make-bundle.sh builds and installs an app, then calls `pack`. The format
is described in docs/BUNDLES.md; this file is its reference implementation
(the Store reads the same rules). Standard library only, plus the `zstd` program.
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

ID_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
VERSION_RE = re.compile(r"[0-9]+(\.[0-9]+)+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?")
OSVER_RE = re.compile(r"[0-9]+")
SHA_RE = re.compile(r"[0-9a-f]{64}")

MAX_ENTRIES = 50000
MAX_TOTAL = 2 * 1024 ** 3
SMALL = 1024 * 1024  # files read whole: desktop, service, metainfo, manifest


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
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


# ---------------------------------------------------------------- path rules

def path_problem(p):
    """Why a tree path is not allowed, or None."""
    if p == "" or p.startswith("/"):
        return "empty or absolute path"
    if "\\" in p:
        return "backslash in path"
    for c in p.split("/"):
        if c in ("", ".", ".."):
            return "path has an empty, '.' or '..' component (no './' prefix, no '..')"
        if len(c.encode("utf-8", "surrogateescape")) > 255:
            return "path component longer than 255 bytes"
        if any(ord(ch) < 32 or ord(ch) == 127 for ch in c):
            return "control character in path"
        try:
            c.encode("utf-8")
        except UnicodeEncodeError:
            return "path is not valid UTF-8"
    return None


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
    parts = _walk(by_path, posixpath.dirname(path).split("/") if "/" in path else [], target, 0)
    return "/".join(parts) if parts else None


def _walk(by_path, start, rel, depth):
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
            if depth >= 16 or e.target == "" or e.target.startswith("/") or "\\" in e.target:
                return None
            parts = _walk(by_path, parts[:-1], e.target, depth + 1)
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
        errs.append(f"{total} bytes of files: more than {MAX_TOTAL}")

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
            if archive and e.mode & 0o7777 not in (0o755, 0o644):
                errs.append(f"{e.path}: mode {e.mode & 0o7777:04o}, expected 0755 or 0644")
            if e.path.startswith("bin/") and not e.mode & 0o111:
                errs.append(f"{e.path}: in bin/ but not executable")
            if e.path.startswith("bin/") and e.path.count("/") > 1:
                errs.append(f"{e.path}: bin/ holds no subdirectories")
        elif e.kind == "link":
            dest = resolve_link(e.path, e.target, by_path)
            if dest is None:
                errs.append(f"{e.path}: symlink to {e.target!r}, which is not a relative path inside the tree")
            elif dest not in by_path and not any(x.startswith(dest + "/") for x in by_path):
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

def parse_ini_group(text, group):
    """Keys of one [group] of a .desktop or D-Bus .service file."""
    cur, out = None, {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            cur = line[1:-1]
            continue
        if cur == group and "=" in line:
            k, v = line.split("=", 1)
            out.setdefault(k.strip(), v.strip())
    return out


def exec_values(text):
    """Every Exec= of a .desktop file, the [Desktop Action ...] groups' too: [(group, value)].
    The key is trimmed, as GLib's key-file parser does."""
    cur, out = None, []
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("[") and line.endswith("]"):
            cur = line[1:-1]
        elif cur is not None and "=" in line and not line.startswith("#"):
            key, value = line.split("=", 1)
            if key.strip() == "Exec":
                out.append((cur, value.strip()))
    return out


def exec_name(value):
    """The bare binary name an Exec= line starts with, or raise ValueError."""
    try:
        words = shlex.split(value)
    except ValueError as exc:
        raise ValueError(f"Exec={value!r} cannot be split: {exc}") from None
    if not words:
        raise ValueError("Exec= is empty")
    first = words[0]
    if "/" in first:
        raise ValueError(f"Exec starts with {first!r}: use the bare binary name (the Store fills in the path)")
    return first


def resolves_to_executable(by_path, path):
    """`path` is, or links (inside the tree) to, a regular file with an execute bit."""
    seen = 0
    while path in by_path and seen < 8:
        e = by_path[path]
        if e.kind == "file":
            return bool(e.mode & 0o111)
        if e.kind != "link":
            return False
        path = resolve_link(e.path, e.target, by_path)
        seen += 1
    return False


def check_semantics(by_path, read):
    """The .desktop, metainfo and D-Bus service rules. `read(path)` returns bytes.
    Returns (app id, metainfo dict)."""
    errs = []
    desktops = sorted(p for p, e in by_path.items() if e.kind in ("file", "link") and p.endswith(".desktop"))
    if len(desktops) != 1:
        raise BundleError([f"exactly one .desktop file is required, found {len(desktops)}: {', '.join(desktops) or 'none'}"
                           + " (leave a legacy one out with --exclude)"])
    dpath = desktops[0]
    app_id = posixpath.basename(dpath)[: -len(".desktop")]
    if dpath != f"share/applications/{app_id}.desktop":
        errs.append(f"{dpath}: must be share/applications/<app id>.desktop")
    if not ID_RE.fullmatch(app_id) or "." not in app_id:
        errs.append(f"{dpath}: the app id {app_id!r} must be reverse-DNS: letters, digits, '.', '_' and '-', with a dot")

    if by_path[dpath].kind != "file":
        errs.append(f"{dpath}: must be a regular file")
    else:
        values = exec_values(read(dpath).decode("utf-8", "replace"))
        groups = [g for g, _ in values]
        if "Desktop Entry" not in groups:
            errs.append(f"{dpath}: no Exec= in [Desktop Entry]")
        for g in sorted({g for g in groups if groups.count(g) > 1}):
            errs.append(f"{dpath} [{g}]: Exec= twice")
        for group, value in values:
            try:
                name = exec_name(value)
            except ValueError as exc:
                errs.append(f"{dpath} [{group}]: {exc}")
            else:
                if not resolves_to_executable(by_path, f"bin/{name}"):
                    errs.append(f"{dpath} [{group}]: Exec={name!r}, but bin/{name} is not an executable file in the bundle")

    services = sorted(p for p in by_path if p.startswith("share/dbus-1/services/") and p.endswith(".service")
                      and by_path[p].kind == "file")
    for sp in services:
        values = exec_values(read(sp).decode("utf-8", "replace"))
        if len(values) != 1 or values[0][0] != "D-BUS Service":
            errs.append(f"{sp}: exactly one Exec= in [D-BUS Service] is required")
            continue
        try:
            name = exec_name(values[0][1])
        except ValueError as exc:
            errs.append(f"{sp}: {exc}")
        else:
            if not resolves_to_executable(by_path, f"bin/{name}"):
                errs.append(f"{sp}: Exec={name!r}, but bin/{name} is not an executable file in the bundle")

    meta = {}
    mpath = f"share/metainfo/{app_id}.metainfo.xml"
    others = [p for p in by_path if p.startswith("share/metainfo/") and by_path[p].kind == "file" and p != mpath]
    if others:
        errs.append(f"{others[0]}: the metainfo file must be named <app id>.metainfo.xml ({mpath})")
    if mpath in by_path and by_path[mpath].kind == "file":
        try:
            meta = parse_metainfo(read(mpath), app_id)
        except BundleError as exc:
            errs.extend(f"{mpath}: {m}" for m in exc.problems)
    if errs:
        raise BundleError(errs)
    return app_id, meta


XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"


def parse_metainfo(data, app_id):
    # No entity or DOCTYPE tricks: a metainfo file has neither.
    if b"<!DOCTYPE" in data or b"<!ENTITY" in data or b"\x00" in data or not data.lstrip(b"\xef\xbb\xbf \t\r\n").startswith(b"<"):
        raise BundleError("must be UTF-8 XML without a DOCTYPE or ENTITY declaration")
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
        text = open(path, encoding="utf-8").read()
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
        if not VERSION_RE.fullmatch(wanted):
            raise BundleError(f"version {wanted!r}: dotted numbers with an optional -prerelease (0.2.0, 1.0.0-beta.1)")
        core = wanted.split("-", 1)[0]
        if cm is not None and core != cm:
            raise BundleError(f"version {wanted} does not match project(... VERSION {cm}) in {app_dir}/CMakeLists.txt: "
                              "set the CMake version to the release's before tagging")
        return wanted
    if cm is None:
        raise BundleError(f"no project(... VERSION x.y.z) in {app_dir}/CMakeLists.txt: pass --version")
    if not VERSION_RE.fullmatch(cm):
        raise BundleError(f"project VERSION {cm} needs at least major.minor")
    return cm


def vkey(v):
    return [int(x) for x in v.split(".")]


def spec_min_ui(spec):
    found = {"BuildRequires": [], "Requires": []}
    try:
        lines = open(spec, encoding="utf-8").read().splitlines()
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
    for line in open(spec, encoding="utf-8"):
        m = re.match(rf"^{field}:\s*(\S.*?)\s*$", line)
        if m and "%{" not in m.group(1):
            return m.group(1)
    return ""


# ------------------------------------------------------------------- tree / pack

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
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
                mode = 0o755 if st.st_mode & 0o111 else 0o644
                entries.append(Entry(r, "file", mode, size=st.st_size, sha256=sha256_file(p)))
            else:
                raise BundleError(f"{r}: not a directory, file or symlink")

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


def cmd_pack(a):
    tree = os.path.abspath(a.tree)
    out = os.path.abspath(a.out)
    entries = scan_tree(tree)
    if not entries:
        raise BundleError("the install produced no files")
    by_path = validate(entries, archive=False)
    app_id, mi = check_semantics(by_path, lambda p: open(os.path.join(tree, p), "rb").read(SMALL + 1))

    desktop = parse_ini_group(open(os.path.join(tree, f"share/applications/{app_id}.desktop"),
                                   encoding="utf-8", errors="replace").read(), "Desktop Entry")
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
    for key, rx, what in (("id", ID_RE, "id"), ("version", VERSION_RE, "version"), ("min_os_version", OSVER_RE, "os version")):
        if not rx.fullmatch(meta[key]):
            raise BundleError(f"{what} {meta[key]!r} is not valid")
    if not re.fullmatch(r"[0-9]+(\.[0-9]+)*", meta["min_telamon_ui"]):
        raise BundleError(f"min_telamon_ui {meta['min_telamon_ui']!r} is not a dotted number")

    inner = build_manifest(meta, entries)
    inner_bytes = dump(inner).encode("utf-8")
    entries.append(Entry(MANIFEST, "file", 0o644, size=len(inner_bytes)))
    name = f"{meta['id']}-{meta['version']}-{ARCH}.tar.zst"
    os.makedirs(out, exist_ok=True)
    archive_path = os.path.join(out, name)
    manifest_path = os.path.join(out, MANIFEST)
    tmp = archive_path + ".part"

    try:
        with open(tmp, "wb") as outf:
            z = subprocess.Popen(["zstd", "-19", "-T1", "-q", "-c"], stdin=subprocess.PIPE, stdout=outf)
            try:
                with tarfile.open(fileobj=z.stdin, mode="w|", format=tarfile.PAX_FORMAT) as tf:
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
                            with open(os.path.join(tree, e.path), "rb") as f:
                                tf.addfile(ti, f)
            finally:
                z.stdin.close()
                rc = z.wait()
            if rc != 0:
                raise BundleError(f"zstd failed ({rc})")
        os.replace(tmp, archive_path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

    outer = dict(inner)
    outer["archive"] = {"name": name, "sha256": sha256_file(archive_path), "size": os.path.getsize(archive_path)}
    with open(manifest_path, "w", encoding="utf-8") as f:
        f.write(dump(outer))
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

def read_archive(path):
    """(entries, {path: bytes} for the small files)."""
    try:
        z = subprocess.Popen(["zstd", "-dc", "-q", "--", path], stdout=subprocess.PIPE)
    except FileNotFoundError:
        raise BundleError("zstd is not installed") from None
    entries, small, total = [], {}, 0
    try:
        with tarfile.open(fileobj=z.stdout, mode="r|") as tf:
            for ti in tf:
                name = ti.name
                if ti.isdir():
                    e = Entry(name, "dir", ti.mode)
                elif ti.issym():
                    e = Entry(name, "link", ti.mode, target=ti.linkname)
                elif ti.isreg():
                    if total + ti.size > MAX_TOTAL:
                        raise BundleError("the archive is larger than the limits (entries or bytes)")
                    h = hashlib.sha256()
                    keep = ti.size <= SMALL and (name == MANIFEST or name.endswith((".desktop", ".service", ".metainfo.xml")))
                    buf = bytearray()
                    f = tf.extractfile(ti)
                    for chunk in iter(lambda: f.read(1 << 20), b""):
                        h.update(chunk)
                        if keep:
                            buf += chunk
                    e = Entry(name, "file", ti.mode, size=ti.size, sha256=h.hexdigest())
                    if keep:
                        small[name] = bytes(buf)
                else:
                    raise BundleError(f"{name}: a {tarfile_type(ti)}: only directories, files and symlinks are allowed")
                e.uid, e.gid, e.mtime = ti.uid, ti.gid, int(ti.mtime)
                entries.append(e)
                total += e.size
                if total > MAX_TOTAL or len(entries) > MAX_ENTRIES:
                    raise BundleError("the archive is larger than the limits (entries or bytes)")
        z.stdout.read()
    except tarfile.TarError as exc:
        raise BundleError(f"not a readable tar archive: {exc}") from None
    finally:
        z.stdout.close()
        rc = z.wait()
    if rc != 0:
        raise BundleError(f"zstd could not decompress the archive ({rc})")
    return entries, small


def tarfile_type(ti):
    if ti.islnk():
        return "hard link"
    if ti.isdev():
        return "device or fifo"
    return "special entry"


def load_json_ordered(data, what):
    try:
        return json.loads(data, object_pairs_hook=lambda pairs: dict(pairs))
    except (ValueError, UnicodeDecodeError) as exc:
        raise BundleError(f"{what} is not valid JSON: {exc}") from None


def check_manifest_shape(m, with_archive):
    errs = []
    want = KEY_ORDER + (["archive"] if with_archive else [])
    if list(m.keys()) != want:
        errs.append(f"manifest keys are {list(m.keys())}, expected exactly {want} in that order")
        return errs
    if m["schema"] != SCHEMA or isinstance(m["schema"], bool):
        errs.append(f"schema is {m['schema']!r}, this tool reads {SCHEMA}")
    for k in ("id", "name", "version", "summary", "homepage", "license", "arch", "min_telamon_ui", "min_os_version"):
        if not isinstance(m[k], str) or not m[k]:
            errs.append(f"{k} must be a non-empty string")
    if errs:
        return errs
    if not ID_RE.fullmatch(m["id"]) or "." not in m["id"]:
        errs.append(f"id {m['id']!r} is not reverse-DNS")
    if not VERSION_RE.fullmatch(m["version"]):
        errs.append(f"version {m['version']!r} is not dotted numbers with an optional -prerelease")
    if m["arch"] != ARCH:
        errs.append(f"arch is {m['arch']!r}, expected {ARCH}")
    if not re.fullmatch(r"[0-9]+(\.[0-9]+)*", m["min_telamon_ui"]):
        errs.append(f"min_telamon_ui {m['min_telamon_ui']!r} is not a dotted number")
    if not OSVER_RE.fullmatch(m["min_os_version"]):
        errs.append(f"min_os_version {m['min_os_version']!r} is not a number")
    if not m["homepage"].startswith("https://"):
        errs.append("homepage must be an https:// URL")
    if not isinstance(m["files"], list) or not isinstance(m["links"], list):
        errs.append("files and links must be arrays")
        return errs
    for f in m["files"]:
        if not isinstance(f, dict) or list(f.keys()) != FILE_KEYS:
            errs.append(f"a files entry must have exactly {FILE_KEYS}: {f!r}")
        elif (not isinstance(f["path"], str) or not isinstance(f["size"], int) or isinstance(f["size"], bool)
              or not isinstance(f["sha256"], str) or not SHA_RE.fullmatch(f["sha256"]) or not isinstance(f["executable"], bool)):
            errs.append(f"a files entry has a wrong type or hash: {f!r}")
    for ln in m["links"]:
        if not isinstance(ln, dict) or list(ln.keys()) != LINK_KEYS or not all(isinstance(v, str) for v in ln.values()):
            errs.append(f"a links entry must have exactly {LINK_KEYS}: {ln!r}")
    if errs:
        return errs
    for key in ("files", "links"):
        paths = [x["path"] for x in m[key]]
        if paths != sorted(paths) or len(set(paths)) != len(paths):
            errs.append(f"{key} must be sorted by path, with no duplicates")
    if with_archive:
        ar = m["archive"]
        if not isinstance(ar, dict) or list(ar.keys()) != ARCHIVE_KEYS:
            errs.append(f"archive must have exactly {ARCHIVE_KEYS}")
        elif (not isinstance(ar["name"], str) or not isinstance(ar["sha256"], str) or not SHA_RE.fullmatch(ar["sha256"])
              or not isinstance(ar["size"], int) or isinstance(ar["size"], bool)):
            errs.append("archive has a wrong type or hash")
        elif ar["name"] != f"{m['id']}-{m['version']}-{m['arch']}.tar.zst":
            errs.append(f"archive.name {ar['name']!r} is not <id>-<version>-<arch>.tar.zst")
    return errs


def verify(archive_path, manifest_path, epoch=None):
    errs = []
    try:
        outer_raw = open(manifest_path, "rb").read()
    except OSError as exc:
        raise BundleError(f"cannot read {manifest_path}: {exc}") from None
    outer = load_json_ordered(outer_raw, manifest_path)
    if not isinstance(outer, dict):
        raise BundleError("the manifest is not a JSON object")
    shape = check_manifest_shape(outer, with_archive=True)
    if shape:
        raise BundleError(shape)
    if outer_raw != dump(outer).encode("utf-8"):
        errs.append("the manifest is not in the canonical form (2-space indent, trailing newline)")

    ar = outer["archive"]
    if not os.path.isfile(archive_path):
        raise BundleError(f"cannot read {archive_path}")
    if os.path.basename(archive_path) != ar["name"]:
        errs.append(f"the archive file is {os.path.basename(archive_path)}, the manifest names {ar['name']}")
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
            print(f"bundle: {line}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
