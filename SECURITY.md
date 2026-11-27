# Security Policy

Maintained by **Daniel G. Cosenza from FNX Labs**.

## Supported Versions

Only the latest daily build (`latest`) receives security updates. Immutable date-stamped tags (`<version>-YYYYMMDD`) are frozen for reproducibility.

## Vulnerability Scanning & Gates

- **Trivy** (OS + packages + compiled Go/Python binaries): SARIF uploaded to GitHub Code Scanning; table and JSON reports retained for 90 days; **blocking hard gate** on any fixable finding of any severity (`UNKNOWN`, `LOW`, `MEDIUM`, `HIGH`, `CRITICAL`, `--ignore-unfixed`, exit code 1) on every published architecture.
- **Grype** (on Syft SPDX SBOM): **blocking hard gate** (`--only-fixed --fail-on negligible`); table report retained for 90 days.
- **SBOM & Provenance**: SPDX-JSON and CycloneDX-JSON SBOMs per architecture attached as Cosign attestations; SLSA Build L3 provenance via `actions/attest-build-provenance`; keyless Cosign OIDC signatures on both Docker Hub and GHCR.
- **ISO Integrity**: No OS media are baked into the image. Guest ISOs are downloaded directly from official vendor endpoints at runtime and verified against vendor checksums and (for Debian, Ubuntu, and Omarchy) bundled vendor GPG public keys; mismatches fail closed and delete the downloaded artifact.

## Reporting a Vulnerability

**Do not open a public issue** for security vulnerabilities.

Report privately through GitHub Security Advisories: open the repository's **Security** tab or submit a private advisory directly at [dgcosenza/fnxvm-docker Security Advisories](https://github.com/dgcosenza/fnxvm-docker/security/advisories/new).

For upstream vulnerabilities in QEMU, `qemus/qemu`, or `dockur/windows`, also follow the respective upstream security reporting channels.
