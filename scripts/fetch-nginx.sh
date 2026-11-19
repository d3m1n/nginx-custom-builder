#!/usr/bin/env bash
#
# fetch-nginx.sh — download and cryptographically verify an NGINX tarball.
#
# Usage: fetch-nginx.sh <version> <outdir>
#
# Requires: curl, gpg.
#
# Verification model:
#   - NGINX release tarballs (.asc) are signed by one of the nginx.org
#     release managers' personal keys published on
#     https://nginx.org/en/pgp_keys.html (arut, pluknet, sb, thresh).
#     NOTE: nginx_signing.key (fingerprint 573BFD6B...) signs the APT/RPM
#     package repositories, NOT the source tarballs — do not use it here.
#   - All four release keys are downloaded, imported into an isolated keyring,
#     and checked against the pinned fingerprint set below (detects key-file
#     replacement upstream).
#   - The tarball signature must verify successfully AND the signing key
#     fingerprint must be a member of the pinned set.
#
# Writes metadata to <outdir>/nginx-<version>.meta.
#
set -euo pipefail

VER="${1:?usage: fetch-nginx.sh <version> <outdir>}"
OUT="${2:?usage: fetch-nginx.sh <version> <outdir>}"

# Pinned primary fingerprints of the nginx.org release-manager keys
# (extracted from https://nginx.org/keys/{arut,pluknet,sb,thresh}.key
#  on 2026-11-19; override via env only if you know why).
PINNED_FPS="${NGINX_RELEASE_KEY_FPS:-43387825DDB1BB97EC36BA5D007C8D7C15D87369 D6786CE303D9A9022998DC6CC8464D549AF75C0A 7338973069ED3F443F4D37DFA64FD5B17ADB39A8 13C82A63B603576156E30A4EA0EA981B66B0D967}"

KEY_BASE="https://nginx.org/keys"
KEY_FILES=(arut.key pluknet.key sb.key thresh.key)

BASE="https://nginx.org/download"
TARBALL="nginx-$VER.tar.gz"
ASC="$TARBALL.asc"

mkdir -p "$OUT"

echo "==> downloading $TARBALL + signature"
curl -fsSL --retry 3 -o "$OUT/$TARBALL" "$BASE/$TARBALL"
curl -fsSL --retry 3 -o "$OUT/$ASC" "$BASE/$ASC"

# Isolated GPG home; trust nothing except the pinned release keys.
GNUPGHOME="$(mktemp -d)"
trap 'rm -rf "$GNUPGHOME"' EXIT
chmod 700 "$GNUPGHOME"

echo "==> downloading and importing nginx.org release keys"
for k in "${KEY_FILES[@]}"; do
    curl -fsSL --retry 3 -o "$OUT/$k" "$KEY_BASE/$k"
    gpg --homedir "$GNUPGHOME" --quiet --import "$OUT/$k"
done

# Defense against upstream key-file replacement: every imported PRIMARY key
# fingerprint must be in the pinned set.
while IFS= read -r fpr; do
    [ -z "$fpr" ] && continue
    match=0
    for p in $PINNED_FPS; do
        if [ "$fpr" = "$p" ]; then match=1; break; fi
    done
    if [ "$match" -ne 1 ]; then
        echo "ERROR: imported key fingerprint $fpr is NOT in the pinned set!" >&2
        echo "Pinned: $PINNED_FPS" >&2
        exit 4
    fi
done < <(gpg --homedir "$GNUPGHOME" --list-keys --with-colons | awk -F: '
    /^pub/{want=1; next}
    want==1 && /^fpr/{print $10; want=0; next}
')

echo "==> verifying tarball signature"
set +e
STATUS="$(gpg --homedir "$GNUPGHOME" --status-fd 1 --verify "$OUT/$ASC" "$OUT/$TARBALL" 2>/dev/null)"
RC=$?
set -e

if [ $RC -ne 0 ]; then
    echo "ERROR: GPG signature verification FAILED for $TARBALL (gpg exit $RC)" >&2
    exit 4
fi

ACTUAL_FPR="$(printf '%s\n' "$STATUS" | sed -n 's/^\[GNUPG:\] VALIDSIG \([0-9A-F]*\) .*/\1/p' | head -1)"
if [ -z "$ACTUAL_FPR" ]; then
    echo "ERROR: could not determine the signing key fingerprint" >&2
    exit 4
fi

match=0
for p in $PINNED_FPS; do
    if [ "$ACTUAL_FPR" = "$p" ]; then match=1; break; fi
done
if [ "$match" -ne 1 ]; then
    echo "ERROR: tarball signed by key $ACTUAL_FPR which is NOT in the pinned release-key set!" >&2
    exit 4
fi

SHA256="$(sha256sum "$OUT/$TARBALL" | awk '{print $1}')"

cat > "$OUT/nginx-$VER.meta" <<EOF
NGINX_VERSION=$VER
NGINX_TARBALL_URL=$BASE/$TARBALL
NGINX_TARBALL_SHA256=$SHA256
NGINX_GPG_VERIFIED=yes
NGINX_SIGNING_KEY_FINGERPRINT=$ACTUAL_FPR
NGINX_RELEASE_KEYS_PINNED="$PINNED_FPS"
EOF

echo "==> OK: signature valid; signed by pinned release key $ACTUAL_FPR"
echo "==> sha256($TARBALL) = $SHA256"
