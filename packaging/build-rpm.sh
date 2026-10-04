#!/bin/bash
# Build the atlas-framework RPMs inside a fedora:44 container, as root.
#   packaging/build-rpm.sh <out dir> [rpmbuild options]
# The binary RPMs (no source, no debuginfo) are copied to <out dir>.
# ATLAS_BUILD_CACHE=<dir> (optional, such as a podman cache mount) keeps the
# CMake build in <dir>, and builds in a fixed place, so the next build only
# recompiles what changed.
set -euo pipefail

main() {
    out=${1:?usage: build-rpm.sh <out dir> [rpmbuild options]}
    shift
    rpmopts=("$@")

    here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    src=$(dirname "$here")
    spec=$here/atlas-framework.spec
    version=$(awk '/^Version:/ {print $2; exit}' "$spec")

    dnf -y install rpm-build dnf5-plugins tar gzip >&2
    dnf -y builddep "$spec" >&2

    cache=${ATLAS_BUILD_CACHE:-}
    if [ -n "$cache" ]; then
        mkdir -p "$cache"
        cache=$(cd "$cache" && pwd)
        case $cache/ in
            "$src"/*) echo "ATLAS_BUILD_CACHE must be outside the source tree" >&2; exit 1 ;;
        esac
        # CMake's cache holds absolute paths, so the build tree must sit at
        # the same path every time.
        top=$cache/rpmbuild
        rm -rf "$top"
        # Output built with another compiler or Qt can't be trusted: start
        # over when they change. Also when the version does: the sources
        # unpack to a directory named after it, and CMake refuses a build
        # tree made for another source directory.
        toolchain=$(rpm -q gcc-c++ cmake qt6-qtbase-devel qt6-qtdeclarative-devel kf6-kirigami-devel \
            kf6-kwindowsystem-devel kf6-kconfig-devel || true)
        toolchain="atlas-framework-$version
$toolchain"
        if [ "$(cat "$cache/toolchain" 2>/dev/null)" != "$toolchain" ]; then
            rm -rf "$cache/cmake"
            printf '%s\n' "$toolchain" >"$cache/toolchain"
        fi
        rpmopts+=(--define "_atlas_build_cache $cache")
    else
        top=$(mktemp -d)
    fi
    trap 'rm -rf "$top"' EXIT
    mkdir -p "$top"/{SOURCES,BUILD,RPMS,SRPMS,SPECS}
    tar -C "$src" \
        --exclude=./.git --exclude=./out --exclude=./build --exclude=./target \
        --exclude=./template/target --exclude=./template/build \
        --transform "s,^\./,atlas-framework-$version/," \
        -czf "$top/SOURCES/atlas-framework-$version.tar.gz" .

    rpmbuild -bb "${rpmopts[@]}" --define "_topdir $top" "$spec"

    mkdir -p "$out"
    find "$top/RPMS" -name '*.rpm' ! -name '*.src.rpm' ! -name '*debuginfo*' ! -name '*debugsource*' \
        -exec cp -v {} "$out"/ \;
}

main "$@"
exit $?
