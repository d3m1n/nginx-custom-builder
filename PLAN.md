# Development Plan

Status: **COMPLETE (2026-11-19) — Phases 0-7 done, all targets validated locally, pipeline validated end-to-end on GitHub Actions (run 44530501808: success)**

## Phase 0 — Repository and upstream audit — DONE (2026-11-19)
- [x] Inspect the repository and identify existing content. (Only docs/spec files present; no implementation code.)
- [x] Verify candidate projects in `docs/UPSTREAM_RESEARCH.md` directly. (pkg-oss, angristan/nginx-autoinstall, u-sb/nginx-source, darylounet/libnginx-mod-brotli, google/ngx_brotli — all inspected via GitHub API/raw sources on 2026-11-19.)
- [x] Inspect `nginx/pkg-oss` packaging sources and official package layout. (debian/Makefile, debian/debian/*, Makefile.module-brotli, contrib/src/ngx_brotli, ci.yml.)
- [x] Compare licenses, maintenance activity, build systems, supported Ubuntu versions, modules, packaging, and release process. (Comparison table in UPSTREAM_RESEARCH.md.)
- [x] Identify a reusable base or conclude that a clean implementation is justified. (Vendor pkg-oss BSD-2 debian skeleton + thin own orchestration layer.)
- [x] Update research notes with links, dates, evidence, risks, and recommendation. (UPSTREAM_RESEARCH.md rewritten; ARCHITECTURE.md drafted with resolved decisions D1–D7.)

Key evidence (see docs/UPSTREAM_RESEARCH.md for details):
- pkg-oss is the official nginx.org packaging source, BSD-2-Clause, actively maintained (commits 2026-11-09..11, nginx 1.31.9).
- nginx.org Ubuntu targets in 2026-11: jammy, noble, resolute only — bionic/focal dropped.
- Current versions: mainline 1.31.9, stable 1.30.7.
- angristan/nginx-autoinstall and darylounet are GPL-3.0 → reference-only (no code reuse).
- Brotli: official pkg-oss recipe exists (ngx_brotli + libbrotli-dev, filter + static submodules).

Exit criteria met: evidence-based upstream recommendation recorded; licensing (BSD-2 attribution) and packaging questions resolved into Phase 1 test items.


## Phase 1 — Architecture and design — DONE (2026-11-19)
- [x] Define workflow inputs and validation. (Draft in ARCHITECTURE.md pipeline step 1; threat model D6 defines input hardening.)
- [x] Define target Ubuntu build matrix and EOL repository strategy. (D4: bionic/focal via containers with old-releases fallback, best-effort.)
- [x] Define version resolution for exact / Stable / Mainline. (Pipeline step 2; implemented in scripts/resolve-version.sh, tested — stable resolves to 1.30.7.)
- [x] Define module catalog, default module set, Brotli and custom module schema. (D3: pkg-oss BASE_CONFIGURE_ARGS baseline; brotli static-into-binary default; REQUIRED/OPTIONAL flag classes in packaging/configure-args.sh.)
- [x] Define package name, version/revision, dependencies, file layout, maintainer scripts, service lifecycle. (Name/layout/scripts in D2/D5; revision scheme validated — see below; build-dep availability proven for all 4 targets.)
- [x] Define nginx.org package upgrade/replace compatibility strategy. (D2: same package name, Provides/Conflicts/Replaces from pkg-oss; upgrade tests in Phase 3.)
- [x] Define release naming, metadata, checksums, and provenance. (D6/D7; manifest generator implemented in scripts/make-manifest.sh.)
- [x] Document threat model and reproducibility approach. (D6 expanded with threat table + provenance model.)
- [x] Validate `dpkg --compare-versions` behavior for the revision scheme against real nginx.org version strings. (scripts/validate-version-scheme.sh: 19/19 PASS on dpkg 1.21.1 in ubuntu:22.04. Candidate `1~jammy+ncb<n>` REJECTED — sorts below bare revision `1` because `~` sorts before end-of-string; adopted scheme `<VERSION>-1ncb<n>~<codename>`.)
- [x] Pin concrete build-dep lists per target from a dry-run container probe. (scripts/probe-build-deps.sh: all deps incl. libbrotli-dev and debhelper>=11 present on bionic/focal/jammy/noble; archive.ubuntu.com currently serves even bionic/focal; old-releases fallback kept.)
Exit criteria met: architecture reviewed in docs; compatibility assumptions have test plans (dpkg tests done; Phase 3 container test plan in TESTING.md).

Evidence captured during Phase 1 also corrected a verification model assumption:
nginx source tarballs are signed by the release managers' personal keys
(pgp_keys.html: arut/pluknet/sb/thresh), not by nginx_signing.key (which signs
the APT/RPM repositories). Pinned fingerprints are in scripts/fetch-nginx.sh.


## Phase 2 — Minimal build prototype — DONE (2026-11-19)
- [x] Build one pinned NGINX version for one target Ubuntu (pilot **jammy**, nginx **1.30.7** stable — resolved by scripts/resolve-version.sh).
- [x] Build with standard modules and Brotli. (39 required + 1 optional (v3) + brotli filter/static compiled in; `--with-http_json_module` correctly excluded for 1.30.x and recorded.)
- [x] Produce one installable `.deb`. (`nginx_1.30.7-1ncb1~jammy_amd64.deb`, 1.17 MB after strip — nginx.org parity size; single package incl. nginx-debug binary; separate nginx-dbg package dropped per single-.deb requirement.)
- [x] Record build metadata and checksums. (`out/manifest.json` + `out/SHA256SUMS` + `build-env-packages.txt`; deb sha256 2e7c43d7…6c2761.)
- [x] Validate in a disposable target container. (`scripts/test-package.sh` — **26/26 PASS**: install, version/args parity, layout (nginx.org paths, units, logrotate, modules symlink), systemd unit verification, HTTP 200, `nginx -t`, brotli dynamic + static + no-compress-without-accept-encoding, ordinary remove preserves user configs/logs, reinstall, documented purge semantics.)
Exit criteria met: clean package installs, NGINX starts, `nginx -t` succeeds, basic HTTP and Brotli tests pass.

Implementation notes (evidence from prototype debugging):
- Build tree lives on the container-native filesystem (`/build`); only artifacts are copied to the mounted workspace (Docker Desktop gRPC-FUSE mounts break dpkg-source tree walks and are slow for compilation).
- Vendored skeleton files must be permission-normalized after overlay (debhelper ≥ 13 executes config files carrying +x; Windows mounts set +x everywhere).
- nginx `./configure --help` exits 1 after printing help (upstream quirk) — tolerated explicitly.
- `debian/rules clean` runs `rm -rf debian/build-*` — build metadata file named `ncb-build-info.env` to survive it.
- Per-target build images created: `containers/Dockerfile.{jammy,noble,focal,bionic}` with digest-pinned bases (`nginx-custom-builder:build-jammy` used for the prototype).
- nginx tarball GPG verification uses the pinned set of nginx.org release-manager keys (tarballs are signed by release managers, not by nginx_signing.key).


## Phase 3 — Debian package and compatibility — DONE (2026-11-19)
- [x] Match nginx.org filesystem paths and command behavior where feasible. (Vendored pkg-oss skeleton; layout verified by tests: sbin, conf, modules symlink, units, logrotate, default conf, html.)
- [x] Review package metadata and dependency model. (scripts/inspect-package.sh: Depends auto-incl. libbrotli1; Provides/Conflicts/Replaces mirror nginx.org; 11 conffiles exactly as nginx.org.)
- [x] Implement safe maintainer scripts. (pkg-oss set + postinst `nginx -t` guard; guard validated in guard scenario.)
- [x] Preserve existing config files and user data. (Conffile semantics byte-verified in both migration scenarios.)
- [x] Test install over clean OS. (Phase 2 suite 26/26.)
- [x] Test upgrade over nginx.org package in disposable environment. (nginx-org scenario 13/13: apt upgrade without flags, **zero-downtime binary upgrade master 403→465**, user data intact, rollback path validated.)
- [x] Test config preservation with customized nginx.conf, conf.d, site configs, and certificates. (Hash-verified markers on modified nginx.conf, custom vhost, TLS cert/key, log, cache marker — intact in all scenarios.)
- [x] Test package removal and purge behavior; do not delete user data on ordinary removal. (remove preserves everything; purge documented as full wipe — nginx.org parity; see docs/COMPATIBILITY.md.)
Exit criteria met: compatibility matrix documented (docs/COMPATIBILITY.md); all package lifecycle tests pass.

Evidence from Phase 3 debugging:
- A test-harness bug was found and fixed: starting nginx with a bare command name (`nginx`) makes the USR2 binary-upgrade exec use a relative argv[0] and fail with ENOENT. Real systems start nginx via systemd/init with the absolute path (`/usr/sbin/nginx`) — as our vendored unit/init do — and the upgrade works. Package behavior confirmed identical to official nginx.org packages.


## Phase 4 — Configurable build and modules — DONE (2026-11-19)
- [x] Support exact NGINX version, Stable, Mainline. (resolve-version.sh: mainline→1.31.9, stable→1.30.7, exact verbatim — 6/6 validation tests incl. malformed/nonexistent/unknown-mode failures.)
- [x] Validate version resolution; never silently change requested version. (Nonexistent exact version = hard error with available-versions hint; tested.)
- [x] Implement module catalog/configuration. (packaging/modules-catalog.json + scripts/select-modules.sh + scripts/fetch-custom-module.sh; ad-hoc modules via CUSTOM_MODULES_JSON.)
- [x] Enable Brotli by default, including filter/static module functionality as supported. (Both compiled into binary; dynamic+static compression tests pass.)
- [x] Support optional external modules by URL plus pinned tag/commit. (ref resolved to immutable commit via git ls-remote (raw SHAs accepted); commit + tree sha256 recorded in manifest; catalog entry headers-more upgraded to SHA pin after validation.)
- [x] Validate module compatibility and fail with actionable messages. (7/7 select-modules tests: unknown module, non-https URL, dynamic type, missing config — all fail BEFORE compile with explicit messages.)
- [x] Test default and custom module builds. (headers-more v0.37 @ 06dc0be5 built into jammy package: 5/5 functional checks incl. more_set_headers header injection and brotli regression pass.)
Exit criteria met: build inputs are validated, modules are reproducibly pinned, package metadata identifies module versions (manifest + ncb-build-info.env).
Known limitation (documented, ARCHITECTURE.md deferred decisions): dynamic (.so) modules are not yet packaged in the single-package model — selection fails before compile with an explicit message; nginx.org-parity dynamic modules (geoip, njs, perl, xslt, otel, acme) are future work.


## Phase 5 — Ubuntu target expansion — DONE (2026-11-19)
- [x] Build/test Bionic 18.04. (Build OK on digest-pinned ubuntu@sha256:152dc042… with debhelper 11 / OpenSSL 1.1.1 / gcc 7; package tests 26/26 — systemd 237 has no offline unit verification, test falls back to structural unit check, documented.)
- [x] Build/test Focal 20.04. (Build OK; 26/26.)
- [x] Build/test Jammy 22.04. (Build OK; 26/26 + full migration suites from Phase 3.)
- [x] Build/test Noble 24.04. (Build OK; 26/26.)
- [ ] Add later Ubuntu releases when supported and verified. (26.04 resolute — deferred until validated; nginx.org supports it today.)
- [x] Document unsupported combinations (NGINX version/module/target) rather than silently skipping. (Configure-flag validation fails per resolved version; bionic OpenSSL 1.1.1 EOL caveat documented in ARCHITECTURE D4; dynamic modules fail selection with explicit message.)
Exit criteria met: each advertised target has evidence from package installation and smoke tests (docs/COMPATIBILITY.md matrix with artifact hashes and per-target manifests).

Per-target artifacts (all nginx 1.30.7, brotli compiled in, stripped):
- `nginx_1.30.7-1ncb1~jammy_amd64.deb` — sha256 28a2ba0d… (26/26 + migration 26/26)
- `nginx_1.30.7-1ncb1~focal_amd64.deb` — sha256 ac66884f… (26/26)
- `nginx_1.30.7-1ncb1~noble_amd64.deb` — sha256 7519cae9… (26/26)
- `nginx_1.30.7-1ncb1~bionic_amd64.deb` — sha256 27656a18… (26/26)
- `nginx_1.30.7-1ncb2~jammy_amd64.deb` — sha256 75c5a5bc… (jammy + headers-more, 5/5)


## Phase 6 — GitHub Actions and Releases — DONE (2026-11-19, **validated by a real end-to-end run**)
- [x] Add manual `workflow_dispatch`. (.github/workflows/build.yml; no push/PR triggers.)
- [x] Inputs: target Ubuntu, NGINX version/channel, module selection/custom modules, release publishing choice. (All inputs enum/regex-validated via env vars — no shell injection surface.)
- [x] Use least-privilege workflow permissions. (Top-level contents:read; release job alone gets contents:write behind the `release` environment; all three actions pinned by commit SHA.)
- [x] Build in isolated target environment. (Per-target digest-pinned Dockerfiles built in-job; build tree on container-native fs.)
- [x] Run test jobs before publication. (Separate test job: fresh-container package suite for every target + jammy migration suites nginx-org/ubuntu-distro/guard.)
- [x] Create release assets only after all required tests pass. (release job needs: test.)
- [x] Publish `.deb`, SHA256 checksums, build metadata, and module manifest. (.deb + .changes + .buildinfo + manifest.json + SHA256SUMS + build-env snapshot; checksum verified pre-publish.)
- [x] Prevent accidental overwrite or confusing release tag collisions. (Tag `nginx-<VERSION>-<CODENAME>`; explicit pre-check refuses an existing release with guidance to increment ncb_build.)
Exit criteria met with evidence — real run https://github.com/d3m1n/nginx-custom-builder/actions/runs/44530501808 (jammy/stable/ncb4, publish=false):
- build → success (2.6 min), test → success (2.9 min), release → skipped (as designed).
- Package suite **26/26**, nginx-org migration **13/13**, distro take-over **8/8**, postinst guard **5/5** — all on the GitHub-hosted runner.
- Artifact `nginx-deb-jammy-ncb4` (1.18 MB) uploaded with .deb/.changes/.buildinfo/manifest.json/SHA256SUMS/build-env snapshot.


## Phase 7 — Documentation and final review — DONE (2026-11-19)
- [x] README installation, upgrade, build, and troubleshooting instructions. (Full rewrite: install + checksum verification, nginx.org upgrade + rollback, distro migration, removal/purge semantics with warnings, module selection, provenance, troubleshooting table.)
- [x] Document supported Ubuntu/NGINX/module matrix. (README matrix + docs/COMPATIBILITY.md with per-target artifacts and hashes.)
- [x] Document compatibility limitations and migration rollback. (COMPATIBILITY.md limitations section; purge warning; sites-enabled migration caveat; bionic OpenSSL caveat.)
- [x] Document checksum verification. (README Install section + release-notes template in the workflow.)
- [x] Review license obligations for all upstream sources and modules. (NOTICE.md: BSD-2 pkg-oss attribution, nginx/ngx_brotli/brotli licenses, GPL references-only statement. OPEN DECISION: license for the project's own orchestration code deliberately unset — user chooses before publication.)
- [x] Review workflow permissions and supply-chain risks. (D6 threat model; actions pinned by SHA; env-based input validation; workflow_dispatch only.)
Exit criteria met: a user can select a build, verify the release, install/upgrade safely, and recover using documented steps.


## Final acceptance — validated 2026-11-19 (evidence: docs/COMPATIBILITY.md, PLAN.md phase sections)
- [x] All advertised targets are tested in disposable environments. (jammy/focal/noble/bionic — 26/26 each)
- [x] Package installs and uninstalls correctly. (Phase 2 suite: install/remove/reinstall/purge)
- [x] Upgrade from nginx.org package tested. (jammy, 13/13, zero-downtime binary upgrade)
- [x] Existing user configuration and certificates preserved. (hash-verified markers across all scenarios)
- [x] `nginx -t` passes. (all suites)
- [x] NGINX service starts and responds over HTTP/HTTPS. (HTTP 200 all targets; HTTPS request with test certificate verified — nginx -t with ssl directives + `curl -sk https://` body check)
- [x] Brotli verified with request/response test. (dynamic + static + negative, all targets)
- [x] All advertised modules verified. (default set: configure args + nginx -t; brotli functional)
- [x] Custom module build tested. (headers-more, 5/5 functional)
- [x] Release assets and SHA256 verified. (SHA256SUMS generated and consumed by tests/manifest)
- [x] No release/deployment occurred without explicit user approval. (nothing pushed/published; workflow requires explicit publish input)
