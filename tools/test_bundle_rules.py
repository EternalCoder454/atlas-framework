#!/usr/bin/env python3
"""Tests of tools/bundle.py's archive, path and manifest rules, and a seedable fuzzer for them.

    python3 -I tools/test_bundle_rules.py [--cases N] [--seed S] [-v]

`--cases` is how many random inputs each fuzz test makes (default 2000; CI runs 20000, about
half a minute); `--seed` fixes them (default: a new one each run, printed so a failure can be
replayed). Standard library only. Needs the `zstd` program for the few tests that run a whole
archive through `verify`.

What is checked:

* The Store's rules are written out again here as a reference (`store_*`, each with the file and
  function of telamon-store-core that it follows) and the tool must accept only what the Store
  accepts, and nothing that the Store would read differently: an accepted path is the very
  string the Store's unpacker sees, a manifest the tool accepts parses to the same thing there.
* The tar reader takes one canonical form of tar and refuses everything else with a BundleError,
  never a traceback; and when it accepts, Python's own `tarfile` reads the same entries.
* Every validator, on any input, either accepts or says why not (BundleError): it never raises
  anything else.
"""

import argparse
import hashlib
import io
import json
import os
import posixpath
import random
import re
import subprocess
import sys
import tarfile
import tempfile
import unicodedata
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bundle as b  # noqa: E402

CASES = 2000
SEED = None


# ------------------------------------------------------------ the Store's rules, as a reference
# Each follows the code named, in telamon-store-core (crates/telamon-store-core/src). They are written out
# again on purpose: a change to the tool that loosens a rule must fail here.

def store_hidden(c):
    """launch.rs `hidden`."""
    o = ord(c)
    return (unicodedata.category(c) == "Cc" or o in (0xAD, 0x34F, 0x61C, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x200B, 0x200E, 0x200F,
                                                     0x3164, 0xFEFF, 0xFFA0)
            or 0x180B <= o <= 0x180F or 0x2028 <= o <= 0x202E or 0x2060 <= o <= 0x206F or 0xFE00 <= o <= 0xFE0F
            or 0xFFF9 <= o <= 0xFFFB or 0x1BCA0 <= o <= 0x1BCA3 or 0x1D173 <= o <= 0x1D17A
            or 0xE0000 <= o <= 0xE007F or 0xE0100 <= o <= 0xE01EF)


def store_valid_rel_path(p):
    """native/manifest.rs `valid_rel_path`."""
    return (p != "" and len(p.encode("utf-8")) <= 1024 and not p.startswith("/")
            and all(n != "" and n not in (".", "..") and len(n.encode("utf-8")) <= 255 and not any(store_hidden(c) for c in n)
                    for n in p.split("/")))


def store_entry_path(raw, is_dir):
    """native/archive.rs `entry_path`: the member name as the unpacker uses it, or None (refused). The root
    entry "./" gives ""."""
    try:
        s = raw.decode("utf-8")
    except UnicodeDecodeError:
        return None
    s = s[2:] if s.startswith("./") else s
    s = s[:-1] if is_dir and s.endswith("/") else s
    if s == "" or s == ".":
        return "" if is_dir else None
    return s if store_valid_rel_path(s) else None


def store_link_target_ok(path, target):
    """native/manifest.rs `link_target_ok`."""
    if target == "" or len(target.encode("utf-8")) > 1024 or target.startswith("/") or any(store_hidden(c) for c in target):
        return False
    depth = len(path.split("/")) - 1
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


def store_valid_app_id(i):
    """native/mod.rs `valid_app_id` (bytes: Rust's `len` and `bytes`)."""
    raw = i.encode("utf-8")
    parts = i.split(".")
    return (len(raw) <= 128 and len(parts) >= 3 and all(p != "" and not p.startswith("-") for p in parts)
            and all(c < 128 and (chr(c).isalnum() or chr(c) in "._-") for c in raw))


def store_number(s):
    if s == "" or len(s) > 9 or not all(c in "0123456789" for c in s) or (len(s) > 1 and s[0] == "0"):
        return None
    return int(s)


def store_version_ok(s):
    """native/version.rs `Version::parse` (does it parse)."""
    if s == "" or len(s.encode("utf-8")) > 64:
        return False
    core, _, pre = s.partition("-")
    has_pre = "-" in s
    nums = [store_number(p) for p in core.split(".")]
    if None in nums or len(nums) > 6:
        return False
    if has_pre:
        for part in pre.split("."):
            if part == "" or not all(c in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-" for c in part):
                return False
    return True


def store_manifest_accepts(raw, outer):
    """serde_json into `Manifest` and then `Manifest::check` (native/manifest.rs): would the Store take these
    bytes as a manifest. Unknown keys are ignored there; a missing `links` or `executable` is empty / false.
    A model of what matters, not a copy of serde: wrong types, duplicate keys of known fields and numbers
    that do not fit refuse."""
    if len(raw) > b.MAX_MANIFEST:
        return False
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return False
    known = {"schema", "id", "name", "version", "summary", "homepage", "license", "arch", "min_telamon_ui",
             "min_os_version", "files", "links", "archive", "path", "size", "sha256", "executable", "target"}

    def pairs(ps):
        d = {}
        for k, v in ps:
            if k in d and k in known:
                raise ValueError("duplicate field")
            d[k] = v
        return d

    def nofloat(s):
        raise ValueError("float")

    try:
        m = json.loads(text, object_pairs_hook=pairs, parse_float=nofloat, parse_constant=lambda n: (_ for _ in ()).throw(ValueError(n)))
    except (ValueError, RecursionError):
        return False

    def u(v, bits):
        return type(v) is int and 0 <= v < 1 << bits

    def s_(v):
        return isinstance(v, str)

    try:
        if not isinstance(m, dict):
            return False
        for k in ("id", "name", "version", "summary", "homepage", "license", "arch", "min_telamon_ui", "min_os_version"):
            if not s_(m[k]):
                return False
        if not u(m["schema"], 32) or not isinstance(m["files"], list):
            return False
        files = m["files"]
        for f in files:
            if not isinstance(f, dict) or not s_(f["path"]) or not u(f["size"], 64) or not s_(f["sha256"]):
                return False
            if "executable" in f and not isinstance(f["executable"], bool):
                return False
        links = m.get("links", [])
        if not isinstance(links, list):
            return False
        for ln in links:
            if not isinstance(ln, dict) or not s_(ln["path"]) or not s_(ln["target"]):
                return False
        ar = m.get("archive")
        if ar is not None and (not isinstance(ar, dict) or not s_(ar["name"]) or not s_(ar["sha256"]) or not u(ar["size"], 64)):
            return False
    except (KeyError, TypeError):
        return False
    # check()
    if m["schema"] != 1 or not store_valid_app_id(m["id"]):
        return False
    if store_clean_ref(m["name"], 80) == "":
        return False
    if not store_version_ok(m["version"]) or m["arch"] != "x86_64":
        return False
    if m["homepage"] and b.https_url(m["homepage"]) != m["homepage"]:       # launch.rs `https_url`, ported in the tool
        return False
    if not store_version_ok(m["min_telamon_ui"]):
        return False
    mo = m["min_os_version"]
    if mo == "" or len(mo) > 4 or not all(c in "0123456789" for c in mo):
        return False
    if not files or len(files) > b.MAX_FILES or len(links) > b.MAX_FILES:
        return False
    seen, total = set(), 0
    for f in files:
        if not store_valid_rel_path(f["path"]) or f["path"] == b.MANIFEST:
            return False
        if len(f["sha256"]) != 64 or not all(c in "0123456789abcdef" for c in f["sha256"]) or f["size"] > b.MAX_FILE:
            return False
        total += f["size"]
        if f["path"] in seen:
            return False
        seen.add(f["path"])
    if total > b.MAX_TOTAL:
        return False
    for ln in links:
        if not store_valid_rel_path(ln["path"]) or ln["path"] in seen or not store_link_target_ok(ln["path"], ln["target"]):
            return False
        seen.add(ln["path"])
    if outer:
        if ar is None or ar["name"] != f"{m['id']}-{m['version']}-x86_64.tar.zst":
            return False
        if len(ar["sha256"]) != 64 or not all(c in "0123456789abcdef" for c in ar["sha256"]) or ar["size"] == 0 or ar["size"] > b.MAX_ARCHIVE:
            return False
    elif ar is not None:
        return False
    return True


def store_clean_ref(s, max_chars):
    """text.rs `clean`, written once more, differently (a state machine over a list)."""
    spaces = set("\t\n\x0b\x0c\r \x85\xa0     　") | {chr(c) for c in range(0x2000, 0x200B)}
    out = []
    chars = 0
    pending = False
    for c in s:
        o = ord(c)
        if c in spaces:
            pending = chars > 0
            continue
        invisible = (o in (0xAD, 0x34F, 0x61C, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x3164, 0xFEFF, 0xFFA0, 0x200B)
                     or 0x180B <= o <= 0x180F or 0x202A <= o <= 0x202E or 0x2060 <= o <= 0x206F or 0xFE00 <= o <= 0xFE0F
                     or 0xFFF9 <= o <= 0xFFFC or 0x1BCA0 <= o <= 0x1BCA3 or 0x1D173 <= o <= 0x1D17A
                     or 0xE0000 <= o <= 0xE007F or 0xE0100 <= o <= 0xE01EF)
        if unicodedata.category(c) == "Cc" or invisible or 0xFDD0 <= o <= 0xFDEF or (o & 0xFFFE) == 0xFFFE:
            continue
        extra = int(pending) + 1
        if chars + extra > max_chars:
            break
        if pending:
            out.append(" ")
            pending = False
        out.append(c)
        chars += extra
    return "".join(out)


# --------------------------------------------------------------------------- tar construction

def _num(v, width):
    return (b"%0*o" % (width - 1, v)) + b"\0"


def header(name=b"", mode=0o644, uid=0, gid=0, size=0, mtime=0, flag=b"0", link=b"", magic=b"ustar\0", version=b"00",
           uname=b"", gname=b"", prefix=b"", devmajor=b"", devminor=b"", size_field=None, mode_field=None, chksum=None):
    h = bytearray(512)
    h[0:len(name)] = name
    h[100:108] = mode_field or _num(mode, 8)
    h[108:116] = _num(uid, 8)
    h[116:124] = _num(gid, 8)
    h[124:136] = size_field or _num(size, 12)
    h[136:148] = _num(mtime, 12)
    h[148:156] = b" " * 8
    h[156:157] = flag
    h[157:157 + len(link)] = link
    h[257:263] = magic
    h[263:265] = version
    h[265:265 + len(uname)] = uname
    h[297:297 + len(gname)] = gname
    h[329:329 + len(devmajor)] = devmajor
    h[337:337 + len(devminor)] = devminor
    h[345:345 + len(prefix)] = prefix
    h[148:156] = chksum if chksum is not None else (b"%06o" % sum(h)) + b"\0 "
    return bytes(h)


def pad(data):
    return data + b"\0" * (-len(data) % 512)


def pax(**records):
    body = b""
    for k, v in records.items():
        rest = k.encode() + b"=" + v.encode() + b"\n"
        n = len(rest) + 1
        while len(b"%d " % n) + len(rest) != n:
            n = len(b"%d " % n) + len(rest)
        body += b"%d " % n + rest
    return header(b"PaxHeader/x", flag=b"x", size=len(body)) + pad(body)


def file_entry(name, data=b"x", **kw):
    return header(name.encode(), size=len(data), **kw) + pad(data)


def dir_entry(name, **kw):
    kw.setdefault("mode", 0o755)
    return header(name.encode(), flag=b"5", **kw)


def link_entry(name, target, **kw):
    kw.setdefault("mode", 0o777)
    return header(name.encode(), flag=b"2", link=target.encode(), **kw)


END = b"\0" * 1024
GOOD = (dir_entry("bin") + file_entry("bin/app", b"#!/bin/sh\n", mode=0o755) + dir_entry("share") + link_entry("bin/a", "app")
        + END)


def scan(raw, small=False):
    return b.scan_tar(io.BytesIO(raw), small)


class Refuses(unittest.TestCase):
    def refuses(self, raw, rx=""):
        with self.assertRaisesRegex(b.BundleError, rx):
            scan(raw)


# ------------------------------------------------------------------------ the tar reader

class TarReader(Refuses):
    def test_a_canonical_tar_is_read(self):
        entries, _ = scan(GOOD)
        self.assertEqual([(e.path, e.kind) for e in entries], [("bin", "dir"), ("bin/app", "file"), ("share", "dir"), ("bin/a", "link")])
        self.assertEqual(entries[1].sha256, hashlib.sha256(b"#!/bin/sh\n").hexdigest())
        self.assertEqual(entries[3].target, "app")

    def test_the_end_of_the_archive(self):
        self.refuses(GOOD[:-1024], "no end marker|ends in the middle")
        self.refuses(GOOD[:-1024] + b"\0" * 512, "no end marker")
        self.refuses(GOOD + b"x", "data after its end")
        self.refuses(GOOD + header(b"late", size=0), "data after its end")
        scan(GOOD + b"\0" * 10240)       # the padding to a full record is zeros

    def test_only_directories_files_and_symlinks(self):
        for flag, rx in ((b"1", "hard link"), (b"3", "device or fifo"), (b"4", "device or fifo"), (b"6", "device or fifo"),
                         (b"7", "contiguous"), (b"g", "global pax"), (b"S", "sparse"), (b"L", "GNU long name"),
                         (b"K", "GNU long link"), (b"\0", "old-style"), (b"Z", "special entry")):
            self.refuses(header(b"bin/x", flag=flag, link=b"bin/app") + END, rx)

    def test_one_format_only(self):
        self.refuses(header(b"bin/x", magic=b"ustar ", version=b" \0") + END, "POSIX ustar")        # GNU tar
        self.refuses(header(b"bin/x", magic=b"\0" * 6, version=b"\0\0") + END, "POSIX ustar")        # V7
        self.refuses(header(b"bin/x", chksum=b"0000000\0") + END, "checksum")
        self.refuses(header(b"bin/x", size_field=b"\x80\0\0\0\0\0\0\0\0\0\0\x05") + b"x" * 512 + END, "octal")   # base-256
        self.refuses(header(b"bin/x", size_field=b"-000001\0\0\0\0\0") + END, "octal")
        self.refuses(header(b"bin/x", size_field=b"0000000009\0 ") + END, "octal")
        self.refuses(header(b"bin/x", mode_field=b"0x1ed\0\0\0") + END, "octal")
        self.refuses(header(b"bin/x", uname=b"root") + END, "owner names")
        self.refuses(header(b"bin/x", gname=b"root") + END, "owner names")
        self.refuses(header(b"x", prefix=b"bin") + END, "prefix")
        self.refuses(header(b"bin/x", devmajor=b"0000001\0") + END, "device numbers")
        self.refuses(header(b"bin/x\0y") + END, "after its end")

    def test_pax_headers_carry_a_path_and_a_link_path_and_nothing_else(self):
        entries, _ = scan(pax(path="share/" + "n" * 200) + file_entry("trunc") + END)
        self.assertEqual(entries[0].path, "share/" + "n" * 200)
        entries, _ = scan(pax(linkpath="l" * 200) + link_entry("bin/l", "x") + END)
        self.assertEqual(entries[0].target, "l" * 200)
        for rec in ({"size": "5"}, {"uid": "1000"}, {"mtime": "1.5"}, {"gid": "0"}, {"comment": "x"}, {"hdrcharset": "BINARY"},
                    {"GNU.sparse.name": "x"}, {"SCHILY.xattr.user.a": "b"}, {"path": "a", "mtime": "1"}):
            self.refuses(pax(**rec) + file_entry("a") + END, "pax header")
        self.refuses(pax(path="a") + pax(path="b") + file_entry("c") + END, "pax header")           # two in a row
        self.refuses(pax(path="a") + END, "")                                                          # none follows
        body = b"9 path=a\n9 path=b\n"
        self.refuses(header(b"p", flag=b"x", size=len(body)) + pad(body) + file_entry("c") + END, "one `path`")
        for body in (b"path=a\n", b"99 path=a\n", b"12 path=a\n", b"x path=a\n", b"9 path=a", b"\xff\xff\xff\xff"):
            self.refuses(header(b"p", flag=b"x", size=len(body)) + pad(body) + file_entry("c") + END, "pax header")
        self.refuses(header(b"p", flag=b"x", size=b.MAX_PAX + 1) + END, "pax header")
        self.refuses(header(b"p", flag=b"x", size=0) + END, "pax header")
        body = b"\xff"
        self.refuses(header(b"p", flag=b"x", size=0) + END, "pax header")
        rec = b"11 path=\xff\xfe\n"
        self.refuses(header(b"p", flag=b"x", size=len(rec)) + pad(rec) + file_entry("c") + END, "UTF-8")

    def test_padding_is_zeros(self):
        self.refuses(header(b"bin/x", size=3) + b"abc" + b"\0" * 508 + b"\x01" + END[1:] + b"\0", "padding")
        body = b"136 path=" + b"n" * 126 + b"\n"
        self.refuses(header(b"p", flag=b"x", size=len(body)) + body + b"\x08" + b"\0" * (511 - len(body)) + file_entry("c") + END, "padding")

    def test_names_must_be_text(self):
        self.refuses(header(b"a\xffb", size=0) + END, "UTF-8")
        self.refuses(header(b"a\xc3", size=0) + END, "UTF-8")                 # a cut-off character
        self.refuses(header(b"a\xc0\xafb", size=0) + END, "UTF-8")            # an overlong "/"
        self.refuses(header(b"a\xed\xa0\x80b", size=0) + END, "UTF-8")        # a surrogate

    def test_sizes_and_counts(self):
        self.refuses(header(b"bin/big", size=b.MAX_FILE + 1) + END, "512 MiB")
        self.refuses(header(b"bin/x", size=100) + b"x" * 50, "ends in the middle")
        self.refuses(header(b"d", flag=b"5", size=3) + pad(b"abc") + END, "directory with data")
        self.refuses(header(b"d", flag=b"2", size=3, link=b"x") + pad(b"abc") + END, "link with data")

    def test_the_limits_of_the_store(self):
        old = b.MAX_ENTRIES
        try:
            b.MAX_ENTRIES = 3
            scan(dir_entry("a") + dir_entry("b") + dir_entry("c") + END)
            self.refuses(dir_entry("a") + dir_entry("b") + dir_entry("c") + dir_entry("d") + END, "limits")
        finally:
            b.MAX_ENTRIES = old
        old = b.MAX_DECOMPRESSED
        try:
            b.MAX_DECOMPRESSED = 4096
            self.refuses(file_entry("bin/x", b"z" * 8000) + END, "limits")
            self.refuses(dir_entry("a") + END + b"\0" * 10000, "limits|after its end")
        finally:
            b.MAX_DECOMPRESSED = old

    def test_this_is_what_pack_writes(self):
        """The reader reads exactly the form `pack` (Python's tarfile, PAX_FORMAT) writes."""
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w|", format=tarfile.PAX_FORMAT, encoding="utf-8", errors="strict") as tf:
            for name, typ, link, data in (("bin", tarfile.DIRTYPE, "", b""), ("bin/" + "long" * 40, tarfile.REGTYPE, "", b"x" * 700),
                                          ("share", tarfile.DIRTYPE, "", b""), ("share/é中.txt", tarfile.REGTYPE, "", b""),
                                          ("share/l", tarfile.SYMTYPE, "../" * 3 + "x" * 150, b"")):
                ti = tarfile.TarInfo(name)
                ti.type, ti.linkname, ti.size, ti.mode, ti.mtime = typ, link, len(data), 0o755 if typ == tarfile.DIRTYPE else 0o644, 1767225600
                tf.addfile(ti, io.BytesIO(data) if typ == tarfile.REGTYPE else None)
        entries, _ = scan(buf.getvalue())
        self.assertEqual([e.path for e in entries], ["bin", "bin/" + "long" * 40, "share", "share/é中.txt", "share/l"])
        self.assertEqual({e.mtime for e in entries}, {1767225600})
        self.assertEqual(entries[4].target, "../" * 3 + "x" * 150)


# ---------------------------------------------------------------------------- whole archives

def write(path, data):
    with open(path, "wb") as f:
        f.write(data)


def zstd(data):
    return subprocess.run(["zstd", "-19", "-q", "-c"], input=data, capture_output=True, check=True).stdout


class WholeArchive(unittest.TestCase):
    """verify() on an archive made by hand: every defect named in the Store's reader is a refusal."""

    DESKTOP = b"[Desktop Entry]\nType=Application\nName=Fake\nExec=fake-app\n"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="telamon-test-rules.")
        self.addCleanup(self.tmp.cleanup)

    def members(self, extra=b"", skip=()):
        app = b"#!/bin/sh\n"
        parts = [("bin", dir_entry("bin", mtime=7)), ("bin/fake-app", file_entry("bin/fake-app", app, mode=0o755, mtime=7)),
                 ("share", dir_entry("share", mtime=7)), ("share/applications", dir_entry("share/applications", mtime=7)),
                 ("share/applications/net.example.fake.desktop", file_entry("share/applications/net.example.fake.desktop", self.DESKTOP, mtime=7))]
        return [p for n, p in parts if n not in skip], app

    def manifest(self, entries_data, archive):
        files = [{"path": n, "size": len(d), "sha256": hashlib.sha256(d).hexdigest(), "executable": ex} for n, d, ex in entries_data]
        inner = {"schema": 1, "id": "net.example.fake", "name": "Fake", "version": "1.2.3", "summary": "A fake", "homepage": "https://example.net/fake",
                 "license": "MIT", "arch": "x86_64", "min_telamon_ui": "2.0.2", "min_os_version": "44", "files": files, "links": []}
        return inner

    def build(self, extra=b""):
        parts, app = self.members()
        data = [("bin/fake-app", app, True), ("share/applications/net.example.fake.desktop", self.DESKTOP, False)]
        inner = self.manifest(data, None)
        man = json.dumps(inner, indent=2, ensure_ascii=False).encode() + b"\n"
        tarb = b"".join(parts) + file_entry("telamon-bundle.json", man, mtime=7) + extra
        # sorted: bin, bin/fake-app, share, share/applications, share/applications/..., telamon-bundle.json
        return tarb + END, inner

    def run_verify(self, tarb, inner):
        z = zstd(tarb)
        name = "net.example.fake-1.2.3-x86_64.tar.zst"
        outer = dict(inner)
        outer["archive"] = {"name": name, "sha256": hashlib.sha256(z).hexdigest(), "size": len(z)}
        ap, mp = os.path.join(self.tmp.name, name), os.path.join(self.tmp.name, "telamon-bundle.json")
        write(ap, z)
        write(mp, b.dump(outer).encode())
        return b.verify(ap, mp, epoch=7)

    def test_the_hand_made_archive_is_good(self):
        tarb, inner = self.build()
        self.assertEqual(self.run_verify(tarb, inner)["id"], "net.example.fake")

    def test_a_second_archive_after_the_end_marker_is_refused(self):
        tarb, inner = self.build()
        with self.assertRaisesRegex(b.BundleError, "after its end"):
            self.run_verify(tarb + file_entry("bin/evil", b"x", mode=0o755, mtime=7) + END, inner)

    def test_a_decompression_bomb_stops_at_the_cap(self):
        tarb, inner = self.build()
        old = b.MAX_DECOMPRESSED
        try:
            b.MAX_DECOMPRESSED = 50000
            with self.assertRaisesRegex(b.BundleError, "limits"):
                self.run_verify(tarb[:-1024] + file_entry("share/zeros", b"\0" * 400000, mtime=7) + END, inner)
        finally:
            b.MAX_DECOMPRESSED = old

    def test_a_zstd_stream_that_is_not_a_tar_or_is_cut_off(self):
        tarb, inner = self.build()
        z = zstd(tarb)
        for bad in (z[:len(z) // 2], b"\x28\xb5\x2f\xfd" + b"\xff" * 20, b"\x50\x2a\x4d\x18\x00\x00\x00\x00", b"junk"):
            name = "net.example.fake-1.2.3-x86_64.tar.zst"
            outer = dict(inner)
            outer["archive"] = {"name": name, "sha256": hashlib.sha256(bad).hexdigest(), "size": len(bad)}
            ap, mp = os.path.join(self.tmp.name, name), os.path.join(self.tmp.name, "telamon-bundle.json")
            write(ap, bad)
            write(mp, b.dump(outer).encode())
            with self.assertRaises(b.BundleError):
                b.verify(ap, mp)

    def test_special_modes_and_owners_are_refused_not_stripped(self):
        for kw, rx in (({"mode": 0o4755}, "expected 0755 or 0644"), ({"mode": 0o2755}, "expected 0755 or 0644"),
                       ({"mode": 0o1755}, "expected 0755 or 0644"), ({"mode": 0o666}, "expected 0755 or 0644"),
                       ({"mode": 0o777}, "expected 0755 or 0644"), ({"mode": 0o755, "uid": 1000}, "expected 0:0"),
                       ({"mode": 0o755, "gid": 5}, "expected 0:0")):
            tarb, inner = self.build()
            tarb = tarb.replace(file_entry("bin/fake-app", b"#!/bin/sh\n", mode=0o755, mtime=7), file_entry("bin/fake-app", b"#!/bin/sh\n", mtime=7, **kw))
            with self.assertRaisesRegex(b.BundleError, rx):
                self.run_verify(tarb, inner)


# ------------------------------------------------------------------------------- manifests

def good_manifest(with_archive=True):
    m = {"schema": 1, "id": "net.example.fake", "name": "Fake", "version": "1.2.3", "summary": "A fake app", "homepage": "https://example.net/fake",
         "license": "MIT", "arch": "x86_64", "min_telamon_ui": "2.0.2", "min_os_version": "44",
         "files": [{"path": "bin/fake-app", "size": 10, "sha256": "a" * 64, "executable": True}],
         "links": [{"path": "bin/l", "target": "fake-app"}]}
    if with_archive:
        m["archive"] = {"name": "net.example.fake-1.2.3-x86_64.tar.zst", "sha256": "b" * 64, "size": 1000}
    return m


def man(m):
    return b.dump(m).encode()


class Manifests(unittest.TestCase):
    def ok(self, raw, outer=True):
        return b.parse_manifest(raw, "m", outer)

    def refuses(self, raw, rx="", outer=True):
        with self.assertRaisesRegex(b.BundleError, rx):
            self.ok(raw, outer)

    def test_a_good_manifest(self):
        self.assertEqual(self.ok(man(good_manifest()))["id"], "net.example.fake")
        self.assertTrue(store_manifest_accepts(man(good_manifest()), True))
        self.assertTrue(store_manifest_accepts(man(good_manifest(False)), False))
        self.ok(man(good_manifest(False)), outer=False)

    def test_the_json_itself(self):
        good = man(good_manifest())
        self.refuses(b"\xef\xbb\xbf" + good, "byte order mark")
        self.refuses(good.decode().encode("utf-16"), "")
        self.refuses(good.decode().encode("utf-16-le"), "")
        self.refuses(good.replace(b"Fake", b"Fa\xffke", 1), "")
        self.refuses(good.replace(b'"schema": 1', b'"schema": 1,\n  "schema": 1', 1), "twice")
        self.refuses(good.replace(b'"name": "Fake"', b'"name": "Fake",\n  "name": "Other"', 1), "twice")
        self.refuses(good.replace(b'"schema": 1', b'"schema": 1.0'), "fraction")
        self.refuses(good.replace(b'"schema": 1', b'"schema": 1e0'), "fraction")
        self.refuses(good.replace(b'"schema": 1', b'"schema": NaN'), "NaN")
        self.refuses(good.replace(b'"size": 10', b'"size": Infinity'), "Infinity")
        self.refuses(good.replace(b'"size": 10', b'"size": -Infinity'), "Infinity")
        self.refuses(good.replace(b'"size": 10', b'"size": ' + b"9" * 400), "")
        self.refuses(good.replace(b'"size": 10', b'"size": 99999999999999999999'), "")
        self.refuses(good.replace(b'"size": 10', b'"size": -1'), "")
        self.refuses(good.replace(b'"size": 10', b'"size": 18446744073709551615'), "")
        self.refuses(good.replace(b'"size": 10', b'"size": true'), "")
        self.refuses(good.replace(b'"Fake"', b'"\\ud800"'), "")
        self.refuses(good.replace(b'"Fake"', b'"\\udc00\\ud800"'), "")
        self.refuses(good + b"x", "")
        self.refuses(good + b"\n", "canonical")
        self.refuses(good.replace(b"  ", b"\t", 1), "")
        self.refuses(b"[" * 100000, "")
        self.refuses(b'{"a":' * 100000, "")
        self.refuses(b"x" * (b.MAX_MANIFEST + 1), "larger than")
        self.refuses(b"", "")
        self.refuses(b"null", "not a JSON object")
        self.refuses(b"[]", "not a JSON object")
        self.refuses(good.replace(b"1.2.3", b"1.2.3\\u0000", 1), "")

    def test_keys_and_types(self):
        for edit, rx in (
            (lambda m: m.pop("links"), "keys"),
            (lambda m: m.update(extra=1), "keys"),
            (lambda m: m.update(schema=2), "schema"),
            (lambda m: m.update(schema=True), "schema"),
            (lambda m: m.update(schema="1"), "schema"),
            (lambda m: m.update(id=5), "id"),
            (lambda m: m.update(id="a.b"), "id"),
            (lambda m: m.update(id="a.b.c/d"), "id"),
            (lambda m: m.update(name=""), "name"),
            (lambda m: m.update(name="‮"), "name"),
            (lambda m: m.update(name="A  B"), "name"),
            (lambda m: m.update(name=" A"), "name"),
            (lambda m: m.update(name="A\n"), "name"),
            (lambda m: m.update(name="x" * 81), "name"),
            (lambda m: m.update(summary="x" * 301), "summary"),
            (lambda m: m.update(license="x" * 101), "license"),
            (lambda m: m.update(license="MIT​"), "license"),
            (lambda m: m.update(version="v1.2.3"), "version"),
            (lambda m: m.update(version="1"), "version"),
            (lambda m: m.update(version="1.2.3\n"), "version"),
            (lambda m: m.update(arch="aarch64"), "arch"),
            (lambda m: m.update(homepage="http://example.net/"), "homepage"),
            (lambda m: m.update(homepage="https://Example.net/"), "homepage"),
            (lambda m: m.update(min_telamon_ui="2.0.2-beta"), "min_telamon_ui"),
            (lambda m: m.update(min_telamon_ui=""), "min_telamon_ui"),
            (lambda m: m.update(min_os_version="44.1"), "min_os_version"),
            (lambda m: m.update(min_os_version="12345"), "min_os_version"),
            (lambda m: m.update(files=[]), "files is empty"),
            (lambda m: m.update(files={}), "arrays"),
            (lambda m: m["files"][0].update(size=1.5), "fraction|wrong type"),
            (lambda m: m["files"][0].update(size=b.MAX_FILE + 1), "wrong type, size"),
            (lambda m: m["files"][0].update(size=-1), "wrong type, size"),
            (lambda m: m["files"][0].update(size=True), "wrong type, size"),
            (lambda m: m["files"][0].update(sha256="A" * 64), "wrong type, size or hash"),
            (lambda m: m["files"][0].update(sha256="a" * 63), "wrong type, size or hash"),
            (lambda m: m["files"][0].update(executable=1), "wrong type, size or hash"),
            (lambda m: m["files"][0].update(path="../x"), "component"),
            (lambda m: m["files"][0].update(path="/etc/passwd"), "absolute"),
            (lambda m: m["files"][0].update(path="a\\b"), "backslash"),
            (lambda m: m["files"][0].update(path="a/​"), "hidden"),
            (lambda m: m["files"][0].update(path="telamon-bundle.json"), "lists itself"),
            (lambda m: m["files"][0].update(path="a" * 2000), "longer"),
            (lambda m: m["files"].append(dict(m["files"][0])), "no duplicates"),
            (lambda m: m["links"][0].update(path="bin/fake-app"), "both a file and a link"),
            (lambda m: m["links"][0].update(target="/etc/passwd"), "leaves the tree"),
            (lambda m: m["links"][0].update(target="../../x"), "leaves the tree"),
            (lambda m: m["links"][0].update(target="a//b"), "leaves the tree"),
            (lambda m: m["links"][0].update(target=""), "leaves the tree"),
            (lambda m: m["links"][0].update(target="a​b"), "leaves the tree"),
            (lambda m: m["archive"].update(size=0), "archive has a wrong"),
            (lambda m: m["archive"].update(size=b.MAX_ARCHIVE + 1), "archive has a wrong"),
            (lambda m: m["archive"].update(sha256="x" * 64), "archive has a wrong"),
            (lambda m: m["archive"].update(name="other.tar.zst"), "archive.name"),
            (lambda m: m["archive"].update(extra=1), "archive must have"),
            (lambda m: m["files"][0].update(extra=1), "exactly"),
        ):
            m = good_manifest()
            edit(m)
            raw = man(m)
            self.refuses(raw, rx)

    def test_total_size_and_counts(self):
        m = good_manifest()
        m["files"] = [{"path": f"bin/f{i}", "size": b.MAX_FILE, "sha256": "a" * 64, "executable": False} for i in range(3)]
        self.refuses(man(m), "1 GiB")
        m = good_manifest()
        m["files"] = [{"path": f"bin/f{i:05d}", "size": 0, "sha256": "a" * 64, "executable": False} for i in range(b.MAX_FILES + 1)]
        self.refuses(man(m), "at most|larger than")       # the 1 MiB cap on the manifest comes first

    def test_the_inner_manifest_has_no_archive(self):
        self.refuses(man(good_manifest(True)), "keys", outer=False)
        self.refuses(man(good_manifest(False)), "keys", outer=True)


# ------------------------------------------------------------------------------- units

class Units(unittest.TestCase):
    def test_hidden_covers_the_stores_hidden(self):
        """Every code point the Store hides, the tool refuses in a name too (and more of them)."""
        for o in range(0x110000):
            c = chr(o)
            if 0xD800 <= o <= 0xDFFF:
                continue
            if store_hidden(c):
                self.assertTrue(b.hidden(c), hex(o))

    def test_store_clean_agrees_with_its_second_writing(self):
        rnd = random.Random(7)
        pool = list("ab \t\n  ​‮\u0007　﻿\U0001f600￾\u0085\x1f") + ["é", "é"]
        for _ in range(3000):
            s = "".join(rnd.choice(pool) for _ in range(rnd.randrange(0, 40)))
            for cap in (0, 1, 2, 5, 80):
                self.assertEqual(b.store_clean(s, cap), store_clean_ref(s, cap), (s, cap))

    def test_path_rules_match_the_stores_on_known_names(self):
        for p, want in (("bin/app", True), ("a", True), ("", False), ("/a", False), ("a/", False), ("a//b", False), ("./a", False), ("a/./b", False),
                        ("a/../b", False), ("..", False), ("a\\b", False), ("a\0b", False), ("a\nb", False), ("a​b", False), ("a‮b", False),
                        ("x" * 255, True), ("x" * 256, False), ("a/" + "x" * 255, True), ("é" * 128, False), ("é" * 127, True),
                        ("/".join(["ab"] * 340), True), ("/".join(["ab"] * 342), False), ("a b", True), ("a\tb", False)):
            self.assertEqual(b.path_problem(p) is None, want, repr(p[:40]))
        self.assertTrue(store_valid_rel_path("a\\b"))          # the Store allows a backslash; the tool does not
        self.assertFalse(store_valid_rel_path("a\0b"))

    def test_ids_versions(self):
        for s in ("net.example.fake", "a.b.c", "a.b.c-d_e", "a.b", "a..b.c", ".a.b.c", "a.-b.c", "a.b.c d", "a.b.é", "a." + "b" * 130 + ".c"):
            if b.valid_app_id(s):
                self.assertTrue(store_valid_app_id(s), s)
        for s in ("1.0", "1.0.0", "1.0.0-beta.1", "1", "01.0", "1.0.0-", "1.0.0-a..b", "1.0.0-a_b", "v1", "1.2.3.4.5.6.7", "1." + "0" * 10):
            if b.valid_version(s):
                self.assertTrue(store_version_ok(s), s)

    def test_resolve_and_link_rules_agree_with_the_store(self):
        for path, target in (("bin/l", "app"), ("share/a/b/l", "../../x"), ("l", "x"), ("bin/l", "../.."), ("bin/l", "a/../b"), ("a/b/c", "../../../x")):
            if b.link_target_ok(path, target):
                self.assertTrue(store_link_target_ok(path, target), (path, target))
            else:
                self.assertFalse(store_link_target_ok(path, target) and "\\" not in target, (path, target))


# ----------------------------------------------------------------------------------- fuzzing

PIECES = ["a", "b", "bin", "share", "x.y", "..", ".", "", "//", "/", "\\", "\0", "\n", "\t", " ", "-", "~", "é", "é", "Å", "Å",
          "Å", "​", "‮", " ", "﻿", "\u0085", "ㅤ", "\U000e0001", "\U0001f600", "中", "ı", "I", "i", "ſ", "K", "K",
          "x" * 100, "y" * 254, "z" * 256, "\ud800", "\udfff", "\x7f", "\x1b[31m", "%2e", "%00", "..\\", "bin/", "./", "../", "C:", "con"]


def gen_path(rnd):
    n = rnd.choice((1, 1, 2, 3, 4, 6, 12))
    parts = []
    for _ in range(n):
        if rnd.random() < 0.55:
            parts.append(rnd.choice(("a", "b", "bin", "share", "x.y", "net.example.fake")))
        else:
            parts.append(rnd.choice(PIECES))
    sep = "/" if rnd.random() < 0.9 else rnd.choice(("//", "\\", "/./", "/../"))
    p = sep.join(parts)
    r = rnd.random()
    if r < 0.05:
        p = "/" + p
    elif r < 0.1:
        p += "/"
    elif r < 0.13:
        p = "./" + p
    elif r < 0.15:
        p = p * rnd.choice((8, 40, 300))
    return p


def normalize_forms(p):
    return [p, unicodedata.normalize("NFC", p), unicodedata.normalize("NFD", p), unicodedata.normalize("NFKC", p)]


class Fuzz(unittest.TestCase):
    def rnd(self, label):
        seed = SEED if SEED is not None else random.SystemRandom().randrange(1 << 32)
        self.addCleanup(lambda: None)
        self.seed = seed
        return random.Random(f"{label}:{seed}")

    def test_paths(self):
        rnd = self.rnd("paths")
        accepted = 0
        for _ in range(CASES):
            for p in normalize_forms(gen_path(rnd)):
                try:
                    bad = b.path_problem(p)
                except Exception as exc:                  # a traceback: never
                    self.fail(f"seed {self.seed}: path_problem({p!r}) raised {exc!r}")
                if bad is None:
                    accepted += 1
                    # accepted: relative, plain, normalised, inside the tree
                    self.assertFalse(p.startswith("/") or p == "" or "\0" in p or "\\" in p, (self.seed, p))
                    self.assertEqual(posixpath.normpath(p), p, (self.seed, p))
                    self.assertNotIn("..", p.split("/"), (self.seed, p))
                    # the Store reads the very same string back (as a file, and as a directory)
                    self.assertTrue(store_valid_rel_path(p), (self.seed, p))
                    self.assertEqual(store_entry_path(p.encode("utf-8"), False), p, (self.seed, p))
                    self.assertEqual(store_entry_path(p.encode("utf-8"), True), p, (self.seed, p))
                    self.assertEqual(len(p.encode("utf-8")), len(p.encode("utf-8")))
                    self.assertLessEqual(len(p.encode("utf-8")), b.MAX_PATH)
                    self.assertTrue(all(len(c.encode("utf-8")) <= 255 for c in p.split("/")))
                else:
                    # refused: if the Store takes it, the tool refuses it for a reason the Store does not check
                    try:
                        store_ok = store_valid_rel_path(p)
                    except UnicodeEncodeError:
                        store_ok = False                   # a lone surrogate is not text in Rust
                    if store_ok:
                        extra = "\\" in p or any(b.hidden(c) and not store_hidden(c) for c in p) or "\0" in p
                        self.assertTrue(extra, (self.seed, p, bad))
        self.assertGreater(accepted, CASES // 20)           # the generator does produce good names

    def test_tar_names_both_ways(self):
        """What the Store's unpacker makes of a member name, against what the tool takes."""
        rnd = self.rnd("tarnames")
        for _ in range(CASES):
            p = gen_path(rnd)
            try:
                raw = p.encode("utf-8")
            except UnicodeEncodeError:
                continue
            for is_dir in (False, True):
                name = store_entry_path(raw, is_dir)
                if b.path_problem(p) is None:
                    self.assertEqual(name, p, (self.seed, p))

    def test_link_targets(self):
        rnd = self.rnd("links")
        for _ in range(CASES):
            path, target = gen_path(rnd), gen_path(rnd)
            if rnd.random() < 0.5:
                target = "/".join(rnd.choice(("..", "a", "b", "x.y", "")) for _ in range(rnd.randrange(1, 6)))
            try:
                ok = b.link_target_ok(path, target)
                dest = b.resolve_link(path, target, {}) if ok else None
            except Exception as exc:
                self.fail(f"seed {self.seed}: link_target_ok({path!r}, {target!r}) raised {exc!r}")
            if ok and b.path_problem(path) is None:
                self.assertTrue(store_link_target_ok(path, target), (self.seed, path, target))
                if dest is not None:
                    self.assertFalse(dest.startswith("/") or {"", ".", ".."} & set(dest.split("/")), (self.seed, path, target, dest))

    def mutate_manifest(self, rnd, m):
        m = json.loads(json.dumps(m))
        r = rnd.random()
        spots = [m]
        stack = [m]
        while stack:
            x = stack.pop()
            for v in (x.values() if isinstance(x, dict) else x):
                if isinstance(v, (dict, list)):
                    spots.append(v)
                    stack.append(v)
        for _ in range(rnd.choice((1, 1, 2, 3))):
            t = rnd.choice(spots)
            if isinstance(t, dict) and t:
                k = rnd.choice(list(t))
                op = rnd.randrange(9)
                if op == 0:
                    del t[k]
                elif op == 1:
                    t[k] = rnd.choice((None, True, False, 0, -1, 1, 2, 1.5, 2 ** 64, 2 ** 63, 10 ** 30, "", "x", [], {}, [1], "‮", "a" * 5000))
                elif op == 2:
                    t["extra" + str(rnd.randrange(3))] = rnd.choice((1, "x", [], {}))
                elif op == 3 and isinstance(t[k], str):
                    s = t[k]
                    t[k] = s[:rnd.randrange(len(s) + 1)] + rnd.choice(PIECES) + s[rnd.randrange(len(s) + 1):]
                elif op == 4:
                    items = list(t.items())
                    rnd.shuffle(items)
                    t.clear()
                    t.update(items)
                elif op == 5 and isinstance(t[k], int) and not isinstance(t[k], bool):
                    t[k] = t[k] + rnd.choice((-1, 1, 2 ** 32, -2 ** 31))
                elif op == 6:
                    t[k] = gen_path(rnd)
                elif op == 7 and isinstance(t[k], list):
                    t[k] = t[k] + t[k]
                else:
                    t[k] = rnd.choice(("1.0.0", "x86_64", "44", "net.a.b", "https://example.net/", "a" * 64, "0" * 64))
            elif isinstance(t, list) and t:
                op = rnd.randrange(3)
                if op == 0:
                    t.append(json.loads(json.dumps(rnd.choice(t))))
                elif op == 1:
                    t.pop(rnd.randrange(len(t)))
                else:
                    rnd.shuffle(t)
        return m

    def bytes_mutation(self, rnd, raw):
        raw = bytearray(raw)
        for _ in range(rnd.choice((0, 0, 1, 2, 5))):
            if not raw:
                break
            op = rnd.randrange(8)
            i = rnd.randrange(len(raw))
            if op == 0:
                raw[i] = rnd.randrange(256)
            elif op == 1:
                del raw[i:i + rnd.randrange(1, 20)]
            elif op == 2:
                raw[i:i] = rnd.choice((b"\xef\xbb\xbf", b"\0", b"\xff", b'\\ud800', b"NaN", b"1e5", b"\xed\xa0\x80", b'"', b",", b"{", b"\n", b"\t"))
            elif op == 3:
                raw[i:i] = raw[max(0, i - 40):i]
            elif op == 4:
                del raw[i:]
            elif op == 5:
                raw[i:i] = b'"' + bytes(rnd.choice(b"abc") for _ in range(3)) + b'": 1, '
            elif op == 6:
                raw = bytearray(raw.replace(b'"', b"'", 1))
            else:
                raw = bytearray(b"\xef\xbb\xbf" + bytes(raw))
        return bytes(raw)

    def test_manifests(self):
        rnd = self.rnd("manifests")
        taken = 0
        for n in range(CASES):
            outer = rnd.random() < 0.7
            base = good_manifest(outer)
            m = self.mutate_manifest(rnd, base) if rnd.random() < 0.9 else base
            try:
                raw = json.dumps(m, indent=2, ensure_ascii=rnd.random() < 0.3).encode("utf-8", "surrogatepass") + b"\n"
            except (ValueError, TypeError):
                continue
            if rnd.random() < 0.5:
                try:
                    raw = b.dump(m).encode("utf-8", "surrogatepass")
                except (ValueError, TypeError):
                    continue
            raw = self.bytes_mutation(rnd, raw)
            try:
                got = b.parse_manifest(raw, "m", outer)
            except b.BundleError:
                got = None
            except Exception as exc:
                self.fail(f"seed {self.seed}: parse_manifest raised {exc!r} on {raw[:300]!r}")
            if got is not None:
                taken += 1
                self.assertTrue(store_manifest_accepts(raw, outer), (self.seed, raw[:400]))
                self.assertEqual(raw, b.dump(got).encode("utf-8"))
                self.assertEqual(list(got), b.KEY_ORDER + (["archive"] if outer else []))
                self.assertEqual(got["name"], store_clean_ref(got["name"], 80))
        self.assertGreater(taken, CASES // 50)

    def test_manifest_bytes_never_crash_the_json_loader(self):
        rnd = self.rnd("json")
        alphabet = [b"{", b"}", b"[", b"]", b'"', b":", b",", b"1", b"-", b"0", b"e", b".", b"null", b"true", b"NaN", b"\\u", b"\\ud800", b" ", b"\n",
                    b"\xef\xbb\xbf", b"\xff", b"\0", b"a", b"\xc3\xa9", b"9" * 30, b'"schema"', b'"files"']
        for _ in range(CASES):
            raw = b"".join(rnd.choice(alphabet) for _ in range(rnd.randrange(0, 30)))
            for outer in (True, False):
                try:
                    b.parse_manifest(raw, "m", outer)
                except b.BundleError:
                    pass
                except Exception as exc:
                    self.fail(f"seed {self.seed}: parse_manifest raised {exc!r} on {raw!r}")

    def test_tar_bytes(self):
        """A valid tar with bytes flipped, cut, inserted: the reader says BundleError or reads it, and what it
        reads, Python's tarfile reads as the same entries."""
        rnd = self.rnd("tar")
        seeds = [GOOD, pax(path="share/" + "n" * 120) + file_entry("trunc", b"abc") + dir_entry("share/d") + END,
                 pax(linkpath="t" * 130) + link_entry("bin/l", "x") + file_entry("bin/é", b"z" * 700, mode=0o755) + END]
        read = 0
        for _ in range(CASES):
            raw = bytearray(rnd.choice(seeds))
            for _ in range(rnd.choice((1, 1, 2, 4, 8))):
                if not raw:
                    break
                op = rnd.randrange(7)
                i = rnd.randrange(len(raw))
                if op == 0:
                    raw[i] = rnd.randrange(256)
                elif op == 1:
                    raw[i] ^= 1 << rnd.randrange(8)
                elif op == 2:
                    del raw[i:i + rnd.randrange(1, 600)]
                elif op == 3:
                    raw[i:i] = bytes(rnd.randrange(256) for _ in range(rnd.randrange(1, 40)))
                elif op == 4:
                    raw[i:i] = raw[(i // 512) * 512:(i // 512) * 512 + 512]       # a header or block twice
                elif op == 5:
                    del raw[i:]
                else:
                    # fix the checksum of the header the change fell in, so the rest of the checks are reached
                    j = (i // 512) * 512
                    if j + 512 <= len(raw):
                        raw[j + 148:j + 156] = b" " * 8
                        raw[j + 148:j + 156] = (b"%06o" % sum(raw[j:j + 512])) + b"\0 "
            raw = bytes(raw)
            try:
                entries, _ = scan(raw)
            except b.BundleError:
                continue
            except Exception as exc:
                self.fail(f"seed {self.seed}: scan_tar raised {exc!r} on {raw[:200]!r}")
            read += 1
            try:
                with tarfile.open(fileobj=io.BytesIO(raw), mode="r:") as tf:
                    ref = [(m.name, "dir" if m.isdir() else "link" if m.issym() else "file" if m.isreg() else "?", m.size, m.linkname) for m in tf]
            except Exception as exc:
                self.fail(f"seed {self.seed}: scan_tar accepted what tarfile cannot read ({exc!r}): {raw[:300]!r}")
            mine = [(e.path, e.kind, e.size if e.kind == "file" else 0, e.target) for e in entries]
            if mine != ref:
                open("/src/failraw.bin", "wb").write(raw)
            self.assertEqual(mine, ref, (self.seed, raw[:300]))
        self.assertGreater(read, 0)

    def test_whole_pipeline_on_random_trees(self):
        """Random entry lists, written as pack writes them, read back and checked: no traceback, and a tree that
        validate() accepts has only names the Store reads as the same names."""
        rnd = self.rnd("trees")
        accepted = 0
        for _ in range(max(50, CASES // 10)):
            names = sorted({gen_path(rnd) for _ in range(rnd.randrange(1, 6))} | {"bin", "bin/app"})
            buf = io.BytesIO()
            try:
                with tarfile.open(fileobj=buf, mode="w|", format=tarfile.PAX_FORMAT, encoding="utf-8", errors="strict") as tf:
                    for name in names:
                        ti = tarfile.TarInfo(name)
                        kind = rnd.choice(("file", "file", "dir", "link"))
                        ti.mtime = 0
                        if kind == "dir":
                            ti.type, ti.mode = tarfile.DIRTYPE, 0o755
                            tf.addfile(ti)
                        elif kind == "link":
                            ti.type, ti.mode, ti.linkname = tarfile.SYMTYPE, 0o777, gen_path(rnd)
                            tf.addfile(ti)
                        else:
                            ti.size, ti.mode = 2, rnd.choice((0o644, 0o755, 0o4755, 0o666))
                            tf.addfile(ti, io.BytesIO(b"hi"))
            except (UnicodeError, ValueError):
                continue                                 # tarfile itself cannot write that name
            try:
                entries, _ = scan(buf.getvalue(), small=True)
                by_path = b.validate(entries, archive=True)
            except b.BundleError:
                continue
            except Exception as exc:
                self.fail(f"seed {self.seed}: reading and validating {names!r} raised {exc!r}")
            accepted += 1
            for e in entries:
                self.assertEqual(store_entry_path(e.path.encode("utf-8"), e.kind == "dir"), e.path, (self.seed, e.path))
                self.assertIn(e.mode & 0o7777, (0o755, 0o644, 0o777))
                self.assertEqual((e.uid, e.gid), (0, 0))
        # most random trees are refused (bin/ and share/ only, a desktop file...): that is the point

    def test_semantics_never_crash(self):
        """check_semantics on random trees with random small file contents."""
        rnd = self.rnd("semantics")
        contents = [b"", b"[Desktop Entry]\nType=Application\nExec=app\n", b"\xff", b"\0", b"[D-BUS Service]\nName=a.b.c\nExec=app\n",
                    b"<component><id>a.b.c</id></component>", b"<!DOCTYPE x [<!ENTITY a 'b'>]><component/>", b"<", b"x=1\n" * 500,
                    b"[Desktop Entry]\n" + b"k" * 9000 + b"=v\n"]
        for _ in range(max(50, CASES // 4)):
            paths = ["share/applications/" + rnd.choice(("a.b.c.desktop", "x.desktop", "a.b.c.desktop/y", ".desktop")),
                     "share/" + rnd.choice(("icons/hicolor/48x48/apps/a.b.c.png", "metainfo/a.b.c.metainfo.xml", "dbus-1/services/a.b.c.service",
                                            "knotifications6/telamon-c.notifyrc", "icons/x", "metainfo", "dbus-1", "icons/hicolor/a.png")),
                     "bin/" + rnd.choice(("app", "a b", "app/x", ".app"))]
            by = {"bin": b.Entry("bin", "dir", 0o755), "share": b.Entry("share", "dir", 0o755)}
            data = {}
            for p in paths:
                kind = rnd.choice(("file", "file", "file", "dir", "link"))
                size = 0
                if kind == "file":
                    data[p] = rnd.choice(contents)
                    size = len(data[p])
                by[p] = b.Entry(p, kind, 0o755 if kind != "link" else 0o777, size=size, target="app")
            try:
                b.check_semantics(by, lambda p: data.get(p, b""))
            except b.BundleError:
                pass
            except Exception as exc:
                self.fail(f"seed {self.seed}: check_semantics raised {exc!r} for {sorted(by)!r}")


def main():
    global CASES, SEED
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--cases", type=int, default=CASES, help="random inputs per fuzz test (default %(default)s)")
    ap.add_argument("--seed", type=int, help="fix the random inputs (default: new each run, printed)")
    ap.add_argument("-v", "--verbose", action="store_true")
    a, rest = ap.parse_known_args()
    CASES, SEED = a.cases, a.seed
    if SEED is None:
        SEED = random.SystemRandom().randrange(1 << 32)
    print(f"test_bundle_rules: {CASES} cases per fuzz test, seed {SEED} (replay: --seed {SEED})", file=sys.stderr)
    unittest.main(argv=[sys.argv[0], *(["-v"] if a.verbose else []), *rest])


if __name__ == "__main__":
    main()
