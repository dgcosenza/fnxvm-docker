# Changelog

All notable changes to this container image are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Maintained by **Daniel G. Cosenza from FNX Labs**.

<!-- changelog:auto -->

## [6.06.5] — 2026-11-27

### Fixed
- **Debian multi-connection `"Too many redirects"` mirror resilience (`src/common/download.sh`, `src/fnxvm-resolve`, `src/generic/install.sh`):**
  - **Root cause:** `cdimage.debian.org` (backed by the ACC Umeå redirector cluster) returns HTTP `302` redirects to backend mirror nodes that can cross-redirect under parallel-connection load, while `aria2` never resets `Request::redirectCount_` on HTTP `200`/`206` responses and aborts fatally with `errorCode=23 Too many redirects: count=20`.
  - Pre-resolve HTTP redirect chains once up front (`resolveDownloadUrl` via `curl` `HEAD`, falling back to `Range: bytes=0-0` with `--max-filesize` guard) before invoking `aria2c` so all parallel connections download directly from the resolved mirror with 0 redirect hops; add `--min-split-size=20M` and automatic single-connection downgrade when a mirror advertises `Accept-Ranges: none`.
  - Fail fast (`rc=23`) on hard redirect loops instead of repeating the broken URL, and wire automatic official mirror fallback in `src/generic/install.sh` (`FNXVM_MIRROR_URLS` populated from `fnxvm-resolve` for `debian` and `haiku`). Checksum manifests (`SHA256SUMS` + `SHA256SUMS.sign`) are still always fetched from canonical `cdimage.debian.org` and verified fail-closed with `gpgv` + SHA-256.
- **Standalone `init.sh` default (`src/common/init.sh`):** Default `SUPPORT` inside `init.sh` so sourcing it outside `entry.sh` cannot trigger `SUPPORT: unbound variable`.

### Added
- **Automated redirect & mirror fallback tests (`tests/test_download_redirects.py`, invoked by `tests/smoke.sh` on both `amd64` and `arm64`):** Exercises 302 pre-resolution (asserting exactly 1 redirector hit under `CONNECTIONS=4`), looping 302 fail-fast (`rc=23`) with automatic mirror fallback recovery, `Accept-Ranges: none` single-connection downgrade, Debian resolver fallback mirrors, and `init.sh` `SUPPORT` default.

---

## [6.06.4] — 2026-11-27

### Fixed
- **Debian CD GPG keyring (`keys/debian-cd.asc` -> `/etc/fnxvm/keys/debian-cd.gpg`):** Replaced the previously UID-less key export (which caused `gpgv` to fail with `No public key` and prevented `OS=debian` from booting) with all three complete official Debian CD signing keys from `hkps://keyring.debian.org` matching [debian.org/CD/verify](https://www.debian.org/CD/verify) (`10460DAD76165AD81FBC0CE9988021A964E6EA7D`, `DF9B9C49EAA9298432589D76DA87E80D6294BE9B`, `F41D30342F3546695F65C66942468F4009EA8AC3`, with full user IDs, self-signatures, and subkeys).
- **Ubuntu CD GPG keyring (`keys/ubuntu-cd.asc`):** Refreshed cleanly (`--export-options export-clean`) from `hkps://keyserver.ubuntu.com` (`843938DF228D22F7B3742BC0D94AA3F0EFE21092`, shrinking from 65 KB of third-party keyserver noise to 1.7 KB) and verified against official Ubuntu docs; confirmed `keys/omarchy.asc` (`40DFB630FF42BCFFB047046CF0134EE680CAC571`) matches `keys.openpgp.org` and `omacom/omarchy` verbatim.
- **Fail-closed cleanup & diagnostics (`src/generic/install.sh`):** Log `gpgv` stderr on signature verification failure and delete the unverified downloaded ISO on every failure path in `verifyFnxvmDownload`.

### Added
- **Build-time keyring validation (`Dockerfile`):** After dearmoring `keys/*.asc`, `asset-builder` imports each `.gpg` keyring with `gpg --batch --import` and asserts `pub:`, `uid:`, and `fpr:` packets exist, making UID-less keyrings impossible to build.
- **Automated live keyring, signature, and checksum verification (`tests/test_verify_keyrings.py`, invoked by `tests/smoke.sh` on both `amd64` and `arm64`):**
  - Verifies every bundled `/etc/fnxvm/keys/*.gpg` keyring contains pinned fingerprints, User IDs, and UID self-signatures (cross-checked with host `gpg --import`).
  - Downloads live Debian `SHA256SUMS` + `SHA256SUMS.sign` (`amd64` live GNOME/KDE and `arm64` DVD-1) and Ubuntu `SHA256SUMS` + `SHA256SUMS.gpg` (`amd64` and `arm64`) inside the built container and verifies them with `gpgv --keyring /etc/fnxvm/keys/...` plus negative tampered-file rejection tests.
  - Verifies Omarchy `.iso.sha256`, `.iso.sig` issuer fingerprint (`amd64` + `arm64`), and live `gpgv` verification against Omarchy's small official signed `omarchy-keyring` package (`pkgs.omarchy.org`), plus negative tampered-file rejection (full multi-GB ISO `.iso.sig` check runs at runtime).
  - Exercises live small checksum-file fetches and parsing for Daemonarchy (`amd64` + `arm64`), FreeBSD (`amd64` + `arm64`), and Haiku (`amd64`, including `.minisig`).
- Documented pinned vendor OpenPGP key fingerprints and official verification sources in `README.md` (`Security`) and `THIRD-PARTY-NOTICES.md`.

---

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

## [6.06.5] — 2026-11-27

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
- Vulnerability gate: **0 fixable findings of any severity** in Trivy and Grype (SBOM scan) (76 upstream-unfixed).
- Published multi-arch digest (Docker Hub + GHCR): `dgcosenza/fnxvm@sha256:83ce673973338a216196384be1b54615b3a79230657a0f5b7e0edea0b2c55490` (Cosign OIDC signed + SPDX/CycloneDX SBOM + SLSA L3 provenance).
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
