#!/usr/bin/env bash
# Opens a pull request in an Atlas app that moves its atlas-framework crates
# to a release tag. Run by .github/workflows/release.yml in two steps, in two
# separate jobs, because the app's checkout is not trusted (cargo runs what
# its .cargo/config.toml names) and the token can push to every app:
#
#   tools/open-update-pr.sh lock <owner/repo> <vX.Y.Z> <out dir>
#       No token. Clones the app, moves the pins and runs `cargo update` for
#       the atlas-framework crates; writes the base commit and the changed
#       Cargo.lock files to <out dir>. Nothing else from that job is used.
#
#   FRAMEWORK_COMMIT=<sha> tools/open-update-pr.sh publish <owner/repo> <vX.Y.Z> <branch> <in dir>
#       With GH_TOKEN. Never checks the app out and runs nothing from it:
#       builds the commit from git objects (the Cargo.toml rewrite done here
#       again, on the blobs; the lock files from <in dir>, checked), pushes
#       the branch and opens the pull request. FRAMEWORK_COMMIT is the commit
#       the tag names; run it from a checkout of that commit, whose Cargo.lock
#       says which crates the framework can bring in.
#
# A lock job could be made to forge another app's lock files, so publish
# accepts only changes a framework update can make: atlas-framework crates at
# exactly FRAMEWORK_COMMIT, and crates.io packages the app already had or the
# framework's own Cargo.lock names. Anything else, and nothing is pushed.
#
# Every `atlas-framework-*` git dependency on this repository, pinned by rev,
# tag or branch, becomes `tag = "<vX.Y.Z>"`. Nothing else changes: the app's
# own `atlas-ui >=` requirement is its decision.
set -euo pipefail

usage() {
    echo "usage: open-update-pr.sh lock <owner/repo> <vX.Y.Z> <out dir>" >&2
    echo "       open-update-pr.sh publish <owner/repo> <vX.Y.Z> <branch> <in dir>" >&2
    exit 2
}
[ $# -ge 1 ] || usage
mode=$1
shift
case $mode in
lock) [ $# -eq 3 ] || usage; repo=$1 tag=$2 dir=$3 ;;
publish) [ $# -eq 4 ] || usage; repo=$1 tag=$2 branch=$3 dir=$4 ;;
*) usage ;;
esac
[[ $repo =~ ^[A-Za-z0-9_-][A-Za-z0-9._-]*/[A-Za-z0-9_-][A-Za-z0-9._-]*$ ]] || { echo "bad repository: $repo" >&2; exit 2; }
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "bad tag: $tag" >&2; exit 2; }
if [ "$mode" = publish ]; then
    [[ $branch =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "bad branch: $branch" >&2; exit 2; }
fi
url="https://github.com/$repo.git"
dir=$(realpath -m -- "$dir")
# Manifests larger than this are skipped (and a person moves them by hand).
max_manifest=1048576

# Moves the pins in the Cargo.toml files named, in place. Only inline tables
# naming this repository; the pin key may come before or after `git`.
move_pins() {
    # shellcheck disable=SC2016 # perl, not shell, expands these
    TAG=$tag timeout 60 perl -0pi -e '
        s#(atlas-framework-[a-z0-9-]+\s*=\s*\{[^}\n]*?github\.com/EternalCoder454/atlas-framework(?:\.git)?"[^}\n]*?)\b(?:rev|tag|branch)\s*=\s*"[^"]*"#$1tag = "$ENV{TAG}"#g;
        s#(atlas-framework-[a-z0-9-]+\s*=\s*\{[^}\n]*?)\b(?:rev|tag|branch)\s*=\s*"[^"]*"([^}\n]*?github\.com/EternalCoder454/atlas-framework(?:\.git)?")#$1tag = "$ENV{TAG}"$2#g;
    ' -- "$@"
}

# Paths of regular-file blobs (mode 100644) named $1 in tree-ish $2 of the
# repository in the current directory, one per line. Symlinks (120000) and
# anything under one are not blobs of this kind, so they never appear.
blobs_named() {
    local entry meta path
    git ls-tree -r -z "$2" | while IFS= read -r -d '' entry; do
        meta=${entry%%$'\t'*}
        path=${entry#*$'\t'}
        [ "${meta%% *}" = 100644 ] || continue
        [[ $path == *[[:cntrl:]]* ]] && continue
        case $path in "$1" | */"$1") printf '%s\n' "$path" ;; esac
    done
}

if [ "$mode" = lock ]; then
    # Nothing here may hold a token: this runs code from the app.
    unset GH_TOKEN GITHUB_TOKEN
    export RUSTUP_TOOLCHAIN=stable
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    git clone --quiet --depth 1 "$url" "$work/app"
    cd "$work/app"
    base=$(git rev-parse HEAD)
    manifests=()
    while IFS= read -r m; do
        if [ "$(stat -c %s "./$m")" -gt "$max_manifest" ]; then
            echo "::warning::$repo: $m is too large to move, do it by hand"
            continue
        fi
        manifests+=("$m")
    done < <(blobs_named Cargo.toml HEAD)
    mapfile -t locks < <(blobs_named Cargo.lock HEAD)
    rm -rf "$dir"
    mkdir -p "$dir/files"
    printf '%s\n' "$base" >"$dir/base"
    : >"$dir/locks"
    if [ ${#manifests[@]} -gt 0 ]; then
        move_pins "${manifests[@]/#/./}"
    fi
    for lock in "${locks[@]}"; do
        mapfile -t pkgs < <(grep -oE '^name = "atlas-framework-[a-z0-9-]+"' "./$lock" | sed -E 's/.*"(.*)"/\1/' | sort -u)
        [ ${#pkgs[@]} -gt 0 ] || continue
        args=()
        for p in "${pkgs[@]}"; do args+=(-p "$p"); done
        (cd "$(dirname "./$lock")" && cargo update --quiet "${args[@]}")
        if ! git diff --quiet -- "./$lock"; then
            mkdir -p "$dir/files/$(dirname "$lock")"
            cp -- "./$lock" "$dir/files/$lock"
            printf '%s\n' "$lock" >>"$dir/locks"
        fi
    done
    echo "$repo: base $base, $(wc -l <"$dir/locks") lock file(s) updated"
    exit 0
fi

# publish: GH_TOKEN is set. Git reads no config but ours, runs no hooks, and
# never writes a work tree.
if [ -n "$(gh pr list --repo "$repo" --head "$branch" --state all --json number --jq '.[].number')" ]; then
    echo "$repo: a pull request for $branch already exists"
    exit 0
fi
fw_commit=${FRAMEWORK_COMMIT:-}
[[ $fw_commit =~ ^[0-9a-f]{40}$ ]] || { echo "FRAMEWORK_COMMIT is not a commit id: $fw_commit" >&2; exit 2; }
fw_lock=$(dirname -- "$(realpath -- "$0")")/../Cargo.lock
[ -f "$fw_lock" ] || { echo "no atlas-framework Cargo.lock at $fw_lock" >&2; exit 2; }
# The lock job's output: base, locks and files/, nothing else, no symlinks.
if [ "$(find "$dir" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort | tr '\n' ' ')" != "base files locks " ] ||
    [ -L "$dir/base" ] || [ ! -f "$dir/base" ] || [ -L "$dir/locks" ] || [ ! -f "$dir/locks" ] ||
    [ -L "$dir/files" ] || [ ! -d "$dir/files" ]; then
    echo "::error::$repo: the lock job's output is not what it writes: nothing pushed" >&2
    exit 1
fi
base=$(head -n1 "$dir/base")
[[ $base =~ ^[0-9a-f]{40}$ ]] || { echo "$repo: bad base commit from the lock job" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=$tmp/gitconfig
git config --global core.hooksPath /dev/null
git config --global credential.https://github.com.helper '!gh auth git-credential'
head=$(git ls-remote "$url" HEAD | cut -f1)
if [ "$base" != "$head" ]; then
    echo "::warning::$repo moved on while the release ran ($base, now $head): run the release's update again"
    exit 1
fi
git init --quiet --bare "$tmp/repo"
cd "$tmp/repo"
git fetch --quiet --depth 1 "$url" "$base"
export GIT_INDEX_FILE=$tmp/index
git read-tree "$base"
changed=0

# Cargo.toml: rewritten here from the blobs.
while IFS= read -r m; do
    if [ "$(git cat-file -s "$base:$m")" -gt "$max_manifest" ]; then
        echo "::warning::$repo: ${m//[[:cntrl:]]/?} is too large to move, do it by hand"
        continue
    fi
    git cat-file blob "$base:$m" >"$tmp/manifest"
    cp "$tmp/manifest" "$tmp/manifest.old"
    move_pins "$tmp/manifest"
    # What the rewrite could not move (an inline table without a pin key, or
    # a dependency written as its own [dependencies.atlas-framework-x]
    # table): a person has to.
    left=$({
        grep -nE '^[[:space:]]*atlas-framework-[a-z0-9-]+[[:space:]]*=.*github\.com/EternalCoder454/atlas-framework' "$tmp/manifest" |
            grep -vF "tag = \"$tag\"" || true
        grep -nE '^[[:space:]]*\[([^]]*\.)?atlas-framework-[a-z0-9-]+\]' "$tmp/manifest" || true
    })
    if [ -n "$left" ]; then
        left=${left//[[:cntrl:]]/; }
        echo "::warning::$repo: $m not moved to $tag, do it by hand: $left"
    fi
    if ! cmp -s "$tmp/manifest" "$tmp/manifest.old"; then
        git update-index --cacheinfo "100644,$(git hash-object -w "$tmp/manifest"),$m"
        changed=1
    fi
done < <(blobs_named Cargo.toml "$base")

# Whether the lock file $1 is written exactly as cargo writes one: the
# header, `version = N`, then [[package]] tables of name, version, source,
# checksum and a dependencies list, one key per line, each at most once. Any
# other TOML (other spacing, indentation, other tables, inline arrays) could
# hide a package from lock_packages, so it is refused.
lock_shaped() {
    LC_ALL=C awk '
        NR == 1 { if ($0 != "# This file is automatically @generated by Cargo.") exit 1; next }
        inarr && /^ "[^"\\]+",$/ { next }
        inarr && /^\]$/ { inarr = 0; next }
        inarr { exit 1 }
        /^$/ || /^# / { next }
        !pkg && /^version = [0-9]+$/ && !top++ { next }
        /^\[\[package\]\]$/ { pkg = 1; split("", seen); next }
        pkg && /^(name|version|source|checksum) = "[^" \\]+"$/ && !seen[$1]++ { next }
        pkg && /^dependencies = \[$/ && !seen["dependencies"]++ { inarr = 1; next }
        { exit 1 }
        END { if (inarr) exit 1 }' "$1"
}

# "name version source" of every package in the lock file $1, sorted. Only
# for files lock_shaped accepts.
lock_packages() {
    awk '/^\[\[package\]\]/ { if (n != "") print n, v, src; n = v = src = ""; next }
         /^name = /    { n = $3 } /^version = / { v = $3 } /^source = / { src = $3 }
         END { if (n != "") print n, v, src }' "$1" | tr -d '"' | sort
}

# Names of the packages the framework can bring in.
fw_names=$(lock_packages "$fw_lock" | cut -d' ' -f1 | sort -u)
fw_source="git+https://github.com/EternalCoder454/atlas-framework?tag=$tag#$fw_commit"
fw_source_git="git+https://github.com/EternalCoder454/atlas-framework.git?tag=$tag#$fw_commit"
crates_io="registry+https://github.com/rust-lang/crates.io-index"

# Cargo.lock: from the lock job, only over lock files the base has, only what
# looks like one, and only changes a framework update can make (see the top).
# Anything else means the lock job went wrong (or was made to): nothing is
# pushed.
mapfile -t base_locks < <(blobs_named Cargo.lock "$base")
refused=0
others=()
while IFS= read -r lock; do
    [ -n "$lock" ] || continue
    ok=0
    for b in "${base_locks[@]}"; do [ "$b" = "$lock" ] && ok=1; done
    file=$dir/files/$lock
    real=$(realpath -e -- "$file" 2>/dev/null || true)
    if [ "$ok" != 1 ] || [ "$real" != "$(realpath -- "$dir/files")/$lock" ] || [ ! -f "$file" ] ||
        [ "$(stat -c %s "$file")" -gt 8388608 ] || ! lock_shaped "$file"; then
        echo "::error::$repo: unexpected lock file from the lock job (not one the base has, or not in cargo's current format): ${lock//[[:cntrl:]]/?}"
        refused=1
        continue
    fi
    git cat-file blob "$base:$lock" >"$tmp/lock.old"
    base_names=$(lock_packages "$tmp/lock.old" | cut -d' ' -f1 | sort -u)
    bad=0
    while read -r name version source; do
        shown="${lock//[^A-Za-z0-9 ._\/-]/?}: ${name//[^A-Za-z0-9._-]/?} ${version//[^A-Za-z0-9.+-]/?}"
        if [[ $name == atlas-framework-* ]]; then
            if [ "$source" = "$fw_source" ] || [ "$source" = "$fw_source_git" ]; then
                continue
            fi
        elif [ "$source" = "$crates_io" ] &&
            grep -qxF -- "$name" <<<"$base_names"$'\n'"$fw_names"; then
            # For the reviewer: anything else the update changed.
            others+=("$shown")
            continue
        fi
        echo "::error::$repo: the lock job's $shown is not from crates.io or atlas-framework $tag (${source//[^A-Za-z0-9._:\/+#?=-]/?})"
        bad=1
    done < <(comm -13 <(lock_packages "$tmp/lock.old") <(lock_packages "$file"))
    if [ "$bad" = 1 ]; then
        refused=1
        continue
    fi
    git update-index --cacheinfo "100644,$(git hash-object -w "$file"),$lock"
    changed=1
done <"$dir/locks"
if [ "$refused" = 1 ]; then
    echo "$repo: nothing pushed" >&2
    exit 1
fi

if [ "$changed" = 0 ]; then
    echo "$repo: nothing to change"
    exit 0
fi
tree=$(git write-tree)
commit=$(GIT_AUTHOR_NAME="atlas-framework release" GIT_AUTHOR_EMAIL=atlas@eterneon.net \
    GIT_COMMITTER_NAME="atlas-framework release" GIT_COMMITTER_EMAIL=atlas@eterneon.net \
    git commit-tree "$tree" -p "$base" -m "Move atlas-framework to $tag")
# Forced: no pull request uses the branch (checked above), so it can only be
# left over from a run that failed before opening one. A branch of that name
# whose tip is not this script's is someone's work and left alone (a guard
# against accidents: anyone can write that author). The lease makes the push
# fail if the branch changed after this look.
old=$(git ls-remote "$url" "refs/heads/$branch" | cut -f1)
if [ -n "$old" ]; then
    git fetch --quiet --depth 1 "$url" "$old"
    if [ "$(git log -1 --format='%an <%ae>' "$old")" != "atlas-framework release <atlas@eterneon.net>" ]; then
        echo "::error::$repo already has a branch $branch that the release did not make: nothing pushed"
        exit 1
    fi
fi
git push --quiet --force-with-lease="refs/heads/$branch:$old" "$url" "$commit:refs/heads/$branch"
cd /

if [ ${#others[@]} -eq 0 ]; then
    other_text="Other packages in Cargo.lock: none changed."
else
    other_text="Other crates.io packages added or changed in Cargo.lock (check that the new atlas-framework needs them):"
    for p in "${others[@]}"; do other_text+=$'\n'"- \`$p\`"; done
fi
gh pr create --repo "$repo" --head "$branch" \
    --title "Move atlas-framework to $tag" \
    --body "atlas-framework $tag was released: https://github.com/EternalCoder454/atlas-framework/releases/tag/$tag

This moves every atlas-framework crate to the tag and updates Cargo.lock. Check the release notes for anything the app should adopt, and whether its \`atlas-ui >=\` requirement (spec) or \`ui:\` in \`app!\` should rise with it. Build with \`--locked\`.

$other_text

Opened by atlas-framework's release workflow."
