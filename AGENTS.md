# Agent Instructions — NGINX Custom Debian Builder

## Mission
Build a maintainable GitHub project that manually compiles configurable NGINX versions into a single Debian `.deb` package for Ubuntu targets, publishes packages to GitHub Releases, and preserves compatibility with existing nginx.org installations and configurations.

## Language and working style
- Repository documentation and user-facing instructions: English.
- Communicate progress and decisions to the user in Russian unless asked otherwise.
- Work in small, reviewable phases. Do not jump directly to implementation.
- Prefer well-maintained upstream tooling and reuse existing projects where their licenses and architecture fit.
- Avoid unnecessary dependencies and avoid building a custom packaging system when Debian tooling can do the job.

## Mandatory first steps
1. Inspect the repository and current files before changing anything.
2. Research the candidate upstream projects listed in `docs/UPSTREAM_RESEARCH.md`, including their current state, licenses, release activity, build design, package layout, and whether they actually meet the target requirements. Verify claims using source repositories, not search snippets alone.
3. Inspect official nginx.org package layout and packaging sources (`nginx/pkg-oss`) and determine which packaging components can be reused safely.
4. Produce/update `PLAN.md`, `docs/ARCHITECTURE.md`, and `docs/UPSTREAM_RESEARCH.md` with evidence, trade-offs, and a recommended implementation before coding.
5. Report the proposed architecture and any blocking decisions. If there are no blockers, proceed with the smallest safe prototype after documenting the plan.

## User requirements (fixed)
- Target Ubuntu: start at 18.04 (Bionic), then 20.04 (Focal), 22.04 (Jammy), 24.04 (Noble), and future Ubuntu releases when support is feasible.
- NGINX: support exact version, Stable, and Mainline selection. Build older versions when technically feasible; don't silently substitute a requested version.
- Architecture: amd64 only.
- Build trigger: manual GitHub Actions workflow (`workflow_dispatch`).
- Distribution: GitHub Releases.
- Package output: one `.deb` per selected target/version combination.
- Default module set: modules corresponding to standard nginx.org package capabilities, after research and documented mapping.
- Brotli: enabled by default, including HTTP filter and static modules where supported.
- Custom modules: extensible mechanism to add third-party modules by repository and pinned tag/commit. Disabled by default unless selected.
- Compatibility: nginx.org-like filesystem layout, commands, service behavior and package upgrade/downgrade expectations where feasible.
- Install/upgrade must preserve existing configuration, sites, certificates, logs, and user data. Never overwrite user configuration without explicit user choice.
- Package must be installable over an existing nginx.org package where dependency and package-manager behavior permits. Investigate package naming, conflicts, provides/replaces, and migration behavior before asserting compatibility.
## Safety and integrity requirements
- Do not run destructive commands on the host or modify an existing NGINX installation during development/testing.
- Test installation, upgrade, removal, and config preservation only in disposable containers or VMs.
- Never delete, replace, or rewrite `/etc/nginx` user configuration as part of package installation.
- Do not make package scripts automatically reload/restart NGINX if configuration validation fails.
- Avoid unsafe shell evaluation, unpinned downloads, unverified checksums, or secrets in logs.
- Pin external module revisions (tag or commit); record them in build metadata.
- Treat third-party source code and build scripts as untrusted until reviewed.
- Validate all workflow inputs; don't allow arbitrary shell injection through inputs.
- Build for the selected Ubuntu target in a target-compatible environment; do not compile against a newer libc/OpenSSL and package the result for an older Ubuntu release.
- Clearly document unsupported targets or versions instead of silently falling back.
## Engineering preferences
- Use Docker/OCI target build environments where practical; GitHub-hosted runners should orchestrate, not contaminate target dependencies.
- Use Debian packaging standards and maintainers scripts carefully. Prefer reproducible builds and deterministic metadata where practical.
- Keep build configuration declarative and validate it with a schema or strict validation code.
- Include source URL/version, configure arguments, modules, target Ubuntu, architecture, build commit, and hashes in metadata.
- Separate version resolution, source acquisition, module acquisition, compilation, packaging, testing, and release publishing.
- Default to full standard module capabilities plus Brotli, while allowing selected additional modules.
- Do not make undocumented assumptions about module compatibility across NGINX versions.
## Workflow expectations
- Keep a `PLAN.md` with checkboxes and update it as tasks are completed.
- Each phase should have tests and evidence before being marked complete.
- Run formatting, linting, validation, and tests relevant to changed files.
- For each phase, report: changes, commands/tests run, results, remaining risks, and next step.
- Do not publish a release or deploy anything unless the user explicitly authorizes it.
## Completion definition
The project is not complete until all target Ubuntu builds (or explicitly documented unsupported targets) are built and tested; package install, upgrade from nginx.org, configuration preservation, NGINX config test, HTTP/HTTPS, Brotli, modules, systemd behavior, package removal, checksums, and GitHub Release asset workflow have been validated in disposable environments.
