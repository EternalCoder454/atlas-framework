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
for tool in cmake python3 zstd tar sha256sum cmp; do
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
set(FAKE_FILE "" CACHE STRING "a file to add, relative to the prefix")
set(FAKE_CONTENT "x" CACHE STRING "its content")
set(FAKE_EXEC "" CACHE STRING "Exec= of the .desktop file, in place of fake-app")

install(PROGRAMS data/fake-app DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES data/net.example.fake.metainfo.xml DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo)
install(FILES data/net.example.fake.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
install(DIRECTORY share-data/ DESTINATION ${CMAKE_INSTALL_DATADIR}/net.example.fake)
if(FAKE_EXEC)
    install(CODE "file(WRITE \"${CMAKE_INSTALL_PREFIX}/share/applications/net.example.fake.desktop\" \"[Desktop Entry]\\nType=Application\\nName=Fake\\nExec=${FAKE_EXEC}\\n\")")
elseif(FAKE STREQUAL "bad-exec")
    install(FILES data/bad-exec.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications
            RENAME net.example.fake.desktop)
else()
    install(FILES data/net.example.fake.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
endif()
if(FAKE STREQUAL "quote-exec")
    install(CODE "file(WRITE \"${CMAKE_INSTALL_PREFIX}/share/applications/net.example.fake.desktop\" \"[Desktop Entry]\\nType=Application\\nName=Fake\\nExec=\\\"fake-app\\\"\\n\")")
endif()
if(FAKE_FILE)
    install(CODE "file(WRITE \"${CMAKE_INSTALL_PREFIX}/${FAKE_FILE}\" \"${FAKE_CONTENT}\")")
endif()
if(FAKE STREQUAL "good-extras")
    install(CODE "file(WRITE \"${CMAKE_INSTALL_PREFIX}/share/dbus-1/services/net.example.fake.Service.service\" \"[D-BUS Service]\\nName=net.example.fake.Service\\nExec=fake-app --gapplication-service\\n\")")
    install(CODE "file(WRITE \"${CMAKE_INSTALL_PREFIX}/share/knotifications6/telamon-fake-alerts.notifyrc\" \"[Global]\\nName=Fake\\n\")")
    install(CODE "file(WRITE \"${CMAKE_INSTALL_PREFIX}/share/icons/hicolor/48x48/apps/net.example.fake-small.png\" \"png\")")
    install(CODE "file(WRITE \"${CMAKE_INSTALL_PREFIX}/share/icons/hicolor/scalable/apps/net.example.fake_dark.svg\" \"svg\")")
endif()
if(FAKE STREQUAL "export-link")
    install(CODE "file(CREATE_LINK ../net.example.fake/hello.txt \"${CMAKE_INSTALL_PREFIX}/share/metainfo/net.example.fake.appdata.xml\" SYMBOLIC)")
endif()
if(FAKE STREQUAL "link-to-export")
    install(CODE "file(CREATE_LINK ../applications/net.example.fake.desktop \"${CMAKE_INSTALL_PREFIX}/share/net.example.fake/d\" SYMBOLIC)")
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
expect_fail "a .desktop Exec naming a missing binary" "bin/fake-missing is not an executable file in the bundle" --cmake-arg -DFAKE=bad-exec
expect_fail "two .desktop files" "share/applications must hold exactly one file.*found 2" --cmake-arg -DFAKE=two-desktops
expect_fail "the stage path inside a binary" "not relocatable" --cmake-arg -DFAKE=stage-leak
expect_fail "a symlink pointing outside the tree" "not a relative path inside the tree" --cmake-arg -DFAKE=link-out
expect_fail "an absolute symlink" "not a relative path inside the tree" --cmake-arg -DFAKE=link-abs
expect_fail "a file under lib/" "outside bin/ and share/" --cmake-arg -DFAKE=lib
expect_fail "an app that forces its install prefix" "sets CMAKE_INSTALL_PREFIX" --cmake-arg -DFAKE=force-prefix
expect_fail "an --exclude that matches nothing" "matches nothing" --exclude share/nothing.desktop
expect_fail "a non-empty --stage" "is not empty" --stage "$scratch/out1"
expect_fail "a missing app dir" "does not exist" --app-dir apps/nope

# What the Store copies out: icons, metainfo, D-Bus, notifications, Exec
expect_fail "an icon of another app (shadowing the theme)" "icons are only share/icons/hicolor" \
    --cmake-arg -DFAKE_FILE=share/icons/hicolor/48x48/apps/other.png
expect_fail "a file under share/icons outside hicolor/<size>/apps" "icons are only share/icons/hicolor" \
    --cmake-arg -DFAKE_FILE=share/icons/hicolor/index.theme
expect_fail "an icon with another extension" "icons are only share/icons/hicolor" \
    --cmake-arg -DFAKE_FILE=share/icons/hicolor/48x48/apps/net.example.fake.xpm
expect_fail "another file in share/metainfo" "share/metainfo holds only" --cmake-arg -DFAKE_FILE=share/metainfo/other.metainfo.xml
expect_fail "another file in share/applications" "share/applications must hold exactly one file" \
    --cmake-arg -DFAKE_FILE=share/applications/mimeinfo.cache
expect_fail "a notification file named after another app" "share/knotifications6 holds only telamon-fake" \
    --cmake-arg -DFAKE_FILE=share/knotifications6/telamon-other.notifyrc
expect_fail "a notification file not named telamon-<name>.notifyrc" "share/knotifications6 holds only" \
    --cmake-arg -DFAKE_FILE=share/knotifications6/fake.notifyrc
expect_fail "a D-Bus service of another name" "must be net.example.fake or" --cmake-arg -DFAKE_FILE=share/dbus-1/services/org.other.service \
    --cmake-arg '-DFAKE_CONTENT=[D-BUS Service]\nName=org.other\nExec=fake-app\n'
expect_fail "a D-Bus service whose Exec is a path" "use the bare binary name" --cmake-arg -DFAKE_FILE=share/dbus-1/services/net.example.fake.service \
    --cmake-arg '-DFAKE_CONTENT=[D-BUS Service]\nName=net.example.fake\nExec=/usr/bin/fake-app\n'
expect_fail "another file in share/dbus-1" "share/dbus-1 holds only" --cmake-arg -DFAKE_FILE=share/dbus-1/system.d/x.conf
expect_fail "an Exec with a path" "use the bare binary name" --cmake-arg '-DFAKE_EXEC=/usr/bin/fake-app'
expect_fail "an Exec that starts with env" "starts with .env." --cmake-arg '-DFAKE_EXEC=env X=1 fake-app'
expect_fail "an Exec that starts with a quote" "starts with a quote" --cmake-arg -DFAKE=quote-exec
expect_fail "an Exec naming a symlink in bin/ (not a regular file)" "is not an executable file" --cmake-arg -DFAKE=link-ok --cmake-arg '-DFAKE_EXEC=fake'
expect_fail "a symlink among the exported files" "not allowed \(a regular file\)" --cmake-arg -DFAKE=export-link
expect_fail "a symlink to an exported file" "a file the Store copies out" --cmake-arg -DFAKE=link-to-export
expect_fail "a hidden (zero-width) character in a name" "hidden character" \
    --cmake-arg "-DFAKE_FILE=share/net.example.fake/a$(printf '\xe2\x80\x8b')b"
expect_fail "a bidi control in a name" "hidden character" \
    --cmake-arg "-DFAKE_FILE=share/net.example.fake/a$(printf '\xe2\x80\xae')b"
if run_make "$scratch/out-extras" --min-os-version 44 --cmake-arg -DFAKE=good-extras &&
    python3 -I "$bundle_py" verify "$scratch/out-extras"/*.tar.zst "$scratch/out-extras/telamon-bundle.json" >/dev/null; then
    ok "a D-Bus service, a notifyrc and icons named after the app are accepted"
else bad "good extras are accepted" "$(tail -n 8 "$scratch/log")"; fi

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
more = []
if mode == "reorder":
    out.reverse()
if mode == "linkdots":
    # d -> .. is share/net.example.fake/sub/.. ; e climbs one more through d
    extra = ("share/net.example.fake/sub/d", b"", tarfile.SYMTYPE, "../..")
    more = [("share/net.example.fake/sub/e", b"", tarfile.SYMTYPE, "d/../../../../bin")]
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
for name, data, typ, link in ([extra] if extra else []) + more:
    ti = tarfile.TarInfo(name)
    ti.type, ti.linkname, ti.mode, ti.mtime = typ, link, 0o644, out[0][0].mtime
    ti.size = len(data) if typ == tarfile.REGTYPE else 0
    out.append((ti, data if typ == tarfile.REGTYPE else None))
if mode != "reorder":
    out.sort(key=lambda m: m[0].name)
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
tamper reorder "not sorted by path"
tamper linkdots "not a relative path inside the tree"
tamper mtime "different modification times"
# The Store's reader rules, as units (the Store's own tests cover its side)
cat >"$scratch/units.py" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import bundle as b
E = b.Entry

def raises(fn, *args):
    try:
        fn(*args)
    except b.BundleError:
        return True
    return False

# whole-field matches
assert not b.valid_version("1.0.0\n") and not b.OSVER_RE.fullmatch("44\n") and not b.ID_RE.fullmatch("a.b.c\n")
# versions: up to 6 numbers of 9 digits, no leading zeros, a prerelease of [0-9A-Za-z-] parts, 64 characters
for ok in ("0.1.0", "1.0.0-beta.1", "1.2.3.4.5.6", "999999999.0", "1.0-a-b.c-d"):
    assert b.valid_version(ok), ok
for bad in ("1", "01.0", "1.2.3.4.5.6.7", "1234567890.0", "1.0.0-", "1.0.0-a..b", "1.0.0-a_b", "v1.0.0", "1.0.0+x", "1." + "0." * 31 + "0-" + "a" * 20):
    assert not b.valid_version(bad), bad
assert b.valid_min_ui("2") and b.valid_min_ui("2.0.2") and not b.valid_min_ui("2.0.2-x") and not b.valid_min_ui("")
# app ids: three parts, no empty part, none starting with '-', 128 bytes
for ok in ("net.example.fake", "net.eterneon.telamon.gates", "a.b.c-d_e"):
    assert b.valid_app_id(ok), ok
for bad in ("a.b", "gates", "a..b.c", ".a.b.c", "a.b.c.", "a.-b.c", "a.b.c/d", "a.b.c d", "a." + "b" * 130 + ".c"):
    assert not b.valid_app_id(bad), bad
# the home page, as the Store normalises it
for url in ("https://github.com/EternalCoder454/atlas-framework", "https://example.net/fake", "https://a.b.org/p?q=1#f"):
    assert b.https_url(url) == url, url
for url in ("http://github.com/x", "https://github.com:8443/x", "https://localhost/x", "https://a.local/", "https://x.test/", "https://x.example/",
            "https://1.2.3.4/", "https://x.c0m/", "https://single/", "https://x.com/a/../b", "https://x.com/%2e%2E/b", 'https://x.com/a"b',
            "https://x.com/a b", "https://x.com/a\\b", "https://x.com/<", "https://x.com/{", "https://-a.com/", "https://x.com/\u00e9"):
    assert b.https_url(url) != url, url
assert b.https_url("https://GitHub.com:443/x") == "https://github.com/x"   # the Store's own form differs: a bundle must write it normalised
# link targets
for ok in ("telamon-x", "../bin/x", "a/b"):
    assert b.link_target_ok("share/n/l", ok), ok
for bad in ("", "a//b", "./x", "a/./b", "a/", "/etc/passwd", "../../../x", "a\u200bb", "a\u3164b", "a\nb", "x" * 1100):
    assert not b.link_target_ok("share/n/l", bad), repr(bad)
# hidden characters in names
for ch in ("\u200b", "\u3164", "\uffa0", "\u115f", "\u1160", "\u17b4", "\u180c", "\u034f", "\ufe0f", "\u2060", "\u2066", "\U000e0001", "\u202e", "\ufeff", "\x07"):
    assert b.path_problem("share/a" + ch + "b"), repr(ch)
assert b.path_problem("share/" + "a/" * 600 + "x") and b.path_problem("share/" + "x" * 256)
assert b.path_problem("share/ok-name_1.txt") is None
# desktop files are read like the Store reads them
good = b"[Desktop Entry]\nType=Application\nName=F\nName[de]=G\nExec=fake-app %U\n"
by = {"bin/fake-app": E("bin/fake-app", "file", 0o755)}
assert not b.exec_errors(b.parse_keyfile(good, "d"), "d", by)
for bad in (good + b"Exec[de]=fake-app\n", good + b"TryExec[de]=x\n", good + b"Path[de]=x\n", good + b"just a line\n", b"Exec=x\n[Desktop Entry]\n",
            good + b"[Desktop Action a]\nExec=.hidden\n", good + b"[Desktop Action a]\nExec=" + b"x" * 101 + b"\n",
            good + b"[Desktop Action a]\nExec=a$b\n", good + b"[Bad\n", b"\xff\xfe", good + b"a\x00b\n", good + b"x=1\n" * 1001, b"[Desktop Entry]\n" + b"k=v\n" * 401):
    try:
        errs = b.exec_errors(b.parse_keyfile(bad, "d"), "d", by)
    except b.BundleError:
        continue
    assert errs, bad[:60]
assert raises(b.parse_keyfile, b"x" * 70000, "d")
# the Store's caps
many = [E("bin", "dir", 0o755)] + [E(f"bin/l{i}", "link", 0o777, target="x") for i in range(20001)]
assert raises(b.validate, many, False)
assert raises(b.validate, [E("bin", "dir", 0o755), E("bin/big", "file", 0o755, size=513 * 1024 ** 2)], False)
assert raises(b.validate, [E("bin", "dir", 0o755), E("bin/a", "file", 0o755, size=500 * 1024 ** 2), E("bin/b", "file", 0o755, size=500 * 1024 ** 2),
                           E("bin/c", "file", 0o755, size=100 * 1024 ** 2)], False)
# notification names come from the app id
assert b.notifyrc_ok("share/knotifications6/telamon-gates.notifyrc", "net.eterneon.telamon.gates")
assert b.notifyrc_ok("share/knotifications6/telamon-gates-alerts.notifyrc", "net.eterneon.telamon.gates")
assert b.notifyrc_ok("share/knotifications6/telamon-gates_x.notifyrc", "net.eterneon.telamon.gates")
for bad in ("telamon-other.notifyrc", "telamon-gatesx.notifyrc", "gates.notifyrc", "telamon-gates.txt", "telamon-gates-.x/y.notifyrc"):
    assert not b.notifyrc_ok("share/knotifications6/" + bad, "net.eterneon.telamon.gates"), bad
print("units ok")
EOF
check "the Store's reader rules hold as units (versions, ids, home page, links, names, key files, caps, notification names)" \
    python3 -I "$scratch/units.py" "$here"
mkdir "$scratch/nover"
printf 'cmake_minimum_required(VERSION 3.24)\nproject(nover LANGUAGES NONE)\n' >"$scratch/nover/CMakeLists.txt"
if python3 -I "$bundle_py" version --app-dir "$scratch/nover" --version 1.0.0 >/dev/null 2>&1; then
    bad "--version with a CMake project() that has no VERSION was accepted"; else ok "--version fails when project() has no VERSION"; fi
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
