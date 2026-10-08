#!/bin/bash
# Build a Telamon app and pack it as a native bundle (docs/BUNDLES.md): the
# <id>-<version>-x86_64.tar.zst and its telamon-bundle.json. Run it from the
# app's repository root, INSIDE the fedora:44 build container with the app's
# build dependencies and telamon-ui installed. It starts no container.
#
#   tools/make-bundle.sh [--app-dir apps/foo] [--spec packaging/foo.spec]
#                        [--out DIR] [--version X.Y.Z] [--stage DIR]
#
#   --app-dir DIR    the CMake source dir (default: the one apps/*/CMakeLists.txt,
#                    else ./CMakeLists.txt)
#   --spec FILE      the RPM spec whose `BuildRequires: telamon-ui >= X` becomes
#                    min_telamon_ui (default: the one packaging/*.spec; without a
#                    spec, the installed telamon-ui)
#   --out DIR        where the two files go (default: bundle-out)
#   --version V      must agree with project(... VERSION) in CMake; a tag's
#                    version, with -prerelease allowed (v1.0.0-beta.1)
#   --stage DIR      the install prefix the app is built for: a new or empty
#                    directory (default: a fresh temporary one)
#   --build-dir DIR  the CMake build tree (default: a temporary one)
#   --exclude PATH   leave a path (a glob, relative to the tree) out of the
#                    bundle, such as a legacy .desktop file; repeatable
#   --cmake-arg ARG  an extra argument for the cmake configure step; repeatable
#   --min-telamon-ui X, --min-os-version N   override what is read from the spec
#                    and /etc/os-release
#   --keep           keep the temporary directories
#
# SOURCE_DATE_EPOCH is the commit time (git log -1) unless it is set. The
# result is checked again from the archive (tools/bundle.py verify).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bundle_py=$here/bundle.py

die() {
    echo "make-bundle: $*" >&2
    exit 1
}

app_dir=
spec=
out=bundle-out
version=
stage=
build=
keep=0
min_ui=
min_os=
excludes=()
cmake_args=()

need_arg() { [ "$2" -ge 2 ] || die "$1 needs a value"; }
while [ $# -gt 0 ]; do
    case $1 in
    --app-dir) need_arg "$1" $#; app_dir=$2; shift 2 ;;
    --spec) need_arg "$1" $#; spec=$2; shift 2 ;;
    --out) need_arg "$1" $#; out=$2; shift 2 ;;
    --version) need_arg "$1" $#; version=$2; shift 2 ;;
    --stage) need_arg "$1" $#; stage=$2; shift 2 ;;
    --build-dir) need_arg "$1" $#; build=$2; shift 2 ;;
    --exclude) need_arg "$1" $#; excludes+=("$2"); shift 2 ;;
    --cmake-arg) need_arg "$1" $#; cmake_args+=("$2"); shift 2 ;;
    --min-telamon-ui) need_arg "$1" $#; min_ui=$2; shift 2 ;;
    --min-os-version) need_arg "$1" $#; min_os=$2; shift 2 ;;
    --keep) keep=1; shift ;;
    -h | --help) sed -n '2,31p' "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
    esac
done

for tool in cmake python3 zstd grep; do
    command -v "$tool" >/dev/null || die "$tool is not installed (this runs in the fedora:44 build container)"
done
[ "$(uname -m)" = x86_64 ] || die "bundles are x86_64 only, this is $(uname -m)"

# Which app: the only apps/*/CMakeLists.txt, else ./CMakeLists.txt.
if [ -z "$app_dir" ]; then
    mapfile -t found < <(compgen -G 'apps/*/CMakeLists.txt' || true)
    if [ ${#found[@]} -eq 1 ]; then
        app_dir=$(dirname "${found[0]}")
    elif [ ${#found[@]} -eq 0 ] && [ -f CMakeLists.txt ]; then
        app_dir=.
    else
        die "cannot tell which app to bundle (${#found[@]} apps/*/CMakeLists.txt): pass --app-dir"
    fi
fi
[ -f "$app_dir/CMakeLists.txt" ] || die "$app_dir/CMakeLists.txt does not exist"
app_dir=$(cd "$app_dir" && pwd)

if [ -z "$spec" ]; then
    mapfile -t found < <(compgen -G 'packaging/*.spec' || true)
    if [ ${#found[@]} -eq 1 ]; then
        spec=${found[0]}
    fi
fi
if [ -n "$spec" ]; then
    [ -f "$spec" ] || die "spec $spec does not exist"
fi

# The version first, so a mismatch fails before the build.
version=$(python3 -I "$bundle_py" version --app-dir "$app_dir" ${version:+--version "$version"}) || exit 1

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    SOURCE_DATE_EPOCH=$(git -c safe.directory='*' -C "$app_dir" log -1 --format=%ct 2>/dev/null || true)
fi
[[ ${SOURCE_DATE_EPOCH:-} =~ ^[0-9]+$ ]] || die "no SOURCE_DATE_EPOCH and no git commit to take it from: set SOURCE_DATE_EPOCH"
export SOURCE_DATE_EPOCH
unset DESTDIR

work=
cleanup() {
    [ "$keep" = 1 ] || { [ -z "$work" ] || rm -rf -- "$work"; }
}
trap cleanup EXIT
work=$(mktemp -d "${TMPDIR:-/tmp}/telamon-bundle.XXXXXX")
[ -n "$stage" ] || stage=$work/stage
[ -n "$build" ] || build=$work/build
case $stage in /*) ;; *) stage=$PWD/$stage ;; esac
case $build in /*) ;; *) build=$PWD/$build ;; esac
case $out in /*) ;; *) out=$PWD/$out ;; esac
if [ -e "$stage" ] && [ -n "$(ls -A -- "$stage" 2>/dev/null)" ]; then
    die "--stage $stage is not empty"
fi
[ "${#stage}" -ge 12 ] || die "--stage $stage is too short: a path that short could match anything in a binary"
mkdir -p -- "$stage"

# The prefix is the stage, not /usr, so a binary that learns its install paths
# at build time carries the stage path, which the check below then finds
# (built for /usr it would carry /usr/share and fail only on a user's computer).
# The remapped prefixes keep the source, build and cargo paths out of
# panic messages and __FILE__.
rustflags=()
if [ -n "${CARGO_ENCODED_RUSTFLAGS:-}" ]; then
    IFS=$'\x1f' read -r -a rustflags <<<"$CARGO_ENCODED_RUSTFLAGS"
elif [ -n "${RUSTFLAGS:-}" ]; then
    read -r -a rustflags <<<"$RUSTFLAGS"
fi
cargo_home=${CARGO_HOME:-$HOME/.cargo}
for pair in "$PWD=." "$build=build" "$cargo_home=cargo"; do
    rustflags+=("--remap-path-prefix=$pair")
done
CARGO_ENCODED_RUSTFLAGS=$(IFS=$'\x1f'; echo "${rustflags[*]}")
export CARGO_ENCODED_RUSTFLAGS
unset RUSTFLAGS
if [[ $PWD$build$cargo_home == *[[:space:]]* ]]; then
    echo "make-bundle: warning: a path has a space: C++ paths are not remapped" >&2
else
    export CFLAGS="${CFLAGS:+$CFLAGS }-ffile-prefix-map=$PWD=. -ffile-prefix-map=$build=build"
    export CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }-ffile-prefix-map=$PWD=. -ffile-prefix-map=$build=build"
fi

gen=()
command -v ninja >/dev/null && gen=(-G Ninja)
echo "== configure ($app_dir, version $version)" >&2
cmake -S "$app_dir" -B "$build" "${gen[@]}" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$stage" "${cmake_args[@]}" >&2
# An app that forces its own prefix would install somewhere else, over /usr.
got=$(sed -n 's/^CMAKE_INSTALL_PREFIX:[A-Z]*=//p' "$build/CMakeCache.txt")
[ "$got" = "$stage" ] || die "the app's CMake sets CMAKE_INSTALL_PREFIX to $got, not $stage: make it only a default (if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT))"
echo "== build" >&2
cmake --build "$build" >&2
echo "== install" >&2
cmake --install "$build" >&2
[ -n "$(ls -A -- "$stage")" ] || die "cmake --install put nothing in $stage"

# Legacy files an app still installs for its RPM (an old .desktop file, a
# renamed command's link) do not go in a bundle.
for pattern in "${excludes[@]}"; do
    case $pattern in /* | *..*) die "--exclude $pattern: a path inside the tree, without '..'" ;; esac
    matched=0
    while IFS= read -r -d '' path; do
        rm -rf -- "$path"
        matched=1
    done < <(cd "$stage" && compgen -G "$pattern" | while IFS= read -r f; do printf '%s\0' "$stage/$f"; done)
    [ "$matched" = 1 ] || die "--exclude $pattern matches nothing in the install"
done

# Relocatable: the tree may not name where it was built or staged.
echo "== relocatability" >&2
leaks=$(grep -rlaF --binary-files=text -e "$stage" -e "$build" -- "$stage" || true)
if [ -n "$leaks" ]; then
    echo "make-bundle: these files hold the stage or build path, so the app is not relocatable:" >&2
    echo "${leaks//"$stage"\//  }" >&2
    die "find the path with: grep -a -o -e '${stage}[^[:space:]]*' <file>; an app finds its data relative to its executable (docs/BUNDLES.md, \"Data\")"
fi

echo "== pack" >&2
python3 -I "$bundle_py" pack --tree "$stage" --out "$out" --epoch "$SOURCE_DATE_EPOCH" --version "$version" \
    ${spec:+--spec "$spec"} ${min_ui:+--min-telamon-ui "$min_ui"} ${min_os:+--min-os-version "$min_os"}
