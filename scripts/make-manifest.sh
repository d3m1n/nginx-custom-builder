#!/usr/bin/env bash
#
# make-manifest.sh — assemble the build manifest (JSON) and checksums.
#
# Usage: make-manifest.sh <workdir>
#
# Reads metadata fragments written by the stage scripts (all copied to out/):
#   <workdir>/out/nginx-<ver>.meta        (fetch-nginx.sh)
#   <workdir>/out/ngx-brotli.meta         (fetch-ngx-brotli.sh)
#   <workdir>/out/build-info.env          (prepare-debian.sh)
#   <workdir>/out/configure-args.final    (prepare-debian.sh)
#   <workdir>/out/configure-args.excluded (prepare-debian.sh)
#   <workdir>/out/*.deb
#
# Environment: BUILDER_COMMIT (git commit of this repository), optional
# BUILDER_RUNNER description.
#
set -euo pipefail

WORK="${1:?usage: make-manifest.sh <workdir>}"
BUILDER_COMMIT="${BUILDER_COMMIT:-unknown}"
BUILDER_RUNNER="${BUILDER_RUNNER:-local}"

# --- load metadata -------------------------------------------------------------
info_env="$WORK/out/ncb-build-info.env"
[ -f "$info_env" ] || { echo "ERROR: ncb-build-info.env not found (build first)" >&2; exit 2; }
# shellcheck disable=SC1090
. "$info_env"

# shellcheck disable=SC1091
. "$WORK/out/nginx-$NGINX_VERSION.meta"
# shellcheck disable=SC1091
. "$WORK/out/ngx-brotli.meta"

DEB="$(find "$WORK/out" -maxdepth 1 -name 'nginx_*.deb' | head -1)"
[ -n "$DEB" ] || { echo "ERROR: no .deb in $WORK/out" >&2; exit 2; }
DEB_NAME="$(basename "$DEB")"
DEB_SHA256="$(sha256sum "$DEB" | awk '{print $1}')"
DEB_SIZE="$(stat -c %s "$DEB")"

CONFIGURE_ARGS="$(cat "$WORK/out/configure-args.final")"
EXCLUDED_ARGS="$(cat "$WORK/out/configure-args.excluded")"

# --- build the modules JSON array (brotli + any selected custom modules) ------
MODULES_JSON="    {
      \"name\": \"ngx_brotli (filter + static)\",
      \"url\": \"$NGX_BROTLI_URL\",
      \"commit\": \"$NGX_BROTLI_COMMIT\",
      \"tree_sha256\": \"$NGX_BROTLI_TREE_SHA256\",
      \"linkage\": \"$NGX_BROTLI_LINKAGE\"
    }"
for mf in "$WORK"/out/module-*.meta; do
    [ -e "$mf" ] || continue
    # shellcheck disable=SC1090
    . "$mf"
    MODULES_JSON+=",
    {
      \"name\": \"$MODULE_NAME\",
      \"url\": \"$MODULE_URL\",
      \"requested_ref\": \"$MODULE_REF\",
      \"commit\": \"$MODULE_COMMIT\",
      \"tree_sha256\": \"$MODULE_TREE_SHA256\",
      \"type\": \"$MODULE_TYPE\"
    }"
done

GENERATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

OUT="$WORK/out/manifest.json"
cat > "$OUT" <<EOF
{
  "schema_version": 1,
  "generated_at": "$GENERATED",
  "builder": {
    "project": "nginx-custom-builder",
    "commit": "$BUILDER_COMMIT",
    "runner": "$BUILDER_RUNNER"
  },
  "package": {
    "name": "nginx",
    "version": "$FULL_DEB_VERSION",
    "file": "$DEB_NAME",
    "sha256": "$DEB_SHA256",
    "size_bytes": $DEB_SIZE,
    "architecture": "amd64",
    "target_codename": "$TARGET_CODENAME"
  },
  "nginx_source": {
    "version": "$NGINX_VERSION",
    "channel": "$NGINX_CHANNEL",
    "url": "$NGINX_TARBALL_URL",
    "sha256": "$NGINX_TARBALL_SHA256",
    "gpg_verified": "$NGINX_GPG_VERIFIED",
    "signing_key_fingerprint": "$NGINX_SIGNING_KEY_FINGERPRINT"
  },
  "modules": [
$MODULES_JSON
  ],
  "packaging": {
    "based_on": "nginx/pkg-oss",
    "pkg_oss_commit": "$PKG_OSS_COMMIT",
    "configure_args": "$CONFIGURE_ARGS",
    "optional_flags_excluded": "$EXCLUDED_ARGS"
  }
}
EOF

echo "==> manifest written: $OUT"
sha256sum "$DEB" "$OUT" > "$WORK/out/SHA256SUMS"
cat "$WORK/out/SHA256SUMS"
