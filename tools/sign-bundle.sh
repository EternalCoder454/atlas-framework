#!/bin/bash
# Sign the manifest of a Telamon native bundle with minisign (docs/BUNDLES.md,
# "Signing"): reads DIR/telamon-bundle.json and writes
# DIR/telamon-bundle.json.minisig, which Telamon Store checks against the keys
# in its catalog. It runs in the `sign` job of .github/workflows/bundle.yml, in
# a fedora:44 container with minisign, python3 and zstd, and works the same by
# hand.
#
#   MINISIGN_KEY='<the secret key file's content>' [MINISIGN_PASSWORD=...] \
#       tools/sign-bundle.sh [--public-key RW...] DIR
#
#   DIR   what tools/make-bundle.sh wrote: the archive and telamon-bundle.json
#         and nothing else
#   --public-key RW...   the key the catalog pins for the app: the signature
#         is then verified with it, so a wrong key in the CI secret fails
#         here and not on a user's computer
#
# What it does, in this order:
#   1. checks the bundle with `bundle.py verify` (the archive against the
#      manifest and the layout rules), so a build can only get a *valid*
#      bundle signed, never an arbitrary file;
#   2. without MINISIGN_KEY it stops there: nothing is signed, it says so
#      (Store will not offer an unsigned release) and exits 0;
#   3. writes the key to a file in tmpfs (mode 0600, umask 077), signs the
#      manifest with `minisign -S` (the default, hashed signature that the
#      Store accepts), and removes and shreds the key file whatever happens;
#   4. checks the signature's form (hashed, 'ED', a key ID) and, with
#      --public-key, verifies it with `minisign -V`.
#
# The key and the password are read from the environment only: never an
# argument (they would show in the process list), never printed, and tracing
# is switched off. With GITHUB_OUTPUT set it writes `signed=true|false` and
# `manifest-sha256=<hex>`.
set -euo pipefail
set +x
umask 077

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bundle_py=$here/bundle.py
MANIFEST=telamon-bundle.json

# A message may hold a name from the bundle: no control character reaches the log.
die() {
    local msg=$*
    echo "sign-bundle: ${msg//[[:cntrl:]]/?}" >&2
    exit 1
}

dir=
pub=
while [ $# -gt 0 ]; do
    case $1 in
    --public-key)
        [ $# -ge 2 ] || die "--public-key needs a value"
        pub=$2
        shift 2
        ;;
    -h | --help)
        sed '/^set -euo/,$d;1d' "$0"
        exit 0
        ;;
    -*) die "unknown argument: $1 (see --help)" ;;
    *)
        [ -z "$dir" ] || die "one directory only"
        dir=$1
        shift
        ;;
    esac
done
[ -n "$dir" ] || die "needs the directory of the bundle (see --help)"
[ -z "$pub" ] || [[ $pub =~ ^RW[A-Za-z0-9+/]{54}$ ]] || die "--public-key is the 56 characters of a minisign public key, starting RW"
[ -d "$dir" ] && [ ! -L "$dir" ] || die "$dir is not a directory"
for tool in python3 zstd sha256sum; do
    command -v "$tool" >/dev/null || die "$tool is not installed"
done

# The key never stays: whatever happens, the file is shredded and removed and
# the variables are gone.
keydir=
cleanup() {
    set +x
    if [ -n "$keydir" ] && [ -d "$keydir" ]; then
        find "$keydir" -type f -exec shred -u -- {} + 2>/dev/null || true
        rm -rf -- "$keydir"
    fi
    unset MINISIGN_KEY MINISIGN_PASSWORD
}
trap cleanup EXIT

# The directory holds the bundle and nothing else.
shopt -s nullglob dotglob
archives=("$dir"/*.tar.zst)
others=()
for f in "$dir"/*; do
    case ${f##*/} in
    "$MANIFEST" | *.tar.zst) ;;
    *) others+=("$f") ;;
    esac
done
shopt -u nullglob dotglob
[ "${#archives[@]}" -eq 1 ] || die "$dir must hold one .tar.zst archive, it holds ${#archives[@]}"
[ -f "$dir/$MANIFEST" ] && [ ! -L "$dir/$MANIFEST" ] && [ -f "${archives[0]}" ] && [ ! -L "${archives[0]}" ] ||
    die "$dir must hold the archive and $MANIFEST as plain files"
[ "${#others[@]}" -eq 0 ] || die "$dir holds a file that is not part of the bundle: ${others[0]##*/}"
manifest=$dir/$MANIFEST
sig=$dir/$MANIFEST.minisig

echo "== verify the bundle" >&2
python3 -I "$bundle_py" verify "${archives[0]}" "$manifest" >&2 || die "the bundle does not verify: nothing is signed"
manifest_sha=$(sha256sum -- "$manifest")
manifest_sha=${manifest_sha%% *}

out() { # out name value: a step output for GitHub Actions
    if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "$1=$2" >>"$GITHUB_OUTPUT"; fi
}
out manifest-sha256 "$manifest_sha"

key=${MINISIGN_KEY:-}
password=${MINISIGN_PASSWORD:-}
unset MINISIGN_KEY MINISIGN_PASSWORD
if [ -z "$key" ]; then
    unset password
    out signed false
    msg="no signing key (the minisign-key secret is empty or missing): $MANIFEST is not signed, and Telamon Store will not offer an unsigned release"
    if [ "${GITHUB_ACTIONS:-}" = true ]; then
        echo "::warning::$msg"
    else
        echo "sign-bundle: warning: $msg" >&2
    fi
    exit 0
fi
command -v minisign >/dev/null || die "minisign is not installed"
[ ! -e "$sig" ] || die "$sig exists already"

# The secret key file is two lines: an untrusted comment and the key.
key=${key//$'\r'/}
if [ "${#key}" -gt 2048 ] || [[ $key != "untrusted comment: "* ]] || [[ $key != *$'\n'* ]]; then
    die "the signing key is not a minisign secret key file: give the whole file (its first line starts 'untrusted comment:')"
fi

# tmpfs only: a key must not reach a disk. TELAMON_SIGN_TMPDIR exists for the tests.
tmp=${TELAMON_SIGN_TMPDIR:-/dev/shm}
case $(stat -f -c %T -- "$tmp" 2>/dev/null || true) in
tmpfs | ramfs) ;;
*) die "$tmp is not a tmpfs: the key would be written to disk" ;;
esac
keydir=$(mktemp -d "$tmp/telamon-sign.XXXXXX")
keyfile=$keydir/minisign.key
printf '%s\n' "$key" >"$keyfile"
unset key

echo "== sign $MANIFEST" >&2
set +e
if [ -n "$password" ]; then
    printf '%s\n' "$password" | minisign -S -s "$keyfile" -m "$manifest" -x "$sig" >&2
else
    minisign -S -s "$keyfile" -m "$manifest" -x "$sig" </dev/null >&2
fi
rc=$?
set -e
unset password
find "$keydir" -type f -exec shred -u -- {} + 2>/dev/null || true
rm -rf -- "$keydir"
keydir=
if [ "$rc" -ne 0 ]; then
    rm -f -- "$sig"
    die "minisign failed ($rc): is the key complete, and is minisign-password the right one?"
fi

# The form the Store reads: 4 lines, the signature of the *hash* ('ED', not the legacy 'Ed').
keyid=$(python3 -I - "$sig" <<'EOF'
import base64, sys
data = open(sys.argv[1], "rb").read()
if len(data) > 4096:
    sys.exit("the signature file is larger than 4096 bytes")
lines = data.decode("utf-8").split("\n")
if len(lines) != 5 or lines[4] != "" or not lines[0].startswith("untrusted comment:") or not lines[2].startswith("trusted comment:"):
    sys.exit("the signature file is not in minisign's four-line form")
raw = base64.b64decode(lines[1], validate=True)
if len(raw) != 74 or raw[:2] != b"ED":
    sys.exit("the signature is not the hashed kind ('ED'): the Store refuses the legacy kind")
print(raw[2:10][::-1].hex().upper())
EOF
) || {
    rm -f -- "$sig"
    die "the signature minisign wrote is not usable"
}
if [ -n "$pub" ]; then
    minisign -V -H -q -P "$pub" -m "$manifest" -x "$sig" ||
        {
            rm -f -- "$sig"
            die "the signature does not verify with --public-key $pub: the signing key is not the one the catalog pins (key ID of the secret key: $keyid)"
        }
    echo "signature verified with the public key given" >&2
else
    echo "sign-bundle: the signature was not checked against the catalog's key (no --public-key)" >&2
fi
out signed true
out key-id "$keyid"
echo "signed $MANIFEST with the key $keyid -> ${sig##*/}" >&2
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "Signed \`$MANIFEST\` with minisign key \`$keyid\`." >>"$GITHUB_STEP_SUMMARY"
fi
