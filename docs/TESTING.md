# Testing strategy
All package lifecycle tests must run in disposable containers or VMs. Never test package replacement on the agent's host.

## Target matrix
Minimum planned matrix:
- Ubuntu 18.04 Bionic amd64
- Ubuntu 20.04 Focal amd64
- Ubuntu 22.04 Jammy amd64
- Ubuntu 24.04 Noble amd64
Add newer releases only after verifying dependencies and packaging.

## Build/package tests
- Source version resolution exactness.
- Build completes.
- `.deb` exists and metadata is valid (`dpkg-deb --info`).
- Package file list is reviewed (`dpkg-deb --contents`).
- Dependencies resolve on target.
- `nginx -V` reports expected version and build flags.
- Build manifest accurately records target/version/modules/source revisions.
- SHA256 checksum verifies.

## Runtime tests
- Install package in clean target environment.
- `nginx -t` succeeds.
- Start and stop using systemd where container environment supports it; otherwise test service script/unit statically and use an alternate runtime integration test.
- HTTP request succeeds.
- HTTPS request succeeds with test certificate.
- Brotli negotiation and compressed response verified (e.g., request with `Accept-Encoding: br`, inspect `Content-Encoding`).
- Expected modules are present/loadable.
- Custom module configuration can be compiled and tested.

## Upgrade and preservation tests
In disposable target environments, install an official nginx.org package (or a faithfully prepared package/config fixture) and create unique user data:
- custom `nginx.conf` marker;
- custom `conf.d` virtual host;
- site configuration if supported;
- test certificate/key;
- custom log path or log marker;
- cache directory marker where relevant.
Then install/upgrade custom package and assert:
- user config files remain byte-identical;
- certificates remain byte-identical;
- custom site continues to pass `nginx -t`;
- service remains controllable;
- no package script silently deletes data.
Test rollback/downgrade feasibility and document any limitations.

## Removal tests
- Ordinary removal must preserve user configuration and certificates.
- Purge behavior must be documented and must not remove unrelated user data.
- Validate package ownership and file removal behavior.

## Release tests
- Release only after tests pass.
- Asset names are unique and contain target/version/arch.
- Checksums match assets.
- Manifest and module inventory are present.
- Workflow permissions are minimal.
- Workflow cannot publish releases from untrusted PRs.
