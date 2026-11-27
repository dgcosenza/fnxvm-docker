# Changelog

All notable changes to this container image are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Maintained by **Daniel G. Cosenza from FNX Labs**.

<!-- changelog:auto -->

## [6.06.2] — 2026-11-27

### Added
- New guest OS **`OS=daemonarchy`** ([jordanhubbard/daemonarchy](https://github.com/jordanhubbard/daemonarchy), Omarchy Hyprland desktop on FreeBSD 16.0-CURRENT, not affiliated with Omarchy) with dynamic GitHub Releases resolution matching `^daemonarchy-[0-9]+\.[0-9]+\.[0-9]+$` (skipping package/checkout/extension feeds, drafts, and prereleases), graceful unauthenticated runtime fallback, fail-closed SHA-256 verification of the compressed `.iso.xz` prior to `xz -dc` decompression, and full `amd64` + `arm64` (UEFI-only community-validation) support.
- Host <-> guest clipboard sharing (`CLIPBOARD=Y|N`, default `Y`): attaches `virtio-serial-pci` + `com.redhat.spice.0` with QEMU 10's `-chardev qemu-vdagent,id=vdagent,name=vdagent,clipboard=on` for VNC/noVNC (and `spicevmc` when optional `SPICE=Y` is active); restores native `RFB.clipboardPasteFrom()` in the noVNC Clipboard panel alongside a **Type** keystroke fallback for guests without `spice-vdagent`.
- Configurable video acceleration via **`GPU=auto|virtio|virgl|qxl|std`** (default `auto`): installs official Debian 13 `qemu-system-modules-opengl`, `qemu-system-modules-spice`, and `libegl-mesa0`; selects safe software display devices when `/dev/dri` is absent; preserves Windows upstream defaults and Haiku VESA compatibility; gracefully falls back with a warning instead of crashing when `GPU=virgl` is requested without `/dev/dri`.
- Authenticated-by-default console access:
  - Web UI (`8006`, including `/websockify`, `/status`, and `/audio`) protected by nginx HTTP Basic Authentication with **bcrypt** hashes (`apache2-utils` `htpasswd -niB`), configured via `WEB_USER` (default `fnxvm`), `WEB_PASSWORD`, and `WEB_PASSWORD_FILE` (separate from Windows `USERNAME`/`PASSWORD`). Auto-generates a 24-character random password on first start, prints it once, and persists only its bcrypt hash in `/storage/.fnxvm-web.htpasswd`. Includes an explicit `WEB_AUTH=N` escape hatch with a loud startup warning.
  - VNC (`5900`) protected by QEMU `-vnc ...,password=on` configured over a private QMP Unix socket (`set_password`) via `VNC_PASSWORD` / `VNC_PASSWORD_FILE` (when unset, an independent random 8-character secret is generated, printed once, and persisted mode `0600` in `/storage/.fnxvm-vnc.secret`; it is never derived from the Web UI password and never exposed in `/proc/<pid>/cmdline`).
  - Container-internal Unix-socket nginx health endpoint (`/run/shm/nginx-health.sock`) for `fnxvm-healthcheck` so no unauthenticated TCP routes exist on port `8006`.
- Date-stamped tags (`<version>-<YYYYMMDD>`) are now immutable: a second same-day build publishes `<version>-<YYYYMMDD>.N` instead of re-pointing an already released tag.
- Expanded `tests/smoke.sh` to verify HTTP Basic Auth (`401`/`401`/`200`) on `8006`, WebSocket auth (`401`/`401`/`101`) on `/websockify`, RFB VNC Authentication (security type `2`, never `None`) on `5900`, first-start hash persistence across restarts, `WEB_PASSWORD_FILE`/`VNC_PASSWORD_FILE` secrets, `qemu-vdagent` + `virtio-serial` in QEMU args and live QMP `query-chardev`, `GPU=auto`/`virtio`/`virgl` fallback, `CLIPBOARD=N`, `WEB_AUTH=N`, and all 7 OS resolvers.

---

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
- Published multi-arch digest (Docker Hub + GHCR): `dgcosenza/fnxvm@sha256:5f1c711d3438fb735b06de103bcfaefd89e97ac04dee452b99402446c2f3d0ff` (Cosign OIDC signed + SPDX/CycloneDX SBOM + SLSA L3 provenance).
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
