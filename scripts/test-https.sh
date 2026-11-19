#!/usr/bin/env bash
#
# test-https.sh — Final acceptance: HTTPS request with a test certificate.
# Runs INSIDE a disposable target container. Never on a host with nginx.
#
# Usage: DEB=/work/out/nginx_*.deb bash test-https.sh
#
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq curl openssl >/dev/null 2>&1
DEB="$(ls /work/out/nginx_*.deb | head -1)"
apt-get install -y -qq "$DEB" >/dev/null 2>&1

mkdir -p /srv/ssl-test
echo "https-ok" > /srv/ssl-test/index.html
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /etc/nginx/ssl-acceptance.key -out /etc/nginx/ssl-acceptance.crt \
    -days 1 -subj "/CN=localhost" >/dev/null 2>&1
cat > /etc/nginx/conf.d/zz-ssl-acceptance.conf <<'EOF'
server {
    listen 8443 ssl;
    ssl_certificate     /etc/nginx/ssl-acceptance.crt;
    ssl_certificate_key /etc/nginx/ssl-acceptance.key;
    root /srv/ssl-test;
}
EOF
nginx -t >/dev/null 2>&1 || { echo "FAIL: nginx -t with ssl directives"; exit 1; }
echo "PASS: nginx -t with ssl server block"
nginx
sleep 0.5
body="$(curl -sk https://127.0.0.1:8443/index.html)"
if [ "$body" = "https-ok" ]; then
    echo "PASS: HTTPS request over self-signed cert returns expected body"
else
    echo "FAIL: HTTPS request body: '$body'"
fi
nginx -s quit 2>/dev/null
