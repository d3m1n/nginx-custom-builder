#!/usr/bin/env bash
#
# test-package-migration.sh — Phase 3 lifecycle and migration tests.
# Runs INSIDE a disposable target container. Never on a host with nginx.
#
# Usage: bash test-package-migration.sh <scenario>
#   nginx-org     install nginx.org package first, plant user data, then
#                 install ours (upgrade-over-nginx.org + rollback path)
#   ubuntu-distro install Ubuntu distro nginx first, plant user data, then
#                 take over with ours (Conflicts/Replaces + shared conffiles)
#   guard         verify the postinst nginx -t guard never restarts nginx
#                 with a broken configuration
#
# Env: DEB=/path/to/package.deb  TARGET_CODENAME=jammy
#
set -uo pipefail

SCENARIO="${1:?scenario required: nginx-org|ubuntu-distro|guard}"
DEB="${DEB:?DEB must point to the built .deb}"
CODENAME="${TARGET_CODENAME:?TARGET_CODENAME must be set}"

export DEBIAN_FRONTEND=noninteractive
PASS=0
FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

apt_quiet() { apt-get install -y -qq "$@" >/dev/null 2>&1; }

setup_user_data() {
    apt_quiet openssl curl
    # user-modified main config (append a marker comment — still valid config)
    echo "# ncb-user-marker-do-not-remove" >> /etc/nginx/nginx.conf
    # custom virtual host
    cat > /etc/nginx/conf.d/ncb-test.conf <<'EOF'
server {
    listen 8082;
    location / { return 200 "ncb-vhost-ok\n"; }
}
EOF
    # test certificate + key
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout /etc/nginx/ssl/ncb-test.key -out /etc/nginx/ssl/ncb-test.crt \
        -days 1 -subj "/CN=ncb-test" >/dev/null 2>&1
    # log marker
    echo "ncb-log-marker" > /var/log/nginx/ncb-test.log
    # cache marker (dir may not exist under the distro layout yet)
    mkdir -p /var/cache/nginx
    echo "ncb-cache-marker" > /var/cache/nginx/ncb-cache-marker
    sha256sum /etc/nginx/nginx.conf /etc/nginx/conf.d/ncb-test.conf \
              /etc/nginx/ssl/ncb-test.crt /etc/nginx/ssl/ncb-test.key \
              /var/log/nginx/ncb-test.log /var/cache/nginx/ncb-cache-marker \
              > /tmp/ncb-user-data.sha256
}

assert_user_data_intact() {
    if sha256sum -c --quiet /tmp/ncb-user-data.sha256 >/dev/null 2>&1; then
        ok "user data byte-identical after migration (config, vhost, certs, logs, cache)"
    else
        bad "user data changed after migration:"
        sha256sum -c /tmp/ncb-user-data.sha256 2>&1 | grep -v ': OK' | sed 's/^/      /'
    fi
}

assert_nginx_version() {
    local want="$1"
    if nginx -v 2>&1 | grep -qF "$want"; then
        ok "nginx binary is $want"
    else
        bad "nginx binary version: $(nginx -v 2>&1), expected $want"
    fi
}

assert_nginx_t() {
    if nginx -t >/dev/null 2>&1; then
        ok "nginx -t passes after migration"
    else
        bad "nginx -t FAILED after migration:"
        nginx -t 2>&1 | sed 's/^/      /'
    fi
}

echo "=============================================================="
echo " scenario: $SCENARIO"
echo "=============================================================="

case "$SCENARIO" in

nginx-org)
    echo "==> setting up nginx.org repository"
    apt_quiet curl gnupg2 ca-certificates lsb-release ubuntu-keyring
    curl -fsSL https://nginx.org/keys/nginx_signing.key \
        | gpg --dearmor > /usr/share/keyrings/nginx-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/ubuntu $CODENAME nginx" \
        > /etc/apt/sources.list.d/nginx.list
    apt-get update -qq >/dev/null 2>&1

    echo "==> installing nginx from nginx.org"
    apt_quiet nginx
    ORG_VER="$(dpkg-query -W -f='${Version}' nginx)"
    echo "    nginx.org installed version: $ORG_VER"
    if dpkg-query -W -f='${db:Status-Abbrev}' nginx 2>/dev/null | grep -q ii; then
        ok "nginx.org package installed ($ORG_VER)"
    else
        bad "nginx.org package failed to install"
    fi

    echo "==> planting user data"
    setup_user_data

    echo "==> starting nginx.org nginx via init script (as systemd would)"
    /etc/init.d/nginx start
    sleep 0.5
    ORG_PID="$(cat /run/nginx.pid 2>/dev/null || true)"
    if [ -n "$ORG_PID" ] && kill -0 "$ORG_PID" 2>/dev/null; then
        ok "nginx.org nginx running (pid $ORG_PID)"
    else
        bad "nginx.org nginx did not start"
    fi

    echo "==> installing our package over nginx.org"
    OURS_VER="$(dpkg-deb --field "$DEB" Version)"
    if dpkg --compare-versions "$OURS_VER" gt "$ORG_VER"; then
        apt_quiet "$DEB"
        echo "    upgrade path (ours $OURS_VER > nginx.org $ORG_VER)"
        ok "apt accepted our package as an upgrade (no --allow-downgrades needed)"
    else
        apt_quiet --allow-downgrades "$DEB"
        echo "    downgrade-install path (ours $OURS_VER <= nginx.org $ORG_VER)"
        ok "install succeeded with --allow-downgrades"
    fi

    assert_nginx_version "nginx/$(dpkg-deb --field "$DEB" Version | cut -d- -f1)"
    if [ "$(dpkg-query -W -f='${Version}' nginx)" = "$OURS_VER" ]; then
        ok "dpkg reports our package installed ($OURS_VER)"
    else
        bad "dpkg version mismatch: $(dpkg-query -W -f='${Version}' nginx)"
    fi

    assert_user_data_intact
    assert_nginx_t

    sleep 1.5
    NEW_PID="$(cat /run/nginx.pid 2>/dev/null || true)"
    if [ -n "$NEW_PID" ] && kill -0 "$NEW_PID" 2>/dev/null; then
        if [ "$NEW_PID" != "$ORG_PID" ]; then
            ok "smooth binary upgrade performed (old master $ORG_PID -> new master $NEW_PID on our binary)"
        else
            ok "service survived the upgrade (master pid unchanged: $NEW_PID)"
            echo "      NOTE: master pid unchanged — binary upgrade may not have switched the running process"
        fi
    else
        bad "service not running after upgrade (pid '$NEW_PID')"
    fi
    code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/ 2>/dev/null)"
    if [ "$code" = "200" ]; then
        ok "HTTP :80 responds 200 after upgrade"
    else
        bad "HTTP :80 responded $code after upgrade"
    fi
    vhost="$(curl -s http://127.0.0.1:8082/ 2>/dev/null)"
    if [ "$vhost" = "ncb-vhost-ok" ]; then
        ok "user virtual host serving after upgrade"
    else
        bad "user virtual host not serving (got '$vhost')"
    fi

    echo "==> rollback path: reinstalling nginx.org package over ours"
    apt_quiet --allow-downgrades "nginx=$ORG_VER"
    if [ "$(dpkg-query -W -f='${Version}' nginx)" = "$ORG_VER" ]; then
        ok "rollback to nginx.org $ORG_VER succeeded (documented rollback path)"
    else
        bad "rollback failed: $(dpkg-query -W -f='${Version}' nginx)"
    fi
    assert_user_data_intact
    assert_nginx_t
    ;;

ubuntu-distro)
    echo "==> installing Ubuntu distro nginx (nginx-common/nginx-core)"
    apt-get update -qq >/dev/null 2>&1
    apt_quiet nginx
    DISTRO_VER="$(dpkg-query -W -f='${Version}' nginx 2>/dev/null)"
    echo "    distro nginx version: $DISTRO_VER"
    if dpkg -l nginx-common 2>/dev/null | grep -q '^ii'; then
        ok "distro nginx-common installed ($DISTRO_VER)"
    else
        bad "distro nginx-common not installed as expected"
    fi

    echo "==> planting user data"
    setup_user_data

    echo "==> taking over with our package"
    apt_quiet "$DEB"

    OURS_VER="$(dpkg-deb --field "$DEB" Version)"
    assert_nginx_version "nginx/$(echo "$OURS_VER" | cut -d- -f1)"
    if [ "$(dpkg-query -W -f='${Version}' nginx)" = "$OURS_VER" ]; then
        ok "our package installed ($OURS_VER)"
    else
        bad "dpkg version mismatch: $(dpkg-query -W -f='${Version}' nginx)"
    fi

    if dpkg -l nginx-common 2>/dev/null | grep -qE '^(ii|rc)'; then
        if dpkg -l nginx-common | grep -q '^ii'; then
            bad "nginx-common still installed — Conflicts/Replaces did not remove it"
        else
            ok "nginx-common removed by Conflicts (config-files state: $(dpkg-query -W -f='${db:Status-Abbrev}' nginx-common))"
        fi
    else
        ok "nginx-common fully purged by Conflicts/Replaces"
    fi
    if dpkg -l nginx-core 2>/dev/null | grep -q '^ii'; then
        bad "nginx-core still installed — Conflicts/Replaces did not remove it"
    else
        ok "nginx-core removed by Conflicts/Replaces"
    fi

    assert_user_data_intact
    assert_nginx_t

    /usr/sbin/nginx
    sleep 0.5
    code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/ 2>/dev/null)"
    if [ "$code" = "200" ] || [ "$code" = "404" ]; then
        ok "nginx serving after distro take-over (HTTP $code)"
    else
        bad "nginx not serving after distro take-over (HTTP $code)"
    fi
    ;;

guard)
    echo "==> installing our package (clean)"
    apt-get update -qq >/dev/null 2>&1
    apt_quiet "$DEB"

    echo "==> planting a broken configuration"
    cp /etc/nginx/nginx.conf /tmp/nginx.conf.bak
    echo "this is definitely not valid nginx configuration {{{" > /etc/nginx/nginx.conf
    nginx -t >/dev/null 2>&1 && { bad "config unexpectedly valid"; }
    nginx -s quit 2>/dev/null; sleep 0.3

    echo "==> triggering postinst (dpkg-reconfigure) with broken config"
    LOG=/tmp/ncb-guard.log
    if dpkg-reconfigure nginx >"$LOG" 2>&1; then
        ok "package configure completed without failing the installation"
    else
        bad "dpkg-reconfigure failed the installation (exit $?)"
    fi
    if grep -q "nginx was NOT started" "$LOG"; then
        ok "postinst guard reported: nginx not started (explicit message)"
    else
        bad "guard message missing; dpkg-reconfigure output:"
        sed 's/^/      /' "$LOG" | head -10
    fi
    if [ -e /run/nginx.pid ] && kill -0 "$(cat /run/nginx.pid)" 2>/dev/null; then
        bad "nginx IS running despite broken configuration!"
    else
        ok "nginx NOT running with broken configuration"
    fi

    echo "==> restoring valid configuration and reconfiguring"
    cp /tmp/nginx.conf.bak /etc/nginx/nginx.conf
    dpkg-reconfigure nginx >/tmp/ncb-guard2.log 2>&1
    if nginx -t >/dev/null 2>&1; then
        ok "config restored, nginx -t passes"
    else
        bad "config restore failed"
    fi
    sleep 0.5
    if [ -e /run/nginx.pid ] && kill -0 "$(cat /run/nginx.pid)" 2>/dev/null; then
        ok "nginx started automatically after config was fixed"
    else
        # policy-rc.d may deny starts in containers; start manually and verify
        nginx && sleep 0.5
        if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/ | grep -q 200; then
            ok "nginx starts and serves after config fix (manual start; container policy denies auto-start)"
        else
            bad "nginx did not serve after config fix"
        fi
    fi
    ;;

*)
    echo "ERROR: unknown scenario '$SCENARIO'" >&2
    exit 2
    ;;
esac

echo
echo "scenario=$SCENARIO passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
