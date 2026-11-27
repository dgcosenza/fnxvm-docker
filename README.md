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
[![Version](https://img.shields.io/badge/version-6.06.2-blue.svg)](CHANGELOG.md)

Maintainer: Daniel G. Cosenza from FNX Labs

**FNXVM** is a multi-OS QEMU/KVM virtual machine container built on **Debian 13.8 (`debian:13.8-slim`)**. It provides an authenticated **noVNC** web viewer (HTTP Basic + bcrypt), password-protected **VNC**, **RDP** (Windows), host-guest **clipboard** (`qemu-vdagent` / SPICE vdagent), and configurable **GPU acceleration** (`GPU=auto|virtio|virgl|qxl|std`), combining [`qemus/qemu`](https://github.com/qemus/qemu) with [`dockur/windows`](https://github.com/dockur/windows).

**No OS ISOs or proprietary media are ever bundled or redistributed.** When `OS=` is set, FNXVM resolves the latest official release directly from the vendor at runtime, downloads it, and verifies checksums and cryptographic signatures before booting (failing closed on mismatch).

## Supported tags

- `latest` — latest daily verified multi-arch build (`linux/amd64` + `linux/arm64`)
- `<version>` — FNXVM release version (e.g. `6.06.2`), `<version>-<YYYYMMDD>` (immutable), `sha-<short>`
- Digest pinning (recommended): `dgcosenza/fnxvm@sha256:<digest>` / `ghcr.io/dgcosenza/fnxvm@sha256:<digest>` (identical Cosign-signed digests on Docker Hub and GHCR)

## Supported guest operating systems

Select a guest with `OS=` (or pass `BOOT=<url>`, or `VERSION=` for Windows). Unknown `OS` values fail fast.

| `OS` | Guest | Version policy | Arch | Official source | Runtime verification |
| --- | --- | --- | --- | --- | --- |
| `debian` | Debian Desktop (`DESKTOP=gnome` or `kde`) | Latest stable live ISO (`amd64`); DVD-1 installer (`arm64`, no official arm64 live ISO) | `amd64`, `arm64` | `cdimage.debian.org` | GPG (`SHA256SUMS.sign`) + SHA-256 |
| `ubuntu` | Ubuntu Desktop LTS | Latest even-year `.04` LTS point release | `amd64`, `arm64` | `releases.ubuntu.com` / `cdimage.ubuntu.com` | GPG (`SHA256SUMS.gpg`) + SHA-256 |
| `freebsd` | FreeBSD | Latest production `-RELEASE` (skips `BETA`/`RC`/`ALPHA`) | `amd64`, `arm64` | `download.freebsd.org` | SHA-256 (`CHECKSUM.SHA256`) |
| `daemonarchy` | Daemonarchy (Omarchy Hyprland desktop on FreeBSD) | Latest stable release; **tracks FreeBSD 16.0-CURRENT, no LTS** | `amd64` (BIOS/UEFI), `arm64` (UEFI-only community-validation) | `github.com/jordanhubbard/daemonarchy` | SHA-256 on compressed `.iso.xz` before `xz -dc` |
| `haiku` | Haiku | Latest release (`R1/betaN`) | `amd64` only | `haiku-os.org` / CDN | SHA-256 (`.iso.sha256`; `.minisig` published) |
| `omarchy` | Omarchy (Arch-based) | Latest rolling ISO — **rolling; no LTS exists** | `amd64`, `arm64` | `omarchy.org` / `iso.omarchy.org` | SHA-256 + GPG (`.iso.sig`) |
| `windows` | Windows (`VERSION=11` default; supports `dockur/windows` values + `ltsc`/`iot-ltsc`) | Official Microsoft endpoints (consumer ISO / ESD / Eval Center) | `amd64` (all), `arm64` (Win 10/11 ARM64) | Microsoft official endpoints | Microsoft ESD SHA-1/SHA-256 (`VERIFY=Y`) |
| *(unset + `BOOT=`)* | Custom ISO / raw / qcow2 / vmdk / vhdx | User-supplied URL or `/boot.iso` / `/boot.img` | `amd64`, `arm64` | User-specified | User-managed |

> **Daemonarchy note:** [Daemonarchy](https://github.com/jordanhubbard/daemonarchy) (Jordan Hubbard) is **not affiliated with Omarchy**; it tracks FreeBSD 16.0-CURRENT with **no LTS**. Use **`DISK_SIZE>=40G`** (default `64G`) and keep Internet access during install (~1,200 packages downloaded). The `aarch64` asset is a UEFI-only community-validation image verified in QEMU. **Omarchy** is also rolling with no LTS.

## Supported architectures

Built and tested natively in CI on `linux/amd64` (`qemu-system-x86_64`, OVMF/SeaBIOS/swtpm) and `linux/arm64` (`qemu-system-aarch64`, AAVMF/swtpm). `amd64` supports all 7 OSes; `arm64` supports `debian`, `ubuntu`, `freebsd`, `daemonarchy` (UEFI community-validation), `omarchy`, and Windows 10/11 ARM64 (`haiku` fails fast on `arm64` as no official arm64 release ISO exists).

## Quick start

If `WEB_PASSWORD` / `WEB_PASSWORD_FILE` are omitted on first start, FNXVM generates a strong random password, prints it **once** in logs, and persists **only its bcrypt hash** in `/storage/.fnxvm-web.htpasswd`.

```bash
# Choose OS: debian (DESKTOP=gnome|kde), ubuntu, freebsd, daemonarchy, haiku, omarchy, or windows (VERSION=11|ltsc|iot-ltsc|...)
docker run -it --rm \
  --device /dev/kvm --device /dev/net/tun --cap-add NET_ADMIN \
  -p 127.0.0.1:8006:8006 \
  -e OS=debian -e DESKTOP=gnome \
  -v fnxvm-debian:/storage \
  dgcosenza/fnxvm:latest

# Daemonarchy (>=40G disk + network during install)
docker run -it --rm \
  --device /dev/kvm --device /dev/net/tun --cap-add NET_ADMIN \
  -p 127.0.0.1:8006:8006 \
  -e OS=daemonarchy -e DISK_SIZE=64G -e RAM_SIZE=4G \
  -v fnxvm-daemonarchy:/storage \
  dgcosenza/fnxvm:latest

# Windows 11 with RDP
docker run -it --rm \
  --device /dev/kvm --device /dev/net/tun --cap-add NET_ADMIN \
  -p 127.0.0.1:8006:8006 -p 127.0.0.1:3389:3389 \
  -e OS=windows -e VERSION=11 \
  -v fnxvm-windows:/storage \
  dgcosenza/fnxvm:latest

# Dry-run OS resolution without KVM or ISO download
docker run --rm -e RESOLVE_ONLY=1 -e OS=daemonarchy dgcosenza/fnxvm:latest
docker run --rm --user vmuser --entrypoint fnxvm-resolve dgcosenza/fnxvm:latest daemonarchy --verify-urls
```

Open `http://127.0.0.1:8006` and sign in with `WEB_USER` (`fnxvm`) + your configured or first-start password.

## Compose example

Create `chmod 600` secret files `./secrets/web_password.txt` and `./secrets/vnc_password.txt` first (full example in [`docker-compose.example.yml`](docker-compose.example.yml)):

```yaml
services:
  fnxvm:
    image: dgcosenza/fnxvm:latest
    container_name: fnxvm
    environment:
      OS: "debian"
      DESKTOP: "gnome"
      GPU: "auto"
      CLIPBOARD: "Y"
      WEB_AUTH: "Y"
      WEB_USER: "fnxvm"
      WEB_PASSWORD_FILE: "/run/secrets/fnxvm_web_password"
      VNC_PASSWORD_FILE: "/run/secrets/fnxvm_vnc_password"
      RAM_SIZE: "4G"
      CPU_CORES: "2"
      DISK_SIZE: "64G"
    secrets:
      - fnxvm_web_password
      - fnxvm_vnc_password
    devices:
      - /dev/kvm:/dev/kvm
      - /dev/net/tun:/dev/net/tun
      # - /dev/dri:/dev/dri   # Optional for GPU=virgl (add host render GID via group_add)
    cap_drop: [ALL]
    cap_add: [NET_ADMIN, CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID, NET_BIND_SERVICE]
    security_opt: ["no-new-privileges:true"]
    ports:
      - "127.0.0.1:8006:8006"
    volumes:
      - fnxvm_storage:/storage
    stop_grace_period: 2m
    restart: unless-stopped

secrets:
  fnxvm_web_password:
    file: ./secrets/web_password.txt
  fnxvm_vnc_password:
    file: ./secrets/vnc_password.txt

volumes:
  fnxvm_storage:
```

## Authentication

Both the web viewer (`8006`) and VNC (`5900`) require authentication by default; no credentials are ever baked into the image.

- **Web UI (`8006`):** nginx HTTP Basic Auth with **bcrypt** hashes protects `/`, `/vnc.html`, `/websockify`, `/status`, and `/audio`. Configured via `WEB_USER` (default `fnxvm`), `WEB_PASSWORD_FILE`, or `WEB_PASSWORD` — separate from `dockur/windows`'s `USERNAME`/`PASSWORD` guest variables.
  - **First start & persistence:** When unset, FNXVM generates a 24-character random password, prints it **once** in container logs, and persists **only the bcrypt hash** (`0600`) in `/storage/.fnxvm-web.htpasswd`. Restarts reuse the hash silently.
  - **Rotation:** Supply a new `WEB_PASSWORD_FILE`/`WEB_PASSWORD` and restart, or delete `/storage/.fnxvm-web.htpasswd` and restart to generate a fresh secret.
  - **Escape hatch (`WEB_AUTH=N`):** Disables nginx Basic Auth with a **loud warning** in logs. Use only behind an authenticating reverse proxy or strictly on loopback.
- **VNC (`5900`):** Always launched with `-vnc ...,password=on` (RFB security type `2`, never `None`) and configured via QEMU's private QMP socket (`set_password` — never in `/proc/<pid>/cmdline`). Set `VNC_PASSWORD_FILE` / `VNC_PASSWORD`; if neither is set, FNXVM generates an **independent** random 8-character VNC secret (never derived from the Web UI password), prints it **once** in the logs, and persists it with mode `0600` in `/storage/.fnxvm-vnc.secret` (QEMU needs the plaintext for `set_password`). Delete that file and restart to rotate it. The noVNC viewer asks for this VNC password after the Web UI sign-in. **RFB caps VNC passwords at 8 characters and is unencrypted — do not publish port `5900` publicly**; use authenticated noVNC behind TLS instead.

## Clipboard (host <-> guest)

Enabled by default (`CLIPBOARD=Y`; set `CLIPBOARD=N` to omit). QEMU attaches `virtio-serial-pci` + `virtserialport` (`com.redhat.spice.0`) backed by `-chardev qemu-vdagent,id=vdagent,name=vdagent,clipboard=on` for VNC/noVNC (or `spicevmc` when `SPICE=Y`). In noVNC's **Clipboard** panel, guest copies appear automatically; click **Copy to VM** for RFB Extended Clipboard sync, or **Type** to send keystrokes to guests without `spice-vdagent`.

| Guest `OS` | Native vdagent clipboard | Guest tools / notes |
| --- | --- | --- |
| `debian` | **Supported** | `spice-vdagent` usually preinstalled on live desktop ISOs (`sudo apt install spice-vdagent`). |
| `ubuntu` | **Supported** | `sudo apt install spice-vdagent` if not preinstalled. |
| `omarchy` | **Supported (Wayland notes)** | `sudo pacman -S spice-vdagent && sudo systemctl enable --now spice-vdagentd`; Hyprland may need XWayland or `wl-clipboard` bridge (**Type** fallback always works). |
| `windows` | **Supported (guest tools)** | `vioserial` driver is staged from `virtio-win`; install official `spice-guest-tools` or Fedora `virtio-win-guest-tools.exe` inside Windows for noVNC clipboard. Native RDP (`3389`) also syncs clipboard. |
| `freebsd` | **Unsupported natively** | No `spice-vdagent` port in FreeBSD `pkg`; use noVNC **Type**, SSH, or `/shared` (9p). (`pkg install qemu-guest-agent` works for `QGA`.) |
| `daemonarchy` | **Unsupported natively** | FreeBSD 16.0-CURRENT lacks `spice-vdagent`; use noVNC **Type**, SSH, or `/shared` (9p). |
| `haiku` | **Unsupported** | No vdagent for Haiku; use noVNC **Type** or `/shared`. |

## Video acceleration (`GPU`)

Set `GPU=` (`auto` default, `virtio`, `virgl`, `qxl`, `std`):

- **`auto` (default):** Chooses a safe software device (`VGA` on `amd64`, `ramfb` on `arm64`; Windows preserves upstream behavior; Haiku uses `VGA`) when no `/dev/dri` is present — never fails on CI or headless servers. Activates `virgl` automatically only on Linux guests when an accessible `/dev/dri/renderD*` node and QEMU OpenGL support are present.
- **`std`:** Safe software display (`VGA` on `amd64`, `ramfb` on `arm64`).
- **`virtio`:** 2D VirtIO GPU (`virtio-vga` on `amd64`, `virtio-gpu-pci` on `arm64`).
- **`virgl`:** Hardware OpenGL via `egl-headless` + `virtio-vga-gl` (`amd64`) / `virtio-gpu-gl-pci` (`arm64`). Pass `--device /dev/dri` and host render group GID (`--group-add "$(stat -c '%g' /dev/dri/renderD128)"`; pin device with `RENDERNODE=/dev/dri/renderD128`). If `/dev/dri` is missing or inaccessible, logs a clear warning and **falls back cleanly** to software rendering without crashing.
- **`qxl`:** QXL display (`qxl-vga` on `amd64`; falls back with warning on `arm64`); pair with `SPICE=Y` (`SPICE_PORT=5901`) for native SPICE clients.
- **VFIO PCIe GPU passthrough:** Out of scope for standard container execution (requires host IOMMU / `vfio-pci` binding).

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `OS` | *(empty -> `debian`)* | `debian`, `ubuntu`, `freebsd`, `daemonarchy`, `haiku`, `omarchy`, `windows` (fail-fast on unknown). |
| `DESKTOP` | `gnome` | For `OS=debian`: `gnome` or `kde`. |
| `VERSION` | `11` (`windows`) | Any `dockur/windows` edition (`11`, `11e`, `11l`/`ltsc`, `11i`/`iot-ltsc`, `10`, `2025`, etc.). |
| `BOOT` | *(empty)* | Custom HTTP(S) ISO/disk URL (when `OS` is unset) or `qemus/qemu` alias. |
| `RESOLVE_ONLY` | `N` | Resolve and print OS version, ISO URL, and checksum URL without starting QEMU. |
| `GPU` / `RENDERNODE` | `auto` / *(auto)* | Display mode (`auto`, `virtio`, `virgl`, `qxl`, `std`) and optional `/dev/dri/renderD*` node. |
| `CLIPBOARD` | `Y` | Enable `virtio-serial-pci` + `qemu-vdagent`/`spicevmc` (`com.redhat.spice.0`). |
| `WEB_AUTH` / `WEB_USER` | `Y` / `fnxvm` | HTTP Basic Auth toggle and username on `WEB_PORT`. |
| `WEB_PASSWORD` / `WEB_PASSWORD_FILE` | *(auto-generated)* | Web UI password or secret file path (bcrypt-hashed into `/storage/.fnxvm-web.htpasswd`). |
| `VNC_PASSWORD` / `VNC_PASSWORD_FILE` | *(auto-generated, 8 chars)* | VNC RFB password or secret file path (max 8 chars, set via QMP). |
| `SPICE` / `SPICE_PORT` | `N` / `5901` | Optional QMP-authenticated SPICE server alongside noVNC/VNC. |
| `RAM_SIZE` / `CPU_CORES` / `DISK_SIZE` | `4G` / `2` / `64G` | Guest RAM, vCPUs (`half`/`max`), and `/storage` disk size (`>=40G` for `daemonarchy`). |
| `DISK_FMT` / `BOOT_MODE` | `raw` / *(auto)* | `raw` or `qcow2`; `uefi`, `secure`, `legacy`, `windows`, `windows_secure`, `windows_legacy`. |
| `KVM` / `NETWORK` / `DHCP` | `Y` / `Y` / `N` | KVM (`/dev/kvm`, or `KVM=N` TCG); `Y`/TAP, `user`/`passt`, or `N`; macvlan DHCP. |
| `WEB` / `WEB_PORT` / `VNC_PORT` | `Y` / `8006` / `5900` | Web viewer toggle (`WEB=N` for headless VNC) and listening ports. |
| `USERNAME` / `PASSWORD` | `Docker` / `admin` | Windows guest account credentials only (does not affect FNXVM Web UI auth). |
| `VERIFY` / `AUDIO` / `SAMBA` | `Y` / `N` / `Y` | Windows ESD verification; browser audio; `/shared` Samba (Windows) / 9p (Unix). |
| `LANGUAGE` / `REGION` / `KEYBOARD` / `ARGUMENTS` / `DEBUG` | `en` / *(empty)* / `N` | Windows locale, extra QEMU flags, verbose diagnostics. |

**Ports:** `8006/tcp` (authenticated noVNC), `5900/tcp` (passworded VNC — keep local), `3389/tcp+udp` (RDP), `22/tcp` (SSH), optional `5901/tcp` (SPICE). **Volumes:** `/storage` (disks, NVRAM, `.fnxvm-web.htpasswd`), optional `/shared`. **Users:** `root` (UID 0) default for `/dev/kvm` and TAP networking; `vmuser` (UID/GID 1000) for non-root CLI tools. **PID 1:** `tini`.

## Healthcheck

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD ["/usr/local/bin/fnxvm-healthcheck"]
```

Probes nginx's internal Unix socket (`/run/shm/nginx-health.sock` -> `/healthz`, never exposed on TCP), checks `127.0.0.1:${WEB_PORT}/` returns `401` (when `WEB_AUTH=Y`) or `200` (`WEB_AUTH=N`), checks `/run/shm/status-ws.sock` (or `127.0.0.1:${VNC_PORT}` when `WEB=N`), and verifies QEMU's PID once started. Verified on both `amd64` and `arm64` in CI; do not override or disable in Compose.

## Current versions

<!-- versions:start -->
| Component | Resolved Version |
| --- | --- |
| dockur/windows | `6.06` |
| qemus/qemu | `7.50` |
| Base OS | `Debian 13.8 (13.8-slim)` |
| Architectures | `linux/amd64, linux/arm64` |
| Uncompressed size (per arch) | `amd64: 170.8 MB, arm64: 906.4 MB` |
| Last verified build (UTC) | `2026-11-27` |
| Published multi-arch digest | `dgcosenza/fnxvm@sha256:5f1c711d3438fb735b06de103bcfaefd89e97ac04dee452b99402446c2f3d0ff` |
| GHCR mirror | `ghcr.io/dgcosenza/fnxvm@sha256:5f1c711d3438fb735b06de103bcfaefd89e97ac04dee452b99402446c2f3d0ff` |
| Supply chain | Cosign OIDC signed + SPDX & CycloneDX SBOM attestations + SLSA Build L3 provenance |
| Security gate (Trivy + Grype on SBOM) | **0 fixable findings of any severity** (68 upstream-unfixed C/H) |

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
<!-- versions:end -->

## Upgrade / migration

- **From FNXVM `6.06` to `6.06.2`:** Auth is now ON by default (`WEB_AUTH=Y`, `WEB_USER`, `WEB_PASSWORD_FILE`/`WEB_PASSWORD`, `VNC_PASSWORD_FILE`/`VNC_PASSWORD`; replaces legacy `PROTECT`/`PASS`). Pull the new digest while keeping `/storage`.
- **From `dockur/windows` / `qemux/qemu`:** Switch image to `dgcosenza/fnxvm:latest` (or digest); existing `VERSION`, `BOOT`, sizing vars, and `/storage` remain drop-in compatible.

## Security

- **Auth on by default:** Web UI (`8006`, including `/websockify`, `/status`, `/audio`) uses nginx HTTP Basic + bcrypt (`0600` hash-only in `/storage/.fnxvm-web.htpasswd`). VNC (`5900`) uses QEMU `password=on` set via QMP (`set_password`). Never expose `8006`, `5900`, or `3389` publicly without TLS; avoid publishing `5900` publicly (RFB 8-char limit).
- **Zero fixable vulnerabilities of any severity:** Hard-gated by **Trivy** (`UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL`, `--ignore-unfixed`, exit 1) AND **Grype** on the Syft SPDX SBOM (`--only-fixed --fail-on negligible`) on both `amd64` and `arm64`.
- **Supply-chain hardening:** Pinned `debian:13.8-slim` + `golang:1.27.4-trixie`, keyless Cosign OIDC signatures (Docker Hub + GHCR), SPDX & CycloneDX SBOM attestations, SLSA Build L3 provenance, Hadolint, Gitleaks, Dive (`>= 95%`), OpenSSF Scorecard, OpenSSF Best Practices Passing, Renovate, and Dependabot.
- **Fail-closed ISO verification:** Bundled offline vendor GPG keys (`gpgv`) for Debian/Ubuntu/Omarchy; SHA-256 for FreeBSD, Daemonarchy (compressed `.iso.xz` before `xz -dc`), and Haiku; `VERIFY=Y` default for Windows. Unfixed upstream CVEs are tracked in `versions.json`.

```bash
# Verify Cosign OIDC signature
cosign verify \
  --certificate-identity-regexp='^https://github\.com/dgcosenza/fnxvm-docker/\.github/workflows/daily\.yml@refs/heads/main$' \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  ghcr.io/dgcosenza/fnxvm@sha256:<digest>

# Verify SLSA Build L3 provenance
gh attestation verify oci://ghcr.io/dgcosenza/fnxvm@sha256:<digest> --owner dgcosenza
```

Report vulnerabilities privately via [GitHub Security Advisories](https://github.com/dgcosenza/fnxvm-docker/security/advisories/new) ([`SECURITY.md`](SECURITY.md)).

## Build locally

```bash
docker build -t fnxvm:local .
./tests/smoke.sh fnxvm:local
```

## Update policy

`.github/workflows/daily.yml` runs daily with `--no-cache` on both `amd64` and `arm64`: resolves upstreams, base digests, and all 7 guest OSes; builds and runs full smoke/auth/clipboard/GPU/resolver tests; gates on Dive (`>= 95%`), Trivy, and Grype (0 fixable findings of any severity); publishes identical Cosign-signed multi-arch digests with SBOMs and SLSA L3 provenance to GHCR, Docker Hub, and GitHub Releases; updates `versions.json`/`README.md`/`CHANGELOG.md` and syncs Docker Hub; opens/auto-closes a `ci-failure` issue on failure/recovery.

## Design decisions

- **Official Debian 13.8 `main` packages (no frozen Sid snapshot, no `non-free`):** Uses `qemu-system-x86`/`arm`, `qemu-system-modules-opengl`, `qemu-system-modules-spice`, `libegl-mesa0`, `ovmf`, `qemu-efi-aarch64`, `seabios`, `passt`, `swtpm`, `samba`, `wimtools`, `nginx`, and `apache2-utils` for continuous security updates and 0 fixable CVEs. OpenGL/SPICE modules + `libegl-mesa0` enable `GPU=virgl`/`qxl` and `spicevmc` without third-party `.deb` bundles or Vulkan/LLVM bloat.
- **From-source helpers & isolated Python:** `websocketd`, `boot-logo`, and `udfread` compile from SHA-256-verified source with `golang:1.27.4-trixie` / Debian 13; `qemu.qmp` is isolated without `python3-pip` in runtime.
- **Separated auth & internal health socket:** `WEB_USER`/`WEB_PASSWORD_FILE` never collide with Windows `USERNAME`/`PASSWORD`; QMP sets VNC passwords off the command line; nginx healthchecks stay on a container-internal Unix socket.
- **Native noVNC RFB clipboard + Type fallback:** Restores `RFB.clipboardPasteFrom()` for `qemu-vdagent` while keeping simulated keystrokes for agentless guests.

## License

Packaging is licensed under the **MIT License**, Copyright (c) 2026 Daniel G. Cosenza from FNX Labs ([`LICENSE`](LICENSE)). Reused `dockur/windows` and `qemus/qemu` assets are MIT; third-party notices are in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md). Guest OS media downloaded at runtime remain under their vendor licenses.

## Credits

Maintainer: **Daniel G. Cosenza from FNX Labs**. Built upon [`dockur/windows`](https://github.com/dockur/windows), [`qemus/qemu`](https://github.com/qemus/qemu), QEMU, EDK2/OVMF, noVNC, Passt, Debian, Ubuntu, FreeBSD, Daemonarchy (Jordan Hubbard), Haiku, and Omarchy.
