#!/usr/bin/env bash
#
# resolve-version.sh — resolve the requested NGINX version.
#
# Usage: resolve-version.sh <exact|stable|mainline> [EXACT_VERSION]
#
# Prints KEY=VALUE lines on stdout:
#   NGINX_VERSION=1.30.7
#   NGINX_CHANNEL=stable
#   NGINX_TARBALL_URL=https://nginx.org/download/nginx-1.30.7.tar.gz
#   NGINX_ASC_URL=https://nginx.org/download/nginx-1.30.7.tar.gz.asc
#
# Exact versions are never substituted: a requested exact version that does
# not exist on nginx.org is a hard error (AGENTS.md requirement).
#
set -euo pipefail

MODE="${1:-}"
WANT="${2:-}"
BASE="https://nginx.org"

require_mode() {
    case "$MODE" in
        exact|stable|mainline) ;;
        *) echo "ERROR: usage: resolve-version.sh <exact|stable|mainline> [EXACT_VERSION]" >&2; exit 2 ;;
    esac
}

fetch_index() {
    # The download page lists mainline, stable, and legacy versions.
    curl -fsSL --retry 3 "$BASE/en/download.html"
}

parse_versions() {
    # Extract all versions referenced as .tar.gz on the page.
    grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' \
        | sed -E 's/nginx-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.gz/\1/' \
        | sort -uV
}

require_mode

if command -v curl >/dev/null 2>&1; then
    :
else
    echo "ERROR: curl is required" >&2
    exit 2
fi

index="$(fetch_index)"
mapfile -t all < <(printf '%s' "$index" | parse_versions)

if [ "${#all[@]}" -eq 0 ]; then
    echo "ERROR: could not parse any versions from $BASE/en/download.html (page layout changed?)" >&2
    exit 3
fi

mainline="${all[${#all[@]}-1]}"
ml_branch="${mainline%.*}"
stable="$(printf '%s\n' "${all[@]}" | grep -v "^${ml_branch}\." | tail -1 || true)"

if [ -z "$stable" ]; then
    echo "ERROR: could not determine the stable version (page layout changed?)" >&2
    exit 3
fi

case "$MODE" in
    exact)
        if [ -z "$WANT" ]; then
            echo "ERROR: exact mode requires a VERSION argument" >&2
            exit 2
        fi
        if ! printf '%s' "$WANT" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo "ERROR: invalid version format '$WANT' (expected X.Y.Z)" >&2
            exit 2
        fi
        if ! printf '%s\n' "${all[@]}" | grep -Fx "$WANT"; then
            echo "ERROR: requested exact version $WANT was not found on nginx.org." >&2
            echo "Available (latest 10): ${all[*]: -10}" >&2
            echo "Refusing to substitute a different version." >&2
            exit 3
        fi
        VER="$WANT"
        ;;
    stable)
        VER="$stable"
        ;;
    mainline)
        VER="$mainline"
        ;;
esac

cat <<EOF
NGINX_VERSION=$VER
NGINX_CHANNEL=$MODE
NGINX_TARBALL_URL=$BASE/download/nginx-$VER.tar.gz
NGINX_ASC_URL=$BASE/download/nginx-$VER.tar.gz.asc
NGINX_MAINLINE_REFERENCE=$mainline
NGINX_STABLE_REFERENCE=$stable
EOF
