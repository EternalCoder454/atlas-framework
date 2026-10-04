#!/usr/bin/env bash
# Opens a pull request in an Atlas app that moves its atlas-framework crates
# to a release tag. Run by .github/workflows/release.yml; GH_TOKEN must be
# able to push branches and open pull requests in the app's repository.
#
#   tools/open-update-pr.sh <owner/repo> <vX.Y.Z> <branch> <work dir>
#
# Every `atlas-framework-*` git dependency on this repository, pinned by rev,
# tag or branch, becomes `tag = "<vX.Y.Z>"`, and Cargo.lock follows. Nothing
# else changes: the app's own `atlas-ui >=` requirement is its decision.
#
# The app's checkout is not trusted: the token stays out of the environment
# of everything that reads it (perl, cargo) and is used only to push and open
# the pull request. Only regular files are rewritten, and only the manifests
# and lock files are committed.
set -euo pipefail

repo=$1 tag=$2 branch=$3 dir=$4
[[ $repo =~ ^[A-Za-z0-9_-][A-Za-z0-9._-]*/[A-Za-z0-9_-][A-Za-z0-9._-]*$ ]] || { echo "bad repository: $repo" >&2; exit 2; }
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "bad tag: $tag" >&2; exit 2; }
[[ $branch =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "bad branch: $branch" >&2; exit 2; }

if [ -n "$(gh pr list --repo "$repo" --head "$branch" --state all --json number --jq '.[].number')" ]; then
    echo "$repo: a pull request for $branch already exists"
    exit 0
fi

# Runs a command without the token, on the stable toolchain whatever the
# checkout's rust-toolchain.toml says.
untrusted() { env -u GH_TOKEN -u GITHUB_TOKEN RUSTUP_TOOLCHAIN=stable "$@"; }

rm -rf "$dir"
untrusted git clone --quiet --depth 1 "https://github.com/$repo.git" "$dir"
cd "$dir"

manifests=()
while IFS= read -r m; do
    # A symlink could point perl at a file outside the checkout.
    if [ -f "$m" ] && [ ! -L "$m" ]; then manifests+=("./$m"); fi
done < <(git ls-files '*Cargo.toml' 'Cargo.toml')
if [ ${#manifests[@]} -eq 0 ]; then
    echo "$repo: no Cargo.toml"
    exit 0
fi
# Only inline tables naming this repository; the pin key may come before or
# after `git`.
# shellcheck disable=SC2016 # perl, not shell, expands these
TAG=$tag untrusted perl -0pi -e '
    s#(atlas-framework-[a-z]+\s*=\s*\{[^}\n]*?github\.com/EternalCoder454/atlas-framework(?:\.git)?"[^}\n]*?)\b(?:rev|tag|branch)\s*=\s*"[^"]*"#$1tag = "$ENV{TAG}"#g;
    s#(atlas-framework-[a-z]+\s*=\s*\{[^}\n]*?)\b(?:rev|tag|branch)\s*=\s*"[^"]*"([^}\n]*?github\.com/EternalCoder454/atlas-framework(?:\.git)?")#$1tag = "$ENV{TAG}"$2#g;
' -- "${manifests[@]}"

# What the rewrite could not move (no pin key, a multi-line table): a person
# has to.
if left=$(grep -nE '^[[:space:]]*atlas-framework-[a-z]+[[:space:]]*=' -- "${manifests[@]}" | grep -v "tag = \"$tag\""); then
    echo "::warning::$repo: not moved to $tag, do it by hand: ${left//$'\n'/; }"
fi
if git diff --quiet; then
    echo "$repo: nothing to change"
    exit 0
fi

locks=()
while IFS= read -r lock; do
    if [ ! -f "$lock" ] || [ -L "$lock" ]; then continue; fi
    locks+=("./$lock")
    lockdir=$(dirname "$lock")
    mapfile -t pkgs < <(grep -oE '^name = "atlas-framework-[a-z]+"' "$lock" | sed -E 's/.*"(.*)"/\1/' | sort -u)
    [ ${#pkgs[@]} -gt 0 ] || continue
    args=()
    for p in "${pkgs[@]}"; do args+=(-p "$p"); done
    (cd "$lockdir" && untrusted cargo update "${args[@]}")
done < <(git ls-files 'Cargo.lock' '*/Cargo.lock')

git switch --quiet -c "$branch"
git add -- "${manifests[@]}" "${locks[@]}"
git -c user.name="atlas-framework release" -c user.email="atlas@eterneon.net" \
    commit --quiet -m "Move atlas-framework to $tag"
gh auth setup-git
git push --quiet origin "$branch"

gh pr create --repo "$repo" --head "$branch" \
    --title "Move atlas-framework to $tag" \
    --body "atlas-framework $tag was released: https://github.com/EternalCoder454/atlas-framework/releases/tag/$tag

This moves every atlas-framework crate to the tag and updates Cargo.lock. Check the release notes for anything the app should adopt, and whether its \`atlas-ui >=\` requirement (spec) or \`ui:\` in \`app!\` should rise with it.

Opened by atlas-framework's release workflow."
