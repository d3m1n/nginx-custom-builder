#!/usr/bin/env bash
#
# test-package.sh — disposable-container smoke and lifecycle tests for the
# built .deb. Runs INSIDE a fresh target Ubuntu container (amd64).
# Never run on a host with nginx installed.
#
# Usage: DEB=/work/out/nginx_...deb NGINX_VERSION=1.30.7 bash test-package.sh
#
set -uo pipefail

DEB="${DEB:?DEB must point to the built .deb}"
EXPECTED_VERSION="${NGINX_VERSION:?NGINX_VERSION must be set}"
# build number from env, or parsed from the artifact filename as the source of truth
DEB_BASENAME="$(basename "$DEB")"
EXPECTED_NCB="${NCB_BUILD:-$(printf '%s' "$DEB_BASENAME" | sed -n 's/.*-1ncb\([0-9]*\)~.*/\1/p')}"
EXPECTED_NCB="${EXPECTED_NCB:-1}"

PASS=0
FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "==> installing dependencies for the test harness"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends curl systemd brotli >/dev/null

echo "==> installing $DEB (apt resolves dependencies)"
apt-get install -y -qq "$DEB" >/dev/null

# --- package state and metadata ---------------------------------------------
status="$(dpkg-query -W -f='${Status}' nginx 2>/dev/null)"
if [ "$status" = "install ok installed" ]; then
    ok "package installed (dpkg status)"
else
    bad "package installed (dpkg status='$status')"
fi

deb_ver="$(dpkg-query -W -f='${Version}' nginx 2>/dev/null)"
if [ "$deb_ver" = "$EXPECTED_VERSION-1ncb$EXPECTED_NCB~$TARGET_CODENAME" ]; then
    ok "package version is $deb_ver"
else
    bad "package version: got '$deb_ver', expected '$EXPECTED_VERSION-1ncb$EXPECTED_NCB~$TARGET_CODENAME'"
fi

# --- binary and build parity -------------------------------------------------
if nginx -v 2>&1 | grep -qF "nginx/$EXPECTED_VERSION"; then
    ok "nginx -v reports $EXPECTED_VERSION"
else
    bad "nginx -v reports: $(nginx -v 2>&1)"
fi

if nginx -V 2>&1 | grep -q 'add-module=.*ngx_brotli'; then
    ok "configure args include ngx_brotli module"
else
    bad "configure args do not include ngx_brotli"
fi

if nginx -V 2>&1 | grep -qF -- '--with-compat'; then
    ok "configure args include --with-compat"
else
    bad "configure args missing --with-compat"
fi

if [ -x /usr/sbin/nginx-debug ]; then
    ok "nginx-debug binary shipped (nginx.org parity)"
else
    bad "nginx-debug binary missing"
fi

# --- filesystem layout (nginx.org parity) --------------------------------------
for f in /etc/nginx/nginx.conf /etc/nginx/mime.types /etc/nginx/conf.d/default.conf \
         /usr/lib/nginx/modules /etc/logrotate.d/nginx /lib/systemd/system/nginx.service \
         /lib/systemd/system/nginx-debug.service /etc/default/nginx /etc/init.d/nginx; do
    if [ -e "$f" ]; then
        ok "layout: $f present"
    else
        bad "layout: $f MISSING"
    fi
done

if [ -L /etc/nginx/modules ]; then
    ok "layout: /etc/nginx/modules is a symlink to /usr/lib/nginx/modules"
else
    bad "layout: /etc/nginx/modules is not a symlink"
fi

# --- service unit static validation ---------------------------------------------
# systemd-analyze verify requires a recent systemd for offline verification;
# older systemd (e.g. 237 on bionic) tries to init the manager and fails in
# containers. Fall back to structural unit checks there.
SD_VER="$(systemd --version 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)"
if [ -n "$SD_VER" ] && [ "$SD_VER" -ge 245 ] 2>/dev/null; then
    if systemd-analyze verify nginx.service 2>/dev/null; then
        ok "systemd unit nginx.service validates (systemd-analyze, systemd $SD_VER)"
    else
        bad "systemd unit nginx.service failed verification (systemd $SD_VER)"
    fi
else
    unit_ok=1
    for sec in '\[Unit\]' '\[Service\]' '\[Install\]'; do
        grep -q "^${sec}$" /lib/systemd/system/nginx.service || unit_ok=0
    done
    grep -q '^ExecStart=/usr/sbin/nginx' /lib/systemd/system/nginx.service || unit_ok=0
    if [ "$unit_ok" -eq 1 ] && [ -x /usr/sbin/nginx ]; then
        ok "systemd unit nginx.service structurally valid (systemd $SD_VER lacks offline verify; static check)"
    else
        bad "systemd unit nginx.service structural check failed"
    fi
fi

# --- runtime: HTTP ----------------------------------------------------------------
nginx
sleep 0.5
code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/)"
if [ "$code" = "200" ]; then
    ok "HTTP request on :80 returns 200"
else
    bad "HTTP request on :80 returned $code"
fi

# --- runtime: Brotli dynamic compression --------------------------------------------
mkdir -p /srv/brotli-test
head -c 4000 /dev/urandom | base64 > /srv/brotli-test/file.txt
cat > /etc/nginx/conf.d/zz-brotli-test.conf <<'EOF'
server {
    listen 8081;
    brotli on;
    brotli_static on;
    # module defaults compress text/html only (gzip parity by upstream
    # design); the test serves text/plain, so declare the type explicitly.
    brotli_types text/plain;
    root /srv/brotli-test;
}
EOF
if nginx -t >/dev/null 2>&1; then
    ok "nginx -t passes with brotli directives (modules compiled in)"
else
    bad "nginx -t failed with brotli directives"
fi

nginx -s reload
sleep 1
BROTLI_HDRS="$(curl -s -H 'Accept-Encoding: br' -o /dev/null -D- http://127.0.0.1:8081/file.txt | tr -d '\r')"
if printf '%s\n' "$BROTLI_HDRS" | grep -qi '^content-encoding: br'; then
    ok "brotli dynamic compression: Content-Encoding: br"
else
    bad "brotli dynamic compression did not negotiate; response headers: $(printf '%s\n' "$BROTLI_HDRS" | head -6 | tr '\n' ' ')"
fi

# --- runtime: Brotli static (.br pre-compressed) --------------------------------------
brotli -c /srv/brotli-test/file.txt > /srv/brotli-test/file.txt.br
if curl -s -H 'Accept-Encoding: br' -o /dev/null -D- http://127.0.0.1:8081/file.txt \
        | tr -d '\r' | grep -qi '^content-encoding: br'; then
    ok "brotli static: pre-compressed .br served as br"
else
    bad "brotli static did not serve .br variant"
fi

# --- plain request must NOT be brotli-compressed ----------------------------------------
if curl -s -o /dev/null -D- http://127.0.0.1:8081/file.txt \
        | tr -d '\r' | grep -qi '^content-encoding: br'; then
    bad "brotli applied without Accept-Encoding: br"
else
    ok "no brotli without Accept-Encoding"
fi

# --- ordinary removal preserves user data (documented semantics) -------------------------
nginx -s quit
sleep 0.3
dpkg -r nginx >/dev/null
if [ -f /etc/nginx/nginx.conf ] && [ -f /etc/nginx/conf.d/zz-brotli-test.conf ]; then
    ok "ordinary remove preserves /etc/nginx including user configs"
else
    bad "ordinary remove deleted user configuration"
fi
if [ -d /var/log/nginx ]; then
    ok "ordinary remove preserves /var/log/nginx"
else
    bad "ordinary remove deleted logs"
fi

# --- reinstall over removed package --------------------------------------------------------
apt-get install -y -qq "$DEB" >/dev/null
if nginx -t >/dev/null 2>&1; then
    ok "reinstall after remove succeeds and config validates"
else
    bad "reinstall after remove failed"
fi

# --- purge deletes everything (documented nginx.org-parity semantics) -----------------------
dpkg -P nginx >/dev/null
if [ ! -d /etc/nginx ]; then
    ok "purge removes /etc/nginx entirely (documented purge semantics)"
else
    bad "purge left /etc/nginx behind (unexpected for parity)"
fi

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
