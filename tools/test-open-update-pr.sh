#!/bin/bash
# Tests tools/open-update-pr.sh and tools/lib/update-pr-lib.sh without a
# network or a token: the apps and the framework are local bare repositories
# (git is wrapped so that https://github.com/ means them), `gh` and `cargo` are
# stand-ins that record what they were asked, and the lock job's output is
# forged by hand, as an attacker who runs code in the lock job could.
#
# The claim under test is the trust split of .github/workflows/release.yml:
# whatever the lock job (which runs an untrusted app's cargo) hands to the
# publish job, publish pushes only a Cargo.toml rewritten from git blobs and
# Cargo.lock files that differ from the app's by what a framework update can
# change, and it says nothing a workflow command could be forged from. Needs
# bash, git, perl, awk, find, realpath, stat and timeout (about 30 s). Also
# runs the lock-file checks under every awk it finds (gawk, mawk, original).
#
#   tools/test-open-update-pr.sh
# shellcheck disable=SC1090 # the library is found through $lib
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script=$here/open-update-pr.sh
lib=$here/lib/update-pr-lib.sh
for tool in git perl awk find realpath stat timeout comm mkfifo; do
    command -v "$tool" >/dev/null || { echo "test-open-update-pr: $tool is not installed" >&2; exit 2; }
done
real_git=$(command -v git)

scratch=$(mktemp -d "${TMPDIR:-/tmp}/telamon-test-update-pr.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
T=$scratch
mkdir -p "$T/bin" "$T/gh/EternalCoder454" "$T/work"
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
tab=$(printf '\t')
export GIT_TERMINAL_PROMPT=0

# ------------------------------------------------------------------ stand-ins
# git: https://github.com/ is the local directory. The script sets
# GIT_ALLOW_PROTOCOL-free defaults and GIT_CONFIG_GLOBAL itself; -c is the
# command line's and still applies.
cat >"$T/bin/git" <<EOF
#!/bin/sh
exec "$real_git" -c "url.file://$T/gh/.insteadOf=https://github.com/" "\$@"
EOF
# gh: pr list answers from \$T/prs, pr create is recorded.
cat >"$T/bin/gh" <<EOF
#!/bin/sh
case "\$1 \$2" in
"pr list") cat "$T/prs" 2>/dev/null; exit 0 ;;
"pr create") shift 2; printf '%s\n' "\$@" >>"$T/pr-create.log"; echo "---" >>"$T/pr-create.log"; exit 0 ;;
*) echo "gh \$*" >>"$T/gh-other.log"; exit 1 ;;
esac
EOF
# cargo: the app's code, as far as the lock job is concerned. It records the
# environment it runs in and writes the Cargo.lock the test asks for.
cat >"$T/bin/cargo" <<EOF
#!/bin/sh
env >"$T/cargo-env.log"
echo "\$PWD \$*" >>"$T/cargo-calls.log"
if [ -n "\${FAKE_CARGO_LOCK:-}" ]; then cp "\$FAKE_CARGO_LOCK" Cargo.lock; fi
if [ -n "\${FAKE_CARGO_FAIL_ONCE:-}" ] && [ ! -e "$T/cargo-failed" ]; then
    : >"$T/cargo-failed"
    echo "error: failed to select a version for \\\`zbus\\\`." >&2
    echo "    ... required by package \\\`telamon-framework-core v2.0.7\\\`" >&2
    echo "previously selected package \\\`zbus v4.0.0\\\`" >&2
    exit 101
fi
exit 0
EOF
chmod +x "$T/bin/git" "$T/bin/gh" "$T/bin/cargo"

# ------------------------------------------------------------------ fixtures
sha() { printf '%s' "$1" | cut -c1; }
c40() { printf '%040d' 0 | tr 0 "$1"; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.org GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.org

# the framework: one commit, an annotated tag v2.0.7 (the script peels it)
git init -q --bare "$T/gh/EternalCoder454/atlas-framework"
mkdir "$T/work/fw"
(cd "$T/work/fw" && git init -q . && echo fw >README && git add README && git commit -q -m fw &&
    git tag -a -m release v2.0.7 && git push -q "$T/gh/EternalCoder454/atlas-framework" HEAD:refs/heads/main refs/tags/v2.0.7)
fw_commit=$(git -C "$T/work/fw" rev-parse 'v2.0.7^{commit}')
old_commit=$(c40 b)

# a crates.io crate the framework's own Cargo.lock has (publish allows those, besides the app's own)
fw_crate=$(awk '/^name = /{n=$3} /^source = "registry/{print n; exit}' "$here/../Cargo.lock" | tr -d '"')
[ -n "$fw_crate" ] || { echo "test-open-update-pr: no crates.io package in $here/../Cargo.lock" >&2; exit 2; }
crates_io='registry+https://github.com/rust-lang/crates.io-index'
fwsrc_old="git+https://github.com/EternalCoder454/atlas-framework?tag=v2.0.6#$old_commit"
fwsrc_new="git+https://github.com/EternalCoder454/atlas-framework?tag=v2.0.7#$fw_commit"

write_manifest() {
    cat >"$1" <<EOF
[package]
name = "app"
version = "0.1.0"

[dependencies]
telamon-framework-core = { git = "https://github.com/EternalCoder454/atlas-framework", tag = "v2.0.6" }
telamon-framework-ui = { tag = "v2.0.6", git = "https://github.com/EternalCoder454/atlas-framework.git" }
telamon-framework-system = { git = "https://github.com/EternalCoder454/atlas-framework", rev = "$old_commit" }
telamon-framework-logging = { git = "https://github.com/EternalCoder454/atlas-framework", branch = "main" }
telamon-framework-polkit = { git = "https://github.com/someone/else", tag = "v1.0.0" }
$fw_crate = "1"

[dependencies.telamon-framework-flatpak]
git = "https://github.com/EternalCoder454/atlas-framework"
tag = "v2.0.6"
EOF
}
write_lock() { # write_lock <file> <fw source> <crate version> <crate checksum>
    cat >"$1" <<EOF
# This file is automatically @generated by Cargo.
# It is not intended for manual editing.
version = 4

[[package]]
name = "app"
version = "0.1.0"
dependencies = [
 "$fw_crate",
 "telamon-framework-core",
]

[[package]]
name = "$fw_crate"
version = "$3"
source = "$crates_io"
checksum = "$4"

[[package]]
name = "telamon-framework-core"
version = "2.0.7"
source = "$2"
EOF
}
sum1=$(c40 a)aaaaaaaaaaaaaaaaaaaaaaaa
sum2=$(c40 d)dddddddddddddddddddddddd
write_lock "$T/lock-old" "$fwsrc_old" 1.0.100 "$sum1"
write_lock "$T/lock-new" "$fwsrc_new" 1.0.200 "$sum2"

new_app() { # new_app <name>: a bare repository with the manifest and the old lock; prints nothing
    local name=$1 w=$T/work/$1
    mkdir -p "$w"
    git init -q --bare "$T/gh/EternalCoder454/$name.git"
    (cd "$w" && git init -q . && write_manifest Cargo.toml && cp "$T/lock-old" Cargo.lock && mkdir -p crates/inner &&
        write_manifest crates/inner/Cargo.toml && cp "$T/lock-old" crates/inner/Cargo.lock &&
        git add -A && git commit -q -m app && git push -q "$T/gh/EternalCoder454/$name.git" HEAD:refs/heads/main)
    git --git-dir="$T/gh/EternalCoder454/$name.git" symbolic-ref HEAD refs/heads/main
}
new_app app
app_git=$T/gh/EternalCoder454/app.git
base=$(git --git-dir="$app_git" rev-parse HEAD)
branch=telamon-framework-v2.0.7

# out_good <dir>: the lock job's output for a good update of the two locks in the app
out_good() {
    rm -rf "$1"
    mkdir -p "$1/files/crates/inner"
    printf '%s\n' "$base" >"$1/base"
    printf '%s\n' Cargo.lock crates/inner/Cargo.lock >"$1/locks"
    cp "$T/lock-new" "$1/files/Cargo.lock"
    cp "$T/lock-new" "$1/files/crates/inner/Cargo.lock"
}
reset_remote() {
    git --git-dir="$app_git" update-ref -d "refs/heads/$branch" 2>/dev/null
    : >"$T/prs"
    rm -f "$T/pr-create.log" "$T/gh-other.log"
}
# publish <dir> [tag] [branch] [repo]: runs the script; the output is in $log, the status in $rc
publish() {
    local dir=$1 tg=${2:-v2.0.7} br=${3:-$branch} rp=${4:-EternalCoder454/app}
    log=$T/publish.log
    (cd "$T" && FRAMEWORK_COMMIT=$fw_commit GH_TOKEN=not-a-token PATH="$T/bin:$PATH" timeout 120 "$script" publish "$rp" "$tg" "$br" "$dir") >"$log" 2>&1
    rc=$?
}
pushed() { git --git-dir="$app_git" rev-parse --verify -q "refs/heads/$branch" >/dev/null; }
# refused <name> <regexp>: the last publish failed with that message and pushed nothing
refused() {
    if [ "$rc" = 0 ]; then bad "$1: was accepted" "$(tail -n 8 "$log")"
    elif pushed; then bad "$1: failed but a branch was pushed" "$(tail -n 8 "$log")"
    elif ! grep -qE -- "$2" "$log"; then bad "$1: refused, but not as expected ($2)" "$(tail -n 8 "$log")"
    else ok "$1: refused, nothing pushed"; fi
    forged_output "$1"
}
# No line of the output may start a workflow command we did not mean, and no raw control byte may reach the log.
forged_output() {
    if grep -qE '^::(set-output|set-env|add-mask|add-path|save-state|stop-commands|echo)' "$log" ||
        LC_ALL=C grep -q $'[\r\033\a\b\f\v]' "$log" ||
        grep -vE '^(::(error|warning|notice)::|EternalCoder454/|usage:|bad |FRAMEWORK_COMMIT|no |    |[a-z-]+: |$)' "$log" | grep -q .; then
        bad "$1: the output could forge a workflow command or holds a control byte" "$(grep -vE '^(::(error|warning|notice)::|EternalCoder454/)' "$log" | cat -v | head -n 5)"
    fi
}

# ---------------------------------------------------------- publish: the good path
reset_remote
out_good "$T/out"
publish "$T/out"
if [ "$rc" = 0 ] && pushed; then
    ok "a good update is pushed"
    tmpclone=$T/clone
    rm -rf "$tmpclone"
    git clone -q --branch "$branch" "file://$app_git" "$tmpclone" 2>/dev/null
    check "the commit has the old base as its only parent" bash -c "[ \"\$(git -C '$tmpclone' rev-list --parents -n1 HEAD)\" = \"\$(git -C '$tmpclone' rev-parse HEAD) $base\" ]"
    check "the author is the release workflow's" bash -c "[ \"\$(git -C '$tmpclone' log -1 --format='%an <%ae>')\" = 'telamon-framework release <atlas@eterneon.net>' ]"
    check "Cargo.toml: tag, tag-before-git, branch pins move to the tag; a rev moves to the commit" bash -c \
        "grep -q 'telamon-framework-core = { git = \"https://github.com/EternalCoder454/atlas-framework\", tag = \"v2.0.7\" }' '$tmpclone/Cargo.toml' &&
         grep -q 'telamon-framework-ui = { tag = \"v2.0.7\", git = ' '$tmpclone/Cargo.toml' &&
         grep -q 'rev = \"$fw_commit\"' '$tmpclone/Cargo.toml' &&
         grep -q 'telamon-framework-logging = { git = \"https://github.com/EternalCoder454/atlas-framework\", tag = \"v2.0.7\" }' '$tmpclone/Cargo.toml'"
    check "Cargo.toml: another repository's telamon-framework-* and plain crates are untouched" bash -c \
        "grep -q 'telamon-framework-polkit = { git = \"https://github.com/someone/else\", tag = \"v1.0.0\" }' '$tmpclone/Cargo.toml' && grep -q '^$fw_crate = \"1\"' '$tmpclone/Cargo.toml'"
    check "Cargo.toml: a [dependencies.telamon-framework-x] table is not rewritten, and the log says so" bash -c \
        "grep -q '^tag = \"v2.0.6\"' '$tmpclone/Cargo.toml' && grep -q '::warning::EternalCoder454/app: Cargo.toml not moved to v2.0.7' '$log'"
    check "both Cargo.lock files are the lock job's" bash -c "cmp '$tmpclone/Cargo.lock' '$T/lock-new' && cmp '$tmpclone/crates/inner/Cargo.lock' '$T/lock-new'"
    check "the pull request is opened against the branch with the tag in the title" bash -c \
        "grep -qx -- '--head' '$T/pr-create.log' && grep -qx '$branch' '$T/pr-create.log' && grep -qx 'Move telamon-framework to v2.0.7' '$T/pr-create.log'"
    check "the pull request body lists the crates.io package the update changed" grep -q "$fw_crate 1.0.200" "$T/pr-create.log"
    check "nothing else from gh was asked" bash -c "[ ! -e '$T/gh-other.log' ]"
    forged_output "good update"
else
    bad "a good update is pushed" "$(tail -n 10 "$log")"
fi
# a second run: the pull request exists
echo 7 >"$T/prs"
publish "$T/out"
if [ "$rc" = 0 ] && grep -q "already exists" "$log"; then ok "a branch that has a pull request is left alone"; else bad "existing pull request" "$(tail -n 4 "$log")"; fi
: >"$T/prs"
# a leftover branch of the release's own is replaced (forced with a lease); someone else's is not
publish "$T/out"
if [ "$rc" = 0 ] && pushed; then ok "a leftover branch the release made is replaced"; else bad "a leftover branch the release made is replaced" "$(tail -n 4 "$log")"; fi
(cd "$T/work/app" && git checkout -q -b mine && echo x >x && git add x && git -c user.name=someone -c user.email=s@example.org commit -q -m mine &&
    git push -q -f "file://$app_git" "mine:refs/heads/$branch")
mine=$(git --git-dir="$app_git" rev-parse "refs/heads/$branch")
publish "$T/out"
if [ "$rc" != 0 ] && grep -q "did not make" "$log" && [ "$(git --git-dir="$app_git" rev-parse "refs/heads/$branch")" = "$mine" ]; then
    ok "a branch of that name that the release did not make is left alone"; else bad "someone else's branch" "rc=$rc $(tail -n 3 "$log")"; fi
git --git-dir="$app_git" update-ref -d "refs/heads/$branch"

# ---------------------------------------------------- publish: forged lock files
# forge <name> <expected message>: copies the good output, applies the edit given by the function body in $edit
variant() { # variant <name> <message regexp> <edit command run in the output directory>
    local name=$1 rx=$2
    shift 2
    reset_remote
    out_good "$T/forged"
    (cd "$T/forged" && eval "$*")
    publish "$T/forged"
    refused "$name" "$rx"
}
append_pkg() { printf '\n[[package]]\nname = "%s"\nversion = "%s"\n%s\n' "$1" "$2" "$3"; }

# sources
variant "a package from a git repository that is not the framework" "not from crates.io or telamon-framework" \
    "$(declare -f append_pkg); append_pkg evil 1.0.0 'source = \"git+https://github.com/attacker/evil#$(c40 e)\"' >>files/Cargo.lock"
variant "a telamon-framework crate from another repository" "not from crates.io or telamon-framework v2.0.7" \
    "sed -i 's|EternalCoder454/atlas-framework|attacker/atlas-framework|' files/Cargo.lock"
variant "a telamon-framework crate at another commit" "not from crates.io or telamon-framework v2.0.7" \
    "sed -i 's|#$fw_commit|#$(c40 c)|' files/Cargo.lock"
variant "a telamon-framework crate at another tag" "not from crates.io or telamon-framework v2.0.7" \
    "sed -i 's|?tag=v2.0.7|?tag=v9.9.9|' files/Cargo.lock"
variant "a telamon-framework crate on a branch" "not from crates.io or telamon-framework v2.0.7" \
    "sed -i 's|?tag=v2.0.7|?branch=main|' files/Cargo.lock"
variant "a telamon-framework crate without a source (a path dependency)" "not from crates.io or telamon-framework v2.0.7" \
    "sed -i '/^source = \"git/d' files/Cargo.lock"
variant "a crates.io name from an altered registry" "not from crates.io or telamon-framework" \
    "sed -i 's|registry+https://github.com/rust-lang/crates.io-index|registry+https://github.com/attacker/index|' files/Cargo.lock"
variant "a crates.io package from a sparse registry" "not from crates.io or telamon-framework" \
    "sed -i 's|registry+https://github.com/rust-lang/crates.io-index|sparse+https://index.crates.io/|' files/Cargo.lock"
variant "a new crates.io package that neither the app nor the framework has" "not from crates.io or telamon-framework" \
    "$(declare -f append_pkg); append_pkg left-pad 9.9.9 'source = \"$crates_io\"' >>files/Cargo.lock"
variant "a new package with no source (a path dependency)" "not from crates.io or telamon-framework" \
    "$(declare -f append_pkg); append_pkg evil-local 1.0.0 '' >>files/Cargo.lock"
variant "a new package from the framework's name with a crates.io source (dependency confusion)" "not from crates.io or telamon-framework" \
    "$(declare -f append_pkg); append_pkg telamon-framework-evil 1.0.0 'source = \"$crates_io\"' >>files/Cargo.lock"
variant "a changed checksum of a crates.io version the app already had" "changed the checksum" \
    "sed -i 's|$sum2|$sum1|; s|^version = \"1.0.200\"|version = \"1.0.100\"|; s|$sum1|$(c40 f)ffffffffffffffffffffffff|' files/Cargo.lock"
# the same attacks, hidden from the parser that reads the lock
variant "a source with a tab: awk reads the address up to it, cargo's URL parser drops the tab" "unexpected lock file" \
    "sed -i 's|^source = \"registry+https://github.com/rust-lang/crates.io-index\"|source = \"registry+https://github.com/rust-lang/crates.io-index${tab}/../../attacker/index\"|' files/Cargo.lock"
variant "a source with a carriage return" "unexpected lock file" \
    "sed -i 's|^\\(source = \"registry.*\\)\"\$|\\1\"\r|' files/Cargo.lock"
variant "a NUL byte in a value" "unexpected lock file" \
    "printf 'name = \"x\\\\000y\"\\n' | tr '\\\\\\\\' '\\\\000' >/dev/null; sed -i 's|^version = \"1.0.200\"|version = \"1.0.2\\x0000\"|' files/Cargo.lock"
variant "a non-ASCII character in a value" "unexpected lock file" \
    "sed -i 's|^version = \"1.0.200\"|version = \"1.0.200\xc3\xa9\"|' files/Cargo.lock"
variant "a space inside a value" "unexpected lock file" \
    "sed -i 's|^version = \"1.0.200\"|version = \"1.0.200 evil\"|' files/Cargo.lock"
variant "a package hidden behind a comment: name = \"x\" # more" "unexpected lock file" \
    "sed -i 's|^name = \"telamon-framework-core\"|name = \"telamon-framework-core\" # [[package]]|' files/Cargo.lock"
variant "a [[patch.unused]] table" "unexpected lock file" \
    "printf '\n[[patch.unused]]\nname = \"serde\"\nversion = \"1.0.0\"\n' >>files/Cargo.lock"
variant "a [metadata] table" "unexpected lock file" "printf '\n[metadata]\n\"checksum x 1\" = \"abc\"\n' >>files/Cargo.lock"
variant "an inline dependencies array" "unexpected lock file" \
    "sed -i 's|^dependencies = \\[|dependencies = [ \"x\" ]\\n# [|' files/Cargo.lock"
variant "an indented key" "unexpected lock file" "sed -i 's|^version = \"2.0.7\"|  version = \"2.0.7\"|' files/Cargo.lock"
variant "a key with other spacing" "unexpected lock file" "sed -i 's|^version = \"2.0.7\"|version=\"2.0.7\"|' files/Cargo.lock"
variant "a key given twice in a package" "unexpected lock file" \
    "sed -i 's|^name = \"telamon-framework-core\"|name = \"telamon-framework-core\"\\nname = \"evil\"|' files/Cargo.lock"
variant "a key before the first package" "unexpected lock file" "sed -i 's|^version = 4|version = 4\\nname = \"x\"|' files/Cargo.lock"
variant "a lock file without cargo's header" "unexpected lock file" "sed -i '1d' files/Cargo.lock"
variant "a multi-line string" "unexpected lock file" "printf 'source = \"\"\"\\nx\"\"\"\\n' >>files/Cargo.lock"
variant "CRLF line ends" "unexpected lock file" "sed -i 's|\$|\r|' files/Cargo.lock"
variant "a lock file that is not text" "unexpected lock file" "head -c 3000 /dev/urandom >files/Cargo.lock"
variant "a lock file over 8 MiB" "unexpected lock file" "yes '# x' | head -c 9000000 >>files/Cargo.lock"
variant "an empty lock file" "unexpected lock file" ": >files/Cargo.lock"

# the listing, the files and the directory
variant "a lock file the base does not have" "unexpected lock file" "mkdir -p files/other && cp files/Cargo.lock files/other/Cargo.lock && echo other/Cargo.lock >>locks"
variant "a listed path with .. in it" "unexpected lock file" "echo 'crates/../Cargo.lock' >>locks"
variant "a listed path that leaves the directory" "unexpected lock file" "echo '../base' >>locks"
variant "an absolute listed path" "unexpected lock file" "echo '/etc/passwd' >>locks"
variant "a listed path with a newline-forged workflow command" "unexpected lock file" \
    "printf 'Cargo.lock\n::set-output name=x::y\n::stop-commands::abc\n' >>locks"
variant "a listed path with control characters" "unexpected lock file" "printf 'x\r::add-mask::tok\033[31m\a\n' >>locks"
variant "a listed path in the shape of an option" "unexpected lock file" "echo '--version' >>locks"
variant "a lock file that is a link to a file outside" "unexpected lock file" "rm files/Cargo.lock && ln -s /etc/hostname files/Cargo.lock"
variant "a lock file that is a link to another lock file in the directory" "unexpected lock file" \
    "rm files/crates/inner/Cargo.lock && ln -s ../../Cargo.lock files/crates/inner/Cargo.lock"
variant "a directory in files/ that is a link" "unexpected lock file" "rm -rf files/crates && ln -s /tmp files/crates"
variant "a lock file that is a named pipe" "unexpected lock file" "rm files/Cargo.lock && mkfifo files/Cargo.lock"
variant "a lock file that is a directory" "unexpected lock file" "rm files/Cargo.lock && mkdir files/Cargo.lock"
variant "an extra file beside base, locks and files" "not what it writes" "echo x >extra"
variant "base that is a link" "not what it writes" "mv base real-base && ln -s real-base base"
variant "locks that is a link" "not what it writes" "mv locks real-locks && ln -s real-locks locks"
variant "files that is a link" "not what it writes" "mv files real-files && ln -s real-files files"
variant "no locks file" "not what it writes" "rm locks"
variant "files that is a plain file" "not what it writes" "rm -rf files && echo x >files"
variant "a base that is not a commit id" "bad base" "echo main >base"
variant "a base in capitals" "bad base" "tr a-f A-F <base >b2 && mv b2 base"
variant "a base of 39 digits" "bad base" "cut -c1-39 base >b2 && mv b2 base"
variant "a base that is another commit" "moved on while the release ran" "c40 e >base; $(declare -f c40); c40 e >base"
variant "a base that is the parent of HEAD (an older tree)" "moved on while the release ran" "git --git-dir='$app_git' rev-parse HEAD >/dev/null; $(declare -f c40); c40 9 >base"

# one forged lock among good ones stops the whole push
variant "one bad lock file among good ones: nothing at all is pushed" "not from crates.io" \
    "$(declare -f append_pkg); append_pkg evil 1.0.0 'source = \"git+https://github.com/attacker/evil#$(c40 e)\"' >>files/crates/inner/Cargo.lock"

# lock job reports nothing to do
reset_remote
rm -rf "$T/empty" && mkdir "$T/empty" && printf '%s\n' "$base" >"$T/empty/base" && : >"$T/empty/locks"
publish "$T/empty"
if [ "$rc" = 0 ] && ! pushed && grep -q "nothing to open" "$log"; then ok "an empty list of locks opens nothing"; else bad "empty list of locks" "$(tail -n 3 "$log")"; fi
echo x >"$T/empty/extra"
publish "$T/empty"
refused "an empty list of locks plus an extra file" "not what it writes"
# a lock identical to the base's, and no pin to move: nothing to change, no empty pull request
reset_remote
new_app plain
git -C "$T/work/plain" rm -q --cached Cargo.toml crates/inner/Cargo.toml
printf '[package]\nname = "plain"\n' >"$T/work/plain/Cargo.toml"
cp "$T/work/plain/Cargo.toml" "$T/work/plain/crates/inner/Cargo.toml"
(cd "$T/work/plain" && git add -A && git commit -q -m plain && git push -q -f "$T/gh/EternalCoder454/plain.git" HEAD:refs/heads/main)
plain_base=$(git --git-dir="$T/gh/EternalCoder454/plain.git" rev-parse HEAD)
rm -rf "$T/same" && mkdir -p "$T/same/files" && printf '%s\n' "$plain_base" >"$T/same/base" && echo Cargo.lock >"$T/same/locks" && cp "$T/lock-old" "$T/same/files/Cargo.lock"
publish "$T/same" v2.0.7 "$branch" EternalCoder454/plain
if [ "$rc" = 0 ] && grep -q "nothing to change" "$log" && ! git --git-dir="$T/gh/EternalCoder454/plain.git" rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
    ok "a lock file the update did not change, and no pins to move: nothing is pushed"; else bad "an unchanged lock" "rc=$rc $(cat "$log")"; fi

# ------------------------------------------------- publish: what the app's blobs can do
# Cargo.toml and Cargo.lock paths in the app's tree that must not be followed or trusted
new_app odd
w=$T/work/odd
(cd "$w" && rm -rf crates && mkdir -p sub 'we ird' && cp Cargo.toml sub/Cargo.toml && cp Cargo.toml 'we ird/Cargo.toml' &&
    ln -s ../Cargo.toml sub/link-target.toml && mkdir link-dir-real && cp Cargo.toml link-dir-real/Cargo.toml && ln -s link-dir-real link-dir &&
    mkdir -p "$(printf 'nl\n::set-output name=x::y')" && cp Cargo.toml "$(printf 'nl\n::set-output name=x::y')/Cargo.toml" &&
    mkdir -p "$(printf 'cr\r::add-mask::z')" && cp Cargo.toml "$(printf 'cr\r::add-mask::z')/Cargo.toml" &&
    mkdir ctl && printf 'telamon-framework-core = { git = "https://github.com/EternalCoder454/atlas-framework" }\r::set-output name=x::y\n\033[31mtelamon-framework-ui = { git = "https://github.com/EternalCoder454/atlas-framework", path = "x" }\n' >ctl/Cargo.toml &&
    head -c 1100000 /dev/zero | tr '\0' ' ' >big.toml && { cat Cargo.toml; cat big.toml; } >sub/Cargo.toml && rm big.toml &&
    git add -A && git commit -q -m odd && git push -q -f "$T/gh/EternalCoder454/odd.git" HEAD:refs/heads/main)
odd_base=$(git --git-dir="$T/gh/EternalCoder454/odd.git" rev-parse HEAD)
odd_git=$T/gh/EternalCoder454/odd.git
rm -rf "$T/oddout" && mkdir -p "$T/oddout/files" && printf '%s\n' "$odd_base" >"$T/oddout/base" && echo Cargo.lock >"$T/oddout/locks" && cp "$T/lock-new" "$T/oddout/files/Cargo.lock"
publish "$T/oddout" v2.0.7 "$branch" EternalCoder454/odd
if [ "$rc" = 0 ] && grep -q 'too large to move' "$log" && git --git-dir="$odd_git" rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
    ok "odd paths in the app's tree: a manifest over 1 MiB is skipped with a warning, the rest is rewritten"
else bad "odd paths in the app's tree" "rc=$rc $(cat "$log")"; fi
rm -rf "$T/oddclone"
git clone -q --branch "$branch" "file://$odd_git" "$T/oddclone" 2>/dev/null
check "... the manifest behind a link is not a blob to rewrite, a path with a space is" bash -c \
    "grep -q 'tag = \"v2.0.7\"' '$T/oddclone/we ird/Cargo.toml' && grep -q 'tag = \"v2.0.6\"' '$T/oddclone/sub/link-target.toml' && grep -q 'tag = \"v2.0.6\"' '$T/oddclone/sub/Cargo.toml'"
check "... a pin the rewrite cannot move is reported, with its control characters made harmless" grep -q "::warning::EternalCoder454/odd: ctl/Cargo.toml not moved to v2.0.7, do it by hand: 1:telamon-framework-core.*; ::set-output" "$log"
check "... and the log has no forged command (control characters in a path never reach it)" bash -c \
    "! grep -E '^::(set-output|add-mask)' '$log' && ! LC_ALL=C grep -q \$'[\\r\\033]' '$log'"
git --git-dir="$odd_git" update-ref -d "refs/heads/$branch"

# a manifest made to be slow for the rewrite: bounded by the 60 s timeout, and in practice far below
new_app slow
(cd "$T/work/slow" && { echo '[dependencies]'; printf 'telamon-framework-core = { git = "https://github.com/EternalCoder454/atlas-framework"'; head -c 900000 /dev/zero | tr '\0' 'a'; echo; } >Cargo.toml &&
    rm -rf crates && git add -A && git commit -q -m slow && git push -q -f "$T/gh/EternalCoder454/slow.git" HEAD:refs/heads/main)
slow_base=$(git --git-dir="$T/gh/EternalCoder454/slow.git" rev-parse HEAD)
rm -rf "$T/slowout" && mkdir -p "$T/slowout/files" && printf '%s\n' "$slow_base" >"$T/slowout/base" && : >"$T/slowout/locks"
start=$(date +%s)
publish "$T/slowout" v2.0.7 "$branch" EternalCoder454/slow
elapsed=$(($(date +%s) - start))
if [ "$elapsed" -lt 20 ]; then ok "a 900 KB inline table with no end takes ${elapsed}s to rewrite"; else bad "a slow manifest took ${elapsed}s (the script's cap is 60)" "$(tail -n 3 "$log")"; fi

# ---------------------------------------------------------------- arguments
args_refused() { # args_refused <name> <args...>
    local name=$1
    shift
    if (cd "$T" && PATH="$T/bin:$PATH" FRAMEWORK_COMMIT=$fw_commit timeout 60 "$script" "$@") >"$T/args.log" 2>&1; then
        bad "arguments: $name was accepted" "$(tail -n 3 "$T/args.log")"
    else ok "arguments: $name is refused"; fi
}
args_refused "no arguments"
args_refused "an unknown mode" frob EternalCoder454/app v2.0.7 x
args_refused "a repository of another owner" publish other/app v2.0.7 b "$T/out"
args_refused "a repository with a semicolon" publish 'EternalCoder454/a;id' v2.0.7 b "$T/out"
args_refused "a repository named .." publish EternalCoder454/.. v2.0.7 b "$T/out"
args_refused "a repository with a space" publish 'EternalCoder454/a b' v2.0.7 b "$T/out"
args_refused "a repository with a newline" publish "$(printf 'EternalCoder454/a\n::set-output name=x::y')" v2.0.7 b "$T/out"
args_refused "a repository that is a URL" publish 'https://evil.example/x/y' v2.0.7 b "$T/out"
args_refused "a repository with extra path" publish EternalCoder454/app/extra v2.0.7 b "$T/out"
args_refused "a tag without a v" publish EternalCoder454/app 2.0.7 b "$T/out"
args_refused "a tag with a prerelease" publish EternalCoder454/app v2.0.7-rc1 b "$T/out"
args_refused "a tag that is a ref expression" publish EternalCoder454/app 'v2.0.7^{}' b "$T/out"
args_refused "a branch with a space" publish EternalCoder454/app v2.0.7 'a b' "$T/out"
# shellcheck disable=SC2016 # a literal $( ) is the point
args_refused "a branch with a shell substitution" publish EternalCoder454/app v2.0.7 'a$(id)' "$T/out"
args_refused "a branch with a newline" publish EternalCoder454/app v2.0.7 "$(printf 'a\nb')" "$T/out"
args_refused "an empty branch" publish EternalCoder454/app v2.0.7 '' "$T/out"
args_refused "a missing in-dir argument" publish EternalCoder454/app v2.0.7 b
if (cd "$T" && PATH="$T/bin:$PATH" GH_TOKEN=x timeout 60 "$script" publish EternalCoder454/app v2.0.7 "$branch" "$T/out") >"$T/args.log" 2>&1; then
    bad "publish without FRAMEWORK_COMMIT was accepted"; elif grep -q "FRAMEWORK_COMMIT is not a commit id" "$T/args.log"; then ok "arguments: publish without FRAMEWORK_COMMIT is refused"; else bad "FRAMEWORK_COMMIT" "$(cat "$T/args.log")"; fi
if (cd "$T" && PATH="$T/bin:$PATH" FRAMEWORK_COMMIT=main GH_TOKEN=x timeout 60 "$script" publish EternalCoder454/app v2.0.7 "$branch" "$T/out") >"$T/args.log" 2>&1; then
    bad "FRAMEWORK_COMMIT=main was accepted"; else ok "arguments: FRAMEWORK_COMMIT must be a full commit id"; fi

# ------------------------------------------------------------------ lock mode
lock() { # lock <out dir> [repo]: runs the lock step with a hostile environment; output in $log, status in $rc
    log=$T/lock.log
    (cd "$T" && GH_TOKEN=secret-gh GITHUB_TOKEN=secret-github ACTIONS_RUNTIME_TOKEN=secret-runtime ACTIONS_ID_TOKEN_REQUEST_TOKEN=secret-oidc \
        ACTIONS_ID_TOKEN_REQUEST_URL=https://example.invalid ACTIONS_CACHE_URL=https://example.invalid PATH="$T/bin:$PATH" \
        timeout 120 "$script" lock "${2:-EternalCoder454/app}" v2.0.7 "$1") >"$log" 2>&1
    rc=$?
}
: >"$T/cargo-calls.log"
rm -rf "$T/lockout"
FAKE_CARGO_LOCK=$T/lock-new lock "$T/lockout"
check_lock() {
    [ "$rc" = 0 ] && [ "$(cat "$T/lockout/base")" = "$base" ] && [ "$(sort "$T/lockout/locks" | tr '\n' ' ')" = "Cargo.lock crates/inner/Cargo.lock " ] &&
        cmp -s "$T/lockout/files/Cargo.lock" "$T/lock-new" && cmp -s "$T/lockout/files/crates/inner/Cargo.lock" "$T/lock-new" &&
        [ "$(find "$T/lockout" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | tr '\n' ' ')" = "base files locks " ]
}
if check_lock; then ok "lock: writes base, locks and files/ for each lock file cargo changed"; else bad "lock: writes the output" "$(tail -n 5 "$log"; find "$T/lockout" 2>&1 | head)"; fi
check "lock: the cargo it runs (the app's code, as far as the job goes) has no token in its environment" bash -c \
    "! grep -E '^(GH_TOKEN|GITHUB_TOKEN|ACTIONS_RUNTIME_TOKEN|ACTIONS_ID_TOKEN_REQUEST_TOKEN|ACTIONS_ID_TOKEN_REQUEST_URL|ACTIONS_CACHE_URL)=' '$T/cargo-env.log' && grep -q '^RUSTUP_TOOLCHAIN=stable' '$T/cargo-env.log'"
check "lock: cargo updates the telamon-framework crates of each lock file, in the lock file's directory" bash -c \
    "grep -q 'update --quiet --color never -p telamon-framework-core' '$T/cargo-calls.log' && grep -q 'crates/inner update' '$T/cargo-calls.log'"
# end to end: what the lock job wrote is accepted by publish
reset_remote
publish "$T/lockout"
if [ "$rc" = 0 ] && pushed; then ok "lock then publish: the lock job's own output is accepted"; else bad "lock then publish" "$(tail -n 8 "$log")"; fi
# the retry loop for a crate cargo names as a conflict
reset_remote
rm -f "$T/cargo-failed"
: >"$T/cargo-calls.log"
rm -rf "$T/lockout2"
FAKE_CARGO_FAIL_ONCE=1 FAKE_CARGO_LOCK=$T/lock-new lock "$T/lockout2"
if [ "$rc" = 0 ] && grep -q 'the release needs a newer zbus' "$log" && grep -q -- '-p zbus@4.0.0' "$T/cargo-calls.log"; then ok "lock: a crate cargo names as the conflict is updated too"; else bad "lock: the conflict retry" "$(tail -n 5 "$log")"; fi
# an output directory that holds other things is not emptied; one that is a file is not touched
rm -rf "$T/precious" && mkdir "$T/precious" && echo keep >"$T/precious/important.txt"
FAKE_CARGO_LOCK=$T/lock-new lock "$T/precious"
if [ "$rc" = 2 ] && [ -f "$T/precious/important.txt" ]; then ok "lock: an out dir with other files in it is refused, not emptied"; else bad "lock: out dir with other files" "rc=$rc $(tail -n 3 "$log")"; fi
echo x >"$T/afile"
FAKE_CARGO_LOCK=$T/lock-new lock "$T/afile"
if [ "$rc" = 2 ] && [ -f "$T/afile" ]; then ok "lock: an out dir that is a file is refused"; else bad "lock: out dir that is a file" "rc=$rc"; fi
FAKE_CARGO_LOCK=$T/lock-new lock "/"
if [ "$rc" = 2 ]; then ok "lock: / as the out dir is refused"; else bad "lock: / as out dir" "rc=$rc $(tail -n 3 "$log")"; fi
# a previous run's own output may be replaced
FAKE_CARGO_LOCK=$T/lock-new lock "$T/lockout"
if check_lock; then ok "lock: the output of an earlier run is replaced"; else bad "lock: replaces its own earlier output" "$(tail -n 4 "$log")"; fi
# no framework crate at all
new_app nofw
(cd "$T/work/nofw" && printf '[package]\nname = "nofw"\n' >Cargo.toml && printf '# This file is automatically @generated by Cargo.\nversion = 4\n\n[[package]]\nname = "nofw"\nversion = "0.1.0"\n' >Cargo.lock &&
    rm -rf crates && git add -A && git commit -q -m nofw && git push -q -f "$T/gh/EternalCoder454/nofw.git" HEAD:refs/heads/main)
rm -rf "$T/nofwout"
lock "$T/nofwout" EternalCoder454/nofw
if [ "$rc" = 0 ] && [ ! -s "$T/nofwout/locks" ]; then ok "lock: an app with no telamon-framework crate lists no lock file"; else bad "lock: no framework crate" "$(tail -n 4 "$log")"; fi
publish "$T/nofwout" v2.0.7 "$branch" EternalCoder454/nofw
if [ "$rc" = 0 ] && grep -q "nothing to open" "$log"; then ok "... and publish opens nothing"; else bad "publish with no lock changed" "$(tail -n 3 "$log")"; fi
rm -rf "$T/missing"
lock "$T/missing" EternalCoder454/does-not-exist
if [ "$rc" != 0 ]; then ok "lock: a repository that does not exist fails"; else bad "lock: a missing repository"; fi
git -C "$T/work/fw" tag v2.0.8 >/dev/null 2>&1
rm -rf "$T/notag"
if ! (cd "$T" && PATH="$T/bin:$PATH" timeout 60 "$script" lock EternalCoder454/app v9.9.9 "$T/notag") >"$T/lock.log" 2>&1 && grep -q "has no tag v9.9.9" "$T/lock.log"; then ok "lock: a tag the framework does not have fails"; else bad "lock: unknown tag" "$(tail -n 2 "$T/lock.log")"; fi

# ----------------------------------------------- the lock-file checks, directly
# Every awk there is: lock_shaped must say the same under gawk, mawk and the system's own.
mkdir "$T/awks"
impls=()
for a in gawk mawk original-awk busybox; do
    command -v "$a" >/dev/null 2>&1 && impls+=("$a")
done
command -v awk >/dev/null && impls+=(awk)
shaped() { # shaped <awk impl> <file>: lock_shaped under that awk
    local impl=$1 d=$T/awks/$1
    mkdir -p "$d"
    if [ "$impl" = awk ]; then rm -f "$d/awk"; ln -s "$(command -v awk)" "$d/awk"
    elif [ "$impl" = busybox ]; then printf '#!/bin/sh\nexec busybox awk "$@"\n' >"$d/awk"; chmod +x "$d/awk"
    else ln -sf "$(command -v "$impl")" "$d/awk"; fi
    (PATH="$d:$PATH"; . "$lib"; lock_shaped "$2")
}
for impl in "${impls[@]}"; do
    d=$T/units-$impl
    mkdir -p "$d"
    cp "$T/lock-old" "$d/good"
    if shaped "$impl" "$d/good"; then ok "lock_shaped under $impl: cargo's own format is accepted"; else bad "lock_shaped under $impl accepts a good lock file"; fi
    sed -E 's|^(source = "git\+[^"]*)"|\1"|' "$T/lock-new" >"$d/good2"
    if shaped "$impl" "$d/good2"; then ok "lock_shaped under $impl: a framework git source is accepted"; else bad "lock_shaped under $impl: a git source"; fi
    # a real cargo lock file of the framework itself
    if shaped "$impl" "$here/../Cargo.lock"; then ok "lock_shaped under $impl: the framework's own Cargo.lock is accepted"; else bad "lock_shaped under $impl: the framework's own Cargo.lock"; fi
    n=0
    while IFS= read -r edit; do
        n=$((n + 1))
        cp "$T/lock-old" "$d/bad$n"
        eval "$edit" "$d/bad$n"
        if shaped "$impl" "$d/bad$n"; then bad "lock_shaped under $impl accepted: $edit"; else :; fi
    done <<EOF
sed -i 's|index"|index${tab}x"|'
sed -i 's|^name = "app"|name = "app" |'
sed -i 's|^name = "app"|name = "ap p"|'
sed -i 's|^name = "app"|name = "ap\\\\p"|'
sed -i 's|^version = 4|version = 4 # x|'
sed -i 's|^version = 4|version = "4"|'
sed -i '1s|\$|x|'
sed -i 's|^\\[\\[package\\]\\]|[[package]] |'
sed -i 's|^dependencies = \\[|dependencies = []|'
sed -i 's|^ "telamon-framework-core",| "telamon-framework-core"|'
sed -i 's|^ "telamon-framework-core",| "telamon-framework-core"\\t,|'
sed -i 's|checksum = |checksum   = |'
printf '[patch.crates-io]\\n' >>
printf '\\x00' >>
printf 'a = 1\\n' >>
printf '\\r' >>
printf 'name = "x\\xc3\\xa9"\\n' >>
EOF
done
# and the parts that read it, on the same files
want=$(printf '%s\n' "app 0.1.0 " "$fw_crate 1.0.100 $crates_io" "telamon-framework-core 2.0.7 $fwsrc_old" | LC_ALL=C sort | tr '\n' '|')
got=$(. "$lib"; lock_packages "$T/lock-old" | tr '\n' '|')
if [ "$got" = "$want" ]; then ok "lock_packages: name version source, sorted, a path package has an empty source"; else bad "lock_packages" "$got"; fi
drift=$(. "$lib"; lock_checksum_drift "$T/lock-old" "$T/lock-new" | tr '\n' '|')
if [ -z "$drift" ]; then ok "lock_checksum_drift: a new version is not a changed checksum"; else bad "lock_checksum_drift" "$drift"; fi
sed "s|$sum1|$(c40 f)ffffffffffffffffffffffff|" "$T/lock-old" >"$T/lock-drift"
drift=$(. "$lib"; lock_checksum_drift "$T/lock-old" "$T/lock-drift" | tr '\n' '|')
if [ "$drift" = "$fw_crate 1.0.100|" ]; then ok "lock_checksum_drift: the same version with another checksum is named"; else bad "lock_checksum_drift names the package" "$drift"; fi
printf '%s\0' "100644 blob aaaa${tab}Cargo.toml" "100644 blob bbbb${tab}sub/Cargo.toml" "120000 blob cccc${tab}link/Cargo.toml" \
    "100755 blob dddd${tab}exec/Cargo.toml" "100644 blob eeee${tab}x
Cargo.toml" "100644 blob ffff${tab}notCargo.toml" "100644 blob 1111${tab}Cargo.toml/sub" "160000 commit 2222${tab}submodule/Cargo.toml" >"$T/ls"
if [ "$(. "$lib"; blobs_named Cargo.toml "$T/ls" | tr '\n' '|')" = "Cargo.toml|sub/Cargo.toml|" ]; then
    ok "blobs_named: plain files named so; no links, executables, submodules, look-alikes or paths with control characters"; else bad "blobs_named"; fi

echo
echo "test-open-update-pr: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
