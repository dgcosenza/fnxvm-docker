# FNXVM — Multi-OS Virtual Machines in a Container

[![Daily CI](https://github.com/dgcosenza/fnxvm-docker/actions/workflows/daily.yml/badge.svg)](https://github.com/dgcosenza/fnxvm-docker/actions/workflows/daily.yml)
[![OpenSSF Scorecard Workflow](https://github.com/dgcosenza/fnxvm-docker/actions/workflows/scorecard.yml/badge.svg)](https://github.com/dgcosenza/fnxvm-docker/actions/workflows/scorecard.yml)
[![Gitleaks Secret Scan](https://github.com/dgcosenza/fnxvm-docker/actions/workflows/gitleaks.yml/badge.svg)](https://github.com/dgcosenza/fnxvm-docker/actions/workflows/gitleaks.yml)
[![Public Content Check](https://github.com/dgcosenza/fnxvm-docker/actions/workflows/public-check.yml/badge.svg)](https://github.com/dgcosenza/fnxvm-docker/actions/workflows/public-check.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/dgcosenza/fnxvm-docker/badge)](https://scorecard.dev/viewer/?uri=github.com/dgcosenza/fnxvm-docker)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/17182/badge)](https://www.bestpractices.dev/projects/17182)

[![Trivy + Grype: 0 Fixable CVEs](https://img.shields.io/badge/Trivy%20%2B%20Grype-0%20fixable%20CVEs-brightgreen?logo=trivy&logoColor=white)](https://github.com/dgcosenza/fnxvm-docker/security/code-scanning)
[![Signed: Cosign OIDC](https://img.shields.io/badge/signed-Cosign%20OIDC-blueviolet)](https://github.com/dgcosenza/fnxvm-docker#security)
[![SLSA Build L3](https://img.shields.io/badge/SLSA-Build%20L3-brightgreen)](https://github.com/dgcosenza/fnxvm-docker/attestations)
[![SBOM: SPDX + CycloneDX](https://img.shields.io/badge/SBOM-SPDX%20%2B%20CycloneDX-0A7BBB?logo=spdx&logoColor=white)](https://github.com/dgcosenza/fnxvm-docker/releases/latest)
[![Base OS](https://img.shields.io/badge/base-Debian%2013%20(trixie--slim)-A81D33?logo=debian&logoColor=white)](https://github.com/dgcosenza/fnxvm-docker/blob/main/Dockerfile)
[![Architectures](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-007ec6?logo=linux&logoColor=white)](https://github.com/dgcosenza/fnxvm-docker#supported-architectures)
[![Healthcheck: CI Verified](https://img.shields.io/badge/healthcheck-CI%20verified-brightgreen?logo=docker&logoColor=white)](https://github.com/dgcosenza/fnxvm-docker#healthcheck)
[![Renovate Enabled](https://img.shields.io/badge/renovate-enabled-1A1F6C?logo=renovate&logoColor=white)](https://github.com/dgcosenza/fnxvm-docker/blob/main/renovate.json)
[![Dependabot Enabled](https://img.shields.io/badge/dependabot-enabled-025E8C?logo=dependabot&logoColor=white)](https://github.com/dgcosenza/fnxvm-docker/blob/main/.github/dependabot.yml)
[![Daily Rebuilds](https://img.shields.io/badge/rebuilds-daily-2088FF?logo=githubactions&logoColor=white)](https://github.com/dgcosenza/fnxvm-docker/actions/workflows/daily.yml)

[![Latest Release](https://img.shields.io/github/v/release/dgcosenza/fnxvm-docker?label=version&logo=github)](https://github.com/dgcosenza/fnxvm-docker/releases/latest)
[![Release Date](https://img.shields.io/github/release-date/dgcosenza/fnxvm-docker?label=released&logo=github)](https://github.com/dgcosenza/fnxvm-docker/releases/latest)
[![Last Commit](https://img.shields.io/github/last-commit/dgcosenza/fnxvm-docker?logo=github)](https://github.com/dgcosenza/fnxvm-docker/commits/main)
[![Docker Pulls](https://img.shields.io/docker/pulls/dgcosenza/fnxvm?logo=docker&logoColor=white)](https://hub.docker.com/r/dgcosenza/fnxvm)
[![Docker Image Size](https://img.shields.io/docker/image-size/dgcosenza/fnxvm/latest?logo=docker&logoColor=white)](https://hub.docker.com/r/dgcosenza/fnxvm)
[![Registries: Docker Hub + GHCR](https://img.shields.io/badge/registries-Docker%20Hub%20%2B%20GHCR-2496ED?logo=docker&logoColor=white)](https://github.com/dgcosenza/fnxvm-docker/pkgs/container/fnxvm)
[![Packaging License: MIT](https://img.shields.io/badge/packaging-MIT-blue?logo=opensourceinitiative&logoColor=white)](https://github.com/dgcosenza/fnxvm-docker/blob/main/LICENSE)
[![Upstream License](https://img.shields.io/badge/upstream-MIT-green?logo=opensourceinitiative&logoColor=white)](https://github.com/dgcosenza/fnxvm-docker/blob/main/THIRD-PARTY-NOTICES.md)
[![GitHub Issues](https://img.shields.io/github/issues/dgcosenza/fnxvm-docker?logo=github)](https://github.com/dgcosenza/fnxvm-docker/issues)
[![FNX Labs Catalog](https://img.shields.io/badge/catalog-FNX%20Labs-0b1020?logo=githubpages&logoColor=white)](https://dgcosenza.github.io/)

Maintainer: Daniel G. Cosenza from FNX Labs

**FNXVM** is a multi-OS QEMU/KVM virtual machine container on **Debian 13.8 (`debian:13.8-slim`)**. It combines [`qemus/qemu`](https://github.com/qemus/qemu) and [`dockur/windows`](https://github.com/dockur/windows) with an authenticated **noVNC** web viewer (HTTP Basic + bcrypt, optional built-in **HTTPS/WSS** via `WEB_TLS=Y`), password-protected **VNC**, **RDP** (`3389`), universal bidirectional **clipboard** (`qemu-vdagent`, RFB Extended Clipboard, and browser Async Clipboard API), and configurable **GPU acceleration** (`GPU=auto|virtio|virgl|qxl|std`).

**No OS ISOs or proprietary media are ever bundled or redistributed.** When `OS=` is set, FNXVM resolves the latest official release from the vendor at runtime, downloads it, and verifies checksums and signatures before booting (fail-closed).

## Supported tags

- `latest` — latest daily verified multi-arch build (`linux/amd64` + `linux/arm64`)
- `<version>` — release version (e.g. `6.06.4`), `<version>-<YYYYMMDD>` (immutable; `.N` on same-day rebuilds), `sha-<short>`
- Digest pinning (recommended): `dgcosenza/fnxvm@sha256:<digest>` / `ghcr.io/dgcosenza/fnxvm@sha256:<digest>` (identical Cosign-signed digests)

## Supported guest operating systems

Set `OS=` (or `BOOT=<url>`, or `VERSION=` for Windows). Unknown `OS` values fail fast.

| `OS` | Guest | Version policy | Arch | Official source | Runtime verification |
| --- | --- | --- | --- | --- | --- |
| `debian` | Debian Desktop (`DESKTOP=gnome`\|`kde`) | Latest stable live ISO (`amd64`); DVD-1 (`arm64`) | `amd64`, `arm64` | `cdimage.debian.org` | GPG (`SHA256SUMS.sign`) + SHA-256 |
| `ubuntu` | Ubuntu Desktop LTS | Latest even-year `.04` LTS point release | `amd64`, `arm64` | `releases/cdimage.ubuntu.com` | GPG (`SHA256SUMS.gpg`) + SHA-256 |
| `freebsd` | FreeBSD | Latest production `-RELEASE` | `amd64`, `arm64` | `download.freebsd.org` | SHA-256 (`CHECKSUM.SHA256`) |
| `daemonarchy` | Daemonarchy (Hyprland on FreeBSD) | Latest stable; **FreeBSD 16.0-CURRENT, no LTS** | `amd64`, `arm64` (UEFI) | `jordanhubbard/daemonarchy` | SHA-256 on `.iso.xz` before `xz -dc` |
| `haiku` | Haiku | Latest release (`R1/betaN`) | `amd64` only | `haiku-os.org` / CDN | SHA-256 (`.iso.sha256`) |
| `omarchy` | Omarchy (Arch-based) | **Rolling; no LTS** | `amd64`, `arm64` | `omarchy.org` | SHA-256 + GPG (`.iso.sig`) |
| `windows` | Windows (`VERSION=11`, `ltsc`, `iot-ltsc`, ...) | Official Microsoft endpoints | `amd64`, `arm64` (10/11) | Microsoft official | SHA-1/SHA-256 (`VERIFY=Y`) |
| *(unset + `BOOT=`)* | Custom ISO / raw / qcow2 / vmdk / vhdx | User URL or `/boot.iso` / `/boot.img` | `amd64`, `arm64` | User-specified | User-managed |

> **Notes:** [Daemonarchy](https://github.com/jordanhubbard/daemonarchy) (Jordan Hubbard) is **not affiliated with Omarchy**; use `DISK_SIZE>=40G` and keep Internet access during install (~1,200 packages). Its `arm64` asset is a UEFI-only community-validation image. **Omarchy** is also rolling with no LTS.

## Supported architectures

Built and smoke-tested natively in CI on `linux/amd64` (`qemu-system-x86_64`, OVMF/SeaBIOS/swtpm) and `linux/arm64` (`qemu-system-aarch64`, AAVMF/swtpm). `amd64` supports all 7 OSes; `arm64` supports all except `haiku` (fails fast; no official arm64 ISO).

## Quick start

Omit `WEB_PASSWORD`/`WEB_PASSWORD_FILE` on first start to auto-generate strong Web UI and independent VNC passwords (printed **once** in logs; Web UI persists bcrypt hash only).

```bash
# Debian Desktop (or OS=ubuntu|freebsd|daemonarchy|haiku|omarchy)
docker run -it --rm --device /dev/kvm --device /dev/net/tun --cap-add NET_ADMIN \
  -p 127.0.0.1:8006:8006 -e OS=debian -e DESKTOP=gnome -v fnxvm-debian:/storage \
  dgcosenza/fnxvm:latest

# Windows 11 with RDP + built-in HTTPS on 8006
docker run -it --rm --device /dev/kvm --device /dev/net/tun --cap-add NET_ADMIN \
  -p 127.0.0.1:8006:8006 -p 127.0.0.1:3389:3389 -e OS=windows -e VERSION=11 -e WEB_TLS=Y \
  -v fnxvm-windows:/storage dgcosenza/fnxvm:latest

# Dry-run OS resolution without KVM or download
docker run --rm -e RESOLVE_ONLY=1 -e OS=daemonarchy dgcosenza/fnxvm:latest
```

Open `http://127.0.0.1:8006` (or `https://127.0.0.1:8006` with `WEB_TLS=Y`) and sign in with `WEB_USER` (`fnxvm`).

## Compose example

Create `chmod 600` `./secrets/web_password.txt` and `./secrets/vnc_password.txt` first (full file: [`docker-compose.example.yml`](https://github.com/dgcosenza/fnxvm-docker/blob/main/docker-compose.example.yml)):

```yaml
services:
  fnxvm:
    image: dgcosenza/fnxvm:latest
    environment:
      OS: "debian"
      DESKTOP: "gnome"
      GPU: "auto"
      CLIPBOARD: "Y"
      WEB_AUTH: "Y"
      WEB_USER: "fnxvm"
      WEB_PASSWORD_FILE: "/run/secrets/fnxvm_web_password"
      VNC_PASSWORD_FILE: "/run/secrets/fnxvm_vnc_password"
      # WEB_TLS: "Y"   # Built-in HTTPS/WSS on 8006 (or use a TLS reverse proxy)
      # RDP: "Y"       # Forward 3389/tcp+udp in user-mode networking for Linux/BSD xrdp
      RAM_SIZE: "4G"
      CPU_CORES: "2"
      DISK_SIZE: "64G"
    secrets: [fnxvm_web_password, fnxvm_vnc_password]
    devices: ["/dev/kvm:/dev/kvm", "/dev/net/tun:/dev/net/tun"]
    cap_drop: [ALL]
    cap_add: [NET_ADMIN, CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID, NET_BIND_SERVICE]
    security_opt: ["no-new-privileges:true"]
    ports: ["127.0.0.1:8006:8006"]
    volumes: ["fnxvm_storage:/storage"]
    stop_grace_period: 2m
    restart: unless-stopped
secrets:
  fnxvm_web_password: { file: ./secrets/web_password.txt }
  fnxvm_vnc_password: { file: ./secrets/vnc_password.txt }
volumes:
  fnxvm_storage:
```

## Authentication

- **Web UI (`8006`):** nginx Basic Auth + bcrypt protects `/`, `/vnc.html`, `/websockify`, `/status`, `/audio`. Configure `WEB_USER` (`fnxvm`) + `WEB_PASSWORD_FILE`/`WEB_PASSWORD` (if unset, auto-generates a 24-char secret printed once; bcrypt hash persisted `0600` in `/storage/.fnxvm-web.htpasswd`). `WEB_AUTH=N` disables auth (proxy-only).
- **VNC (`5900`):** Always `password=on` (RFB type `2`) via QMP `set_password` (`VNC_PASSWORD_FILE`/`VNC_PASSWORD`, or auto-generated 8-char secret in `/storage/.fnxvm-vnc.secret`). **Never expose `5900` publicly** (unencrypted, 8-char cap); use noVNC over TLS.

## Clipboard

Bidirectional copy/paste across **noVNC (`8006`)**, **VNC (`5900`)**, and **RDP (`3389`)** via `virtio-serial-pci` + `qemu-vdagent` (`CLIPBOARD=Y`, or `spicevmc` with `SPICE=Y`).

| Guest `OS` | noVNC (`8006`) | VNC (`5900`)\* | RDP (`3389`) | Guest setup / notes |
| --- | --- | --- | --- | --- |
| `windows` | **UTF-8 bidir** | **UTF-8 bidir** | **Native (`rdpclip`)** | Auto-stages SHA-256-verified `spice-vdagent` MSI on x64/x86 (`WINDOWS_VDAGENT=Y`); ARM64 uses native RDP. |
| `debian` / `ubuntu` | **UTF-8 bidir** | **UTF-8 bidir** | **Optional (`xrdp`)** | `spice-vdagent` (preinstalled on Debian live); `RDP=Y` forwards `3389`; Ubuntu 26.04 adds native Wayland RDP. |
| `omarchy` | **UTF-8 bidir** | **UTF-8 bidir** | **Optional (`xrdp`)** | Install `spice-vdagent`; Wayland may need XWayland/`wl-clipboard`; **Type (ASCII)** always works. |
| `freebsd` / `daemonarchy` | **Type (ASCII)** | Unsupported | **Optional (`xrdp`)** | No FreeBSD `spice-vdagent`; use `xrdp` + `xorgxrdp` for bidirectional RDP clipboard, or SSH/`/shared`. |
| `haiku` | **Type (ASCII)** | Unsupported | Unsupported | No vdagent/RDP; use **Type (ASCII)** or `/shared`. |

\*QEMU sends guest->client VNC updates only to clients supporting **RFB Extended Clipboard (`0xC0A1E5CE`)**. Recommended clients: **Chrome/Edge/Safari/Firefox** on **noVNC (HTTPS/localhost)**; **TigerVNC** or **Remmina** for VNC (avoid macOS Screen Sharing, TightVNC, UltraVNC); **mstsc.exe** / **Windows App** / **Remmina** / `xfreerdp3 +clipboard` for RDP.

- **Browser Clipboard & TLS (`WEB_TLS=Y`):** Async Clipboard API requires HTTPS or `localhost` (plain HTTP LAN still supports manual panel actions + US-QWERTY **Type (ASCII)** fallback). `WEB_TLS=Y` persists an ECDSA P-256 cert in `/storage/.fnxvm-tls.{crt,key}` (customize via `WEB_TLS_SAN`, `WEB_TLS_CERT`/`WEB_TLS_KEY`, or terminate TLS in a reverse proxy).
- **Guest agent / RDP one-liners:**
  - Debian/Ubuntu: `sudo apt update && sudo apt install -y spice-vdagent` (or `xrdp xorgxrdp && sudo systemctl enable --now xrdp`)
  - Omarchy: `sudo pacman -S --noconfirm spice-vdagent && sudo systemctl enable --now spice-vdagentd`
  - FreeBSD/Daemonarchy: `sudo pkg install -y xrdp xorgxrdp && sudo sysrc xrdp_enable=YES xrdp_sesman_enable=YES && sudo service xrdp start && sudo service xrdp-sesman start`
  - Windows manual: `spice-vdagent-x64-0.10.0.msi` ([spice-space.org](https://www.spice-space.org/download/windows/vdagent/vdagent-win-0.10.0/)) or `virtio-win-guest-tools.exe` ([fedorapeople.org](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/)).

## Video acceleration (`GPU`)

- `auto` (default): `VGA`/`ramfb` without `/dev/dri`; auto-enables `virgl` on Linux guests when `/dev/dri/renderD*` is accessible.
- `std` / `virtio` / `qxl` / `virgl`: Software VGA/ramfb; 2D VirtIO; QXL (`SPICE=Y`); or OpenGL `virgl` (`--device /dev/dri` + `--group-add "$(stat -c '%g' /dev/dri/renderD128)"`, optional `RENDERNODE=`; falls back cleanly if absent).

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `OS` / `DESKTOP` / `VERSION` | `debian` / `gnome` / `11` | Guest OS (`debian`, `ubuntu`, `freebsd`, `daemonarchy`, `haiku`, `omarchy`, `windows`), Debian desktop, Windows edition. |
| `BOOT` / `RESOLVE_ONLY` | *(empty)* / `N` | Custom ISO/disk URL (when `OS` unset); dry-run OS resolution without QEMU. |
| `GPU` / `RENDERNODE` | `auto` / *(auto)* | Display mode (`auto`, `virtio`, `virgl`, `qxl`, `std`) and optional DRM render node. |
| `CLIPBOARD` / `WINDOWS_VDAGENT` | `Y` / `Y` | Attach `virtio-serial` + `qemu-vdagent`/`spicevmc`; auto-stage verified `spice-vdagent` MSI on x64/x86 Windows. |
| `RDP` | `N` (Windows: on) | Forward guest `3389/tcp+udp` in user-mode networking for Linux/BSD `xrdp` (NAT forwards all non-reserved ports). |
| `WEB_TLS` / `WEB_TLS_SAN` | `N` / `localhost` | Built-in HTTPS/WSS on `WEB_PORT` (`Y` persists self-signed ECDSA cert in `/storage/.fnxvm-tls.{crt,key}`). |
| `WEB_TLS_CERT` / `WEB_TLS_KEY` | *(empty)* | Mounted PEM cert and key paths when `WEB_TLS=Y`. |
| `WEB_AUTH` / `WEB_USER` | `Y` / `fnxvm` | HTTP Basic Auth toggle and username on `WEB_PORT`. |
| `WEB_PASSWORD` / `WEB_PASSWORD_FILE` | *(auto-generated)* | Web UI password or secret file (bcrypt-hashed into `/storage/.fnxvm-web.htpasswd`). |
| `VNC_PASSWORD` / `VNC_PASSWORD_FILE` | *(auto, 8 chars)* | Independent VNC RFB password or secret file (max 8 chars, applied via QMP). |
| `SPICE` / `SPICE_PORT` | `N` / `5901` | Optional QMP-authenticated SPICE server. |
| `RAM_SIZE` / `CPU_CORES` / `DISK_SIZE` | `4G` / `2` / `64G` | Guest RAM, vCPUs, and disk size (`>=40G` for `daemonarchy`). |
| `DISK_FMT` / `BOOT_MODE` / `KVM` | `raw` / *(auto)* / `Y` | `raw`/`qcow2`; `uefi`/`secure`/`legacy`/`windows*`; KVM (`KVM=N` for TCG). |
| `NETWORK` / `DHCP` / `USER_PORTS` | `Y` / `N` / *(empty)* | `Y` (NAT/TAP), `user`/`passt`, or `N`; macvlan DHCP; extra user-mode port forwards. |
| `WEB` / `WEB_PORT` / `VNC_PORT` | `Y` / `8006` / `5900` | Web viewer toggle (`WEB=N` headless VNC) and listening ports. |
| `USERNAME` / `PASSWORD` / `VERIFY` | `Docker` / `admin` / `Y` | Windows guest login (separate from `WEB_USER`) and ESD hash verification. |
| `AUDIO` / `SAMBA` / `ARGUMENTS` / `DEBUG` | `N` / `Y` / *(empty)* / `N` | Browser audio, `/shared` Samba/9p, extra QEMU flags, verbose logs. |

**Ports:** `8006/tcp` (noVNC HTTP/HTTPS), `5900/tcp` (VNC — keep local), `3389/tcp+udp` (RDP), `22/tcp` (SSH), optional `5901/tcp` (SPICE). **Volumes:** `/storage` (disks, NVRAM, auth/TLS state), optional `/shared`. **Users:** `root` (UID 0) for `/dev/kvm`/TAP; `vmuser` (UID/GID 1000) for CLI tools. **PID 1:** `tini`.

## Healthcheck

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD ["/usr/local/bin/fnxvm-healthcheck"]
```

Probes nginx's internal Unix socket (`/run/shm/nginx-health.sock` -> `/healthz`), checks `http(s)://127.0.0.1:${WEB_PORT}/` returns `401` (`WEB_AUTH=Y`) or `200` (`WEB_AUTH=N`), checks `/run/shm/status-ws.sock` (or `127.0.0.1:${VNC_PORT}` when `WEB=N`), and verifies QEMU's PID. Tested on `amd64` + `arm64`; do not disable in Compose.

## Current versions

<!-- versions:start -->
| Component | Resolved Version |
| --- | --- |
| dockur/windows | `6.06` |
| qemus/qemu | `7.50` |
| Base OS | `Debian 13.8 (13.8-slim)` |
| Architectures | `linux/amd64, linux/arm64` |
| Uncompressed size (per arch) | `amd64: 248.2 MB, arm64: 1120.1 MB` |
| Last verified build (UTC) | `2026-11-27` |
| Published multi-arch digest | `dgcosenza/fnxvm@sha256:2391cf506443d7b48a694e3bd5b970bf3dc450f9752a23fb195918662759f14b` |
| GHCR mirror | `ghcr.io/dgcosenza/fnxvm@sha256:2391cf506443d7b48a694e3bd5b970bf3dc450f9752a23fb195918662759f14b` |
| Supply chain | Cosign OIDC signed + SPDX & CycloneDX SBOM attestations + SLSA Build L3 provenance |
| Security gate (Trivy + Grype on SBOM) | **0 fixable findings of any severity** (76 upstream-unfixed) |

**Guest OS versions resolved at last build (resolved dynamically at runtime):**

| `OS` | Resolved Guest Version |
| --- | --- |
| `windows` | `Windows 11 (win11x64, build 26100.4349)` |
| `haiku` | `R1/beta6 (amd64)` |
| `freebsd` | `15.1-RELEASE` |
| `daemonarchy` | `1.5.1 (FreeBSD 16.0-CURRENT, no LTS)` |
| `debian` | `13.8.0 (GNOME / KDE)` |
| `ubuntu` | `26.04.1 LTS` |
| `omarchy` | `4.5.0 (rolling, no LTS)` |

**Recent upstream tracking:**
- **dockur/windows:** `6.06` -> `6.06`
- **qemus/qemu:** `7.50` -> `7.50`
- **Base image:** `debian:13.8-slim` pinned at `sha256:8aa5a7bf5a1955bddbe7d74fcdd0b91ab30e74362a8b73af672b0481b35b44a0`
- **Go builder:** `golang:1.27.4-trixie` pinned at `sha256:430985542100b871e108ccc00e8dcc5eef08ca14ee5825e98ebf563d8ffec4ee`
- `windows`: `Windows 11 (win11x64, build 26100.4349)`
<!-- versions:end -->

## Upgrade / migration

- **From `6.06.4` to `6.06.5`:** Drop-in fix pre-resolving HTTP redirects once before multi-connection `aria2c` downloads, adding automatic official Debian CD mirror fallback (verified against canonical `cdimage.debian.org` GPG-signed `SHA256SUMS`), and defaulting `SUPPORT` in `init.sh`.
- **From `6.06.3` to `6.06.4`:** Complete Debian CD signing keys, cleaned Ubuntu key, and live CI `gpgv`/checksum checks.
- **From `6.06.2` / earlier:** Universal noVNC clipboard (`WEB_TLS=Y`, `RDP=Y`), default auth (`WEB_AUTH=Y`, `WEB_USER`, `WEB_PASSWORD_FILE`, `VNC_PASSWORD_FILE`), drop-in `/storage`.

## Security

- **Auth & TLS:** Web UI (`8006`, incl. `/websockify`, `/status`, `/audio`) enforces nginx Basic Auth + bcrypt (`0600` `/storage/.fnxvm-web.htpasswd`) with optional `WEB_TLS=Y` (TLS 1.2/1.3). VNC (`5900`) uses QMP `set_password` with an independent 8-char secret. Never expose `8006`, `5900`, or `3389` publicly without TLS/tunneling.
- **0 fixable vulnerabilities (any severity):** Hard-gated by **Trivy** (`UNKNOWN`–`CRITICAL`, `--ignore-unfixed`, exit 1) + **Grype** on Syft SPDX SBOM (`--only-fixed --fail-on negligible`) on `amd64` + `arm64` (unfixed CVEs tracked in `versions.json`).
- **Supply chain:** Digest-pinned `debian:13.8-slim` + `golang:1.27.4-trixie`, keyless Cosign OIDC (Hub + GHCR), SPDX/CycloneDX SBOMs, SLSA Build L3, Hadolint, Gitleaks, Dive (`>=95%`), OpenSSF Scorecard & Best Practices Passing, Renovate, Dependabot.
- **Fail-closed runtime verification:** Offline vendor OpenPGP keyrings (`/etc/fnxvm/keys/*.gpg`, live-verified in CI via `gpgv` + tamper tests), SHA-256 for FreeBSD, Daemonarchy (`.iso.xz`), Haiku, and optional Windows `spice-vdagent` MSI; `VERIFY=Y` for Windows. Pinned fingerprints ([`THIRD-PARTY-NOTICES.md`](https://github.com/dgcosenza/fnxvm-docker/blob/main/THIRD-PARTY-NOTICES.md)):
  - **Debian** ([debian.org/CD/verify](https://www.debian.org/CD/verify)): `10460DAD76165AD81FBC0CE9988021A964E6EA7D`, `DF9B9C49EAA9298432589D76DA87E80D6294BE9B`, `F41D30342F3546695F65C66942468F4009EA8AC3`
  - **Ubuntu** ([verify docs](https://ubuntu.com/tutorials/how-to-verify-ubuntu)): `843938DF228D22F7B3742BC0D94AA3F0EFE21092`
  - **Omarchy** (`omacom/omarchy` `manual/48-security.md`): `40DFB630FF42BCFFB047046CF0134EE680CAC571` (CI checks `gpgv` on `omarchy-keyring` + `.iso.sig` issuer; full ISO `.iso.sig` at runtime)

```bash
cosign verify \
  --certificate-identity-regexp='^https://github\.com/dgcosenza/fnxvm-docker/\.github/workflows/daily\.yml@refs/heads/main$' \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  ghcr.io/dgcosenza/fnxvm@sha256:<digest>

gh attestation verify oci://ghcr.io/dgcosenza/fnxvm@sha256:<digest> --owner dgcosenza
```

Report vulnerabilities via [GitHub Security Advisories](https://github.com/dgcosenza/fnxvm-docker/security/advisories/new) ([`SECURITY.md`](https://github.com/dgcosenza/fnxvm-docker/blob/main/SECURITY.md)).

## Build locally

```bash
docker build -t fnxvm:local .
./tests/smoke.sh fnxvm:local
```

## Update policy

`.github/workflows/daily.yml` runs daily with `--no-cache` on `amd64` + `arm64`: resolves upstreams, base digests, and all 7 OSes; runs container, RFB clipboard, Playwright noVNC, GPU, auth, TLS, live `gpgv`/checksum, and resolver tests; gates on Dive (`>=95%`), Trivy, and Grype (0 fixable of any severity); publishes Cosign-signed digests + SBOMs + SLSA L3 to GHCR, Docker Hub, and Releases; updates `versions.json`/`README.md`/`CHANGELOG.md` + Hub overview; manages `ci-failure` issues.

## Design decisions

- **Debian 13.8 `main` packages only:** Official QEMU, OpenGL/SPICE modules, `libegl-mesa0`, OVMF/AAVMF/SeaBIOS, Passt, swtpm, nginx, `apache2-utils`, and `openssl` keep 0 fixable CVEs without Sid snapshots or third-party `.deb` bundles.
- **From-source helpers & isolated Python:** `websocketd`, `boot-logo` (`golang:1.27.4-trixie`), and `udfread` build from SHA-256-verified source; `qemu.qmp` runs without `pip` in runtime.
- **Universal clipboard without heavy RDP gateways:** Fixes noVNC Extended Clipboard caps, adds browser Async Clipboard API + non-ASCII-safe Type fallback, zero-bloat `WEB_TLS=Y`, and auto-staged verified `spice-vdagent` on Windows. Heavy gateways (Guacamole) are omitted to preserve minimalism and 0 fixable CVEs; use direct `3389` over VPN/SSH or noVNC over HTTPS.

## License

Packaging: **MIT License**, Copyright (c) 2026 Daniel G. Cosenza from FNX Labs ([`LICENSE`](https://github.com/dgcosenza/fnxvm-docker/blob/main/LICENSE)). Reused `dockur/windows` and `qemus/qemu` assets are MIT; third-party notices and vendor key details in [`THIRD-PARTY-NOTICES.md`](https://github.com/dgcosenza/fnxvm-docker/blob/main/THIRD-PARTY-NOTICES.md). Guest OS media and runtime agents remain under their vendor licenses.

## Credits

Maintainer: **Daniel G. Cosenza from FNX Labs**. Built upon [`dockur/windows`](https://github.com/dockur/windows), [`qemus/qemu`](https://github.com/qemus/qemu), QEMU, EDK2/OVMF, noVNC, Passt, SPICE, Debian, Ubuntu, FreeBSD, Daemonarchy (Jordan Hubbard), Haiku, and Omarchy.
