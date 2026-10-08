#!/bin/bash
# Tests tools/make-bundle.sh and tools/bundle.py on a tiny fake app (a shell
# script, a .desktop file, metainfo, an icon and a data directory; no Qt, no
# Rust): the archive's layout, the manifest, the hashes, a reproducible
# result, and that every kind of bad bundle is refused. Needs bash, cmake,
# python3, zstd and tar (about 10 s); CI and dev-check.sh run it.
#
#   tools/test-make-bundle.sh
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
make_bundle=$here/make-bundle.sh
bundle_py=$here/bundle.py
for tool in cmake python3 zstd tar sha256sum; do
    command -v "$tool" >/dev/null || { echo "test-make-bundle: $tool is not installed" >&2; exit 2; }
done

scratch=$(mktemp -d "${TMPDIR:-/tmp}/telamon-test-bundle.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
export SOURCE_DATE_EPOCH=1767225600 # 2026-01-01T00:00:00Z
passed=0
failed=0

ok() { passed=$((passed + 1)); echo "ok   $1"; }
bad() {
    local line
    failed=$((failed + 1))
    echo "FAIL $1" >&2
    [ -z "${2:-}" ] || while IFS= read -r line; do echo "     | $line" >&2; done <<<"$2"
}
check() { # check "name" command...: passes when the command succeeds
    local name=$1 out
    shift
    if out=$("$@" 2>&1); then ok "$name"; else bad "$name" "$out"; fi
}

# ---------------------------------------------------------------- fake app
# mkapp <repo dir>: apps/fake with `-DFAKE=<variant>` switching on one defect.
mkapp() {
    local repo=$1 app=$1/apps/fake
    mkdir -p "$app/data" "$app/share-data" "$repo/packaging"
    cat >"$app/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.24)
project(fake-app VERSION 1.2.3 LANGUAGES NONE)
include(GNUInstallDirs)
set(FAKE "" CACHE STRING "which defect to build in")

install(PROGRAMS data/fake-app DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES data/net.example.fake.metainfo.xml DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo)
install(FILES data/net.example.fake.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
install(DIRECTORY share-data/ DESTINATION ${CMAKE_INSTALL_DATADIR}/net.example.fake)
if(FAKE STREQUAL "bad-exec")
    install(FILES data/bad-exec.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications
            RENAME net.example.fake.desktop)
else()
    install(FILES data/net.example.fake.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
endif()
if(FAKE STREQUAL "two-desktops")
    install(FILES data/net.example.fake.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications
            RENAME net.example.other.desktop)
endif()
if(FAKE STREQUAL "stage-leak")
    # a binary that learned its install path at build time
    install(CODE "file(WRITE \"${CMAKE_INSTALL_PREFIX}/bin/fake-helper\" \"#!/bin/sh\\nexec ${CMAKE_INSTALL_PREFIX}/share/x\\n\")")
endif()
if(FAKE STREQUAL "link-out")
    install(CODE "file(CREATE_LINK ../../../../etc/passwd \"${CMAKE_INSTALL_PREFIX}/share/net.example.fake/evil\" SYMBOLIC)")
endif()
if(FAKE STREQUAL "link-abs")
    install(CODE "file(CREATE_LINK /etc/passwd \"${CMAKE_INSTALL_PREFIX}/share/net.example.fake/evil\" SYMBOLIC)")
endif()
if(FAKE STREQUAL "link-ok")
    install(CODE "file(CREATE_LINK fake-app \"${CMAKE_INSTALL_PREFIX}/bin/fake\" SYMBOLIC)")
endif()
if(FAKE STREQUAL "lib")
    install(CODE "file(WRITE \"${CMAKE_INSTALL_PREFIX}/lib/libx.so\" \"x\")")
endif()
if(FAKE STREQUAL "force-prefix")
    set(CMAKE_INSTALL_PREFIX /usr/local/fake-forced CACHE PATH "" FORCE)
endif()
if(FAKE STREQUAL "legacy")
    install(FILES data/net.example.fake.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications
            RENAME net.example.old.desktop)
endif()
EOF
    cat >"$app/data/fake-app" <<'EOF'
#!/bin/sh
here=$(dirname "$(readlink -f "$0")")
cat "$here/../share/net.example.fake/hello.txt"
EOF
    chmod +x "$app/data/fake-app"
    printf '[Desktop Entry]\nType=Application\nName=Fake\nComment=A fake app\nExec=fake-app %%U\nTryExec=fake-app\nIcon=net.example.fake\nActions=new;\n\n[Desktop Action new]\nName=New\nExec=fake-app --new\n' \
        >"$app/data/net.example.fake.desktop"
    printf '[Desktop Entry]\nType=Application\nName=Fake\nExec=fake-app\nIcon=net.example.fake\nActions=new;\n\n[Desktop Action new]\nName=New\nExec=fake-missing --new\n' >"$app/data/bad-exec.desktop"
    cat >"$app/data/net.example.fake.metainfo.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>net.example.fake</id>
  <name>Fake</name>
  <name xml:lang="de">Falsch</name>
  <summary>A fake app for tests</summary>
  <project_license>MIT</project_license>
  <url type="homepage">https://example.net/fake</url>
</component>
EOF
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16"/></svg>\n' \
        >"$app/data/net.example.fake.svg"
    mkdir -p "$app/share-data/sub"
    echo "hello from the data directory" >"$app/share-data/hello.txt"
    echo "nested" >"$app/share-data/sub/nested.txt"
    printf 'Name:           fake\nVersion:        1.2.3\nLicense:        MIT\nBuildRequires:  telamon-ui >= 2.0.2\nBuildRequires:  telamon-ui >= 2.0.1\n' \
        >"$repo/packaging/fake.spec"
}

repo=$scratch/repo
mkapp "$repo"
run_make() { # run_make <out> [make-bundle args]: from the repo root, output to $log
    local out=$1
    shift
    (cd "$repo" && "$make_bundle" --out "$out" --build-dir "$scratch/build-$(basename "$out")" "$@") >"$scratch/log" 2>&1
}

# ------------------------------------------------------------------ good build
out1=$scratch/out1
if run_make "$out1" --min-os-version 44; then ok "make-bundle builds the fake app"; else bad "make-bundle builds the fake app" "$(tail -n 30 "$scratch/log")"; fi
archive=$out1/net.example.fake-1.2.3-x86_64.tar.zst
manifest=$out1/telamon-bundle.json
check "the two release assets exist, and nothing else is in the output" bash -c \
    "[ -f '$archive' ] && [ -f '$manifest' ] && [ \"\$(ls '$out1' | wc -l)\" = 2 ]"

# The listing: relative names, sorted, root-owned, mode 0644/0755, commit time.
zstd -dc -- "$archive" | tar --numeric-owner -tvf - --full-time >"$scratch/list" 2>&1
check "tar entries are relative, with no ./, absolute or .. names" bash -c \
    "! awk '{print \$NF}' '$scratch/list' | grep -E '^(\\./|/)|(^|/)\\.\\.(/|\$)'"
check "every entry is root:root (0/0)" bash -c "! grep -v ' 0/0 ' '$scratch/list'"
check "modes are only 0755/0644 (drwxr-xr-x, -rwxr-xr-x, -rw-r--r--)" bash -c \
    "! grep -vE '^(drwxr-xr-x|-rwxr-xr-x|-rw-r--r--|lrwxrwxrwx) ' '$scratch/list'"
check "every mtime is SOURCE_DATE_EPOCH (2026-01-01 00:00:00)" bash -c \
    "! grep -v ' 2026-01-01 00:00:00' '$scratch/list'"
names=$(awk '{print $NF}' "$scratch/list" | sed 's|/$||')
if [ "$names" = "$(LC_ALL=C sort <<<"$names")" ]; then ok "entries are sorted by path"; else bad "entries are sorted by path" "$names"; fi
for want in bin/fake-app share/applications/net.example.fake.desktop share/metainfo/net.example.fake.metainfo.xml \
    share/icons/hicolor/scalable/apps/net.example.fake.svg share/net.example.fake/hello.txt \
    share/net.example.fake/sub/nested.txt telamon-bundle.json; do
    check "archive holds $want" grep -qxF "$want" <<<"$names"
done
check "archive holds no lib/, etc/ or other top directory" bash -c "! grep -vE '^(bin|share|telamon-bundle.json)(/|\$)' <<<'$names'"

# The manifests, read independently of bundle.py.
tree=$scratch/extracted
mkdir "$tree"
zstd -dc -- "$archive" | tar -xf - -C "$tree"
cat >"$scratch/check_manifest.py" <<'EOF'
import hashlib, json, os, sys
archive, manifest, tree = sys.argv[1:4]
raw = open(manifest, "rb").read().decode()
m = json.loads(raw)
want = ["schema", "id", "name", "version", "summary", "homepage", "license", "arch",
        "min_telamon_ui", "min_os_version", "files", "links", "archive"]
assert list(m) == want, list(m)
assert raw == json.dumps(m, indent=2, ensure_ascii=False) + "\n", "not 2-space indented with a trailing newline"
assert m["schema"] == 1 and m["id"] == "net.example.fake" and m["name"] == "Fake"
assert m["version"] == "1.2.3" and m["summary"] == "A fake app for tests" and m["license"] == "MIT"
assert m["homepage"] == "https://example.net/fake" and m["arch"] == "x86_64"
assert m["min_telamon_ui"] == "2.0.2", m["min_telamon_ui"]   # the highest BuildRequires
assert m["min_os_version"] == "44"
paths = [f["path"] for f in m["files"]]
assert paths == sorted(paths) and "telamon-bundle.json" not in paths
for f in m["files"]:
    assert list(f) == ["path", "size", "sha256", "executable"], f
    data = open(os.path.join(tree, f["path"]), "rb").read()
    assert len(data) == f["size"] and hashlib.sha256(data).hexdigest() == f["sha256"], f["path"]
    assert f["executable"] == bool(os.stat(os.path.join(tree, f["path"])).st_mode & 0o111), f["path"]
assert [f["path"] for f in m["files"] if f["executable"]] == ["bin/fake-app"]
assert m["links"] == []
a = m["archive"]
assert list(a) == ["name", "sha256", "size"]
data = open(archive, "rb").read()
assert a["name"] == os.path.basename(archive) == "net.example.fake-1.2.3-x86_64.tar.zst"
assert a["sha256"] == hashlib.sha256(data).hexdigest() and a["size"] == len(data)
inner = json.loads(open(os.path.join(tree, "telamon-bundle.json")).read())
del m["archive"]
assert inner == m and list(inner) == list(m)
print("manifest ok")
EOF
check "manifest: key order, format, fields, hashes, sizes, inner == outer minus archive" \
    python3 -I "$scratch/check_manifest.py" "$archive" "$manifest" "$tree"
check "the extracted app runs and finds its data relative to itself" bash -c \
    "[ \"\$('$tree/bin/fake-app')\" = 'hello from the data directory' ]"
check "bundle.py verify accepts it" python3 -I "$bundle_py" verify "$archive" "$manifest"

# ------------------------------------------------------------ reproducible
out2=$scratch/out2
if run_make "$out2" --min-os-version 44 --stage "$scratch/another-stage-dir"; then
    check "a second build (other stage and build dirs) is byte-identical: archive" cmp "$archive" "$out2/net.example.fake-1.2.3-x86_64.tar.zst"
    check "a second build is byte-identical: manifest" cmp "$manifest" "$out2/telamon-bundle.json"
else
    bad "a second build works" "$(tail -n 20 "$scratch/log")"
fi

# ---------------------------------------------------------------- version
if run_make "$scratch/out-v" --min-os-version 44 --version v1.2.3 && [ -f "$scratch/out-v/net.example.fake-1.2.3-x86_64.tar.zst" ]; then
    ok "--version v1.2.3 (a tag) matches project VERSION"; else bad "--version v1.2.3 matches" "$(tail -n 5 "$scratch/log")"; fi
if run_make "$scratch/out-pre" --min-os-version 44 --version 1.2.3-rc.1 && [ -f "$scratch/out-pre/net.example.fake-1.2.3-rc.1-x86_64.tar.zst" ]; then
    ok "--version 1.2.3-rc.1 (a prerelease of the CMake version) is accepted"; else bad "prerelease version accepted" "$(tail -n 5 "$scratch/log")"; fi

# expect_fail <name> <message regexp> <make-bundle args...>
expect_fail() {
    local name=$1 rx=$2
    shift 2
    if run_make "$scratch/out-fail" --min-os-version 44 "$@"; then
        bad "$name: was accepted" "$(tail -n 5 "$scratch/log")"
    elif grep -qE "$rx" "$scratch/log" && [ ! -e "$scratch/out-fail/telamon-bundle.json" ]; then
        ok "$name: refused"
    else
        bad "$name: failed, but not as expected ($rx)" "$(tail -n 8 "$scratch/log")"
    fi
    rm -rf "$scratch/out-fail" "$scratch"/build-out-fail
}
expect_fail "a version that is not the CMake version" "does not match project" --version 1.2.4
expect_fail "a version that is not a version" "version .* dotted numbers" --version banana

# --------------------------------------------------------- tampered installs
expect_fail "a .desktop Exec naming a missing binary" "bin/fake-missing is not in the bundle" --cmake-arg -DFAKE=bad-exec
expect_fail "two .desktop files" "exactly one .desktop file is required, found 2" --cmake-arg -DFAKE=two-desktops
expect_fail "the stage path inside a binary" "not relocatable" --cmake-arg -DFAKE=stage-leak
expect_fail "a symlink pointing outside the tree" "not a relative path inside the tree" --cmake-arg -DFAKE=link-out
expect_fail "an absolute symlink" "not a relative path inside the tree" --cmake-arg -DFAKE=link-abs
expect_fail "a file under lib/" "outside bin/ and share/" --cmake-arg -DFAKE=lib
expect_fail "an app that forces its install prefix" "sets CMAKE_INSTALL_PREFIX" --cmake-arg -DFAKE=force-prefix
expect_fail "an --exclude that matches nothing" "matches nothing" --exclude share/nothing.desktop
expect_fail "a non-empty --stage" "is not empty" --stage "$scratch/out1"
expect_fail "a missing app dir" "does not exist" --app-dir apps/nope

# the accepted variants of those
if run_make "$scratch/out-link" --min-os-version 44 --cmake-arg -DFAKE=link-ok &&
    python3 -I -c "
import json,sys
m=json.load(open('$scratch/out-link/telamon-bundle.json'))
assert m['links']==[{'path':'bin/fake','target':'fake-app'}], m['links']"; then
    ok "a relative symlink inside the tree is kept and listed in links"; else bad "a relative symlink is kept" "$(tail -n 8 "$scratch/log")"; fi
if run_make "$scratch/out-legacy" --min-os-version 44 --cmake-arg -DFAKE=legacy --exclude 'share/applications/net.example.old.desktop'; then
    ok "--exclude leaves a legacy .desktop file out"; else bad "--exclude leaves a legacy .desktop out" "$(tail -n 8 "$scratch/log")"; fi

# ------------------------------------- tampered archives (bundle.py verify)
# rewrite <good archive> <new archive> <python statements on tf_in, tf_out, ti, data>
cat >"$scratch/tamper.py" <<'EOF'
"""tamper.py GOOD OUT-DIR MODE: a copy of a good bundle with one defect (and a manifest that agrees on the archive hash)."""
import hashlib, io, json, os, subprocess, sys, tarfile
good, outdir, mode = sys.argv[1:4]
src = subprocess.run(["zstd", "-dc", good], capture_output=True, check=True).stdout
members = []
with tarfile.open(fileobj=io.BytesIO(src)) as tf:
    for ti in tf:
        members.append((ti, tf.extractfile(ti).read() if ti.isreg() else None))
out = []
for ti, data in members:
    if mode == "hash" and ti.name == "share/net.example.fake/hello.txt":
        data = b"HELLO from the data directory\n"
    if mode == "mode" and ti.name == "share/net.example.fake/hello.txt":
        ti.mode = 0o666
    if mode == "owner" and ti.name == "bin/fake-app":
        ti.uid = 1000
    if mode == "mtime" and ti.name == "bin/fake-app":
        ti.mtime += 5
    out.append((ti, data))
extra = None
if mode == "extra":
    extra = ("share/net.example.fake/extra.txt", b"not in the manifest\n", tarfile.REGTYPE, "")
if mode == "dotdot":
    extra = ("share/../../evil", b"x", tarfile.REGTYPE, "")
if mode == "absolute":
    extra = ("/etc/evil", b"x", tarfile.REGTYPE, "")
if mode == "dotslash":
    extra = ("./share/net.example.fake/dot.txt", b"x", tarfile.REGTYPE, "")
if mode == "hardlink":
    extra = ("share/net.example.fake/hard", b"", tarfile.LNKTYPE, "bin/fake-app")
if mode == "fifo":
    extra = ("share/net.example.fake/fifo", b"", tarfile.FIFOTYPE, "")
if mode == "symdir":
    extra = ("share/net.example.fake/sub/up", b"", tarfile.SYMTYPE, "../../../..")
if mode == "toplevel":
    extra = ("lib/libx.so", b"x", tarfile.REGTYPE, "")
if mode == "dupe":
    extra = ("bin/fake-app", b"#!/bin/sh\n", tarfile.REGTYPE, "")
if extra:
    name, data, typ, link = extra
    ti = tarfile.TarInfo(name)
    ti.type, ti.linkname, ti.mode, ti.mtime = typ, link, 0o644, out[0][0].mtime
    ti.size = len(data) if typ == tarfile.REGTYPE else 0
    out.append((ti, data if typ == tarfile.REGTYPE else None))
buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as tf:
    for ti, data in out:
        tf.addfile(ti, io.BytesIO(data) if data is not None else None)
z = subprocess.run(["zstd", "-19", "-q", "-c"], input=buf.getvalue(), capture_output=True, check=True).stdout
os.makedirs(outdir, exist_ok=True)
name = os.path.basename(good)
open(os.path.join(outdir, name), "wb").write(z)
m = json.load(open(os.path.join(os.path.dirname(good), "telamon-bundle.json")))
m["archive"]["sha256"] = hashlib.sha256(z).hexdigest()
m["archive"]["size"] = len(z)
open(os.path.join(outdir, "telamon-bundle.json"), "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
EOF
tamper() { # tamper <mode> <message regexp>
    local mode=$1 rx=$2 dir=$scratch/tampered-$1 msg
    python3 -I "$scratch/tamper.py" "$archive" "$dir" "$mode" || { bad "tamper $mode: could not build the test archive"; return; }
    if msg=$(python3 -I "$bundle_py" verify "$dir/$(basename "$archive")" "$dir/telamon-bundle.json" 2>&1); then
        bad "verify accepted an archive with: $mode"
    elif grep -qE "$rx" <<<"$msg"; then
        ok "verify refuses an archive with: $mode"
    else
        bad "verify refused $mode, but not as expected ($rx)" "$msg"
    fi
}
tamper hash "sha256 differs from the manifest"
tamper extra "in the archive, not in the manifest"
tamper dotdot "'\\.\\.' component|empty, '\\.' or"
tamper absolute "absolute path"
tamper dotslash "empty, '\\.' or '\\.\\.' component"
tamper hardlink "hard link"
tamper fifo "device or fifo"
tamper symdir "not a relative path inside the tree"
tamper toplevel "outside bin/ and share/"
tamper dupe "listed twice"
tamper mode "expected 0755 or 0644"
tamper owner "expected 0:0"
tamper mtime "different modification times"
# a manifest that does not match its archive
cp -r "$out1" "$scratch/badmanifest"
sed -i 's/"size": 1[0-9]*,/"size": 1,/' "$scratch/badmanifest/telamon-bundle.json"
if python3 -I "$bundle_py" verify "$scratch/badmanifest/net.example.fake-1.2.3-x86_64.tar.zst" "$scratch/badmanifest/telamon-bundle.json" >/dev/null 2>&1; then
    bad "verify accepted a manifest with a wrong size"; else ok "verify refuses a manifest with a wrong size"; fi
cp "$archive" "$scratch/badmanifest/other.tar.zst"
if python3 -I "$bundle_py" verify "$scratch/badmanifest/other.tar.zst" "$manifest" >/dev/null 2>&1; then
    bad "verify accepted an archive under another name"; else ok "verify refuses an archive whose name differs from archive.name"; fi
printf 'not zstd' >"$scratch/junk.tar.zst"
if python3 -I "$bundle_py" verify "$scratch/junk.tar.zst" "$manifest" >/dev/null 2>&1; then
    bad "verify accepted junk"; else ok "verify refuses a file that is not an archive"; fi

echo
echo "test-make-bundle: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
