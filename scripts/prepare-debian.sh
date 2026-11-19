#!/usr/bin/env bash
#
# prepare-debian.sh — build the debian/ overlay inside the unpacked NGINX
# source tree, from the vendored pkg-oss skeleton + this project's settings.
#
# Usage: prepare-debian.sh <workdir> <nginx-version> <codename> [ncb-build-number]
#
# Environment:
#   VENDOR           maintainer identity string (default set below)
#   CHANNEL          nginx channel label recorded in metadata (exact|stable|mainline)
#   SOURCE_DATE_EPOCH optional fixed epoch for the changelog date
#   PKG_OSS_COMMIT   pinned pkg-oss commit recorded in metadata
#
# Expects <workdir> to contain:
#   nginx-<version>.tar.gz         verified tarball (fetch-nginx.sh)
#   ngx_brotli/                    pinned module clone (fetch-ngx-brotli.sh)
#   skeleton/                      vendored pkg-oss debian skeleton
#   nginx.copyright                vendored copyright file
#
# Produces <workdir>/src/nginx-<version>/ with a complete debian/ directory,
# plus <workdir>/src/nginx_<version>.orig.tar.gz.
#
set -euo pipefail

WORK="${1:?usage: prepare-debian.sh <workdir> <version> <codename> [ncb-build-number]}"
VER="${2:?usage: prepare-debian.sh <workdir> <version> <codename> [ncb-build-number]}"
CODENAME="${3:?usage: prepare-debian.sh <workdir> <version> <codename> [ncb-build-number]}"
NCB="${4:-1}"
VENDOR="${VENDOR:-NGINX Custom Builder <nginx-custom-builder@localhost>}"
CHANNEL="${CHANNEL:-exact}"
PKG_OSS_COMMIT="${PKG_OSS_COMMIT:-fffcac06856eb0cbe12f8f9e2513bb1b062ee6ac}"
FULLVER="$VER-1ncb$NCB~$CODENAME"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> preparing debian/ for nginx $FULLVER ($CODENAME)"

# --- sanity checks ---------------------------------------------------------
for f in "$WORK/nginx-$VER.tar.gz" "$REPO_ROOT/packaging/nginx.copyright"; do
    [ -f "$f" ] || { echo "ERROR: missing $f" >&2; exit 2; }
done
[ -f "$WORK/ngx_brotli/config" ] || {
    echo "ERROR: $WORK/ngx_brotli/config missing — ngx_brotli not fetched?" >&2
    exit 2
}
SKELETON_DIR="$REPO_ROOT/packaging/debian-skeleton"
[ -d "$SKELETON_DIR" ] || { echo "ERROR: $SKELETON_DIR missing" >&2; exit 2; }

# --- unpack source ----------------------------------------------------------
mkdir -p "$WORK/src"
rm -rf "$WORK/src/nginx-$VER"
tar -C "$WORK/src" -xzf "$WORK/nginx-$VER.tar.gz"
SRC="$WORK/src/nginx-$VER"
[ -d "$SRC" ] || { echo "ERROR: tarball did not produce $SRC" >&2; exit 2; }

# --- overlay vendored skeleton ----------------------------------------------
cp -a "$SKELETON_DIR" "$SRC/debian"
cp "$REPO_ROOT/packaging/nginx.copyright" "$SRC/debian/copyright"
cp "$SRC/CHANGES" "$SRC/debian/CHANGES"

# Normalize permissions: vendored/config files copied from mounts may carry
# bogus executable bits, and debhelper >= 13 EXECUTES executable-looking
# config files (nginx.dirs, nginx.install, ...) instead of parsing them.
find "$SRC/debian" -type f -exec chmod 644 {} +
chmod +x "$SRC/debian/nginx.postinst" "$SRC/debian/nginx.postrm" \
      "$SRC/debian/nginx.preinst" "$SRC/debian/nginx.prerm"
# (debian/rules is generated later in this script and gets +x there)

# docs references README.md; older tarballs ship plain README
if [ ! -f "$SRC/README.md" ] && [ -f "$SRC/README" ]; then
    printf 'README\n' > "$SRC/debian/nginx.docs"
fi

mkdir -p "$SRC/debian/patches"
touch "$SRC/debian/patches/series"

# --- configure flags: validate against this source tree ----------------------
# shellcheck source=../packaging/configure-args.sh
source "$REPO_ROOT/packaging/configure-args.sh"

cd "$SRC"
# NOTE: nginx's ./configure --help exits with status 1 after printing the
# help text (upstream quirk, verified on 1.30.7) — tolerate it explicitly.
HELP="$(./configure --help || true)"

# Flags carrying a value (--prefix=/etc/nginx) are validated by their NAME
# part (the help text shows them as --prefix=PATH); boolean flags are
# matched in full.
check_flag() {
    local name="${1%%=*}"
    grep -Eq "(^|[[:space:]])${name}([=]|[[:space:]]|$)" <<<"$HELP"
}

MISSING_REQUIRED=()
for flag in "${REQUIRED_FLAGS[@]}"; do
    if ! check_flag "$flag"; then
        MISSING_REQUIRED+=("$flag")
    fi
done
if [ "${#MISSING_REQUIRED[@]}" -gt 0 ]; then
    echo "ERROR: required configure flags not supported by nginx $VER:" >&2
    printf '  %s\n' "${MISSING_REQUIRED[@]}" >&2
    echo "Refusing to build with silently dropped flags." >&2
    exit 5
fi

INCLUDED_OPTIONAL=()
EXCLUDED_OPTIONAL=()
for flag in "${OPTIONAL_FLAGS[@]}"; do
    if check_flag "$flag"; then
        INCLUDED_OPTIONAL+=("$flag")
    else
        EXCLUDED_OPTIONAL+=("$flag")
    fi
done

BROTLI_ARGS=(--add-module="$WORK/ngx_brotli")

# --- optional/custom static modules (pinned; selected before the build) -----
MODULE_ARGS=()
MODULE_NAMES=""
if [ -f "$WORK/modules-selected.env" ]; then
    while IFS='|' read -r mname _murl _mref _mtype; do
        [ -z "${mname:-}" ] && continue
        mdir="$WORK/modules/$mname"
        if [ ! -f "$mdir/config" ]; then
            echo "ERROR: selected module '$mname' has no nginx 'config' file at $mdir" >&2
            exit 2
        fi
        MODULE_ARGS+=(--add-module="$mdir")
        MODULE_NAMES="${MODULE_NAMES:+$MODULE_NAMES,}$mname"
    done < "$WORK/modules-selected.env"
fi

BASE_CONFIGURE_ARGS="${REQUIRED_FLAGS[*]} ${INCLUDED_OPTIONAL[*]} ${BROTLI_ARGS[*]} ${MODULE_ARGS[*]}"

printf '%s\n' "$BASE_CONFIGURE_ARGS" > debian/configure-args.final
printf '%s\n' "${EXCLUDED_OPTIONAL[*]:-}" > debian/configure-args.excluded
echo "==> configure flags (${#REQUIRED_FLAGS[@]} required + ${#INCLUDED_OPTIONAL[@]} optional included + brotli)"
if [ "${#EXCLUDED_OPTIONAL[@]}" -gt 0 ]; then
    echo "==> optional flags not supported by nginx $VER (excluded, recorded): ${EXCLUDED_OPTIONAL[*]}"
fi

# --- changelog ----------------------------------------------------------------
BUILD_DATE="$(date -uR -d "@${SOURCE_DATE_EPOCH:-$(date +%s)}")"
cat > debian/changelog <<EOF
nginx ($FULLVER) $CODENAME; urgency=medium

  * Custom build of NGINX $VER (channel: $CHANNEL) with Brotli
    filter and static modules compiled in (google/ngx_brotli).
  * Packaging skeleton based on nginx/pkg-oss @ $PKG_OSS_COMMIT (BSD-2-Clause).
  * Built by nginx-custom-builder; see NOTICE.md for provenance and deviations.

 -- $VENDOR  $BUILD_DATE
EOF

# --- control: substitute, drop the separate nginx-dbg package ------------------
# (project requirement: a single .deb; nginx-debug BINARY stays in the main
# package exactly like nginx.org packages ship it)
awk '/^Package: nginx-dbg$/{exit} {print}' debian/nginx.control.in \
    | {
        tpl="$(cat)"
        tpl="${tpl//%%PACKAGE_VENDOR%%/$VENDOR}"
        tpl="${tpl//%%BASE_VERSION%%/$VER}"
        printf '%s\n' "$tpl"
    } > debian/control
rm -f debian/nginx.control.in

# --- rules: substitute args; drop only the nginx-dbg PACKAGE -------------------
tpl="$(cat debian/nginx.rules.in)"
tpl="${tpl//%%BASE_CONFIGURE_ARGS%%/$BASE_CONFIGURE_ARGS}"
tpl="${tpl//%%CODENAME%%/$CODENAME}"
tpl="${tpl//PKGS = nginx nginx-dbg/PKGS = nginx}"
# remove the build-dbg targets (dh_strip against the dropped nginx-dbg package)
# and fix binary-arch; blocks end at the first blank line.
# Also insert a plain `dh_strip -a` (strip binaries like official nginx.org
# packages do; debug symbols are not shipped in the single-package model).
awk '
    /^build-dbg\.%: install$/ {skip=1; next}
    /^build-dbg: build-dbg\.nginx$/ {skip=1; next}
    skip==1 && /^$/ {skip=0; next}
    skip==1 {next}
    /^binary-arch: install build-dbg$/ {print "binary-arch: install"; next}
    $0 == "\tdh_shlibdeps -a" {print "\tdh_strip -a"}
    {print}
' <<<"$tpl" > debian/rules
rm -f debian/nginx.rules.in
chmod +x debian/rules

# sanity: no nginx-dbg references left where they would break the build
if grep -q 'nginx-dbg' debian/rules; then
    echo "ERROR: rules still references nginx-dbg after patching:" >&2
    grep -n 'nginx-dbg' debian/rules >&2
    exit 5
fi

# --- orig tarball (pristine, for 3.0/quilt) --------------------------------------
cp "$WORK/nginx-$VER.tar.gz" "$WORK/src/nginx_${VER}.orig.tar.gz"

# --- build info for the manifest ---------------------------------------------------
# NOTE: named ncb-* (not build-*) because `debian/rules clean` runs
# `rm -rf debian/build-*` — anything named build-* would be wiped by debuild.
cat > debian/ncb-build-info.env <<EOF
FULL_DEB_VERSION=$FULLVER
NGINX_VERSION=$VER
NGINX_CHANNEL=$CHANNEL
TARGET_CODENAME=$CODENAME
NCB_BUILD=$NCB
PKG_OSS_COMMIT=$PKG_OSS_COMMIT
BROTLI_ARGS=${BROTLI_ARGS[*]}
EOF

if [ -n "$MODULE_NAMES" ]; then
    echo "MODULES_SELECTED=$MODULE_NAMES" >> debian/ncb-build-info.env
fi

echo "==> debian/ prepared in $SRC"
