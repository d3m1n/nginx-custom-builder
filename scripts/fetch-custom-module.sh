#!/usr/bin/env bash
#
# fetch-custom-module.sh — fetch a pinned third-party NGINX module.
#
# Usage: fetch-custom-module.sh <workdir> <name> <url> <ref>
#
# The ref (tag, branch, or commit) is RESOLVED to an immutable commit SHA via
# git ls-remote, then the module is checked out at exactly that commit.
# Resolved commit + source URL + requested ref + tree sha256 are recorded in
# <workdir>/module-<name>.meta for the build manifest.
#
# Untrusted-source policy: the module is fetched and built only inside the
# disposable build container.
#
set -euo pipefail

WORK="${1:?usage: fetch-custom-module.sh <workdir> <name> <url> <ref>}"
NAME="${2:?}"
URL="${3:?}"
REF="${4:?}"

[[ "$NAME" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { echo "ERROR: invalid module name '$NAME'" >&2; exit 2; }
[[ "$URL" =~ ^https:// ]] || { echo "ERROR: module URL must be https (got '$URL')" >&2; exit 2; }

MODDIR="$WORK/modules/$NAME"
rm -rf "$MODDIR"
mkdir -p "$MODDIR"

echo "==> resolving module $NAME ref '$REF' -> commit"
COMMIT=""
if [[ "$REF" =~ ^[0-9a-f]{40}$ ]]; then
    COMMIT="$REF"
else
    REMOTE_REFS="$(git ls-remote "$URL" "$REF" "refs/tags/$REF" "refs/heads/$REF")"
    COMMIT="$(awk 'END{print $1}' <<<"$REMOTE_REFS")"
fi
if ! [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    echo "ERROR: could not resolve ref '$REF' in $URL to a commit (got '${COMMIT:-nothing}')" >&2
    exit 4
fi

echo "==> cloning $URL @ $COMMIT"
git clone --quiet --no-checkout "$URL" "$MODDIR"
git -C "$MODDIR" checkout --quiet --detach "$COMMIT"

[ -f "$MODDIR/config" ] || {
    echo "ERROR: $NAME has no nginx module 'config' file — not an nginx module?" >&2
    exit 4
}

TREE_SHA="$(tar -C "$WORK/modules" -cf - "$NAME" | sha256sum | awk '{print $1}')"

cat > "$WORK/module-$NAME.meta" <<EOF
MODULE_NAME=$NAME
MODULE_URL=$URL
MODULE_REF=$REF
MODULE_COMMIT=$COMMIT
MODULE_TREE_SHA256=$TREE_SHA
MODULE_TYPE=static
EOF

echo "==> OK: $NAME @ $COMMIT (from ref '$REF')"
echo "==> tree sha256 = $TREE_SHA"
