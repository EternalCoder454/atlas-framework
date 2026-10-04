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
#   tools/open-update-pr.sh publish <owner/repo> <vX.Y.Z> <branch> <in dir>
#       With GH_TOKEN. Never checks the app out and runs nothing from it:
#       builds the commit from git objects (the Cargo.toml rewrite done here
#       again, on the blobs; the lock files from <in dir>, checked), pushes
#       the branch and opens the pull request.
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

# Moves the pins in the Cargo.toml files named, in place. Only inline tables
# naming this repository; the pin key may come before or after `git`.
move_pins() {
    # shellcheck disable=SC2016 # perl, not shell, expands these
    TAG=$tag perl -0pi -e '
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
    mapfile -t manifests < <(blobs_named Cargo.toml HEAD)
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

# "name version source" of every package in the lock file $1, sorted.
lock_packages() {
    awk '/^\[\[package\]\]/ { if (n != "") print n, v, src; n = v = src = ""; next }
         /^name = /    { n = $3 } /^version = / { v = $3 } /^source = / { src = $3 }
         END { if (n != "") print n, v, src }' "$1" | tr -d '"' | sort
}

# Cargo.lock: from the lock job, only over lock files the base has, and only
# what looks like one. Anything else means the lock job went wrong (or was
# made to): nothing is pushed.
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
        [ "$(stat -c %s "$file")" -gt 8388608 ] ||
        ! head -n1 "$file" | grep -qx '# This file is automatically @generated by Cargo.'; then
        echo "::error::$repo: unexpected lock file from the lock job: ${lock//[[:cntrl:]]/?}"
        refused=1
        continue
    fi
    git update-index --cacheinfo "100644,$(git hash-object -w "$file"),$lock"
    changed=1
    # For the reviewer: anything else the lock job changed.
    git cat-file blob "$base:$lock" >"$tmp/lock.old"
    while IFS= read -r p; do
        others+=("$lock: ${p//[^A-Za-z0-9 ._:\/+#?=-]/?}")
    done < <(comm -13 <(lock_packages "$tmp/lock.old") <(lock_packages "$file") |
        grep -vE "^atlas-framework-[a-z0-9-]+ [^ ]+ git\+https://github\.com/EternalCoder454/atlas-framework(\.git)?\?tag=${tag//./\\.}#[0-9a-f]{40}\$" || true)
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
# left over from a run that failed before opening one.
git push --quiet --force "$url" "$commit:refs/heads/$branch"

if [ ${#others[@]} -eq 0 ]; then
    other_text="Other packages in Cargo.lock: none changed."
else
    other_text="Other packages added or changed in Cargo.lock (check that the new atlas-framework needs them):"
    for p in "${others[@]}"; do other_text+=$'\n'"- \`$p\`"; done
fi
gh pr create --repo "$repo" --head "$branch" \
    --title "Move atlas-framework to $tag" \
    --body "atlas-framework $tag was released: https://github.com/EternalCoder454/atlas-framework/releases/tag/$tag

This moves every atlas-framework crate to the tag and updates Cargo.lock. Check the release notes for anything the app should adopt, and whether its \`atlas-ui >=\` requirement (spec) or \`ui:\` in \`app!\` should rise with it. Build with \`--locked\`.

$other_text

Opened by atlas-framework's release workflow."
