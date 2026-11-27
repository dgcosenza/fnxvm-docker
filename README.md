# FNXVM — Multi-OS Virtual Machines in a Container

[![Build](https://github.com/dgcosenza/fnxvm-docker/actions/workflows/daily.yml/badge.svg)](https://github.com/dgcosenza/fnxvm-docker/actions/workflows/daily.yml)
[![Packaging](https://img.shields.io/badge/packaging-MIT-blue.svg)](LICENSE)
[![Upstream](https://img.shields.io/badge/upstream-MIT-lightgrey.svg)](THIRD-PARTY-NOTICES.md)
[![Signed](https://img.shields.io/badge/signed-cosign-blue.svg)](https://github.com/dgcosenza/fnxvm-docker)
[![SLSA](https://img.shields.io/badge/SLSA-Build%20L3-brightgreen.svg)](https://github.com/dgcosenza/fnxvm-docker/attestations)
[![Architectures](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-blue.svg)](https://github.com/dgcosenza/fnxvm-docker)
[![Scorecard](https://api.securityscorecards.dev/projects/github.com/dgcosenza/fnxvm-docker/badge)](https://securityscorecards.dev/viewer/?uri=github.com/dgcosenza/fnxvm-docker)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/17182/badge)](https://www.bestpractices.dev/projects/17182)
[![Hub pulls](https://img.shields.io/docker/pulls/dgcosenza/fnxvm.svg)](https://hub.docker.com/r/dgcosenza/fnxvm)
[![Image size](https://img.shields.io/docker/image-size/dgcosenza/fnxvm/latest.svg)](https://hub.docker.com/r/dgcosenza/fnxvm/tags)
[![Version](https://img.shields.io/badge/version-6.06.3-blue.svg)](CHANGELOG.md)

Maintainer: Daniel G. Cosenza from FNX Labs

**FNXVM** is a multi-OS QEMU/KVM virtual machine container on **Debian 13.8 (`debian:13.8-slim`)**. It combines [`qemus/qemu`](https://github.com/qemus/qemu) and [`dockur/windows`](https://github.com/dockur/windows) with an authenticated **noVNC** web viewer (HTTP Basic + bcrypt, optional built-in **HTTPS/WSS** via `WEB_TLS=Y`), password-protected **VNC**, **RDP** (`3389`), universal bidirectional **clipboard** (`qemu-vdagent`, RFB Extended Clipboard, and browser Async Clipboard API), and configurable **GPU acceleration** (`GPU=auto|virtio|virgl|qxl|std`).

**No OS ISOs or proprietary media are ever bundled or redistributed.** When `OS=` is set, FNXVM resolves the latest official release from the vendor at runtime, downloads it, and verifies checksums and signatures before booting (fail-closed).

## Supported tags

- `latest` — latest daily verified multi-arch build (`linux/amd64` + `linux/arm64`)
- `<version>` — release version (e.g. `6.06.3`), `<version>-<YYYYMMDD>` (immutable; `.N` on same-day rebuilds), `sha-<short>`
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

Create `chmod 600` `./secrets/web_password.txt` and `./secrets/vnc_password.txt` first (full file: [`docker-compose.example.yml`](docker-compose.example.yml)):

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

- **Web UI (`8006`):** nginx HTTP Basic Auth + **bcrypt** protects `/`, `/vnc.html`, `/websockify`, `/status`, and `/audio`. Configure `WEB_USER` (default `fnxvm`) + `WEB_PASSWORD_FILE`/`WEB_PASSWORD` (separate from Windows `USERNAME`/`PASSWORD`). When unset, generates a 24-char secret printed **once** and persists only its bcrypt hash (`0600`) in `/storage/.fnxvm-web.htpasswd`. Rotate by deleting that file or setting `WEB_PASSWORD_FILE`. `WEB_AUTH=N` disables auth with a loud warning (use only behind an authenticating proxy).
- **VNC (`5900`):** Always launched with `password=on` (RFB security type `2`, never `None`), set over private QMP (`set_password`, never in `/proc/<pid>/cmdline`). Set `VNC_PASSWORD_FILE`/`VNC_PASSWORD`; when unset, generates an **independent** 8-char secret printed **once** and persisted `0600` in `/storage/.fnxvm-vnc.secret`. **RFB caps passwords at 8 chars and is unencrypted — do not expose `5900` publicly**; use noVNC over TLS.

## Clipboard

Universal bidirectional copy/paste across **noVNC (`8006`)**, **VNC (`5900`)**, and **RDP (`3389`)**. With `CLIPBOARD=Y` (default), QEMU attaches `virtio-serial-pci` + `virtserialport` (`com.redhat.spice.0`) backed by `-chardev qemu-vdagent,id=vdagent,name=vdagent,clipboard=on` (or `spicevmc` when `SPICE=Y`).

### Access method × guest OS

| Guest `OS` | noVNC (`8006`) | VNC (`5900`) | RDP (`3389`) | Guest setup / limits |
| --- | --- | --- | --- | --- |
| `windows` | **Bidirectional UTF-8** | **Bidirectional UTF-8**\* | **Native (`rdpclip`)** | `vioserial` staged; `spice-vdagent` MSI auto-downloaded & SHA-256 verified at runtime on x64/x86 (`WINDOWS_VDAGENT=Y`, never bundled). ARM64: native RDP or manual guest tools. |
| `debian` | **Bidirectional UTF-8** | **Bidirectional UTF-8**\* | **Optional (`xrdp`)** | `spice-vdagent` preinstalled on live ISOs; `RDP=Y` forwards `3389` in user-mode networking. |
| `ubuntu` | **Bidirectional UTF-8** | **Bidirectional UTF-8**\* | **Optional (GNOME RDP / `xrdp`)** | `spice-vdagent` via apt; Ubuntu 26.04 also has native Wayland RDP in *Settings -> System -> Remote Desktop*. |
| `omarchy` | **Bidirectional UTF-8** | **Bidirectional UTF-8**\* | **Optional (`xrdp` X11)** | Install `spice-vdagent`; Hyprland Wayland may need XWayland / `wl-clipboard`; **Type (ASCII)** always works. |
| `freebsd` | **Type (ASCII)** | Unsupported (no vdagent) | **Optional (`xrdp` X11)** | No FreeBSD `spice-vdagent` pkg; install `xrdp` + `xorgxrdp` for bidirectional RDP clipboard, or use SSH / `/shared`. |
| `daemonarchy` | **Type (ASCII)** | Unsupported (no vdagent) | **Optional (`xrdp` X11)** | No `spice-vdagent` on FreeBSD 16.0-CURRENT; Hyprland is Wayland-only (X11 RDP via `xrdp`, or SSH / `/shared`). |
| `haiku` | **Type (ASCII)** | Unsupported | Unsupported | No vdagent or RDP server; use **Type (ASCII)** or `/shared`. |

\*QEMU's VNC server sends guest->client updates **only** to clients negotiating **RFB Extended Clipboard (`0xC0A1E5CE`)**. Legacy-only VNC clients can send ISO-8859-1 `ClientCutText` (client->guest) only.

### Client platform recommendations

| Client OS | Web / noVNC (`8006`, HTTPS or localhost) | VNC client (`5900`) | RDP client (`3389`) |
| --- | --- | --- | --- |
| **Windows** | Chrome/Edge (auto-sync + `Ctrl+V`); Firefox (panel / **Paste from Device**) | **TigerVNC** (full UTF-8) | Built-in `mstsc.exe` |
| **macOS** | Chrome/Edge (`Cmd+V` + auto-sync); Safari (**Paste from Device** / **Copy from VM**) | **TigerVNC** (`brew install --cask tigervnc-viewer`); *avoid macOS Screen Sharing* (prefers Apple ARD auth 30, lacks Extended Clipboard) | **Windows App** (App Store) |
| **Linux** | Chrome/Chromium (auto-sync + `Ctrl+V`); Firefox (panel / buttons) | **TigerVNC** or **Remmina** (`libvncclient >= 0.9.14`) | **Remmina** or `xfreerdp3 /v:127.0.0.1 +clipboard` |
| **ChromeOS** | Chrome (auto-sync + `Ctrl+V` over HTTPS) | **noVNC (HTTPS)** | **Windows App** (Android) / Remmina (Crostini) |
| **Android** | Chrome (**Paste from Device** / **Copy from VM** over HTTPS) | `bVNC` / RealVNC (legacy CutText limits; prefer noVNC HTTPS) | **Windows App** (Play Store) |
| **iOS / iPadOS** | Safari (**Paste from Device** / **Copy from VM** over HTTPS) | RealVNC / RVNC (legacy CutText limits; prefer noVNC HTTPS) | **Windows App** (App Store) |

**Other VNC clients:** **TightVNC** and **UltraVNC** do not implement standard RFB Extended Clipboard (client->guest Latin-1 works; guest->client does not). **RealVNC Viewer** supports RFB Auth (type 2), with Extended Clipboard varying by release; use **TigerVNC**, **Remmina**, **noVNC (HTTPS)**, or **RDP** for guaranteed bidirectional UTF-8.

### Browser clipboard, Type fallback, & HTTPS (`WEB_TLS=Y` or TLS proxy)

- **Secure context requirement:** Browsers expose `navigator.clipboard` (`readText`/`writeText`) only over **HTTPS**, `http://localhost`, or `http://127.0.0.1`. On plain HTTP LAN URLs, the Clipboard panel still works (**Copy to VM**, **Copy from VM**, **Type (ASCII)**).
- **Bidirectional flow:** Guest copies fill `#noVNC_clipboard_text` automatically and write to your device clipboard when permitted; if a browser (Safari/Firefox/mobile) requires a user tap, the Clipboard button highlights for one-tap **Copy from VM**. Client->guest supports focus/click auto-sync (when `clipboard-read` is granted), `Ctrl+V`/`Cmd+V` without overwriting in-VM copies, native DOM `paste`, and **Paste from Device**.
- **Type (ASCII) fallback:** Sends US-QWERTY hardware keystrokes for agentless guests (`freebsd`, `daemonarchy`, `haiku`, UEFI/TTY). Non-ASCII characters are skipped with a status notice and non-US guest keymaps affect punctuation; use **Copy to VM** (with agent) or **RDP** for Unicode.
- **Built-in TLS (`WEB_TLS=Y`):** Serves HTTPS/WSS directly on `8006` with a persisted ECDSA P-256 self-signed cert in `/storage/.fnxvm-tls.{crt,key}` (add hostnames/IPs via `WEB_TLS_SAN="DNS:vm.example.test,IP:192.0.2.10"`, or mount PEMs via `WEB_TLS_CERT`/`WEB_TLS_KEY`). For a CA-trusted cert behind a reverse proxy (Caddy):

```caddyfile
vm.example.test {
    reverse_proxy 127.0.0.1:8006
}
```

### One-line guest agent & RDP setup

- **Debian / Ubuntu (`spice-vdagent`):** `sudo apt update && sudo apt install -y spice-vdagent`
- **Debian / Ubuntu (`xrdp`):** `sudo apt update && sudo apt install -y xrdp xorgxrdp && sudo systemctl enable --now xrdp`
- **Omarchy (`spice-vdagent`):** `sudo pacman -S --noconfirm spice-vdagent && sudo systemctl enable --now spice-vdagentd`
- **FreeBSD / Daemonarchy (`xrdp` X11):** `sudo pkg install -y xrdp xorgxrdp && sudo sysrc xrdp_enable=YES xrdp_sesman_enable=YES && sudo service xrdp start && sudo service xrdp-sesman start` (verify `cliprdr=true` in `/usr/local/etc/xrdp/xrdp.ini`)
- **Windows (existing VM / manual):** automatic on fresh x64/x86 installs (`WINDOWS_VDAGENT=Y`); manually install `spice-vdagent-x64-0.10.0.msi` (`msiexec /i spice-vdagent-x64-0.10.0.msi /qn /norestart`) from [spice-space.org](https://www.spice-space.org/download/windows/vdagent/vdagent-win-0.10.0/) or Fedora's `virtio-win-guest-tools.exe /install /quiet /norestart ACCEPTEULA=1` from [fedorapeople.org](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/).

## Video acceleration (`GPU`)

- **`auto` (default):** Safe software display (`VGA` on `amd64`, `ramfb` on `arm64`; Windows preserves upstream behavior; Haiku uses `VGA`) when `/dev/dri` is absent; activates `virgl` on Linux guests when an accessible `/dev/dri/renderD*` node is present.
- **`std` / `virtio` / `qxl`:** Software VGA/ramfb; 2D VirtIO (`virtio-vga`/`virtio-gpu-pci`); or QXL (`qxl-vga` on `amd64`, pair with `SPICE=Y`).
- **`virgl`:** Hardware OpenGL via `egl-headless` + `virtio-vga-gl`/`virtio-gpu-gl-pci`. Pass `--device /dev/dri` and render group GID (`--group-add "$(stat -c '%g' /dev/dri/renderD128)"`; optional `RENDERNODE=`). Falls back cleanly with a warning if `/dev/dri` is absent. VFIO PCIe passthrough is out of scope.

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
| Published multi-arch digest | `dgcosenza/fnxvm@sha256:4e93cd429f4e0a4ab295234ad85fb0c4d2856fd56edabe7e819a629026c6b428` |
| GHCR mirror | `ghcr.io/dgcosenza/fnxvm@sha256:4e93cd429f4e0a4ab295234ad85fb0c4d2856fd56edabe7e819a629026c6b428` |
| Supply chain | Cosign OIDC signed + SPDX & CycloneDX SBOM attestations + SLSA Build L3 provenance |
| Security gate (Trivy + Grype on SBOM) | **0 fixable findings of any severity** (76 upstream-unfixed C/H) |

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

- **From `6.06.2` to `6.06.3`:** Drop-in upgrade; universal noVNC clipboard is active automatically (set `WEB_TLS=Y` or use a TLS proxy for LAN HTTPS; `RDP=Y` forwards `3389` in user-mode networking for Linux/BSD).
- **From `6.06` / `dockur/windows` / `qemux/qemu`:** Auth is ON by default (`WEB_AUTH=Y`, `WEB_USER`, `WEB_PASSWORD_FILE`, `VNC_PASSWORD_FILE`); `/storage` and sizing/OS vars remain drop-in compatible.

## Security

- **Auth & TLS:** Web UI (`8006`, including `/websockify`, `/status`, `/audio`) uses nginx Basic Auth + bcrypt (`0600` hash in `/storage/.fnxvm-web.htpasswd`) and optional `WEB_TLS=Y` (TLS 1.2/1.3). VNC (`5900`) uses QMP `set_password` with an independent 8-char secret. Never publish `8006`, `5900`, or `3389` publicly without TLS/tunneling.
- **Zero fixable vulnerabilities of any severity:** Hard-gated by **Trivy** (`UNKNOWN`–`CRITICAL`, `--ignore-unfixed`, exit 1) AND **Grype** on the Syft SPDX SBOM (`--only-fixed --fail-on negligible`) on both `amd64` and `arm64`. Unfixed upstream CVEs are tracked in `versions.json`.
- **Supply chain:** Digest-pinned `debian:13.8-slim` + `golang:1.27.4-trixie`, keyless Cosign OIDC signatures (Docker Hub + GHCR), SPDX & CycloneDX SBOM attestations, SLSA Build L3 provenance, Hadolint, Gitleaks, Dive (`>= 95%`), OpenSSF Scorecard, OpenSSF Best Practices Passing, Renovate, and Dependabot.
- **Fail-closed runtime verification:** Offline vendor GPG keys (`gpgv`) for Debian/Ubuntu/Omarchy; SHA-256 for FreeBSD, Daemonarchy (`.iso.xz`), Haiku, and optional Windows `spice-vdagent` MSI; `VERIFY=Y` for Windows.

```bash
cosign verify \
  --certificate-identity-regexp='^https://github\.com/dgcosenza/fnxvm-docker/\.github/workflows/daily\.yml@refs/heads/main$' \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  ghcr.io/dgcosenza/fnxvm@sha256:<digest>

gh attestation verify oci://ghcr.io/dgcosenza/fnxvm@sha256:<digest> --owner dgcosenza
```

Report vulnerabilities privately via [GitHub Security Advisories](https://github.com/dgcosenza/fnxvm-docker/security/advisories/new) ([`SECURITY.md`](SECURITY.md)).

## Build locally

```bash
docker build -t fnxvm:local .
./tests/smoke.sh fnxvm:local
```

## Update policy

`.github/workflows/daily.yml` runs daily with `--no-cache` on `amd64` + `arm64`: resolves upstreams, base digests, and all 7 OSes; runs container, RFB Extended Clipboard protocol, Playwright headless browser, GPU, auth, TLS, and resolver tests; gates on Dive (`>= 95%`), Trivy, and Grype (0 fixable findings of any severity); publishes identical Cosign-signed digests + SBOMs + SLSA L3 provenance to GHCR, Docker Hub, and GitHub Releases; updates `versions.json`/`README.md`/`CHANGELOG.md` and syncs Docker Hub; opens/auto-closes `ci-failure` issues.

## Design decisions

- **Debian 13.8 `main` packages only:** Official QEMU, OpenGL/SPICE modules, `libegl-mesa0`, OVMF/AAVMF/SeaBIOS, Passt, swtpm, nginx, `apache2-utils`, and `openssl` keep 0 fixable CVEs without Sid snapshots or third-party `.deb` bundles.
- **From-source helpers & isolated Python:** `websocketd`, `boot-logo` (`golang:1.27.4-trixie`), and `udfread` build from SHA-256-verified source; `qemu.qmp` runs without `pip` in runtime.
- **Universal clipboard without heavy RDP gateways:** Fixes noVNC Extended Clipboard caps, integrates browser Async Clipboard API + non-ASCII-safe Type fallback, adds zero-bloat `WEB_TLS=Y` via existing `openssl`, and auto-stages verified `spice-vdagent` on Windows. Heavy stacks like Apache Guacamole (Java/Tomcat) or custom RDP proxies are intentionally omitted to protect image minimalism and the 0-fixable-CVE gate; use direct port `3389` over VPN/SSH tunnel or noVNC over HTTPS.

## License

Packaging is licensed under the **MIT License**, Copyright (c) 2026 Daniel G. Cosenza from FNX Labs ([`LICENSE`](LICENSE)). Reused `dockur/windows` and `qemus/qemu` assets are MIT; third-party notices are in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md). Guest OS media and optional runtime agents remain under their vendor licenses.

## Credits

Maintainer: **Daniel G. Cosenza from FNX Labs**. Built upon [`dockur/windows`](https://github.com/dockur/windows), [`qemus/qemu`](https://github.com/qemus/qemu), QEMU, EDK2/OVMF, noVNC, Passt, SPICE, Debian, Ubuntu, FreeBSD, Daemonarchy (Jordan Hubbard), Haiku, and Omarchy.
