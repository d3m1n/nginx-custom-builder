# Compatibility matrix and lifecycle behavior

Status: **Validated 2026-11-19 in disposable containers (Phases 2–5 test suites).**
Artifacts under test per target (all nginx 1.30.7, amd64, default module set + Brotli):

| Target | Artifact | Package tests | Migration tests |
|---|---|---|---|
| 22.04 jammy | `nginx_1.30.7-1ncb1~jammy_amd64.deb` (sha256 `28a2ba0d…`) | 26/26 PASS | nginx-org 13/13, ubuntu-distro 8/8, guard 5/5 |
| 20.04 focal | `nginx_1.30.7-1ncb1~focal_amd64.deb` (sha256 `ac66884f…`) | 26/26 PASS | n/a (nginx.org no longer publishes focal; clean install + distro take-over mechanics identical) |
| 24.04 noble | `nginx_1.30.7-1ncb1~noble_amd64.deb` (sha256 `7519cae9…`) | 26/26 PASS | n/a — jammy nginx.org upgrade mechanics are codename-independent (identical packaging skeleton) |
| 18.04 bionic | `nginx_1.30.7-1ncb1~bionic_amd64.deb` (sha256 `27656a18…`) | 26/26 PASS (systemd 237 lacks offline unit verification — structural unit check used; see test note) | n/a |
| jammy + headers-more (custom module, ncb2) | `nginx_1.30.7-1ncb2~jammy_amd64.deb` (sha256 `75c5a5bc…`) | 5/5 module checks (more_set_headers functional + brotli regression) | n/a |

Build provenance per target: `build/<target>/out/manifest.json` + `SHA256SUMS` + `build-env-packages.txt` (distro library versions incl. OpenSSL per target).

## Package metadata (validated via `dpkg-deb --info`, scripts/inspect-package.sh)

| Field | Value | Notes |
|---|---|---|
| Package / Version | `nginx` / `1.30.7-1ncb1~jammy` | same name as nginx.org → standard dpkg replacement path |
| Depends | `libbrotli1 (>= 0.6.0), libc6 (>= 2.34), libcrypt1, libpcre2-8-0, libssl3, zlib1g` | auto-derived by `dh_shlibdeps` — brotli linked against distro libbrotli |
| Recommends | `logrotate` | as nginx.org |
| Provides | `httpd, nginx, nginx-r1.30.7` | as nginx.org |
| Conflicts / Replaces | `nginx-common, nginx-core` | as nginx.org — takes over Ubuntu distro nginx |
| Conffiles (11) | `nginx.conf`, `conf.d/default.conf`, `mime.types`, `fastcgi/scgi/uwsgi_params`, `logrotate.d/nginx`, `init.d/nginx[,-debug]`, `default/nginx[,-debug]` | exactly the pkg-oss/nginx.org set — dpkg preserves user-modified conffiles on upgrade |
| Contents | `/usr/sbin/nginx`, `/usr/sbin/nginx-debug`, `/etc/nginx/*`, `/lib/systemd/system/nginx*.service`, `/etc/nginx/modules → /usr/lib/nginx/modules`, `/usr/share/nginx/html` | nginx.org layout parity |

## Version comparison vs nginx.org (validated with dpkg 1.21.1, 19/19)

| Scenario | Result |
|---|---|
| Install ours over nginx.org same upstream version (`1.30.7-1~jammy`) | **clean apt upgrade** — no flags needed (`ours 1ncb1~jammy > 1~jammy`) ✔ tested |
| nginx.org publishes a revision bump (`-2~jammy`) | nginx.org **supersedes** ours (authoritative update path preserved) ✔ dpkg-tested |
| Rollback: reinstall nginx.org over ours | works with `apt --allow-downgrades`; **user data survives** ✔ tested |
| Requested old exact version (e.g. 1.26.3 while stable is newer) | installs fine; switching back to nginx.org current is a plain upgrade; installing ours over nginx.org current needs `--allow-downgrades` (documented) ✔ dpkg-tested |

## Migration / lifecycle scenarios (scripts/test-package-migration.sh)

### A. Upgrade over nginx.org package (jammy) — 13/13 PASS
1. nginx.org `nginx 1.30.7-1~jammy` installed; **user data planted**: modified `nginx.conf` (marker), custom `conf.d` vhost, TLS cert+key in `/etc/nginx/ssl`, custom log, cache marker.
2. nginx started via init script (as systemd does); our package installed with plain `apt install` (accepted as upgrade).
3. Results:
   - our package installed; binary reports our build ✔
   - **all user data byte-identical** ✔
   - `nginx -t` passes ✔
   - **zero-downtime smooth binary upgrade**: old master (403) → new master (465) running our binary via the init-script `upgrade` path (USR2) ✔
   - HTTP :80 and the user vhost :8082 keep serving ✔
4. **Rollback**: `apt --allow-downgrades nginx=1.30.7-1~jammy` — succeeds; user data intact; `nginx -t` passes ✔

### B. Take-over of Ubuntu distro nginx (jammy: 1.18.0-6ubuntu14.23) — 8/8 PASS
- `Conflicts/Replaces: nginx-common, nginx-core` removed the distro packages (nginx-common → `rc` state: removed, conffiles retained per dpkg semantics) ✔
- Shared conffile `/etc/nginx/nginx.conf`: **user modifications preserved byte-identical** ✔
- Custom vhost, certs, logs, cache marker: preserved ✔
- `nginx -t` passes; nginx serves after take-over ✔
- Caveat (documented, nginx.org parity): the distro default config includes `/etc/nginx/sites-enabled/*`; the nginx.org-style `nginx.conf` does not. User sites under sites-enabled are not loaded after migration unless the user adds the include. This is exactly what happens when migrating from distro nginx to nginx.org packages.

### C. postinst `nginx -t` guard (local deviation #1) — 5/5 PASS
- Broken `nginx.conf` + `dpkg-reconfigure nginx`: package **configure succeeds** (installation not failed), explicit message `nginx was NOT started or reloaded`, nginx **not running** ✔
- Config restored + reconfigure: `nginx -t` passes; nginx starts and serves ✔ (auto-start is denied by container `policy-rc.d`; on real hosts systemd starts it)

### D. Clean install / remove / purge (Phase 2 suite, scripts/test-package.sh) — 26/26 PASS
- Clean install: layout, units, logrotate, modules symlink, HTTP, brotli (dynamic + static + negative), systemd verify ✔
- **Ordinary removal (`dpkg -r` / `apt remove`): nothing deleted** — `/etc/nginx` incl. user configs and `/var/log/nginx` preserved ✔
- Reinstall after remove: succeeds; conffiles kept ✔
- **Purge (`dpkg -P` / `apt purge`): removes `/etc/nginx`, `/var/log/nginx`, `/var/cache/nginx` entirely** — nginx.org parity semantics; ⚠️ operators must back up certificates/configs before purging (documented in NOTICE.md; to be repeated in README Phase 7)

## Build provenance recorded per package (manifest.json)
Source URL/version/sha256, GPG signing key fingerprint, pinned ngx_brotli + vendored brotli commits and tree hashes, full configure args, excluded optional flags, pkg-oss skeleton commit, target codename/arch, builder commit, package sha256, build environment package snapshot.

## Known limitations (documented, not silently hidden)
- `nginx-dbg` debug-symbols package is not built (single-`.deb` requirement); binaries are stripped like official packages; `nginx-debug` binary is shipped in the main package.
- The running nginx keeps serving the OLD (deleted) binary if the init-script binary upgrade fails for any reason — same as official nginx.org packages; the postinst reports it and the operator can `systemctl restart nginx`.
- Upgrade-over-nginx.org was tested on jammy only (the only target where nginx.org packages exist today); bionic/focal get clean-install take-over of distro nginx (same mechanics, to be validated in Phase 5).
- Container `policy-rc.d` denies service auto-start in test containers; systemd behavior on real hosts follows the vendored units and `dh_installsystemd` wiring (unit files verified with `systemd-analyze verify`).
