# Changelog

All notable changes to this container image are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Maintained by **Daniel G. Cosenza from FNX Labs**.

<!-- changelog:auto -->

---

## [6.06] — 2026-11-26

### Added
- Initial multi-architecture (`linux/amd64`, `linux/arm64`) **FNXVM** release on pinned **Debian 13.8 (`debian:13.8-slim`)**, combining generic QEMU/KVM runtime from `qemus/qemu` (`v7.50`) and Windows unattended installer from `dockur/windows` (`v6.06`).
- Dynamic runtime OS resolver (`fnxvm-resolve` and `RESOLVE_ONLY=1`) supporting `windows`, `haiku`, `freebsd`, `debian` (`DESKTOP=gnome` and `DESKTOP=kde`), `ubuntu` (latest LTS), `omarchy` (rolling Arch-based, no LTS), plus custom `BOOT=<url>` media.
- Fail-closed runtime integrity verification: SHA-256 checksum verification for all resolved Linux/BSD/Haiku/Omarchy ISOs, bundled offline vendor GPG keyrings (`gpgv`) for Debian, Ubuntu, and Omarchy, and default-on verification (`VERIFY=Y`) for Windows ESD/catalog downloads.
- From-source builds of `websocketd`, `boot-logo` (patched Go 1.27.4 toolchain, zero Go CVEs), and `udfread` (`libudfread` 1.2.0); `qemu.qmp` isolated without `python3-pip` in the runtime image; official Debian 13 `main` QEMU, OVMF, AAVMF, SeaBIOS, Passt, and swtpm packages.
- Real container `HEALTHCHECK` (`/usr/local/bin/fnxvm-healthcheck`) verifying the noVNC web viewer (or VNC port in headless mode) and live QEMU hypervisor state.
- Full daily supply-chain CI pipeline: Hadolint, Gitleaks, public-content check, native `amd64` + `arm64` smoke and resolver tests, Dive efficiency gate, Trivy and Grype 0-fixable-any-severity vulnerability gates, Syft SPDX + CycloneDX SBOMs, keyless Cosign OIDC signing, SLSA Build L3 provenance, OpenSSF Scorecard, Renovate, and dual publishing to Docker Hub and GHCR.
