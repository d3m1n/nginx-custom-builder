#!/usr/bin/env bash
#
# fetch-ngx-brotli.sh — fetch the pinned ngx_brotli module source and its
# pinned vendored brotli dependency.
#
# Usage: fetch-ngx-brotli.sh <outdir>
#
# Uses codeload tarballs of pinned commits (no git submodules — they are
# unreliable inside container mounts):
#   - ngx_brotli @ NGX_BROTLI_COMMIT          (module code)
#   - brotli    @ NGX_BROTLI_DEPS_COMMIT      (vendored headers/sources the
#                module's config script requires at deps/brotli/c)
#
# Linkage model (nginx/pkg-oss parity): headers come from the vendored
# pinned brotli tree; -lbrotlienc/-lbrotlicommon resolve from the DISTRO
# libbrotli-dev (recorded in the build environment snapshot).
#
# Both tarballs are verified against pinned sha256 values; a mismatch is a
# hard error (bump deliberately via env after review).
#
# Writes metadata to <outdir>/ngx-brotli.meta.
#
set -euo pipefail

OUT="${1:?usage: fetch-ngx-brotli.sh <outdir>}"

NGX_BROTLI_COMMIT="${NGX_BROTLI_COMMIT:-53e0fb55f250f48fe80c0ddbf6c0f7103cdbaae1}"
NGX_BROTLI_URL="${NGX_BROTLI_URL:-https://github.com/google/ngx_brotli}"
NGX_BROTLI_TARBALL_SHA256="${NGX_BROTLI_TARBALL_SHA256:-27a4352dae4ba4922f9f013f3f0d02359aceeef2701872efa42849c3ba05457a}"

BROTLI_DEPS_COMMIT="${BROTLI_DEPS_COMMIT:-db24a98aed38a16de78cc05ca15cdd8dc2a0d92d}"
BROTLI_URL="${BROTLI_URL:-https://github.com/google/brotli}"
BROTLI_TARBALL_SHA256="${BROTLI_TARBALL_SHA256:-113b9685dfc14dd2f3360d077283266eec2fbdfb0fe3e5600f11be151da0d68e}"

fetch_and_verify() {
    # fetch_and_verify <url> <expected-sha256> <outfile>
    local url="$1" expected="$2" outfile="$3" actual
    curl -fsSL --retry 3 -o "$outfile" "$url"
    actual="$(sha256sum "$outfile" | awk '{print $1}')"
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: tarball sha256 mismatch for $url" >&2
        echo "  expected (pinned): $expected" >&2
        echo "  actual:            $actual" >&2
        echo "Upstream content changed or was tampered with. Review and bump" >&2
        echo "the pinned commit/hash deliberately if intended." >&2
        exit 4
    fi
}

mkdir -p "$OUT"

echo "==> downloading ngx_brotli @ $NGX_BROTLI_COMMIT"
rm -rf "$OUT/ngx_brotli"
fetch_and_verify \
    "$NGX_BROTLI_URL/archive/$NGX_BROTLI_COMMIT.tar.gz" \
    "$NGX_BROTLI_TARBALL_SHA256" \
    "$OUT/ngx_brotli.tar.gz"

mkdir "$OUT/ngx_brotli"
tar -C "$OUT/ngx_brotli" -xzf "$OUT/ngx_brotli.tar.gz" --strip-components=1
rm -f "$OUT/ngx_brotli.tar.gz"

echo "==> downloading vendored brotli @ $BROTLI_DEPS_COMMIT"
rm -rf "$OUT/ngx_brotli/deps/brotli"
fetch_and_verify \
    "$BROTLI_URL/archive/$BROTLI_DEPS_COMMIT.tar.gz" \
    "$BROTLI_TARBALL_SHA256" \
    "$OUT/brotli.tar.gz"

mkdir -p "$OUT/ngx_brotli/deps/brotli"
tar -C "$OUT/ngx_brotli/deps/brotli" -xzf "$OUT/brotli.tar.gz" --strip-components=1
rm -f "$OUT/brotli.tar.gz"

# The module's config script hard-requires these vendored headers.
[ -f "$OUT/ngx_brotli/deps/brotli/c/include/brotli/encode.h" ] || {
    echo "ERROR: deps/brotli/c/include/brotli/encode.h missing after extraction" >&2
    exit 4
}
[ -f "$OUT/ngx_brotli/config" ] || {
    echo "ERROR: ngx_brotli/config missing after extraction" >&2
    exit 4
}

TREE_SHA="$(tar -C "$OUT" -cf - ngx_brotli | sha256sum | awk '{print $1}')"

cat > "$OUT/ngx-brotli.meta" <<EOF
NGX_BROTLI_URL=$NGX_BROTLI_URL/archive/$NGX_BROTLI_COMMIT.tar.gz
NGX_BROTLI_COMMIT=$NGX_BROTLI_COMMIT
NGX_BROTLI_TARBALL_SHA256=$NGX_BROTLI_TARBALL_SHA256
BROTLI_DEPS_URL=$BROTLI_URL/archive/$BROTLI_DEPS_COMMIT.tar.gz
BROTLI_DEPS_COMMIT=$BROTLI_DEPS_COMMIT
BROTLI_DEPS_TARBALL_SHA256=$BROTLI_TARBALL_SHA256
NGX_BROTLI_TREE_SHA256=$TREE_SHA
NGX_BROTLI_LINKAGE="vendored headers + distro libbrotli-dev for -l (pkg-oss parity; distro version in build-env snapshot)"
EOF

echo "==> OK: ngx_brotli @ $NGX_BROTLI_COMMIT + brotli deps @ $BROTLI_DEPS_COMMIT (sha256 verified)"
echo "==> tree sha256 = $TREE_SHA"
