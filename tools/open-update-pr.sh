#!/usr/bin/env bash
# Opens a pull request in a Telamon app that moves its telamon-framework crates
# to a release tag. Run by .github/workflows/release.yml in two steps, in two
# separate jobs, because the app's checkout is not trusted (cargo runs what
# its .cargo/config.toml names) and the token can push to every app:
#
#   tools/open-update-pr.sh lock <owner/repo> <vX.Y.Z> <out dir>
#       No token. Clones the app, moves the pins and runs `cargo update` for
#       the telamon-framework crates (and each crate cargo names as a conflict:
#       a raised floor); writes the base commit and the changed
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
# accepts only changes a framework update can make: telamon-framework crates at
# exactly FRAMEWORK_COMMIT, and crates.io packages the app already had or the
# framework's own Cargo.lock names. Anything else, and nothing is pushed.
#
# Every `telamon-framework-*` git dependency on this repository pinned by tag or
# branch becomes `tag = "<vX.Y.Z>"`; one pinned by rev stays a rev, of the
# commit the tag names (an app's CI may require revs, as Notepad's does).
# Nothing else changes: the app's own `telamon-ui >=` requirement is its
# decision.
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
# Only the organisation's own apps: the token in publish can push to all of them.
[[ $repo == EternalCoder454/* ]] || { echo "bad repository: $repo (an app of EternalCoder454)" >&2; exit 2; }
url="https://github.com/$repo.git"
dir=$(realpath -m -- "$dir")
# Manifests larger than this are skipped (and a person moves them by hand).
max_manifest=1048576
# move_pins, list_tree, blobs_named and the checks of publish (tested without a
# network or a token by tools/test-open-update-pr.sh).
# shellcheck source-path=SCRIPTDIR source=lib/update-pr-lib.sh
. "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")/lib/update-pr-lib.sh"

if [ "$mode" = lock ]; then
    # Nothing here may hold a token: this runs code from the app.
    unset GH_TOKEN GITHUB_TOKEN ACTIONS_RUNTIME_TOKEN ACTIONS_ID_TOKEN_REQUEST_TOKEN ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_CACHE_URL ACTIONS_RESULTS_URL
    export RUSTUP_TOOLCHAIN=stable
    # <out dir> is emptied below: only a directory this script made, or an empty one.
    if [ -e "$dir" ] && [ ! -d "$dir" ]; then echo "$dir is not a directory" >&2; exit 2; fi
    if [ -d "$dir" ] && [ -n "$(find "$dir" -mindepth 1 -maxdepth 1 ! -name base ! -name locks ! -name files -print -quit)" ]; then
        echo "$dir holds something this script did not write: not emptying it (use a new directory)" >&2
        exit 2
    fi
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    # The commit the tag names (peeled, for an annotated tag), for rev pins.
    fw_commit=$(git ls-remote https://github.com/EternalCoder454/atlas-framework "refs/tags/$tag" "refs/tags/$tag^{}" |
        sort -k2 | awk 'END { print $1 }')
    [[ $fw_commit =~ ^[0-9a-f]{40}$ ]] || { echo "telamon-framework has no tag $tag" >&2; exit 1; }
    git clone --quiet --depth 1 "$url" "$work/app"
    cd "$work/app"
    base=$(git rev-parse HEAD)
    list_tree HEAD "$work/tree"
    manifests=()
    while IFS= read -r m; do
        if [ "$(stat -c %s "./$m")" -gt "$max_manifest" ]; then
            echo "::warning::$repo: $m is too large to move, do it by hand"
            continue
        fi
        manifests+=("$m")
    done < <(blobs_named Cargo.toml "$work/tree")
    mapfile -t locks < <(blobs_named Cargo.lock "$work/tree")
    rm -rf "$dir"
    mkdir -p "$dir/files"
    printf '%s\n' "$base" >"$dir/base"
    : >"$dir/locks"
    if [ ${#manifests[@]} -gt 0 ]; then
        move_pins "${manifests[@]/#/./}"
    fi
    for lock in "${locks[@]}"; do
        mapfile -t pkgs < <(grep -oE '^name = "telamon-framework-[a-z0-9-]+"' "./$lock" | sed -E 's/.*"(.*)"/\1/' | sort -u)
        [ ${#pkgs[@]} -gt 0 ] || continue
        args=()
        for p in "${pkgs[@]}"; do args+=(-p "$p"); done
        # Only the framework crates, and then each crate cargo names as the
        # conflict: it won't move a crate the app also depends on itself past
        # its lock entry, so when the release raised that crate's floor (zbus,
        # tokio, ...) the update fails until that crate is named too.
        # (--recursive doesn't help when the crate wasn't the framework's
        # dependency in the old lock, such as behind a newly used feature.)
        updated=0
        for _ in $(seq 10); do
            if (cd "$(dirname "./$lock")" && cargo update --quiet --color never "${args[@]}") 2>"$work/update.err"; then
                updated=1; break
            fi
            # shellcheck disable=SC2016 # the backquotes are cargo's
            name=$(sed -nE '0,/^error: failed to select a version for `([A-Za-z0-9_][A-Za-z0-9_-]*)`.*/s//\1/p' "$work/update.err")
            [ -n "$name" ] || break
            # The locked version cargo kept, so `-p` isn't ambiguous when the
            # lock holds two versions of the crate.
            # shellcheck disable=SC2016
            version=$(sed -nE "0,/^ *previously selected package \`$name v([0-9][0-9A-Za-z.+-]*)\`.*/s//\\1/p" "$work/update.err")
            spec=$name${version:+@$version}
            [[ " ${args[*]} " != *" -p $spec "* ]] || break
            echo "::notice::$repo $lock: the release needs a newer $name than the app's lock has; updating it too"
            args+=(-p "$spec")
        done
        if [ $updated = 0 ]; then
            # Cargo's message, which can quote the app's files: bounded, and
            # no line read as a workflow command.
            head -c 20000 "$work/update.err" | tr '\r\000-\010\013\014\016-\037' ' ' | sed 's/^/    /' >&2
            echo "::error::$repo $lock: cargo update failed" >&2
            exit 1
        fi
        rm -f "$work/update.err"
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
[ -f "$fw_lock" ] || { echo "no telamon-framework Cargo.lock at $fw_lock" >&2; exit 2; }
# No lock changed (an app that uses no telamon-framework crate, such as the
# Installer): nothing to open. The artifact upload drops the empty files/, so
# this is checked before the shape below, from the same two plain files.
if lock_output_empty "$dir"; then
    echo "$repo: no lock file needs this release: nothing to open"
    exit 0
fi
# The lock job's output: base, locks and files/, nothing else, no symlinks.
if ! lock_output_shaped "$dir"; then
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
list_tree "$base" "$tmp/tree"
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
    # a dependency written as its own [dependencies.telamon-framework-x]
    # table): a person has to.
    left=$({
        grep -nE '^[[:space:]]*telamon-framework-[a-z0-9-]+[[:space:]]*=.*github\.com/EternalCoder454/atlas-framework' "$tmp/manifest" |
            grep -vF -e "tag = \"$tag\"" -e "rev = \"$fw_commit\"" || true
        grep -nE '^[[:space:]]*\[([^]]*\.)?telamon-framework-[a-z0-9-]+\]' "$tmp/manifest" || true
    })
    if [ -n "$left" ]; then
        left=${left//[[:cntrl:]]/; }
        echo "::warning::$repo: $m not moved to $tag, do it by hand: $left"
    fi
    if ! cmp -s "$tmp/manifest" "$tmp/manifest.old"; then
        git update-index --cacheinfo "100644,$(git hash-object -w "$tmp/manifest"),$m"
        changed=1
    fi
done < <(blobs_named Cargo.toml "$tmp/tree")

# Names of the packages the framework can bring in.
# shellcheck disable=SC2034 # read by lock_change_ok in the library
fw_names=$(lock_packages "$fw_lock" | cut -d' ' -f1 | LC_ALL=C sort -u)
set_fw_sources

# Cargo.lock: from the lock job, only over lock files the base has, only what
# looks like one, and only changes a framework update can make (see the top).
# Anything else means the lock job went wrong (or was made to): nothing is
# pushed.
mapfile -t base_locks < <(blobs_named Cargo.lock "$tmp/tree")
refused=0
others=()
while IFS= read -r lock; do
    [ -n "$lock" ] || continue
    ok=0
    for b in "${base_locks[@]}"; do [ "$b" = "$lock" ] && ok=1; done
    if [ "$ok" != 1 ] || ! file=$(lock_output_file "$dir" "$lock"); then
        echo "::error::$repo: unexpected lock file from the lock job (not one the base has, or not in cargo's current format): ${lock//[[:cntrl:]]/?}"
        refused=1
        continue
    fi
    git cat-file blob "$base:$lock" >"$tmp/lock.old"
    if ! lock_change_ok "$tmp/lock.old" "$file" "$lock"; then
        refused=1
        continue
    fi
    # A lock file the base already has changes nothing (the lock job lists only the ones it changed):
    # no commit, no pull request, for it.
    cmp -s "$tmp/lock.old" "$file" && continue
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
commit=$(GIT_AUTHOR_NAME="telamon-framework release" GIT_AUTHOR_EMAIL=atlas@eterneon.net \
    GIT_COMMITTER_NAME="telamon-framework release" GIT_COMMITTER_EMAIL=atlas@eterneon.net \
    git commit-tree "$tree" -p "$base" -m "Move telamon-framework to $tag")
# Forced: no pull request uses the branch (checked above), so it can only be
# left over from a run that failed before opening one. A branch of that name
# whose tip is not this script's is someone's work and left alone (a guard
# against accidents: anyone can write that author). The lease makes the push
# fail if the branch changed after this look.
old=$(git ls-remote "$url" "refs/heads/$branch" | cut -f1)
if [ -n "$old" ]; then
    git fetch --quiet --depth 1 "$url" "$old"
    if [ "$(git log -1 --format='%an <%ae>' "$old")" != "telamon-framework release <atlas@eterneon.net>" ]; then
        echo "::error::$repo already has a branch $branch that the release did not make: nothing pushed"
        exit 1
    fi
fi
git push --quiet --force-with-lease="refs/heads/$branch:$old" "$url" "$commit:refs/heads/$branch"
cd /

if [ ${#others[@]} -eq 0 ]; then
    other_text="Other packages in Cargo.lock: none changed."
else
    other_text="Other crates.io packages added or changed in Cargo.lock (check that the new telamon-framework needs them):"
    for p in "${others[@]}"; do other_text+=$'\n'"- \`$p\`"; done
fi
gh pr create --repo "$repo" --head "$branch" \
    --title "Move telamon-framework to $tag" \
    --body "telamon-framework $tag was released: https://github.com/EternalCoder454/atlas-framework/releases/tag/$tag

This moves every telamon-framework crate to the tag and updates Cargo.lock. Check the release notes for anything the app should adopt, and whether its \`telamon-ui >=\` requirement (spec) or \`ui:\` in \`app!\` should rise with it. Build with \`--locked\`.

$other_text

Opened by telamon-framework's release workflow."
