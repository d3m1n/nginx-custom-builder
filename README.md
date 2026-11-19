# NGINX Custom Debian Builder

Manually compiled, configurable NGINX Debian packages for Ubuntu targets,
published as GitHub Release assets. Packages follow the **official
[nginx.org](https://nginx.org/en/linux_packages.html) package layout and
behavior** (they are built on the BSD-2-Clause packaging skeleton from
[nginx/pkg-oss](https://github.com/nginx/pkg-oss)) and can be installed
directly over an existing nginx.org installation while preserving all user
configuration, certificates, logs, and data.

**Default build: full nginx.org static module set + Brotli (filter and
static) compiled in.** Optional third-party modules are supported via a
pinned catalog. One `.deb` per (target Ubuntu, NGINX version) build; amd64
only.

> ⚠️ **Not affiliated with NGINX/F5.** NGINX is a trademark of F5 Networks.
> This project repackages the open-source NGINX web server; it does not
> modify nginx source code.

## Supported matrix

| Ubuntu target | Status | Notes |
|---|---|---|
| 22.04 jammy | ✅ validated | includes upgrade-over-nginx.org, distro take-over, postinst-guard suites |
| 24.04 noble | ✅ validated | |
| 20.04 focal | ✅ validated | best-effort legacy target (Ubuntu standard support ended 2025-05) |
| 18.04 bionic | ✅ validated | best-effort legacy target (EOL 2023-05); **distro OpenSSL 1.1.1 is upstream-EOL** — binaries link it as shipped; plan an OS upgrade |
| 26.04 resolute | planned | add after validation |

NGINX versions: any published exact version, or the current Stable / Mainline
release (resolved at build time from nginx.org; exact versions are **never**
silently substituted). Architecture: amd64.

See [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) for the validated
compatibility matrix, artifact hashes, and lifecycle behavior.

## Install

Download a release asset and verify it before installing:

```bash
# 1. verify the checksum (from the release's SHA256SUMS file)
sha256sum -c SHA256SUMS

# 2. install (resolves dependencies from the Ubuntu archive)
sudo apt install ./nginx_<VERSION>-1ncb<N>~<CODENAME>_amd64.deb

# 3. verify
nginx -v          # reports the NGINX version
nginx -V          # configure arguments — check the modules you expect
```

`systemctl start nginx` / `systemctl enable nginx` behave exactly like the
official nginx.org packages (`nginx.service` and `nginx-debug.service` are
provided).

## Upgrade from nginx.org (validated path)

Packages use the same package name (`nginx`) and a version scheme that sorts
above nginx.org builds of the same upstream version
(`<NGINX_VERSION>-1ncb<N>~<CODENAME>`), so switching from nginx.org is a
plain upgrade:

```bash
sudo apt install ./nginx_<VERSION>-1ncb<N>~<CODENAME>_amd64.deb
```

- **Conffiles**: `/etc/nginx/nginx.conf`, `conf.d/default.conf`,
  `mime.types`, etc. are dpkg conffiles — **modified files are kept**, dpkg
  will not overwrite your configuration.
- **Smooth binary upgrade**: if nginx is running, the package performs an
  on-the-fly binary upgrade (USR2), keeping the service up.
- **Broken configuration**: if `nginx -t` fails, the postinst does **not**
  start or reload nginx; it prints explicit instructions instead. Fix the
  configuration and start manually — the package installation itself
  succeeds.
- **Rollback** to nginx.org:

  ```bash
  sudo apt install --allow-downgrades nginx=<nginx.org-version>
  # e.g. nginx=1.30.7-1~jammy
  ```

  User configuration and data survive the rollback (validated).

### Migrating from Ubuntu's own nginx (nginx-core/nginx-common)

Our package `Conflicts/Replaces: nginx-common, nginx-core` and takes over
automatically. Your modified `/etc/nginx/nginx.conf` and any custom files are
preserved. Note: distro configs often include `/etc/nginx/sites-enabled/*`;
the nginx.org-style default config does not include that directory — add an
`include /etc/nginx/sites-enabled/*;` line if you rely on sites-enabled.

## Removal semantics (important)

| Command | `/etc/nginx` | logs / cache | certs |
|---|---|---|---|
| `apt remove nginx` / `dpkg -r nginx` | **preserved** (conffiles kept) | preserved | preserved |
| `apt purge nginx` / `dpkg -P nginx` | **deleted entirely** | deleted | **deleted** |

`purge` behavior matches official nginx.org packages exactly. **Back up
certificates and configuration before purging.**

## Building packages

Everything is driven by the manual GitHub Actions workflow
(`Actions → Build NGINX deb → Run workflow`). Nothing builds or publishes
automatically; releases are created **only** when you explicitly check the
publish box and all tests pass.

Workflow inputs:

| Input | Meaning |
|---|---|
| Target Ubuntu release | `jammy` (default), `noble`, `focal`, `bionic` |
| NGINX version selection | `stable`, `mainline`, or `exact` (+ exact `X.Y.Z`) |
| Optional modules | comma-separated names from `packaging/modules-catalog.json` (e.g. `headers-more`) |
| Custom modules | JSON array `[{"name","url","ref","type":"static"}]` — built without editing scripts |
| Build number | increments rebuilds of the same version (`1`, `2`, …) |
| Publish release | create a GitHub Release **after tests pass** (refuses to overwrite an existing tag) |

Local builds use the same scripts the workflow runs:

```bash
docker build -f containers/Dockerfile.jammy -t nginx-custom-builder:build-jammy .
docker run --rm -v "$PWD/build/prototype:/work" -v "$PWD:/repo:ro" \
  -e WORKDIR=/work -e TARGET_CODENAME=jammy -e NCB_BUILD=1 \
  nginx-custom-builder:build-jammy bash /repo/scripts/build-in-container.sh
# artifacts land in build/prototype/out/ (.deb, SHA256SUMS, manifest.json)
```

Pipeline stages (each a separate script under `scripts/`): version resolution
→ source download + **GPG verification against pinned nginx.org
release-manager keys** → pinned module fetch → `debian/` preparation
(configure-flag validation per resolved version) → `debuild` in the target
container → disposable-container test suite → manifest + checksums.

### Module selection

```json
// packaging/modules-catalog.json (excerpt)
{
  "name": "headers-more",
  "url": "https://github.com/openresty/headers-more-nginx-module",
  "ref": "06dc0be56e5ec9f7fd814e881b066b5540a85bec",   // immutable commit
  "type": "static",
  "status": "validated"
}
```

Tags are resolved to commit SHAs at build time; the resolved commit and tree
hash are recorded in `manifest.json`. Selected modules are compiled into the
binary (static) — no `load_module` lines needed. Dynamic (`.so`) modules are
not supported in the single-package build yet; selecting one fails early with
an explicit message.

## Provenance and verification

Every release ships `manifest.json`: source URL/version/sha256, GPG signing
key fingerprint, pinned module commits and tree hashes, full configure
arguments, excluded optional flags (e.g. flags absent from older NGINX), the
vendored packaging-skeleton commit, target codename/arch, builder commit, and
the package sha256 — plus `SHA256SUMS` and the exact build-environment
package list.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `nginx was NOT started or reloaded` during install | `nginx -t` fails — run `nginx -t` to see the error, fix the config, then `systemctl start nginx` |
| dpkg conffile prompt on upgrade | you modified a packaged config; choose `keep your version` unless you want the packaged default |
| sites from `/etc/nginx/sites-enabled/` stopped loading after migrating from Ubuntu nginx | nginx.org layout has no sites-enabled include — add it to your `nginx.conf` |
| `apt upgrade` wants to replace our package with nginx.org's | expected when nginx.org ships a higher revision (`-2~codename`); nginx.org is authoritative — see [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) |
| Bionic build/service caveats | distro OpenSSL 1.1.1 (upstream EOL) — documented in the manifest and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) D4 |

## Repository layout

- `containers/` — per-target build images (base images pinned by digest; EOL targets fall back to `old-releases.ubuntu.com`)
- `packaging/debian-skeleton/` — vendored `nginx/pkg-oss` debian packaging (BSD-2-Clause, see `NOTICE.md`)
- `packaging/configure-args.sh` — declarative REQUIRED/OPTIONAL configure flags (nginx.org parity baseline)
- `packaging/modules-catalog.json` — optional module catalog
- `scripts/` — pipeline stages + test suites (version scheme validator, build-dep probe, package tests, migration suites, manifest generator)
- `docs/` — requirements, architecture (decisions D1–D7), upstream research, testing strategy, compatibility matrix

## License

- Vendored packaging files: BSD-2-Clause © F5, Inc. (attribution in
  [NOTICE.md](NOTICE.md) / `packaging/nginx.copyright`).
- NGINX itself: BSD-2-Clause. ngx_brotli: BSD-2-Clause; brotli: MIT.
- GPL-3.0 projects evaluated during research were used as references only —
  no GPL code is included.
- The project's own orchestration code has **no license applied yet** —
  choose one before publishing the repository (e.g. BSD-2-Clause to match the
  ecosystem).

## Further documentation

- [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) — product requirements
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — architecture and resolved decisions
- [docs/UPSTREAM_RESEARCH.md](docs/UPSTREAM_RESEARCH.md) — upstream audit (Phase 0)
- [docs/TESTING.md](docs/TESTING.md) — test strategy
- [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) — validated compatibility matrix
- [NOTICE.md](NOTICE.md) — vendored sources, licenses, local deviations
- [PLAN.md](PLAN.md) — development plan and phase evidence
