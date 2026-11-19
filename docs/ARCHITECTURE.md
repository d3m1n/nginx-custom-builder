# Architecture

Status: **Drafted after Phase 0 upstream research (2026-11-19). Decisions below are grounded in the evidence collected in `UPSTREAM_RESEARCH.md`.**

The implementation reuses the BSD-2-Clause `nginx/pkg-oss` debian packaging skeleton and builds a thin, purpose-owned orchestration layer around it. The runner is orchestration only; every compile and package operation happens inside a container image of the target Ubuntu release.

## Pipeline

```text
workflow_dispatch (manual; least-privilege token)
    |
    v
[1] Input validation (strict allow-lists; no free-form shell)
    |    - target Ubuntu: bionic | focal | jammy | noble
    |    - NGINX: exact "X.Y.Z" | channel=stable | channel=mainline
    |    - optional module list (catalog names) + custom modules (JSON, schema-validated)
    |
    v
[2] Version resolution (on runner, no compilation)
    |    - exact: verbatim, never substituted; fails if unknown
    |    - stable: latest 1.30.x from nginx.org/download; mainline: latest 1.31.x
    |    - records resolved version, tarball URL, sha256, PGP verify result
    |
    v
[3] Source acquisition + verification (on runner)
    |    - nginx tarball from nginx.org, GPG-verified against the pinned set of
    |      nginx.org release-manager keys (arut/pluknet/sb/thresh from
    |      nginx.org/en/pgp_keys.html; NOTE: nginx_signing.key 573BFD6B...
    |      signs APT/RPM repositories, not source tarballs)
    |    - ngx_brotli pinned by commit SHA (google/ngx_brotli), hash recorded
    |    - optional/custom modules pinned by tag/commit, hashes recorded
    |    - pkg-oss debian skeleton vendored in-repo; upstream pkg-oss commit recorded in metadata
    |
    v
[4] Target build container (docker, image pinned by digest, amd64)
    |    - ubuntu:jammy / ubuntu:noble (archive.ubuntu.com)
    |    - ubuntu:focal / ubuntu:bionic (old-releases.ubuntu.com repoint, EOL handling)
    |    - install build-deps (debhelper compat 11, libssl-dev, libpcre2-dev, zlib1g-dev, libbrotli-dev)
    |    - generate debian/ from pkg-oss skeleton + our configure args
    |      (BASE_CONFIGURE_ARGS parity baseline + version-validated flags + brotli)
    |    - debuild -> ONE .deb per (target, version) containing binary + brotli + selected dynamic modules
    |
    v
[5] Disposable test container (same target image)
    |    - dpkg -i (clean) -> nginx -V / -t, HTTP, HTTPS, brotli negotiation test
    |    - upgrade scenario: install nginx.org jammy package first (where available),
    |      plant user config/certs/logs markers, then install ours; assert preservation
    |    - removal/purge behavior; service unit validated (systemd container run or static
    |      unit checks per TESTING.md)
    |
    v
[6] Artifact finalization (on runner)
    |    - SHA256 checksums, JSON build manifest (source URL/version, hashes, configure args,
    |      module inventory + pinned refs, target Ubuntu, arch, builder commit, pkg hash)
    |
    v
[7] GitHub Release (only if user checked "publish"; assets: .deb, .sha256, manifest, module list)
```

Stages 2–7 are separate scripts (not one big script), each with its own failure mode, so a failing stage never publishes anything.

## Resolved decisions from research

### D1. Base / reuse strategy
Vendor (copy into `packaging/debian-skeleton/`) the `debian/debian/` files from `nginx/pkg-oss` @ a pinned upstream commit, BSD-2-Clause attribution in `LICENSE`/`NOTICE` and in `debian/copyright`. Keep our own thin orchestration scripts. Upstream commit recorded in every build manifest. Do not fork pkg-oss.

### D2. Package name, metadata, and nginx.org migration
- Package name: **`nginx`** (identical to nginx.org) — same-name replacement is the standard dpkg path; this mirrors `pkg-oss` itself.
- `Provides: httpd, nginx`; `Conflicts: nginx-common, nginx-core`; `Replaces: nginx-common, nginx-core` (copied semantics from pkg-oss control) to take over distro nginx safely.
- No `Conflicts:` against nginx.org's `nginx` — same-name packages cannot conflict with themselves; upgrade ordering is governed by version comparison.
- Version scheme (**validated 2026-11-19 with `dpkg --compare-versions` on dpkg 1.21.1 — see `scripts/validate-version-scheme.sh`, 19/19 PASS**):
  `<NGINX_VERSION>-1ncb<n>~<CODENAME>` (e.g. `1.30.7-1ncb1~jammy`).
  - The vendor suffix `ncb<n>` is placed **before** the `~codename` part. This is deliberate: a candidate scheme `1~jammy+ncb<n>` was evaluated and **rejected** — `~` sorts before end-of-string in dpkg, so `1~jammy+ncb1` compares LESS than a bare revision `1` (documented pitfall; tests assert the corrected scheme beats both).
  - `ours (1ncb1~jammy) > nginx.org (1~jammy)` → clean `apt` upgrade over an nginx.org install.
  - `nginx.org -2~jammy > ours -1ncb1~jammy` → a nginx.org revision bump remains the authoritative upgrade target (documented rollback path).
  - Our rebuilds increase monotonically (`ncb2`, `ncb10` compare numerically).
  - Requesting an old exact version (e.g. 1.26.3 while nginx.org stable is 1.30.7) yields a version lower than nginx.org current — switching back to nginx.org is a normal upgrade (documented); installing our old-version package over nginx.org current requires `dpkg -i` or `apt --allow-downgrades` (documented).
  - Against distro nginx with the same upstream version (e.g. Ubuntu's `1.18.0-6ubuntu14.4` vs a hypothetical ours `1.18.0-…`), the higher distro revision may win in apt comparisons; direct `dpkg -i` take-over still works and `Conflicts/Replaces` removes the distro packages — covered by Phase 3 tests.
- Conffiles: `/etc/nginx/nginx.conf`, `/etc/nginx/conf.d/default.conf`, `/etc/nginx/mime.types` marked as conffiles exactly like pkg-oss → dpkg preserves user-modified files on upgrade, offers conffile prompts on conflicts, never silently overwrites. `/var/log/nginx`, `/var/cache/nginx`, certs and sites are outside package control and are never touched by maintainer scripts (pkg-oss postrm is already minimal; we audit it line-by-line when vendoring).

### D3. Module policy
- **Default (static, in-binary) module set** = pkg-oss `BASE_CONFIGURE_ARGS` minus NGINX-Plus-only flags: http_addition, http_auth_request, http_dav, http_flv, http_gunzip, http_gzip_static, http_mp4, http_random_index, http_realip, http_secure_link, http_slice, http_ssl, http_stub_status, http_sub, http_v2, http_v3*, mail(+ssl), stream(+realip/ssl/ssl_preread), threads, file-aio, with-compat. This is the nginx.org parity baseline.
  - *Version-sensitive flags (`--with-http_v3_module` needs nginx ≥ 1.25; some flags appeared/disappeared across 1.18→1.31) are validated against `./configure --help` for the resolved version before building; unknown/absent flags fail the build with an actionable message listing supported flags — never silently dropped.
- **Brotli: enabled by default.** Default mode: compile `ngx_http_brotli_filter_module` and `ngx_http_brotli_static_module` **into the binary** (`--add-module`) with `--with-compat` retained. Rationale: single-package requirement, "enabled by default" without touching user config (`load_module` directives would otherwise have to be injected into user-owned config space), no `.so`/ABI coupling for future dynamic-module users. The pkg-oss `Makefile.module-brotli` recipe is the reference for source integration (`libbrotli-dev` at build time; module license files shipped).
- **Optional nginx.org-parity dynamic modules** (catalog entries, off by default; each compiles as dynamic `.so` inside the same single `.deb`): geoip, image-filter, njs, perl, xslt, otel, acme — mirroring nginx.org's separate module packages. Their per-NGINX-version availability is catalog metadata; unsupported combos fail before compile.
- **Custom modules**: JSON input (schema-validated) — `{name, repo URL, ref: tag|commit (immutable), type: static|dynamic, extra deps}`. Commit SHA required for branches/tags when resolvable; everything recorded in the manifest. Untrusted source policy: built in the disposable build container only.

### D4. Target Ubuntu strategy
| Target | Build env | Apt source | Notes |
|---|---|---|---|
| 18.04 bionic | container `ubuntu:18.04` (digest-pinned) | old-releases.ubuntu.com | EOL; best-effort; OpenSSL 1.1.1 (EOL 2023) — documented caveat |
| 20.04 focal | container `ubuntu:20.04` (digest-pinned) | old-releases.ubuntu.com | EOL standard support; best-effort |
| 22.04 jammy | container `ubuntu:22.04` (digest-pinned) | archive.ubuntu.com | fully supported; nginx.org parity exists |
| 24.04 noble | container `ubuntu:24.04` (digest-pinned) | archive.ubuntu.com | fully supported; nginx.org parity exists |
| 26.04 resolute | future addition | archive.ubuntu.com | add after validation |

- All builds always run in the target container — even jammy, where the runner could build natively — for isolation and determinism (AGENTS.md engineering preference).
- **Build-dep probe (2026-11-19, `scripts/probe-build-deps.sh`, evidence):** all required packages available on all four targets — `debhelper` 13.x on every target (compat 11 OK), `libssl-dev` (bionic 1.1.1-1ubuntu2.1~18.04.23 / focal 1.1.1f / jammy 3.0.2 / noble 3.0.13), `libpcre2-dev`, `zlib1g-dev`, **`libbrotli-dev` on every target** (bionic 1.0.3 / focal 1.0.7 / jammy 1.0.9 / noble 1.1.0), plus `quilt`, `devscripts` (debuild), `equivs`, `dpkg-dev`, `lsb-release`, `libxml2-utils`, `xsltproc`, toolchain. Notably, `archive.ubuntu.com` still served both bionic and focal at probe time; the old-releases repoint fallback stays in the build scripts as EOL insurance.
- EOL targets are explicitly documented as best-effort with frozen distro libraries; no silent fallback. If a requested (version, target) combination is unbuildable, the workflow fails with an explicit message.
- Pilot target for Phase 2 prototype: **jammy** (most representative, fully supported by runners, containers, and nginx.org — needed for the upgrade-over-nginx.org tests).

### D5. Service lifecycle
Vendored from pkg-oss: `nginx.service` (systemd), `nginx-debug.service`, init script, logrotate, `nginx.default`. Maintainer scripts keep pkg-oss semantics: `--no-stop-on-upgrade --no-start` wiring + postinst binary-upgrade when running. Hardening on top (our additions): postinst/prerm never touch user data; no reload/restart if `nginx -t` fails (wrap the pkg-oss postinst upgrade path with a `nginx -t` guard and leave the service stopped-but-intact on failure, with a clear message; this is the one intentional deviation from pkg-oss, justified by AGENTS.md safety requirements).

### D6. Supply chain, threat model & reproducibility

**Threat model (supply-chain focused):**

| Threat | Mitigation |
|---|---|
| Compromised/tampered nginx tarball | HTTPS download from nginx.org + **GPG signature verification** against the pinned nginx signing key fingerprint (`573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62`) + sha256 recorded in the manifest; build fails on any mismatch |
| Malicious or hijacked third-party module source | Immutable pin (commit SHA, or tag resolved to SHA at validation time) + hash recorded; module code is built only inside the disposable build container and never executed on the runner |
| Tampered or drifting base images | Docker images pinned **by digest**, not by tag |
| Workflow input injection (arbitrary shell from `workflow_dispatch` inputs) | Inputs reduced to enums (target, channel) and strict regex-validated strings (exact version `^[0-9]+\.[0-9]+\.[0-9]+$`); custom modules passed as JSON validated against a schema (name pattern, HTTPS git URL, commit/tag pattern); inputs are never interpolated into shell without quoting; no `eval`; actions pinned by commit SHA |
| Runner/token compromise leaking publish rights | Least-privilege: `contents: read` everywhere except the final publish job (`contents: write`); `workflow_dispatch` only — no `pull_request` trigger can publish; release job protected |
| Typosquatting / mistaken module repo | Manifest records the resolved git URL, ref, resolved commit SHA and tarball hash for every module — auditable after the fact |
| Package downgrade attack / accidental overwrite | Version scheme keeps nginx.org authoritative above our builds (validated); release tags are never overwritten — a duplicate tag fails the workflow before publishing |
| Unattended unsafe service restart | Maintainer scripts run `nginx -t` before any reload/restart; on validation failure the service is left untouched with an explicit message |

Out of scope / trust boundaries: compromise of nginx.org or the module upstreams themselves is beyond our control; the GPG check and pinned hashes define our verification boundary. Post-install host security is the operator's responsibility (documented in README).

**Reproducibility (best-effort, provenance-complete):**

- All inputs pinned and hashed: nginx tarball (GPG + sha256), module commits, base image digests, vendored pkg-oss skeleton commit, GitHub action SHAs.
- Build environment: container per target release. EOL targets (bionic/focal) are effectively frozen; jammy/noble receive security updates in their repos, so byte-identical rebuilds are **not** promised. Instead, the manifest records the exact build environment snapshot (`dpkg-query` output of build packages) for auditability.
- `SOURCE_DATE_EPOCH` set from the nginx tarball mtime where practical; `debuild` flags fixed; parallelism normalized.
- Manifest (JSON) covers the full provenance chain: source URL/version/hash, GPG verify result, configure args, module inventory with pinned refs and hashes, target Ubuntu + arch + codename, builder git commit, base image digest, package sha256.

### D7. Release naming
Asset name: `nginx_<VERSION>-1ncb<n>~<CODENAME>_amd64.deb` (matches the internal dpkg version; target codename is embedded, so multi-target releases for one nginx version cannot collide). Release tag: `nginx-<VERSION>-<CODENAME>` (one release per target/version combination built in a run; pre-release flag for mainline builds).

## Design constraints (carried from requirements)

- The runner is orchestration; compilation and packaging occur in isolated target environments.
- Target libraries must be compatible with the target Ubuntu release (container-per-target enforces this).
- Package installation must not replace user configuration without conffile protections and tests.
- External module sources are pinned and recorded.
- Release publication happens after test success and only on explicit user input.

## Known risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Bionic OpenSSL 1.1.1 is EOL (2023-09) | Security exposure for bionic builds | Documented best-effort status in README/matrix; no patches possible from us; users advised to upgrade OS; manifest records linked OpenSSL version |
| ngx_brotli has no formal releases | Supply-chain ambiguity | Pin commit SHA + record hash; bump consciously; watch upstream (active: Oct 2026, brotli submodule v1.2.1) |
| dpkg version comparison subtleties vs nginx.org | Broken upgrade/downgrade expectations | Dedicated Phase 1 tests with `dpkg --compare-versions` on real nginx.org version strings; Phase 3 container upgrade tests |
| Conffile behavior differs between "modified" and "unmodified" user configs | Unexpected prompts/overwrites | Phase 3 tests plant modified + unmodified configs; assert dpkg conffile semantics; never use `dpkg --force-confnew` |
| Configure flags drift across nginx versions (1.18…1.31) | Broken builds for older/newer versions | Flag validation against `./configure --help` per resolved version; per-version catalog notes; explicit failures |
| systemd not present by default in plain ubuntu containers | Service tests limited | Per TESTING.md: systemd-enabled container run for jammy/noble + static unit validation elsewhere |
| old-releases.ubuntu.com availability/latency | EOL target build flakiness | Digest-pinned images + retry; document degraded support; focal/bionic are best-effort |
| nginx.org drops jammy support eventually (already dropped bionic/focal) | Upgrade-from-nginx.org tests impossible on newer targets | Upgrade tests only where an nginx.org package exists (jammy today); others test clean install + takeover from distro nginx where feasible |

## Deferred decisions

- ~~Final revision string~~ — **resolved 2026-11-19**: `X.Y.Z-1ncb<n>~<codename>`, validated by `scripts/validate-version-scheme.sh` (19/19 PASS in ubuntu:22.04 container, dpkg 1.21.1).
- Whether optional dynamic modules get `load_module` conf files in a package-owned, non-conffile location without touching user config (exact mechanics during Phase 4).
- Final per-target build-dep lists in Dockerfiles (availability proven by probe; exact lists captured from the Phase 2 prototype).
- Resolution strategy for the nginx.org signing key (pin the current key file + fingerprint; rotate plan when nginx.org rotates keys — key expires 2027-05-24).
