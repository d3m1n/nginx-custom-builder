#!/usr/bin/env bash
#
# build-in-container.sh — full build pipeline executed INSIDE the target
# Ubuntu build container (amd64). Never run on a host with nginx installed.
#
# Usage: docker run -v <workspace>:/work -v <repo>:/repo:ro \
#            -e WORKDIR=/work nginx-custom-builder:build-<target> \
#            bash /repo/scripts/build-in-container.sh
#
# IMPORTANT: the heavy build tree lives on the CONTAINER's native filesystem
# (/build), NOT on the mounted workspace — mount-based filesystems (e.g.
# Docker Desktop gRPC-FUSE) are slow for compilation and break dpkg-source
# tree walks. Only final artifacts and metadata fragments are copied back
# to <WORKDIR>/out.
#
# Expects <WORKDIR>/env.sh defining:
#   NGINX_VERSION, NGINX_CHANNEL, TARGET_CODENAME, NCB_BUILD (opt), BUILDER_COMMIT (opt)
#
# Steps: install build deps -> fetch + verify nginx tarball -> fetch pinned
# ngx_brotli (+ vendored brotli) -> prepare debian/ -> debuild -> copy
# artifacts + metadata to <WORKDIR>/out.
#
set -euo pipefail

WORK="${WORKDIR:?WORKDIR must point to the mounted build workspace}"
BUILD="/build"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> installing build dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    build-essential curl ca-certificates gnupg git \
    devscripts debhelper quilt lsb-release equivs libxml2-utils xsltproc \
    libssl-dev libpcre2-dev zlib1g-dev libbrotli-dev

echo "==> resolving environment"
# shellcheck disable=SC1091
. "$WORK/env.sh"
# Target selection is a build-time input passed via container environment,
# never baked into env.sh (which only carries resolver output).
TARGET_CODENAME="${TARGET_CODENAME:?TARGET_CODENAME must be set (e.g. jammy)}"
NCB_BUILD="${NCB_BUILD:-1}"

rm -rf "$BUILD"
mkdir -p "$BUILD" "$WORK/out"

echo "==> stage: source acquisition + verification"
bash "$REPO/scripts/fetch-nginx.sh" "$NGINX_VERSION" "$BUILD"

echo "==> stage: module acquisition"
bash "$REPO/scripts/fetch-ngx-brotli.sh" "$BUILD"

if [ -n "${SELECTED_MODULES:-}" ]; then
    echo "==> stage: optional/custom module selection ($SELECTED_MODULES)"
    bash "$REPO/scripts/select-modules.sh" \
        "$REPO/packaging/modules-catalog.json" \
        "$SELECTED_MODULES" \
        "${CUSTOM_MODULES_JSON:-[]}" > "$BUILD/modules-selected.env"
    while IFS='|' read -r mname murl mref mtype; do
        [ -z "${mname:-}" ] && continue
        bash "$REPO/scripts/fetch-custom-module.sh" "$BUILD" "$mname" "$murl" "$mref"
    done < "$BUILD/modules-selected.env"
fi

echo "==> stage: debian/ preparation"
CHANNEL="$NGINX_CHANNEL" bash "$REPO/scripts/prepare-debian.sh" \
    "$BUILD" "$NGINX_VERSION" "$TARGET_CODENAME" "${NCB_BUILD:-1}"

echo "==> stage: compile + package"
cd "$BUILD/src/nginx-$NGINX_VERSION"
export DEB_BUILD_OPTIONS="parallel=$(getconf _NPROCESSORS_ONLN)"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date +%s)}"
debuild -us -uc

echo "==> collecting artifacts to the persistent workspace"
mv ../nginx_*.deb "$WORK/out/"
cp -a ../nginx_*.changes ../nginx_*.buildinfo "$WORK/out/" 2>/dev/null || true
SRC="$BUILD/src/nginx-$NGINX_VERSION"
cp -a "$SRC/debian/ncb-build-info.env" "$WORK/out/"
cp -a "$SRC/debian/configure-args.final" "$WORK/out/"
cp -a "$SRC/debian/configure-args.excluded" "$WORK/out/"
cp -a "$BUILD/nginx-$NGINX_VERSION.meta" "$BUILD/ngx-brotli.meta" "$WORK/out/"
cp -a "$BUILD"/module-*.meta "$WORK/out/" 2>/dev/null || true
# record the build environment package snapshot for provenance
dpkg-query -W -f='${Package}\t${Version}\n' | sort > "$WORK/out/build-env-packages.txt"

echo "==> stage results:"
ls -la "$WORK/out/"
sha256sum "$WORK"/out/*.deb
