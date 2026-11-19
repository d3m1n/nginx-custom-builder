#!/usr/bin/env bash
#
# configure-args.sh — declarative configure flag set (sourced by build scripts).
#
# Flags mirror nginx/pkg-oss BASE_CONFIGURE_ARGS (the nginx.org parity
# baseline), classified by behavior across NGINX versions:
#
#   REQUIRED_FLAGS  — must be present in `./configure --help` of the resolved
#                     nginx version, otherwise the build FAILS with an
#                     actionable message. These are layout flags and modules
#                     that exist across all supported versions (1.18+).
#   OPTIONAL_FLAGS  — included only when supported by the resolved version;
#                     inclusion/exclusion is recorded in the build metadata.
#                     Never silently dropped (AGENTS.md requirement).
#
# Brotli is handled separately by the build scripts via
# --add-module=<ngx_brotli> (mandatory; build fails if unavailable).
#

REQUIRED_FLAGS=(
    # filesystem layout — nginx.org parity
    --prefix=/etc/nginx
    --sbin-path=/usr/sbin/nginx
    --modules-path=/usr/lib/nginx/modules
    --conf-path=/etc/nginx/nginx.conf
    --error-log-path=/var/log/nginx/error.log
    --http-log-path=/var/log/nginx/access.log
    --pid-path=/run/nginx.pid
    --lock-path=/run/nginx.lock
    --http-client-body-temp-path=/var/cache/nginx/client_temp
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp
    --user=nginx
    --group=nginx
    --with-compat
    # core capabilities
    --with-file-aio
    --with-threads
    # static HTTP modules (nginx.org set)
    --with-http_addition_module
    --with-http_auth_request_module
    --with-http_dav_module
    --with-http_flv_module
    --with-http_gunzip_module
    --with-http_gzip_static_module
    --with-http_mp4_module
    --with-http_random_index_module
    --with-http_realip_module
    --with-http_secure_link_module
    --with-http_slice_module
    --with-http_ssl_module
    --with-http_stub_status_module
    --with-http_sub_module
    --with-http_v2_module
    # mail / stream
    --with-mail
    --with-mail_ssl_module
    --with-stream
    --with-stream_realip_module
    --with-stream_ssl_module
    --with-stream_ssl_preread_module
)

OPTIONAL_FLAGS=(
    # version-dependent modules; included when the resolved nginx supports them
    --with-http_v3_module      # >= 1.25
    --with-http_json_module    # newest mainline only
)
