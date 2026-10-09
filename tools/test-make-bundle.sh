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
set(FAKE_LINK "" CACHE STRING "a symlink to add, relative to the prefix")
set(FAKE_LINK_TARGET "" CACHE STRING "where it points")

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
if(FAKE_LINK)
    install(CODE "file(CREATE_LINK \"${FAKE_LINK_TARGET}\" \"${CMAKE_INSTALL_PREFIX}/${FAKE_LINK}\" SYMBOLIC)")
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
if(FAKE STREQUAL "connect")
    # an install step that reaches out (to a listener the test runs on 127.0.0.1)
    install(CODE [=[
        execute_process(COMMAND python3 -c "import os, socket; socket.create_connection(('127.0.0.1', int(os.environ['FAKE_PORT'])), 2)"
                        RESULT_VARIABLE r ERROR_QUIET)
        if(NOT r EQUAL 0)
            message(FATAL_ERROR "the build cannot reach 127.0.0.1")
        endif()
    ]=])
endif()
if(FAKE STREQUAL "env")
    install(CODE [=[
        file(WRITE "${CMAKE_INSTALL_PREFIX}/share/net.example.fake/env.txt"
             "CARGO_NET_OFFLINE=$ENV{CARGO_NET_OFFLINE}\nLC_ALL=$ENV{LC_ALL}\nTZ=$ENV{TZ}\nSOURCE_DATE_EPOCH=$ENV{SOURCE_DATE_EPOCH}\nproxy=$ENV{https_proxy}\nZSTD_CLEVEL=$ENV{ZSTD_CLEVEL}\n")
    ]=])
endif()
if(FAKE STREQUAL "touch-lock")
    install(CODE "file(APPEND \"${CMAKE_CURRENT_SOURCE_DIR}/Cargo.lock\" \"# changed by the build\\n\")")
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

# The same bytes whoever builds it and wherever: another checkout path, another
# locale, time zone and umask, other zstd and Python settings in the environment.
cp -r "$repo" "$scratch/another-checkout"
out3=$scratch/out3
if (cd "$scratch/another-checkout" && umask 077 && LC_ALL=tr_TR.UTF-8 LANG=de_DE.UTF-8 TZ=Pacific/Auckland PYTHONHASHSEED=random \
        ZSTD_CLEVEL=3 ZSTD_NBTHREADS=8 PYTHONUTF8=0 HOME="$scratch" TMPDIR="$scratch" \
        "$make_bundle" --out "$out3" --min-os-version 44 --build-dir "$scratch/build-out3") >"$scratch/log" 2>&1; then
    check "a build from another path, locale, time zone, umask and zstd settings: archive is byte-identical" cmp "$archive" "$out3/net.example.fake-1.2.3-x86_64.tar.zst"
    check "... and so is the manifest" cmp "$manifest" "$out3/telamon-bundle.json"
else
    bad "a build in another environment works" "$(tail -n 20 "$scratch/log")"
fi
if run_make "$scratch/out-env" --min-os-version 44 --cmake-arg -DFAKE=env &&
    mkdir "$scratch/env-x" && zstd -dc -- "$scratch"/out-env/*.tar.zst | tar -xf - -C "$scratch/env-x" share/net.example.fake/env.txt; then
    want="CARGO_NET_OFFLINE=true
LC_ALL=C
TZ=UTC
SOURCE_DATE_EPOCH=1767225600
proxy=http://127.0.0.1:9
ZSTD_CLEVEL="
    if [ "$(cat "$scratch/env-x/share/net.example.fake/env.txt")" = "$want" ]; then ok "the build runs with LC_ALL=C, TZ=UTC, SOURCE_DATE_EPOCH, CARGO_NET_OFFLINE, a dead proxy and no ZSTD_CLEVEL"
    else bad "the build's environment" "$(cat "$scratch/env-x/share/net.example.fake/env.txt")"; fi
else bad "a build that records its environment" "$(tail -n 8 "$scratch/log")"; fi
# A name that is not ASCII, built under the C locale (the script sets it): kept, listed, verified and reproducible.
nonascii=$(printf 'share/net.example.fake/caf\xc3\xa9-\xe4\xb8\xad.txt')
if run_make "$scratch/out-u1" --min-os-version 44 --cmake-arg "-DFAKE_FILE=$nonascii" && run_make "$scratch/out-u2" --min-os-version 44 --cmake-arg "-DFAKE_FILE=$nonascii" --stage "$scratch/utf-stage" &&
    python3 -I "$bundle_py" verify "$scratch"/out-u1/*.tar.zst "$scratch/out-u1/telamon-bundle.json" >/dev/null &&
    zstd -dc -- "$scratch"/out-u1/*.tar.zst | tar --quoting-style=literal -tf - | grep -qxF "$nonascii" && cmp "$scratch"/out-u1/*.tar.zst "$scratch"/out-u2/*.tar.zst; then
    ok "a non-ASCII file name is packed as UTF-8 (pax), verified and reproducible"
else bad "a non-ASCII file name" "$(tail -n 8 "$scratch/log")"; fi

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

# ------------------------------------------------------ no network in the build
# shellcheck disable=SC2016 # the ${} are CMake's
# A CMake file that downloads is refused before anything is configured (comments are not read) ...
for variant in 'include(FetchContent)\nFetchContent_Declare(x URL https://example.invalid/x.tgz)\nFetchContent_MakeAvailable(x)' \
    'ExternalProject_Add(x GIT_REPOSITORY https://example.invalid/x.git)' \
    'file(DOWNLOAD https://example.invalid/x.tgz x.tgz)' \
    'execute_process(COMMAND curl -O https://example.invalid/x)' \
    'execute_process(COMMAND wget https://example.invalid/x)' \
    'execute_process(COMMAND git clone https://example.invalid/x.git)' \
    'execute_process(COMMAND pip install requests)' \
    'file(\n  DOWNLOAD https://example.invalid/x.tgz x.tgz)' \
    'execute_process(COMMAND ${GIT_EXECUTABLE} clone https://example.invalid/x.git)'; do
    rm -rf "$scratch/repo-dl"
    cp -r "$repo" "$scratch/repo-dl"
    printf '\n%b\n' "$variant" >>"$scratch/repo-dl/apps/fake/CMakeLists.txt"
    if (cd "$scratch/repo-dl" && "$make_bundle" --out "$scratch/out-dl" --min-os-version 44 --build-dir "$scratch/build-dl") >"$scratch/log" 2>&1; then
        bad "a CMake file that downloads was accepted: ${variant%%$'\n'*}"
    elif grep -q "downloads something at build time" "$scratch/log" && ! grep -q '^== configure' "$scratch/log"; then
        ok "a CMake file that downloads is refused before configure: ${variant%%$'\n'*}"
    else bad "a CMake file that downloads: ${variant%%$'\n'*}" "$(tail -n 5 "$scratch/log")"; fi
done
rm -rf "$scratch/repo-dl"
cp -r "$repo" "$scratch/repo-dl"
printf '\nmessage(STATUS "an app may link libcurl: find_package(CURL) and CURL::libcurl")\n' >>"$scratch/repo-dl/apps/fake/CMakeLists.txt"
if (cd "$scratch/repo-dl" && "$make_bundle" --out "$scratch/out-dl4" --min-os-version 44 --build-dir "$scratch/build-dl4") >"$scratch/log" 2>&1; then
    ok "linking libcurl (find_package(CURL)) is not a download"; else bad "linking libcurl is not a download" "$(tail -n 5 "$scratch/log")"; fi
rm -rf "$scratch/repo-dl"
cp -r "$repo" "$scratch/repo-dl"
printf '\n# curl, wget, git clone and FetchContent_Declare are only words in a comment here\n' >>"$scratch/repo-dl/apps/fake/CMakeLists.txt"
if (cd "$scratch/repo-dl" && "$make_bundle" --out "$scratch/out-dl2" --min-os-version 44 --build-dir "$scratch/build-dl2") >"$scratch/log" 2>&1; then
    ok "a comment that names curl or FetchContent is not a download"; else bad "a comment is not a download" "$(tail -n 5 "$scratch/log")"; fi
rm -rf "$scratch/repo-dl"
cp -r "$repo" "$scratch/repo-dl"
printf '\nfile(DOWNLOAD https://example.invalid/x.tgz x.tgz TIMEOUT 1)\n' >>"$scratch/repo-dl/apps/fake/CMakeLists.txt"
if (cd "$scratch/repo-dl" && "$make_bundle" --allow-network --out "$scratch/out-dl3" --min-os-version 44 --build-dir "$scratch/build-dl3") >"$scratch/log" 2>&1 ||
    ! grep -q "downloads something at build time" "$scratch/log"; then
    ok "--allow-network skips that refusal"; else bad "--allow-network skips the refusal" "$(tail -n 5 "$scratch/log")"; fi
rm -rf "$scratch/repo-dl" "$scratch/out-dl3"

# ... and a build that reaches out anyway fails where the kernel lets a user make a network namespace
# (unshare -rn; GitHub's hosted runners often do not): the test listens on 127.0.0.1 of THIS namespace.
python3 -I -c "
import socket, sys
s = socket.socket(); s.bind(('127.0.0.1', 0)); s.listen(16)
print(s.getsockname()[1], flush=True)
while True:
    c, _ = s.accept(); c.close()
" >"$scratch/port" 2>/dev/null &
listener=$!
trap 'kill "$listener" 2>/dev/null; rm -rf -- "$scratch"' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$scratch/port" ] && break; sleep 0.2; done
FAKE_PORT=$(cat "$scratch/port") && export FAKE_PORT
if run_make "$scratch/out-net" --min-os-version 44 --allow-network --cmake-arg -DFAKE=connect; then
    ok "(control) the connecting build works when the network is allowed"; else bad "(control) the connecting build" "$(tail -n 8 "$scratch/log")"; fi
if unshare -rn true 2>/dev/null; then
    expect_fail "a build that connects to the network" "the build cannot reach 127.0.0.1" --cmake-arg -DFAKE=connect
else
    ok "(skipped: this kernel gives a user no network namespace; make-bundle.sh says so)"
    run_make "$scratch/out-net2" --min-os-version 44 && check "... and warns that it did not isolate the build" grep -q "cannot make a network namespace" "$scratch/log"
fi
kill "$listener" 2>/dev/null

# The crates of a Rust app are the one download, and locked: cargo is a stand-in that records what it was asked.
mkdir "$scratch/shim"
cat >"$scratch/shim/cargo" <<'EOF'
#!/bin/sh
echo "cargo $* [CARGO_NET_OFFLINE=${CARGO_NET_OFFLINE:-}]" >>"$CARGO_LOG"
case $1 in
fetch) [ -z "${CARGO_SHIM_FAIL:-}" ] || exit 1 ;;
locate-project) while [ $# -gt 0 ]; do [ "$1" = --manifest-path ] && { echo "$2"; exit 0; }; shift; done; exit 1 ;;
*) exit 0 ;;
esac
EOF
chmod +x "$scratch/shim/cargo"
rm -rf "$scratch/repo-rs"
cp -r "$repo" "$scratch/repo-rs"
printf '[package]\nname = "fake"\nversion = "1.2.3"\n' >"$scratch/repo-rs/apps/fake/Cargo.toml"
printf '# lock\n' >"$scratch/repo-rs/apps/fake/Cargo.lock"
export CARGO_LOG=$scratch/cargo.log
: >"$CARGO_LOG"
if (cd "$scratch/repo-rs" && PATH="$scratch/shim:$PATH" "$make_bundle" --out "$scratch/out-rs" --min-os-version 44 --build-dir "$scratch/build-rs") >"$scratch/log" 2>&1; then
    ok "an app with a Cargo.toml builds"
    check "the crates are fetched once, with --locked, before configure" bash -c \
        "[ \"\$(grep -c '^cargo fetch' '$CARGO_LOG')\" = 1 ] && grep -q '^cargo fetch --locked --manifest-path .*/apps/fake/Cargo.toml' '$CARGO_LOG' &&
         grep -n '^== fetch\\|^== configure' '$scratch/log' | head -2 | tail -1 | grep -q configure"
    check "the fetch is the only cargo call that may use the network" bash -c "! grep -v '^cargo fetch\\|^cargo locate-project' '$CARGO_LOG'"
else bad "an app with a Cargo.toml builds" "$(tail -n 8 "$scratch/log")"; fi
rm -rf "$scratch/out-rs"
if (cd "$scratch/repo-rs" && CARGO_SHIM_FAIL=1 PATH="$scratch/shim:$PATH" "$make_bundle" --out "$scratch/out-rs" --min-os-version 44 --build-dir "$scratch/build-rs2") >"$scratch/log" 2>&1; then
    bad "a failing cargo fetch --locked was ignored"; elif grep -q "cargo fetch --locked failed" "$scratch/log" && ! grep -q '^== configure' "$scratch/log"; then
    ok "a cargo fetch --locked that fails (the lock is not up to date) stops the build"; else bad "a failing cargo fetch" "$(tail -n 5 "$scratch/log")"; fi
if (cd "$scratch/repo-rs" && PATH="$scratch/shim:$PATH" "$make_bundle" --out "$scratch/out-rs" --min-os-version 44 --build-dir "$scratch/build-rs3" --cmake-arg -DFAKE=touch-lock) >"$scratch/log" 2>&1; then
    bad "a build that changed Cargo.lock was accepted"; elif grep -q "the build changed .*Cargo.lock" "$scratch/log" && [ ! -e "$scratch/out-rs/telamon-bundle.json" ]; then
    ok "a build that changes Cargo.lock is refused"; else bad "a build that changes Cargo.lock" "$(tail -n 5 "$scratch/log")"; fi
rm -rf "$scratch/repo-rs" "$scratch/out-rs"

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

# --exclude is a glob read inside the stage, and removes only what is really
# inside it: a link in the app's tree that leads elsewhere, or a name with a
# newline in it (it split into two paths once), must not send the removal
# out of the install.
victim=$scratch/victim
mkdir "$victim"
echo "keep me" >"$victim/precious"
expect_fail "--exclude through a symlink that leaves the install" "is not inside the install" \
    --cmake-arg -DFAKE_LINK=share/net.example.fake/out --cmake-arg "-DFAKE_LINK_TARGET=$victim" --exclude 'share/net.example.fake/out/prec*'
check "the file that link led to is still there" bash -c "[ \"\$(cat '$victim/precious')\" = 'keep me' ]"
mkdir -p "$scratch/nl"
echo "keep me" >"$scratch/nl/e"
NL=$'\n'
run_make "$scratch/out-nl" --min-os-version 44 --stage "$scratch/nl/stage" \
    --cmake-arg "-DFAKE_FILE=share/net.example.fake/d$NL../e" --exclude 'share/net.example.fake/d*/e'
check "--exclude does not split a name with a newline into two paths (a file beside the stage survives)" bash -c \
    "[ \"\$(cat '$scratch/nl/e')\" = 'keep me' ]"
expect_fail "a file name with a newline in the list of files holding the stage path" "not relocatable" \
    --stage "$scratch/leak-stage" --cmake-arg "-DFAKE_FILE=bin/a$NL::error::x" --cmake-arg "-DFAKE_CONTENT=$scratch/leak-stage"
check "no line of that output starts a workflow command" bash -c "! grep -q '^::' '$scratch/log'"
expect_fail "a name with a control character in a message" "make-bundle: --exclude .*matches nothing" --exclude "share/nothing$NL::error::x"
check "...and no line of that output starts a workflow command either" bash -c "! grep -q '^::' '$scratch/log'"

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
import gzip, hashlib, io, json, os, subprocess, sys, tarfile
good, outdir, mode = sys.argv[1:4]
src = subprocess.run(["zstd", "-dc", good], capture_output=True, check=True).stdout
members = []
with tarfile.open(fileobj=io.BytesIO(src)) as tf:
    for ti in tf:
        members.append((ti, tf.extractfile(ti).read() if ti.isreg() else None))
epoch = members[0][0].mtime
NAME = "telamon-bundle.json"
out = []
for ti, data in members:
    if mode == "hash" and ti.name == "share/net.example.fake/hello.txt":
        data = b"HELLO from the data directory\n"
    if mode == "mode" and ti.name == "share/net.example.fake/hello.txt":
        ti.mode = 0o666
    if mode == "setuid" and ti.name == "bin/fake-app":
        ti.mode = 0o4755
    if mode == "setgid" and ti.name == "bin/fake-app":
        ti.mode = 0o2755
    if mode == "sticky" and ti.name == "share/net.example.fake/hello.txt":
        ti.mode = 0o1644
    if mode == "dirsetuid" and ti.name == "bin":
        ti.mode = 0o4755
    if mode == "owner" and ti.name == "bin/fake-app":
        ti.uid = 1000
    if mode == "mtime" and ti.name == "bin/fake-app":
        ti.mtime += 5
    if mode == "infmtime" and ti.name == "bin/fake-app":
        ti.pax_headers = {"mtime": "inf"}
    if mode == "nanmtime" and ti.name == "bin/fake-app":
        ti.pax_headers = {"mtime": "nan"}
    out.append((ti, data))
extra = None
more = []
raw = b""          # 512-byte blocks written as they are, after the entries
stream_zeros = 0   # bytes of zeros streamed after the end of the tar
PAD = "share/net.example.fake/"
if mode == "reorder":
    out.reverse()
if mode == "linkdots":
    # d -> .. is share/net.example.fake/sub/.. ; e climbs one more through d
    extra = ("share/net.example.fake/sub/d", b"", tarfile.SYMTYPE, "../..")
    more = [("share/net.example.fake/sub/e", b"", tarfile.SYMTYPE, "d/../../../../bin")]
if mode == "belowlink":
    extra = ("share/net.example.fake/lnk", b"", tarfile.SYMTYPE, "sub")
    more = [("share/net.example.fake/lnk/x", b"x", tarfile.REGTYPE, "")]
if mode == "extra":
    extra = (PAD + "extra.txt", b"not in the manifest\n", tarfile.REGTYPE, "")
if mode == "dotdot":
    extra = ("share/../../evil", b"x", tarfile.REGTYPE, "")
if mode == "absolute":
    extra = ("/etc/evil", b"x", tarfile.REGTYPE, "")
if mode == "dotslash":
    extra = ("./share/net.example.fake/dot.txt", b"x", tarfile.REGTYPE, "")
if mode == "hardlink":
    extra = (PAD + "hard", b"", tarfile.LNKTYPE, "bin/fake-app")
if mode == "fifo":
    extra = (PAD + "fifo", b"", tarfile.FIFOTYPE, "")
if mode == "chrdev":
    extra = (PAD + "null", b"", tarfile.CHRTYPE, "")
if mode == "blkdev":
    extra = (PAD + "disk", b"", tarfile.BLKTYPE, "")
if mode == "symdir":
    extra = ("share/net.example.fake/sub/up", b"", tarfile.SYMTYPE, "../../../..")
if mode == "symabs":
    extra = (PAD + "abs", b"", tarfile.SYMTYPE, "/etc/passwd")
if mode == "toplevel":
    extra = ("lib/libx.so", b"x", tarfile.REGTYPE, "")
if mode == "dupe":
    extra = ("bin/fake-app", b"#!/bin/sh\n", tarfile.REGTYPE, "")
if mode == "longname":
    extra = (PAD + "a" * 300, b"", tarfile.REGTYPE, "")
if mode == "longpath":
    extra = (PAD + "/".join(["d" * 100] * 11) + "/f", b"", tarfile.REGTYPE, "")
if mode == "newlinename":
    extra = (PAD + "a\n::error::pwned", b"", tarfile.REGTYPE, "")
if mode == "bidiname":
    extra = (PAD + "a‮b", b"", tarfile.REGTYPE, "")
if mode == "badutf8":
    extra = (PAD + "x\udcffy", b"", tarfile.REGTYPE, "")
if mode == "submanifest":
    # a *file* called telamon-bundle.json deeper down is an ordinary file, not the manifest
    extra = (PAD + NAME, b'{"schema": 2}\n', tarfile.REGTYPE, "")
if mode == "many":
    more = [(PAD + "bulk", b"", tarfile.DIRTYPE, "")] + [(PAD + f"bulk/f{i:06d}", b"", tarfile.REGTYPE, "") for i in range(100000)]
for name, data, typ, link in ([extra] if extra else []) + more:
    ti = tarfile.TarInfo(name)
    ti.type, ti.linkname, ti.mode, ti.mtime = typ, link, 0o644, epoch
    if typ == tarfile.DIRTYPE:
        ti.mode = 0o755
    if typ == tarfile.SYMTYPE:
        ti.mode = 0o777
    ti.size = len(data) if typ == tarfile.REGTYPE else 0
    out.append((ti, data if typ == tarfile.REGTYPE else None))
if mode == "nulname":
    ti = tarfile.TarInfo(PAD + "nul")
    ti.size, ti.mtime, ti.pax_headers = 0, epoch, {"path": PAD + "a\0b"}
    out.append((ti, b""))
if mode != "reorder":
    out.sort(key=lambda m: m[0].name)

m = json.load(open(os.path.join(os.path.dirname(good), NAME)))
if mode == "submanifest":
    # list the extra file in the manifest and carry the new manifest inside the archive
    name, data = extra[0], extra[1]
    m["files"].append({"path": name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest(), "executable": False})
    m["files"].sort(key=lambda f: f["path"])
    inner = {k: v for k, v in m.items() if k != "archive"}
    inner_bytes = (json.dumps(inner, indent=2, ensure_ascii=False) + "\n").encode()
    out = [(ti, inner_bytes if ti.name == NAME else data) for ti, data in out]
    for ti, data in out:
        if ti.name == NAME:
            ti.size = len(inner_bytes)

def hdr(name, size, typ, mode_=0o644):
    h = bytearray(512)
    h[0:len(name)] = name
    h[100:108] = b"%07o\0" % mode_
    h[108:116] = b"0000000\0"
    h[116:124] = b"0000000\0"
    h[124:136] = b"%011o\0" % size
    h[136:148] = b"%011o\0" % epoch
    h[148:156] = b"        "
    h[156:157] = typ
    h[257:265] = b"ustar\x0000"
    h[148:156] = b"%06o\0 " % (sum(h) & 0o777777)
    return bytes(h)

def blocks(body):
    return body + b"\0" * (-len(body) % 512)

if mode == "rawname":        # a ustar header whose name is not UTF-8
    raw = hdr(b"share/net.example.fake/x\xffy", 0, b"0")
if mode == "bombsize":       # a file header that claims 8 GiB (no data follows)
    raw = hdr(b"share/net.example.fake/big", 0o77777777777, b"0")
if mode == "bombpax":        # an extended header that claims 3 GiB, to be read into memory
    raw = hdr(b"PaxHeader", 3 * 1024 ** 3, b"x") + b"\0" * (1 << 20)
if mode == "sparse":
    raw = hdr(b"share/net.example.fake/sparse", 10, b"S") + b"\0" * 4096
if mode == "paxsparse":      # a PAX 1.0 sparse member: tarfile expands it, the Store's reader does not
    def rec(k, v):
        body = f" {k}={v}\n".encode()
        n = len(body) + 1
        while len(str(n)) + len(body) != n:
            n = len(str(n)) + len(body)
        return f"{n}".encode() + body
    pax = rec("GNU.sparse.major", 1) + rec("GNU.sparse.minor", 0) + rec("GNU.sparse.name", PAD + "sparse") + rec("GNU.sparse.realsize", 1000)
    sdata = blocks(b"1\n0\n10\n") + b"0123456789"
    raw = hdr(b"PaxHeader", len(pax), b"x") + blocks(pax) + hdr(b"GNUSparseFile.0/sparse", len(sdata), b"0") + blocks(sdata)
if mode == "globalpax":
    raw = hdr(b"GlobalHeader", 13, b"g") + blocks(b"13 comment=x\n")
if mode == "bombtail":       # real zeros after the end of the tar, more than the limits allow
    stream_zeros = 1700 * (1 << 20)
junk = b"junk after the end" if mode == "trailing" else b""

buf = io.BytesIO()
tf = tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT)
for ti, data in out:
    tf.addfile(ti, io.BytesIO(data) if data is not None else None)
tar = buf.getvalue() + raw + b"\0" * 1024
tar += b"\0" * (-len(tar) % 10240) + junk
os.makedirs(outdir, exist_ok=True)
name = os.path.basename(good)
path = os.path.join(outdir, name)
if mode == "gzip":
    open(path, "wb").write(gzip.compress(tar))
else:
    with open(path, "wb") as f:
        z = subprocess.Popen(["zstd", "-1" if (stream_zeros or mode == "many") else "-19", "-q", "-c"], stdin=subprocess.PIPE, stdout=f)
        z.stdin.write(tar)
        zeros = bytes(1 << 20)
        for _ in range(stream_zeros >> 20):
            z.stdin.write(zeros)
        z.stdin.close()
        if z.wait() != 0:
            sys.exit("zstd failed")
z = open(path, "rb").read()
m["archive"]["sha256"] = hashlib.sha256(z).hexdigest()
m["archive"]["size"] = len(z)
open(os.path.join(outdir, NAME), "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
EOF
tamper() { # tamper <mode> <message regexp>
    local mode=$1 rx=$2 dir=$scratch/tampered-$1 msg
    python3 -I "$scratch/tamper.py" "$archive" "$dir" "$mode" || { bad "tamper $mode: could not build the test archive"; return; }
    if msg=$(python3 -I "$bundle_py" verify "$dir/$(basename "$archive")" "$dir/telamon-bundle.json" 2>&1); then
        bad "verify accepted an archive with: $mode"
    elif grep -q '^::\|Traceback' <<<"$msg"; then
        bad "verify refused $mode, but its output has a workflow command or a traceback" "$msg"
    elif grep -qE "$rx" <<<"$msg"; then
        ok "verify refuses an archive with: $mode"
    else
        bad "verify refused $mode, but not as expected ($rx)" "$msg"
    fi
    rm -rf -- "$dir"
}
tamper_ok() { # tamper_ok <mode>: an archive that must be accepted
    local mode=$1 dir=$scratch/tampered-$1 msg
    python3 -I "$scratch/tamper.py" "$archive" "$dir" "$mode" || { bad "tamper $mode: could not build the test archive"; return; }
    if msg=$(python3 -I "$bundle_py" verify "$dir/$(basename "$archive")" "$dir/telamon-bundle.json" 2>&1); then
        ok "verify accepts an archive with: $mode"
    else
        bad "verify refused an archive with: $mode" "$msg"
    fi
    rm -rf -- "$dir"
}
tamper hash "sha256 differs from the manifest"
tamper extra "in the archive, not in the manifest"
tamper dotdot "'\\.\\.' component|empty, '\\.' or"
tamper absolute "absolute path"
tamper dotslash "empty, '\\.' or '\\.\\.' component"
tamper hardlink "hard link"
tamper fifo "device or fifo"
tamper chrdev "device or fifo"
tamper blkdev "device or fifo"
tamper symdir "not a relative path inside the tree"
tamper symabs "not a relative path inside the tree"
tamper belowlink "which is a link, not a directory"
tamper toplevel "outside bin/ and share/"
tamper dupe "listed twice"
tamper mode "expected 0755 or 0644"
tamper setuid "mode 4755, expected 0755 or 0644"
tamper setgid "mode 2755, expected 0755 or 0644"
tamper sticky "mode 1644, expected 0755 or 0644"
tamper dirsetuid "directory mode 4755, expected 0755"
tamper owner "expected 0:0"
tamper reorder "not sorted by path"
tamper linkdots "not a relative path inside the tree"
tamper mtime "different modification times"
tamper infmtime "pax header"
tamper nanmtime "pax header"
tamper longname "path component longer than 255"
tamper longpath "path longer than 1024"
tamper newlinename "hidden character"
tamper bidiname "hidden character"
tamper nulname "NUL in a name|hidden character"
tamper badutf8 "pax header|not valid UTF-8"
tamper rawname "not valid UTF-8"
tamper many "larger than the limits"
tamper bombsize "more than 536870912|larger than the limits"
tamper bombpax "pax header that is empty, too large"
tamper bombtail "data after its end marker"
tamper sparse "sparse file"
tamper paxsparse "pax header: only one"
tamper globalpax "global pax header"
tamper trailing "data after its end marker"
tamper gzip "not zstd-compressed"
tamper_ok submanifest
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
# hostile input: messages, the writer, the reader of a tree
assert b.printable("a\n::error::b\x1b[2Jc‮d") == "a\\u000a::error::b\\u001b[2Jc\\u202ed"
assert b.printable("share/été.txt") == "share/été.txt"
assert b.dump({"a": 1}) == '{\n  "a": 1\n}\n'
try:
    b.dump({"a": float("nan")})
    raise SystemExit("dump wrote a NaN")
except ValueError:
    pass
import os, stat, tempfile
tree = tempfile.mkdtemp()
os.makedirs(tree + "/bin")
def refused(fn, *args):
    try:
        fn(*args)
    except b.BundleError as exc:
        return str(exc)
    return None
exe = tree + "/bin/x"
open(exe, "w").write("#!/bin/sh\n")
os.chmod(exe, 0o755)
assert [e.mode for e in b.scan_tree(tree) if e.kind == "file"] == [0o755]
for bits in (0o4755, 0o2755, 0o1755):
    os.chmod(exe, bits)
    msg = refused(b.scan_tree, tree)
    assert msg and "setuid, setgid or sticky" in msg, (oct(bits), msg)
os.chmod(exe, 0o755)
os.mkfifo(tree + "/bin/pipe")
msg = refused(b.scan_tree, tree)
assert msg and "not a directory, file or symlink" in msg, msg
os.unlink(tree + "/bin/pipe")
# a symlink is a link entry, never followed; open_regular refuses one
os.symlink("/etc/passwd", tree + "/bin/lnk")
assert [(e.path, e.kind) for e in b.scan_tree(tree)] == [("bin", "dir"), ("bin/lnk", "link"), ("bin/x", "file")]
assert "cannot read" in (refused(b.open_regular, tree + "/bin/lnk") or "")
assert "not a regular file" in (refused(b.open_regular, tree + "/bin") or "")
# hostile input costs time too: the most links and entries the Store allows, and links that name each other
import time
t0 = time.time()
ents = [E("bin", "dir", 0o755), E("share", "dir", 0o755)] + [E(f"share/l{i:05d}", "link", 0o777, target=f"nothere{i}") for i in range(20000)] \
    + [E(f"share/f{i:05d}", "file", 0o644, size=0) for i in range(19000)]
assert raises(b.validate, ents, False)
assert time.time() - t0 < 10, "20000 dangling links took %.1f s" % (time.time() - t0)
def chain(n):
    es = {"share": E("share", "dir", 0o755), f"share/c{n}": E(f"share/c{n}", "dir", 0o755)}
    es.update({f"share/c{i}": E(f"share/c{i}", "link", 0o777, target=f"c{i + 1}") for i in range(n)})
    return es
assert b.resolve_link("share/l", "c0", chain(30)) == "share/c30"   # a chain of links is followed ...
assert b.resolve_link("share/l", "c0", chain(45)) is None          # ... up to the kernel's 40
loop = {"share": E("share", "dir", 0o755), "share/a": E("share/a", "link", 0o777, target="b"), "share/b": E("share/b", "link", 0o777, target="a")}
assert b.resolve_link("share/l", "a", loop) is None
# a link whose target has many components, each a link to a directory with the same links in it, is cut off
big = {"share": E("share", "dir", 0o755)}
for i in range(60):
    big[f"share/d{i}"] = E(f"share/d{i}", "dir", 0o755)
    big[f"share/d{i}/x"] = E(f"share/d{i}/x", "link", 0o777, target="/".join([f"../d{(i + 1) % 60}/x"] * 8))
t0 = time.time()
b.resolve_link("share/l", "d0/x", big)
assert time.time() - t0 < 2
# a metainfo file is UTF-8 XML without a DOCTYPE, whatever it declares
good_xml = b'<?xml version="1.0" encoding="UTF-8"?>\n<component><id>net.example.fake</id><name>F</name></component>\n'
assert b.parse_metainfo(good_xml, "net.example.fake")["name"] == "F"
assert b.parse_metainfo(good_xml.replace(b"UTF-8", b"utf-8"), "net.example.fake")["name"] == "F"
for bad in (good_xml.replace(b"UTF-8", b"cp037"), good_xml.replace(b"UTF-8", b"ISO-8859-1"), b'<?xml version="1.0" encoding="US-ASCII"?><component/>',
            b'<?xml version="1.0"?><!DOCTYPE component [<!ENTITY a "x">]><component/>', b"\xff\xfe<\0c\0/\0>\0"):
    assert raises(b.parse_metainfo, bad, "net.example.fake"), bad
print("units ok")
EOF
check "tools/test_bundle_rules.py: the archive, path and manifest rules against the Store's, with a seeded fuzzer" \
    python3 -I "$here/test_bundle_rules.py" --cases "${TEST_BUNDLE_CASES:-2000}"
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

# ----------------------------------------------------- hostile manifests
# A manifest is input too: whatever is in it, verify answers with a refusal on
# stderr (exit 1), never with a traceback, and does not read without a limit.
cat >"$scratch/manifests.py" <<'EOF'
import json, os, re, subprocess, sys
archive, manifest, work, bundle_py = sys.argv[1:5]
good = open(manifest, "rb").read()
text = good.decode()
big_int = "1" + "0" * 5000
cases = {
    "empty": b"",
    "an empty object": b"{}\n",
    "an array": b"[]\n",
    "not UTF-8": b"\xff\xfe{}",
    "a byte order mark": b"\xef\xbb\xbf" + good,
    "a repeated key": text.replace('"schema": 1,', '"schema": 1,\n  "schema": 1,', 1).encode(),
    "NaN in a size": text.replace('"size":', '"size": NaN, "x":', 1).encode(),
    "Infinity as the schema": text.replace('"schema": 1', '"schema": Infinity', 1).encode(),
    "a lone surrogate in the name": text.replace('"name": "Fake"', '"name": "\\ud800"', 1).encode(),
    "a 5000-digit number": text.replace('"schema": 1', '"schema": ' + big_int, 1).encode(),
    "100000 nested arrays": b"[" * 100000,
    "100000 nested objects": b'{"a":' * 100000,
    "2 MiB of spaces": good + b" " * (2 * 1024 * 1024),
    "a file that is not JSON": b"<xml/>",
    "a true size": re.sub(r'"size": [0-9]+', '"size": true', text, count=1).encode(),
}
failed = 0
for name, data in cases.items():
    path = os.path.join(work, "m.json")
    open(path, "wb").write(data)
    r = subprocess.run([sys.executable, "-I", bundle_py, "verify", archive, path], capture_output=True, text=True)
    err = r.stderr
    if r.returncode != 1 or "Traceback" in err or not err.startswith("bundle: ") or any(l.startswith("::") for l in err.splitlines()):
        failed += 1
        print(f"FAIL {name}: exit {r.returncode}: {err[:300]!r}")
r = subprocess.run([sys.executable, "-I", bundle_py, "verify", archive, work], capture_output=True, text=True)
if r.returncode != 1 or "Traceback" in r.stderr:
    failed += 1
    print("FAIL a directory as the manifest:", r.stderr[:300])
r = subprocess.run([sys.executable, "-I", bundle_py, "verify", archive, os.path.join(work, "nothing")], capture_output=True, text=True)
if r.returncode != 1 or "Traceback" in r.stderr:
    failed += 1
    print("FAIL a missing manifest:", r.stderr[:300])
print(f"{len(cases) + 2} hostile manifests, {failed} not refused cleanly")
sys.exit(1 if failed else 0)
EOF
mkdir "$scratch/hostile-manifests"
check "verify refuses hostile manifests (duplicate keys, NaN, surrogates, huge numbers, deep nesting, 2 MiB, ...) cleanly, without a traceback" \
    python3 -I "$scratch/manifests.py" "$archive" "$manifest" "$scratch/hostile-manifests" "$bundle_py"

# ----------------------------------------------------------------- signing
# tools/sign-bundle.sh with the real minisign CLI: the signature is made over the
# exact bytes of telamon-bundle.json, in the hashed form ('ED') Telamon Store reads.
if ! command -v minisign >/dev/null; then
    if [ -n "${TELAMON_REQUIRE_MINISIGN:-}" ]; then
        bad "minisign is installed (TELAMON_REQUIRE_MINISIGN is set)"
    else
        echo "skip signing tests: minisign is not installed"
    fi
else
    sign=$here/sign-bundle.sh
    keys=$scratch/keys
    mkdir -m 700 "$keys"
    minisign -G -W -p "$keys/a.pub" -s "$keys/a.key" >/dev/null 2>&1
    printf 'correct horse\ncorrect horse\n' | minisign -G -p "$keys/b.pub" -s "$keys/b.key" >/dev/null 2>&1
    minisign -G -W -p "$keys/c.pub" -s "$keys/c.key" >/dev/null 2>&1
    pub_a=$(sed -n 2p "$keys/a.pub")
    pub_c=$(sed -n 2p "$keys/c.pub")
    fresh() { rm -rf -- "$scratch/sign"; cp -r "$out1" "$scratch/sign"; } # a good bundle directory
    mkdir "$scratch/signshim"
    # A stand-in for minisign in front of the real one: records how it is called (arguments, the
    # environment, the key file's mode and place), then runs the real one.
    cat >"$scratch/signshim/minisign" <<EOF
#!/bin/bash
{
    echo "args: \$*"
    echo "env: \$(env | grep -c '^MINISIGN_')"
    prev=
    for a in "\$@"; do
        if [ "\$prev" = -s ]; then echo "keyfile: \$(stat -c '%a %n %F' -- "\$a") on \$(stat -f -c %T -- "\$a")"; fi
        prev=\$a
    done
} >>"$scratch/signshim.log"
exec $(command -v minisign) "\$@"
EOF
    chmod +x "$scratch/signshim/minisign"

    fresh
    if MINISIGN_KEY=$(cat "$keys/a.key") "$sign" --public-key "$pub_a" "$scratch/sign" >"$scratch/log" 2>&1; then
        ok "sign-bundle signs a good bundle (key without a password)"
    else bad "sign-bundle signs a good bundle" "$(cat "$scratch/log")"; fi
    sig=$scratch/sign/telamon-bundle.json.minisig
    check "minisign -V -p pub -m telamon-bundle.json accepts the signature" minisign -V -p "$keys/a.pub" -m "$scratch/sign/telamon-bundle.json"
    check "...also when the prehashed form is required (-H)" minisign -V -H -p "$keys/a.pub" -m "$scratch/sign/telamon-bundle.json"
    check "...and not with another key" bash -c "! minisign -V -p '$keys/c.pub' -m '$scratch/sign/telamon-bundle.json'"
    check "...and not when the manifest changes by one byte" bash -c \
        "cp '$scratch/sign/telamon-bundle.json' '$scratch/m2.json' && printf ' ' >>'$scratch/m2.json' && ! minisign -V -p '$keys/a.pub' -x '$sig' -m '$scratch/m2.json'"
    check "the signature file is the form minisign-verify reads: four lines, 'ED' (hashed), 74 + 64 bytes, a trusted comment" python3 -I - "$sig" <<'EOF'
import base64, sys
data = open(sys.argv[1], "rb").read()
lines = data.decode().split("\n")
assert len(data) < 4096 and len(lines) == 5 and lines[4] == "", lines
assert lines[0].startswith("untrusted comment: ") and lines[2].startswith("trusted comment: ")
sig = base64.b64decode(lines[1], validate=True)
assert len(sig) == 74 and sig[:2] == b"ED", sig[:2]            # 'Ed' would be the legacy kind the Store refuses
assert len(base64.b64decode(lines[3], validate=True)) == 64     # the signature of the trusted comment
EOF
    check "it leaves the archive and the manifest as they were, and adds only the signature" bash -c \
        "cmp '$scratch/sign/telamon-bundle.json' '$manifest' && cmp '$scratch/sign/$(basename "$archive")' '$archive' && [ \"\$(ls '$scratch/sign' | wc -l)\" = 3 ]"
    check "the output names the key ID and never the key" bash -c \
        "grep -q '$(sed -n 1p "$keys/a.pub" | sed 's/.* //')' '$scratch/log' && ! grep -qF '$(sed -n 2p "$keys/a.key")' '$scratch/log'"

    # the key's way through: a password, the process list, the environment, the disk
    fresh
    : >"$scratch/signshim.log"
    ls /dev/shm >"$scratch/shm.before" 2>/dev/null
    if MINISIGN_KEY=$(cat "$keys/b.key") MINISIGN_PASSWORD='correct horse' PATH="$scratch/signshim:$PATH" bash -x "$sign" --public-key "$(sed -n 2p "$keys/b.pub")" "$scratch/sign" >"$scratch/log" 2>&1; then
        ok "sign-bundle signs with a password-protected key (the password on stdin), under bash -x"
    else bad "sign-bundle signs with a password-protected key" "$(tail -n 5 "$scratch/log")"; fi
    check "...the signature verifies with the key's public key" minisign -V -p "$keys/b.pub" -m "$scratch/sign/telamon-bundle.json"
    check "...neither the key file's content nor the password is in the output, even with tracing on" bash -c \
        "! grep -qF '$(sed -n 2p "$keys/b.key")' '$scratch/log' && ! grep -qF 'correct horse' '$scratch/log'"
    check "...minisign got no key or password in its arguments or environment, and a 0600 file in tmpfs" bash -c \
        "grep -q '^env: 0\$' '$scratch/signshim.log' && ! grep -qF 'correct horse' '$scratch/signshim.log' && ! grep -qF '$(sed -n 2p "$keys/b.key")' '$scratch/signshim.log' && grep -qE '^keyfile: 600 /dev/shm/telamon-sign\\.[A-Za-z0-9]+/minisign\\.key regular file on tmpfs\$' '$scratch/signshim.log'"
    check "...and the key file is gone afterwards" bash -c "[ \"\$(ls /dev/shm 2>/dev/null)\" = \"\$(cat '$scratch/shm.before')\" ]"

    # what it refuses
    fresh
    if MINISIGN_KEY=$(cat "$keys/b.key") MINISIGN_PASSWORD='wrong' "$sign" "$scratch/sign" >"$scratch/log" 2>&1; then
        bad "sign-bundle accepted a wrong password"
    elif [ ! -e "$sig" ] && grep -q "minisign failed" "$scratch/log"; then ok "a wrong password fails and leaves no signature"
    else bad "a wrong password fails cleanly" "$(cat "$scratch/log")"; fi
    fresh
    if MINISIGN_KEY=$(cat "$keys/a.key") "$sign" --public-key "$pub_c" "$scratch/sign" >"$scratch/log" 2>&1; then
        bad "sign-bundle accepted a key that is not the catalog's"
    elif [ ! -e "$sig" ] && grep -q "does not verify with --public-key" "$scratch/log"; then ok "a key that is not the one given as --public-key fails and leaves no signature"
    else bad "a wrong key fails cleanly" "$(cat "$scratch/log")"; fi
    fresh
    if MINISIGN_KEY='TESTSECRETMARKER only one line' "$sign" "$scratch/sign" >"$scratch/log" 2>&1; then
        bad "sign-bundle accepted something that is not a key file"
    elif grep -q "not a minisign secret key file" "$scratch/log" && ! grep -q TESTSECRETMARKER "$scratch/log"; then ok "something that is not a key file is refused, and not printed"
    else bad "a malformed key is refused cleanly" "$(cat "$scratch/log")"; fi
    fresh
    if MINISIGN_KEY=$(cat "$keys/a.key") "$sign" --public-key "not a key" "$scratch/sign" >/dev/null 2>&1; then
        bad "sign-bundle accepted a malformed --public-key"; else ok "a malformed --public-key is refused"; fi
    fresh
    echo "extra" >"$scratch/sign/notes.txt"
    if MINISIGN_KEY=$(cat "$keys/a.key") "$sign" "$scratch/sign" >"$scratch/log" 2>&1; then
        bad "sign-bundle accepted a directory with another file in it"
    elif [ ! -e "$sig" ] && grep -q "not part of the bundle" "$scratch/log"; then ok "a directory with a file that is not part of the bundle is refused"
    else bad "an extra file is refused cleanly" "$(cat "$scratch/log")"; fi
    fresh
    : >"$sig"
    if MINISIGN_KEY=$(cat "$keys/a.key") "$sign" "$scratch/sign" >/dev/null 2>&1; then
        bad "sign-bundle accepted a directory that already has a signature"; else ok "a directory that already has a signature is refused"; fi
    # a bundle that does not verify is not signed: a build can get a valid bundle signed, nothing else
    python3 -I "$scratch/tamper.py" "$archive" "$scratch/sign-bad" hash
    if MINISIGN_KEY=$(cat "$keys/a.key") "$sign" "$scratch/sign-bad" >"$scratch/log" 2>&1; then
        bad "sign-bundle signed a bundle whose file differs from the manifest"
    elif [ ! -e "$scratch/sign-bad/telamon-bundle.json.minisig" ] && grep -q "nothing is signed" "$scratch/log"; then ok "a bundle that does not verify is not signed"
    else bad "a bundle that does not verify is refused cleanly" "$(cat "$scratch/log")"; fi
    python3 -I "$scratch/tamper.py" "$archive" "$scratch/sign-bad2" extra
    cp "$scratch/sign-bad2/telamon-bundle.json" "$scratch/sign-bad2/m.json"
    if MINISIGN_KEY=$(cat "$keys/a.key") "$sign" "$scratch/sign-bad2" >/dev/null 2>&1; then
        bad "sign-bundle signed a bundle with a file the manifest does not list"; else ok "a bundle with a file the manifest does not list is not signed"; fi
    if [ "$(stat -f -c %T "$scratch")" != tmpfs ]; then
        fresh
        if TELAMON_SIGN_TMPDIR=$scratch MINISIGN_KEY=$(cat "$keys/a.key") "$sign" "$scratch/sign" >"$scratch/log" 2>&1; then
            bad "sign-bundle wrote the key to a disk"
        elif grep -q "is not a tmpfs" "$scratch/log" && [ ! -e "$sig" ]; then ok "the key is never written outside tmpfs"
        else bad "a non-tmpfs directory is refused cleanly" "$(cat "$scratch/log")"; fi
    fi

    # the key is never in the environment of anything that parses the bundle: stand-ins for python3
    # and zstd record the secret variables they were started with and their arguments
    mkdir "$scratch/signshim2"
    for prog in python3 zstd; do
        cat >"$scratch/signshim2/$prog" <<EOF
#!/bin/bash
echo "$prog: env=\$(env | grep -c '^MINISIGN_') \$*" >>"$scratch/signshim2.log"
exec $(command -v "$prog") "\$@"
EOF
        chmod +x "$scratch/signshim2/$prog"
    done
    fresh
    : >"$scratch/signshim2.log"
    if MINISIGN_KEY=$(cat "$keys/b.key") MINISIGN_PASSWORD='correct horse' PATH="$scratch/signshim2:$PATH" "$sign" "$scratch/sign" >"$scratch/log" 2>&1 &&
        grep -q 'bundle.py verify' "$scratch/signshim2.log" && grep -q '^zstd:' "$scratch/signshim2.log" && ! grep -qv ' env=0 ' "$scratch/signshim2.log"; then
        ok "in one go, python3 and zstd (which parse the bundle) are started without the key or the password"
    else bad "the key is out of the environment of what parses the bundle" "$(cat "$scratch/log" "$scratch/signshim2.log")"; fi

    # the two steps of the sign job
    fresh
    : >"$scratch/gh-output"
    : >"$scratch/signshim2.log"
    if MINISIGN_KEY=$(cat "$keys/a.key") "$sign" --verify-only "$scratch/sign" >"$scratch/log" 2>&1; then
        bad "the verify step ran with the key in its environment"
    elif grep -q "verify step has the signing key" "$scratch/log" && [ ! -e "$sig" ]; then ok "the verify step refuses to run with the key in its environment"
    else bad "the verify step refuses the key cleanly" "$(cat "$scratch/log")"; fi
    if env -u MINISIGN_KEY -u MINISIGN_PASSWORD GITHUB_OUTPUT="$scratch/gh-output" "$sign" --verify-only "$scratch/sign" >"$scratch/log" 2>&1 &&
        [ ! -e "$sig" ] && grep -qx "manifest-sha256=$(sha256sum "$manifest" | cut -d' ' -f1)" "$scratch/gh-output"; then
        ok "step A (--verify-only) verifies, writes the manifest's hash as an output, and signs nothing"
    else bad "step A verifies and prints the hash" "$(cat "$scratch/log" "$scratch/gh-output")"; fi
    sha=$(sha256sum "$manifest" | cut -d' ' -f1)
    if MINISIGN_KEY=$(cat "$keys/a.key") PATH="$scratch/signshim2:$PATH" "$sign" --sign-only --manifest-sha256 "$sha" --public-key "$pub_a" "$scratch/sign" >"$scratch/log" 2>&1 &&
        minisign -V -H -p "$keys/a.pub" -m "$scratch/sign/telamon-bundle.json" >/dev/null &&
        ! grep -q 'bundle.py\|^zstd:' "$scratch/signshim2.log"; then
        ok "step B (--sign-only) signs a manifest with the hash step A verified, and parses nothing (no bundle.py, no zstd)"
    else bad "step B signs without parsing the archive" "$(cat "$scratch/log" "$scratch/signshim2.log")"; fi
    fresh
    if MINISIGN_KEY=$(cat "$keys/a.key") "$sign" --sign-only --manifest-sha256 "$(printf '0%.0s' {1..64})" "$scratch/sign" >"$scratch/log" 2>&1; then
        bad "step B signed a manifest that is not the verified one"
    elif [ ! -e "$sig" ] && grep -q "is not the file that was verified" "$scratch/log"; then ok "step B refuses a manifest whose hash is not the verified one"
    else bad "step B refuses another manifest cleanly" "$(cat "$scratch/log")"; fi
    if MINISIGN_KEY=$(cat "$keys/a.key") "$sign" --sign-only "$scratch/sign" >/dev/null 2>&1; then
        bad "step B ran without the hash"; else ok "step B needs the hash of step A"; fi
    echo extra >"$scratch/sign/notes.txt"
    if MINISIGN_KEY=$(cat "$keys/a.key") "$sign" --sign-only --manifest-sha256 "$sha" "$scratch/sign" >"$scratch/log" 2>&1; then
        bad "step B signed a directory with another file in it"
    elif [ ! -e "$sig" ] && grep -q "not part of the bundle" "$scratch/log"; then ok "step B refuses a directory that holds anything but the archive and the manifest"
    else bad "step B refuses an extra file cleanly" "$(cat "$scratch/log")"; fi

    # a public key but no signing key is a misconfiguration, not an unsigned release
    fresh
    if env -u MINISIGN_KEY GITHUB_ACTIONS=true "$sign" --public-key "$pub_a" "$scratch/sign" >"$scratch/log" 2>&1; then
        bad "sign-bundle went on without a key although --public-key was given"
    elif [ ! -e "$sig" ] && grep -q "there is no signing key" "$scratch/log" && ! grep -q '^::warning::' "$scratch/log"; then ok "--public-key without a signing key fails"
    else bad "--public-key without a key fails cleanly" "$(cat "$scratch/log")"; fi

    # no key: the release is still made, unsigned, with a warning
    fresh
    : >"$scratch/gh-output"
    if env -u MINISIGN_KEY GITHUB_ACTIONS=true GITHUB_OUTPUT="$scratch/gh-output" "$sign" "$scratch/sign" >"$scratch/log" 2>&1 &&
        [ ! -e "$sig" ] && grep -q "^::warning::.*will not offer an unsigned release" "$scratch/log" &&
        grep -qx 'signed=false' "$scratch/gh-output" && grep -qx "manifest-sha256=$(sha256sum "$manifest" | cut -d' ' -f1)" "$scratch/gh-output"; then
        ok "without a key nothing is signed: a ::warning::, signed=false and the manifest's hash as outputs, exit 0"
    else bad "without a key: a warning and no signature" "$(cat "$scratch/log" "$scratch/gh-output")"; fi
fi

# --------------------------------------------------------------- workflow
# bundle.yml runs the app's build and holds the signing key, so its shape is tested:
# no ${{ }} expression inside a shell script (a tag or an input could carry shell), every
# action pinned by sha, every job with its own permissions, no OIDC token, and a secret
# only in the one step that signs.
cat >"$scratch/workflow.py" <<'EOF'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
lines = text.split("\n")
problems = []
in_run = None
for n, line in enumerate(lines, 1):
    stripped = line.lstrip()
    indent = len(line) - len(stripped)
    if in_run is not None:
        if stripped and indent <= in_run:
            in_run = None
        else:
            if "${{" in line:
                problems.append(f"line {n}: an expression inside a run script: {stripped[:80]}")
            continue
    m = re.match(r"(\s*)(- )?run:\s*(.*)$", line)
    if m:
        key_indent = len(m.group(1)) + (2 if m.group(2) else 0)
        if m.group(3)[:1] in ("|", ">"):
            in_run = key_indent
        elif "${{" in m.group(3):
            problems.append(f"line {n}: an expression in a one-line run: {stripped[:80]}")
    m = re.match(r"\s*(- )?uses:\s*(\S+)", line)
    if m and not m.group(2).startswith("./") and not re.search(r"@[0-9a-f]{40}$", m.group(2)):
        problems.append(f"line {n}: {m.group(2)} is not pinned by a full commit sha")
    if "id-token" in line or "secrets: inherit" in line:
        problems.append(f"line {n}: {stripped}")
    if "${{ secrets." in line and not re.fullmatch(r"\s+MINISIGN_(KEY|PASSWORD): \$\{\{ secrets\.minisign-(key|password) \}\}", line):
        problems.append(f"line {n}: a secret outside the signing step's env: {stripped[:80]}")
jobs = {}
cur = None
section = None
for line in lines:
    if re.match(r"^[a-z_-]+:", line):
        section = line.split(":")[0]
    m = re.match(r"^  ([a-z][a-z0-9_-]*):\s*$", line)
    if section == "jobs" and m:
        cur = m.group(1)
        jobs[cur] = []
    elif section == "jobs" and cur:
        jobs[cur].append(line)
if list(jobs) != ["bundle", "sign", "attach"]:
    problems.append(f"jobs are {list(jobs)}, expected bundle, sign, attach")
for name, body in jobs.items():
    if not any(re.match(r"^    permissions:", l) for l in body):
        problems.append(f"job {name} has no permissions of its own")
    block = "\n".join(body)
    if name != "attach" and re.search(r"contents:\s*write", block):
        problems.append(f"job {name} can write")
    if name == "bundle" and "secrets." in block:
        problems.append("the job that runs the app's build can read a secret")
# the step that parses the bundle has no secret; the step that has the key signs and parses nothing
steps = re.split(r"\n      - ", "\n".join(jobs.get("sign", [])))
for st in steps:
    if "secrets." in st and "--verify-only" in st:
        problems.append("the sign job's verifying step has a secret")
    if "secrets." in st and "--sign-only" not in st:
        problems.append("a secret in a sign step that is not the signing one")
if not any("--verify-only" in st for st in steps) or not any("--sign-only" in st and "secrets.minisign-key" in st for st in steps):
    problems.append("the sign job is not split into a verify step and a signing step")
attach = "\n".join(jobs.get("attach", []))
if "ALLOW_UNSIGNED" not in attach or "keep_draft" not in attach:
    problems.append("attach does not keep an unsigned release a draft")
if "    permissions: {}" not in jobs.get("sign", []):
    problems.append("the sign job has a token")
if "    needs: bundle" not in jobs.get("sign", []) or "    needs: [bundle, sign]" not in jobs.get("attach", []):
    problems.append("sign needs bundle and attach needs both")
if text.count(r"^v[0-9]+(\.[0-9]+)+(-[0-9A-Za-z.-]+)?$") < 3:
    problems.append("the tag is not checked against the version pattern in the three jobs that read it")
for p in problems:
    print("FAIL", p)
sys.exit(1 if problems else 0)
EOF
if [ -f "$here/../.github/workflows/bundle.yml" ]; then
    check "bundle.yml: no expression in a script, pins, permissions per job, no OIDC, secrets only in the signing step, tag checked" \
        python3 -I "$scratch/workflow.py" "$here/../.github/workflows/bundle.yml"
    if [ -f "$here/../template/.github/workflows/bundle.yml" ]; then
        check "the template's caller workflow passes no blanket secrets and no OIDC permission" \
            bash -c "! grep -qE 'secrets: inherit|id-token' '$here/../template/.github/workflows/bundle.yml'"
    fi
fi

echo
echo "test-make-bundle: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
