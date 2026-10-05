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

    dnf -y install rpm-build dnf5-plugins tar gzip git >&2
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
    # Only what git tracks: no untracked files, no build output. A dirty
    # tree would package changes that are in no commit.
    # (The source tree is a bind mount owned by another user: git objects it.)
    git() { command git -c safe.directory="$src" "$@"; }
    if ! dirty=$(git -C "$src" status --porcelain --untracked-files=no); then
        echo "build-rpm: cannot read the git state of $src" >&2
        exit 1
    fi
    if [ -n "$dirty" ] && [ "${ATLAS_ALLOW_DIRTY:-}" != 1 ]; then
        echo "build-rpm: the working tree has uncommitted changes (the package is built from HEAD, without them):" >&2
        echo "$dirty" >&2
        echo "build-rpm: commit them, or set ATLAS_ALLOW_DIRTY=1 to package HEAD anyway" >&2
        exit 1
    fi
    git -C "$src" archive --format=tar.gz --prefix="atlas-framework-$version/" HEAD \
        -o "$top/SOURCES/atlas-framework-$version.tar.gz"

    rpmbuild -bb "${rpmopts[@]}" --define "_topdir $top" "$spec"

    mkdir -p "$out"
    found=0
    while IFS= read -r -d '' rpm; do
        cp -v "$rpm" "$out"/
        found=$((found + 1))
    done < <(find "$top/RPMS" -name '*.rpm' ! -name '*.src.rpm' ! -name '*debuginfo*' ! -name '*debugsource*' -print0)
    if [ "$found" -eq 0 ]; then
        echo "build-rpm: rpmbuild produced no RPM" >&2
        exit 1
    fi
}

main "$@"
exit $?
