#!/usr/bin/env bash
#
# probe-build-deps.sh — Phase 1 evidence test.
#
# Probe build-dependency availability for building nginx .deb packages in a
# target Ubuntu environment. Run INSIDE the target container
# (ubuntu:18.04 / 20.04 / 22.04 / 24.04), never on a host with nginx.
#
# EOL releases (bionic, focal) get their apt sources repointed to
# old-releases.ubuntu.com when archive.ubuntu.com no longer serves them.
#
set -uo pipefail

# shellcheck disable=SC1091
. /etc/os-release
codename="${VERSION_CODENAME:-unknown}"
echo "=== probe target: ${PRETTY_NAME:-$codename} (${codename}) ==="

repo="archive.ubuntu.com"

apt_quiet_update() { apt-get update -qq >/dev/null 2>&1; }

repoint_old_releases() {
    local f
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do
        [ -f "$f" ] || continue
        sed -i -E \
            -e 's|//([a-z]{2,3}\.)?archive\.ubuntu\.com|//old-releases.ubuntu.com|g' \
            -e 's|//security\.ubuntu\.com|//old-releases.ubuntu.com|g' \
            "$f"
    done
}

if ! apt_quiet_update; then
    echo "apt update failed against archive.ubuntu.com -> repointing to old-releases.ubuntu.com"
    repo="old-releases.ubuntu.com"
    repoint_old_releases
    if ! apt_quiet_update; then
        echo "FATAL: apt update failed even against old-releases.ubuntu.com"
        exit 2
    fi
fi
echo "apt repository in use: $repo"
echo

# pkg-oss debian build-deps (nginx.control.in) + our additions.
# debhelper must support compat level 11 (pkg-oss debian/compat = 11).
# libbrotli-dev is required for the default Brotli integration.
for p in debhelper dpkg-dev quilt lsb-release devscripts equivs \
         libssl-dev libpcre2-dev libpcre3-dev zlib1g-dev libbrotli-dev \
         libxml2-utils xsltproc gcc g++ make; do
    v="$(apt-cache show "$p" 2>/dev/null | sed -n 's/^Version: //p' | head -1)"
    printf '%-16s %s\n' "$p" "${v:-NOT AVAILABLE}"
done

echo
dh_major="$(apt-cache show debhelper 2>/dev/null | sed -n 's/^Version: //p' | head -1 | cut -d. -f1 | tr -d ':a-z~+')"
if [ -n "$dh_major" ] && [ "$dh_major" -ge 11 ] 2>/dev/null; then
    echo "debhelper compat 11 supported: yes (major $dh_major)"
else
    echo "debhelper compat 11 supported: NO (major '${dh_major:-unknown}')"
fi

ssl="$(apt-cache show libssl-dev 2>/dev/null | sed -n 's/^Version: //p' | head -1)"
echo "OpenSSL dev version: ${ssl:-unknown}"
