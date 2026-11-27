# Changelog

All notable changes to this container image are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Maintained by **Daniel G. Cosenza from FNX Labs**.

<!-- changelog:auto -->

## [6.06.3] — 2026-11-27

### Added
- **Universal Web / noVNC bidirectional clipboard:**
  - Async Clipboard API integration (`navigator.clipboard.writeText` / `readText`) over HTTPS and `localhost` with graceful fallback to the Clipboard panel on plain HTTP, Safari, Firefox, and mobile/tablet browsers (iOS/Android).
  - Guest copies populate the Clipboard panel automatically and sync to the client system clipboard when permitted (highlighting the Clipboard icon with a one-tap **Copy from VM** button when the browser requires a user gesture).
  - Client-to-guest paste works via automatic focus/click sync (when `clipboard-read` is granted), `Ctrl+V` / `Ctrl+Shift+V` / macOS `Cmd+V` interception without clobbering in-VM copy/paste, native DOM `paste` events, **Paste from Device**, **Copy to VM**, and non-ASCII-safe **Type (ASCII)** keystroke fallback (skips non-ASCII characters cleanly with a status notice instead of throwing).
  - Live clipboard transport and sync status indicator plus `Auto-sync system clipboard` toggle in the noVNC Clipboard panel.
- **Optional built-in HTTPS/WSS (`WEB_TLS=Y`):** Enables TLS 1.2/1.3 directly on `WEB_PORT` (`8006`) using user-supplied PEM files (`WEB_TLS_CERT` / `WEB_TLS_KEY`) or an auto-generated persisted ECDSA P-256 self-signed certificate (`/storage/.fnxvm-tls.{crt,key}`, optional `WEB_TLS_SAN`) using the existing `openssl` binary (zero extra packages). `fnxvm-healthcheck` probes `https://127.0.0.1:${WEB_PORT}/` when `WEB_TLS` is enabled.
- **Linux/BSD RDP forwarding (`RDP=Y`):** Forwards `3389/tcp` and `3389/udp` alongside SSH (`22`) in user-mode networking (`NETWORK=user`/`passt`/`slirp`), matching Windows's built-in `3389` forwarding for `xrdp` / GNOME Remote Desktop guests.
- **Automatic Windows SPICE VDAgent staging (`WINDOWS_VDAGENT=Y`):** At runtime during Windows x64/x86 unattended setup, downloads `spice-vdagent-{x64,x86}-0.10.0.msi` from official `spice-space.org`, verifies SHA-256 against both the live `sha256sum` file and pinned digest (fail-closed on mismatch, never bundled in the image), and silently installs via `SetupComplete.cmd`.
- **Comprehensive Clipboard documentation:** Access method (`noVNC`, `VNC`, `RDP`) × guest OS × client platform (Windows, macOS, Linux, ChromeOS, Android, iOS) matrix, verified VNC client notes (including QEMU Extended Clipboard requirements and macOS Screen Sharing limits), one-line guest agent/RDP install commands, and TLS reverse-proxy + `WEB_TLS=Y` examples.
- **Automated protocol and headless browser tests (CI on `amd64` + `arm64`):**
  - `tests/test_rfb_clipboard.py`: Pure-Python authenticated RFB 3.8 client verifying VNC Auth rejection/acceptance, Extended Clipboard (`0xC0A1E5CE`) capability negotiation, bidirectional multi-byte UTF-8 round-trip, and legacy `ClientCutText` delivery through live QEMU.
  - `tests/test_novnc_playwright.py`: Headless Chromium (Playwright) test verifying HTTP Basic Auth login, VNC auth, zero JS console/page errors, live bidirectional UTF-8 clipboard round-trip between browser and QEMU/RFB peer, **Paste from Device**, `Ctrl+V` interception, non-ASCII **Type** fallback, and `WEB_TLS=Y` HTTPS/WSS secure context.

### Fixed
- Fixed upstream noVNC `RFB.messages.extendedClipboardCaps` bitmask encoding and switched Extended Clipboard UTF-8 encode/decode to `TextEncoder` / `TextDecoder` (with fallback) for reliable multi-byte Unicode handling.

---

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

## [6.06.3] — 2026-11-27

### Automated Daily Build
- Verified components: dockur/windows `6.06`, qemus/qemu `7.50`, Base OS `Debian 13.8 (13.8-slim)`.
- Verified guest OS resolvers (HTTP 200): windows `Windows 11 (win11x64, build 26100.4349)`, haiku `R1/beta6 (amd64)`, freebsd `15.1-RELEASE`, daemonarchy `1.5.1 (FreeBSD 16.0-CURRENT, no LTS)`, debian `13.8.0 (GNOME / KDE)`, ubuntu `26.04.1 LTS`, omarchy `4.5.0 (rolling, no LTS)`.
- Architectures verified: `linux/amd64, linux/arm64` (native QEMU/noVNC smoke tests + Dive efficiency gate).
- Upstream tracking:
  - **dockur/windows:** `6.06` -> `6.06`
  - **qemus/qemu:** `7.50` -> `7.50`
  - **Base image:** `debian:13.8-slim` pinned at `sha256:8aa5a7bf5a1955bddbe7d74fcdd0b91ab30e74362a8b73af672b0481b35b44a0`
  - **Go builder:** `golang:1.27.4-trixie` pinned at `sha256:430985542100b871e108ccc00e8dcc5eef08ca14ee5825e98ebf563d8ffec4ee`
  - `windows`: `Windows 11 (win11x64, build 26100.4349)`
- Vulnerability gate: **0 fixable findings of any severity** in Trivy and Grype (SBOM scan) (76 upstream-unfixed C/H).
- Published multi-arch digest (Docker Hub + GHCR): `dgcosenza/fnxvm@sha256:c0517363be2341c8c8f1418afb6474ce4285a612731015d168bf38cc45e01e94` (Cosign OIDC signed + SPDX/CycloneDX SBOM + SLSA L3 provenance).
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
