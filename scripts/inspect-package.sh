#!/usr/bin/env bash
# Phase 3: package metadata inspection — dpkg-deb --info / --contents review
set -euo pipefail
DEB="${1:?usage: inspect-package.sh <deb>}"

echo "===== dpkg-deb --info ====="
dpkg-deb --info "$DEB"

echo
echo "===== conffiles ====="
dpkg-deb --info "$DEB" conffiles 2>/dev/null || dpkg-deb --ctrl-tarfile "$DEB" | tar -xO ./conffiles 2>/dev/null || echo "(no conffiles file?)"

echo
echo "===== contents (top-level) ====="
dpkg-deb --contents "$DEB" | awk '{print $NF}' | grep -vE '/$' | sort | awk -F/ '{print "/"$2"/"$3}' | sort -u | head -30

echo
echo "===== key files ====="
dpkg-deb --contents "$DEB" | grep -E 'usr/sbin/nginx|nginx.conf$|mime.types$|nginx.service$|logrotate|modules$|default.conf$|debug' | head -20

echo
echo "===== shared library deps (Depends line) ====="
dpkg-deb --field "$DEB" Depends
echo
echo "===== Provides / Conflicts / Replaces ====="
dpkg-deb --field "$DEB" Provides
dpkg-deb --field "$DEB" Conflicts
dpkg-deb --field "$DEB" Replaces
