# Changelog

All notable changes to this container image are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Maintained by **Daniel G. Cosenza from FNX Labs**.

<!-- changelog:auto -->

## [6.06] — 2026-11-27

### Automated Daily Build
- Verified components: dockur/windows `6.06`, qemus/qemu `7.50`, Base OS `Debian 13.8 (13.8-slim)`.
- Verified guest OS resolvers (HTTP 200): windows `Windows 11 (win11x64, build 26100.4349)`, haiku `R1/beta6 (amd64)`, freebsd `15.1-RELEASE`, debian `13.8.0 (GNOME / KDE)`, ubuntu `26.04.1 LTS`, omarchy `4.5.0 (rolling, no LTS)`.
- Architectures verified: `linux/amd64, linux/arm64` (native QEMU/noVNC smoke tests + Dive efficiency gate).
- Upstream tracking:
  - **dockur/windows:** `6.06` -> `6.06`
  - **qemus/qemu:** `7.50` -> `7.50`
  - **Base image:** `debian:13.8-slim` pinned at `sha256:8aa5a7bf5a1955bddbe7d74fcdd0b91ab30e74362a8b73af672b0481b35b44a0`
  - **Go builder:** `golang:1.27.4-trixie` pinned at `sha256:430985542100b871e108ccc00e8dcc5eef08ca14ee5825e98ebf563d8ffec4ee`
  - `windows`: `Windows 11 (win11x64, build 26100.4349)`
- Vulnerability gate: **0 fixable findings of any severity** in Trivy and Grype (SBOM scan) (68 upstream-unfixed C/H).
- Published multi-arch digest (Docker Hub + GHCR): `dgcosenza/fnxvm@sha256:4251572dd3ca54a7048d9aced6e0199b0d7ebe8d508fe5785b7aabe8bec03b6c` (Cosign OIDC signed + SPDX/CycloneDX SBOM + SLSA L3 provenance).

---

---

## [6.06] — 2026-11-26

### Added
- Initial multi-architecture (`linux/amd64`, `linux/arm64`) **FNXVM** release on pinned **Debian 13.8 (`debian:13.8-slim`)**, combining generic QEMU/KVM runtime from `qemus/qemu` (`v7.50`) and Windows unattended installer from `dockur/windows` (`v6.06`).
- Dynamic runtime OS resolver (`fnxvm-resolve` and `RESOLVE_ONLY=1`) supporting `windows`, `haiku`, `freebsd`, `debian` (`DESKTOP=gnome` and `DESKTOP=kde`), `ubuntu` (latest LTS), `omarchy` (rolling Arch-based, no LTS), plus custom `BOOT=<url>` media.
- Fail-closed runtime integrity verification: SHA-256 checksum verification for all resolved Linux/BSD/Haiku/Omarchy ISOs, bundled offline vendor GPG keyrings (`gpgv`) for Debian, Ubuntu, and Omarchy, and default-on verification (`VERIFY=Y`) for Windows ESD/catalog downloads.
- From-source builds of `websocketd`, `boot-logo` (patched Go 1.27.4 toolchain, zero Go CVEs), and `udfread` (`libudfread` 1.2.0); `qemu.qmp` isolated without `python3-pip` in the runtime image; official Debian 13 `main` QEMU, OVMF, AAVMF, SeaBIOS, Passt, and swtpm packages.
- Real container `HEALTHCHECK` (`/usr/local/bin/fnxvm-healthcheck`) verifying the noVNC web viewer (or VNC port in headless mode) and live QEMU hypervisor state.
- Full daily supply-chain CI pipeline: Hadolint, Gitleaks, public-content check, native `amd64` + `arm64` smoke and resolver tests, Dive efficiency gate, Trivy and Grype 0-fixable-any-severity vulnerability gates, Syft SPDX + CycloneDX SBOMs, keyless Cosign OIDC signing, SLSA Build L3 provenance, OpenSSF Scorecard, Renovate, and dual publishing to Docker Hub and GHCR.
