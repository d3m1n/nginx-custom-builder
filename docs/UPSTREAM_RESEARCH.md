# Upstream research

Research status: **Verified 2026-11-19 (Phase 0 complete).**
All findings below were checked against the source repositories and official
nginx.org resources on 2026-11-19, not against search snippets.

## Audit date and environment

- Audit date: 2026-11-19.
- NGINX current versions (nginx.org/en/download.html): Mainline **1.31.9**, Stable **1.30.7**, Legacy 1.28.3 / 1.26.3 / 1.24.0 / 1.22.1 / 1.20.2 / 1.18.0.
- nginx.org supported Ubuntu for official packages (nginx.org/en/linux_packages.html): **22.04 jammy, 24.04 noble, 26.04 resolute only.** 18.04 and 20.04 are no longer served by nginx.org repositories.

---

## Candidate audit

### 1. nginx/pkg-oss — official NGINX packaging sources

- URL: https://github.com/nginx/pkg-oss (master branch inspected 2026-11-19).
- License: **BSD-2-Clause** (© F5, Inc.). Safe to copy/adapt with attribution and copyright notice retention.
- Maintenance: official repository of the nginx.org packaging maintainers; 898+ commits; last commits 2026-11-09..11 ("Updated nginx to 1.31.9", "Updated nginx-acme to 0.4.2"). Actively maintained, release-following.
- What it contains (evidence):
  - `debian/Makefile` — the authoritative build recipe. `BASE_CONFIGURE_ARGS` defines the exact nginx.org path layout and static module set (`--prefix=/etc/nginx`, `--sbin-path=/usr/sbin/nginx`, `--modules-path=/usr/lib/nginx/modules`, `--pid-path=/run/nginx.pid`, `--user=nginx`, `--with-compat`, `--with-http_ssl_module`, `--with-http_v2_module`, `--with-http_v3_module`, `--with-stream`, mail, etc.). `BASE_MODULES=acme geoip image-filter njs otel perl xslt` defines the dynamic modules nginx.org ships as separate packages.
  - `debian/debian/` — complete debhelper packaging skeleton: `nginx.control.in`, `nginx.rules.in`, `nginx.postinst`, `nginx.postrm`, `nginx.preinst`, `nginx.prerm`, `nginx.service`, `nginx-debug.service`, `nginx.init.in`, `nginx.logrotate`, `nginx.conf`, `nginx.default.conf`, `nginx.dirs`, `nginx.install`, `nginx.docs`, `nginx.manpages`, `nginx.lintian-overrides`, `compat` (=11).
  - `debian/debian/nginx.control.in` package metadata: `Provides: httpd, nginx, nginx-r%%BASE_VERSION%%`; `Conflicts: nginx-common, nginx-core`; `Replaces: nginx-common, nginx-core`; `Recommends: logrotate`. Same package name `nginx` as nginx.org uses — an identically-named package is the standard dpkg replacement path.
  - `debian/debian/nginx.rules.in`: debhelper 11-style build, `dh_installinit --no-stop-on-upgrade --no-start`, `dh_installsystemd`, hardening flags (`hardening=+all`, `-fPIC`), Ubuntu ≥ 24.04 special-cased (`-fPIC` only, no `-D_FORTIFY_SOURCE=2` redefinition). Confirms the target release affects build flags.
  - `debian/debian/nginx.postinst`: on install/upgrade starts nginx via init script, or performs a binary upgrade (`/etc/init.d/nginx upgrade`) if the master process is running. Never deletes configuration.
  - `debian/Makefile.module-brotli` — **official ready-made Brotli recipe**: builds `ngx_brotli` as dynamic modules (`--add-dynamic-module`), build-depends on `libbrotli-dev`, ships `ngx_http_brotli_filter_module.so` + `ngx_http_brotli_static_module.so`.
  - `contrib/src/ngx_brotli/version` pins `NGX_BROTLI_VERSION := 1.0.0` (contrib tarball snapshot of google/ngx_brotli).
  - `build_module.sh` — supported helper to build third-party dynamic modules against the official package conventions.
  - `.github/workflows/ci.yml` — Ubuntu packages are built **directly on an ubuntu-24.04 runner** (target codename comes from the build environment via `lsb_release -cs`, see `CODENAME` in `debian/Makefile`); Alpine/RHEL builds use containers. This confirms the pkg-oss model: build environment == target release.
- What is reusable:
  - The entire `debian/debian/` packaging skeleton (BSD-2) — control, rules template, maintainer scripts, service unit, logrotate, default configs.
  - `BASE_CONFIGURE_ARGS` as the parity baseline for nginx.org-compatible builds.
  - The brotli module recipe concept (ngx_brotli + libbrotli-dev) adapted to our pipeline.
  - The `Contributors`/`docs/nginx.copyright` approach for license files.
  - The pinned-action CI pattern (`uses: actions/checkout@<sha> # vX`).
- What is NOT directly reusable:
  - The Makefile orchestration itself assumes a single build environment per invocation and builds modules as **separate packages**; our requirement is one `.deb` per target/version with configurable module inclusion, so we need our own thin orchestration layer.
  - No per-Ubuntu-target container matrix (their CI only builds on one Ubuntu at a time).

### 2. angristan/nginx-autoinstall

- URL: https://github.com/angristan/nginx-autoinstall (inspected 2026-11-19).
- License: **GPL-3.0**. Copying any of its code would force GPL-3.0 on this project — avoid copying entirely.
- Maintenance: 457 commits; last meaningful activity ~2022; last commit 2025-01-01 is a dependabot actions bump. Effectively dormant.
- Design: interactive/HEADLESS shell script that compiles and installs NGINX **directly on the host**. Produces **no `.deb`**. Uses apt pinning to *block* apt nginx packages — the opposite of our "installable over nginx.org package" requirement.
- Module menu (brotli, headers-more, geoip2, cache_purge, fancyindex, dav-ext, vts, ModSecurity, lua, rtmp, …) is a useful *catalog reference* for which third-party modules users commonly want.
- Conclusion: **not suitable as a base.** Reference only (module catalog, OpenSSL/brotli compile flag patterns as general knowledge).

### 3. u-sb/nginx-source (n.wtf)

- URL: https://github.com/u-sb/nginx-source (inspected 2026-11-19).
- License: BSD-2-Clause.
- Maintenance: active, ~987 commits; tracks official nginx releases; this is the source fork behind the n.wtf package repository.
- Design: a **fork of the entire nginx source tree** (auto/, src/, conf/ etc.) plus a `debian/` directory derived from **Debian's own nginx packaging** (git-buildpackage; `nginx-common`, `libnginx-mod-*` multi-package layout, sites-enabled, debhelper autoscripts). Third-party modules (brotli, zstd, lua, ndk, rtmp, nchan, geoip2, headers-more, cache-purge, dav-ext, echo, fancyindex, auth-pam, uploadprogress, upstream-fair, subs-filter, acme, …) are vendored into the source tree and packaged as separate `libnginx-mod-*` packages.
- Conclusion: **not suitable as a base** for our goals:
  - Debian-layout multi-package output, not the nginx.org single-`nginx`-package layout we must match.
  - Forking the whole nginx source means re-merging on every upstream change — heavy maintenance.
  - Useful reference: their `debian/` maintainer scripts show how the Debian layout handles conffiles; their module inventory overlaps with angristan's.

### 4. darylounet/libnginx-mod-brotli

- URL: https://github.com/darylounet/libnginx-mod-brotli (stable branch, inspected 2026-11-19).
- License: **GPL-3.0** — no code copying.
- Maintenance: active; last commit 2026-10-27 ("Updated brotli upstream to fix CVE-2026-111497"). 29 commits.
- Design: Dockerfiles that build a **separate** `libnginx-mod-brotli` dynamic-module `.deb` **pairing with official nginx.org packages**; per-distro builds via `--build-arg DISTRIB=ubuntu --build-arg RELEASE=noble --build-arg NGINX_VERSION=1.26.0`; distributes via packagecloud, not GitHub Releases.
- Conclusion: **not suitable as a base** (single module, separate-package model, GPL). Useful reference for: per-target Docker build parameters and for the practice of tracking brotli CVE updates.

### 5. google/ngx_brotli (the Brotli module itself — required dependency)

- URL: https://github.com/google/ngx_brotli (inspected 2026-11-19).
- License: BSD-style 2-clause (module); vendored brotli submodule is MIT.
- Maintenance: canonical module maintained under google org; last commit **2026-10-22** ("Update brotli submodule to v1.2.1"). Sporadic but alive, and nginx's own pkg-oss depends on it.
- Provides both `ngx_http_brotli_filter_module` (on-the-fly compression) and `ngx_http_brotli_static_module` (serving pre-compressed `.br` files). Supports building against system `libbrotli-dev` or the vendored submodule.
- **Risk:** the repository has no meaningful release tags (the "1.0.0" era predates formal releases); pkg-oss works around this with a contrib tarball snapshot. Our mitigation: **pin an immutable commit SHA** (selected at build-spec time, recorded in the manifest), verify its hash, and record it in release metadata.

---

## Official nginx.org references (verified)

- https://nginx.org/en/linux_packages.html:
  - Supported Ubuntu: 22.04 "jammy", 24.04 "noble", 26.04 "resolute" (amd64 + arm64). **18.04/20.04 no longer published** → for those targets there is no nginx.org package to upgrade from, and our builds are standalone additions.
  - Dynamic modules shipped as separate packages: `nginx-module-geoip`, `nginx-module-image-filter`, `nginx-module-njs`, `nginx-module-perl`, `nginx-module-xslt`, plus `nginx-module-otel` (since 1.25.3) and `nginx-module-acme` (since 1.29.1).
  - Repository pinning guidance (`Pin-Priority: 900` for o=nginx) shows apt-level competition between nginx.org and distro packages is an expected scenario; our `Conflicts/Replaces: nginx-common nginx-core` (same as pkg-oss) handles the distro side.
- https://nginx.org/en/download.html: version channels (Mainline 1.31.9 / Stable 1.30.7 as of audit date); tarballs published with detached PGP signatures (`.asc`) signed by the release managers' personal keys listed on https://nginx.org/en/pgp_keys.html (arut, pluknet, sb, thresh; primary fingerprints pinned in `scripts/fetch-nginx.sh`). The `nginx_signing.key` (fingerprint `573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62`, expires 2027-05-24) signs the **package repositories**, not the source tarballs — verified during Phase 2 prototyping and corrected accordingly.
- `nginx/pkg-oss` = official packaging sources for the packages on that page ("The `master` branch holds packaging sources for the current mainline version, while `stable-*` branches contain latest sources for stable releases").

## Ubuntu target feasibility (verified)

- 18.04 bionic: standard support ended 2023-05-31 (ubuntu-announce); packages moved to `old-releases.ubuntu.com`; GitHub-hosted `ubuntu-18.04` runner image is retired. Builds must run in a `ubuntu:18.04` container with apt sources repointed to old-releases. Distro OpenSSL is 1.1.1 (upstream EOL 2023-09) — see Risks.
- 20.04 focal: standard support ended 2025-05; archive moving to old-releases; runner image retired; container builds with old-releases sources; OpenSSL 3.0 (supported).
- 22.04 jammy, 24.04 noble: fully supported by Ubuntu and nginx.org; standard runners can even build jammy natively, but we will still use per-target containers for isolation and determinism.
- 26.04 resolute: exists and is supported by nginx.org; out of our initial matrix, add later.

---

## Comparison table

| Criterion | nginx/pkg-oss | angristan/nginx-autoinstall | u-sb/nginx-source | darylounet/libnginx-mod-brotli |
|---|---|---|---|---|
| License | BSD-2-Clause ✔ | GPL-3.0 ✘ (no copy) | BSD-2-Clause ✔ | GPL-3.0 ✘ (no copy) |
| Maintenance (2026-11) | Official, release-following ✔ | Dormant ~2022 | Active | Active (module-only) |
| Output | `.deb`/`.rpm`/apk, modules as separate packages | No package (host install) | Debian-layout multi-package .debs | Single brotli module .deb |
| nginx.org path/layout parity | **Exact** (it *is* the source) | Partial | No (Debian layout) | Pairs with official packages |
| Ubuntu target coverage | Build env defines target (per-run) | Any Ubuntu (host script) | Several (n.wtf) | Per-docker-arg |
| Version/channel selection | By checkout branch | Menu/script vars | Branch per release | NGINX_VERSION build arg |
| Brotli | Official module recipe present ✔ | Option ✔ (host) | Option ✔ (vendored) | Focus of the project ✔ |
| Custom modules mechanism | `build_module.sh` + Makefile.module-* | Menu options | Vendored in tree | n/a |
| Reusable for us | **Yes — packaging skeleton + configure args + brotli recipe** | No (reference only) | No (reference only) | No (reference only) |

---

## Recommendation

**Option C of the research deliverable, executed concretely: build a new minimal orchestration layer that vendors and adapts the BSD-2-Clause `nginx/pkg-oss` debian packaging skeleton.**

Rationale:
1. `pkg-oss` is the literal source of truth for the nginx.org packages we must stay compatible with — reusing its `debian/debian/` skeleton, `BASE_CONFIGURE_ARGS` and maintainer scripts maximizes layout/behavior parity for free and keeps the licensing clean (BSD-2, attribution).
2. None of the community projects produce a single nginx.org-layout `.deb` with configurable modules for multiple Ubuntu targets; both usable-code candidates (pkg-oss) or suitable references (u-sb, darylounet) confirm this gap, and the two shell-script/ML approaches are GPL-3.0 and/or don't produce packages.
3. The official brotli module recipe (`Makefile.module-brotli` + `contrib/src/ngx_brotli`) gives us a maintained integration path for the mandatory Brotli requirement; we adapt it to build inside our single package (default: compiled into the binary; decision documented in ARCHITECTURE.md).
4. Forking a whole project (u-sb style) or maintaining patches against pkg-oss master would add upstream-tracking burden without adding capabilities we need; a thin, owned pipeline that *consumes* pkg-oss files (pinned by upstream commit, recorded in metadata) is the smallest maintainable surface.

Rejected alternatives:
- **Fork pkg-oss wholesale**: their Makefile orchestration targets one distro per run and multi-package output; a fork would carry permanent divergence. We vendor the debian skeleton instead and pin the upstream revision in build metadata.
- **Base on angristan/nginx-autoinstall or darylounet**: GPL-3.0 blocks code reuse; neither produces the required artifact.
- **Base on u-sb/nginx-source**: wrong package layout (Debian-style), full source fork maintenance burden.

## Open items carried into Phase 1 (design decisions)

- Exact dpkg version/revision scheme vs nginx.org (candidate: `1.30.7-1~jammy+<vendor><n>` so ours supersedes same-rev nginx.org builds while a nginx.org revision bump (`-2~jammy`) still supersedes ours — to be proven with `dpkg --compare-versions` tests).
- Brotli linking policy (default static-into-binary vs dynamic .so) — see ARCHITECTURE.md recommendation.
- Whether optional nginx.org-parity dynamic modules (geoip, image-filter, njs, perl, xslt, otel, acme) are offered in the single-package build, and their per-version availability matrix.
- Bionic/Focal container image pinning by digest and old-releases apt handling details.
