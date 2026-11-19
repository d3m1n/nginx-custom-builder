# Requirements

## 1. Purpose
Build configurable NGINX Debian packages for Ubuntu targets using GitHub Actions. Packages should be suitable for replacing/upgrading an nginx.org package while retaining the familiar NGINX configuration and operational layout.

## 2. Supported build inputs
- Ubuntu target: Bionic 18.04 minimum, then Focal 20.04, Jammy 22.04, Noble 24.04 and future releases as validated.
- CPU architecture: amd64 only.
- NGINX source selection: exact version, Stable channel, Mainline channel.
- Build invocation: manual GitHub Actions workflow.
- Distribution: GitHub Releases.
- Artifact: one `.deb` for each selected target/version configuration.

Version resolver must clearly identify the resolved version and source URL. Exact versions must never be silently replaced. Channel resolution must record the resolved version in the release metadata.

## 3. Modules
- Default module capabilities should align as closely as practical with standard nginx.org packages. Research and document the exact module inventory and whether each is static, dynamic, or unavailable for a target.
- Brotli enabled by default: filter and static functionality, subject to upstream compatibility.
- Additional third-party modules must be configurable.
- Third-party modules must be pinned by immutable commit or verified tag; record source and revision.
- Unsupported module/version/target combinations must fail clearly before compile or be explicitly disabled with a warning only when user requested optional behavior.
- Modules must be packaged in the single resulting `.deb` unless a technical limitation is documented and approved.
## 4. Package and compatibility
- Single `.deb` output.
- Use Debian packaging conventions and lifecycle scripts.
- Match nginx.org paths/operational behavior where feasible: binary, config, modules, logs, cache, PID, service, and command behavior.
- Investigate package name, version scheme, `Conflicts`, `Replaces`, `Provides`, dependencies, upgrade and downgrade behavior. Do not assume the package can safely replace nginx.org solely because paths match.
- Preserve user-owned configuration and data during install/upgrade.
- Never overwrite custom configuration silently.
- Never remove configuration, certificates, logs, or cache containing user data on normal package removal.
- If config validation fails, do not trigger an unsafe reload/restart.
- Provide rollback guidance and test package lifecycle.
## 5. Build security and reproducibility
- Build in isolated target-compatible environments.
- Avoid target packages built against newer libc/OpenSSL.
- Validate inputs; avoid shell injection.
- Pin module source revisions and verify downloads where possible.
- Record source version, source hashes, module revisions, build flags, target Ubuntu, architecture, builder commit, and package hash.
- Use least-privilege GitHub Actions permissions.
- Do not publish releases automatically from untrusted pull requests.
## 6. Release assets
- `.deb` package.
- SHA256 checksum file.
- Build metadata manifest (JSON recommended).
- Module inventory.
- Human-readable release notes with target Ubuntu and NGINX version.
- Release asset names should include NGINX version, Ubuntu version, and architecture.
## 7. User experience
- Manual workflow should offer clear target Ubuntu and NGINX version/channel selection.
- Defaults should be safe and useful; Brotli on by default.
- Custom modules should be supported without editing build scripts.
- README should explain download, checksum verification, installation, upgrade, testing, rollback, and troubleshooting.
