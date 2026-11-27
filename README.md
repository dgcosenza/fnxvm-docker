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
[![Version](https://img.shields.io/badge/version-6.06-blue.svg)](CHANGELOG.md)

Maintainer: Daniel G. Cosenza from FNX Labs

**FNXVM** is a general-purpose, multi-OS virtual machine container built on **Debian 13.8 (`debian:13.8-slim`)**. It runs desktop and server operating systems inside QEMU/KVM with an embedded **noVNC** web viewer, native **VNC**, and **RDP** (for Windows guests), combining the generic QEMU runtime of [`qemus/qemu`](https://github.com/qemus/qemu) with the unattended Windows installer of [`dockur/windows`](https://github.com/dockur/windows).

**No operating system ISOs or proprietary media are ever bundled or redistributed in this image.** When a guest is selected with `OS=`, FNXVM dynamically resolves the latest official release directly from the vendor at runtime, downloads it from the vendor's servers, and verifies published checksums and cryptographic signatures before booting (failing closed on mismatch).

## Supported tags

- `latest` — latest daily verified multi-arch build
- `<version>` — tracked upstream release version, e.g. `6.06`
- `<version>-<YYYYMMDD>` — immutable date-stamped build
- `sha-<short>` — git short commit SHA
- Digest pinning (recommended for production): `dgcosenza/fnxvm@sha256:<digest>` or `ghcr.io/dgcosenza/fnxvm@sha256:<digest>`

Published for `linux/amd64` and `linux/arm64` to both Docker Hub (`dgcosenza/fnxvm`) and GitHub Container Registry (`ghcr.io/dgcosenza/fnxvm`) with identical Cosign-signed multi-arch manifest digests.

## Supported guest operating systems

Select a guest with the `OS` environment variable (or pass a custom image URL with `BOOT=<url>`, or upstream-compatible `VERSION=` for Windows). Unknown `OS` values fail fast and print the list of valid options.

| `OS` value | Guest | Version policy | Architectures | Official source | Runtime verification |
| --- | --- | --- | --- | --- | --- |
| `debian` | Debian Desktop (`DESKTOP=gnome` default, or `kde`) | Latest stable live ISO (`amd64`); latest stable DVD-1 installer (`arm64` — Debian publishes no official arm64 live ISO) | `amd64`, `arm64` | `cdimage.debian.org` | GPG (`SHA256SUMS.sign`) + SHA-256 |
| `ubuntu` | Ubuntu Desktop LTS | Latest LTS point release (even-year `.04`) | `amd64`, `arm64` | `releases.ubuntu.com` (`amd64`), `cdimage.ubuntu.com` (`arm64`) | GPG (`SHA256SUMS.gpg`) + SHA-256 |
| `freebsd` | FreeBSD | Latest production `-RELEASE` (skips `BETA`/`RC`/`ALPHA`) | `amd64`, `arm64` | `download.freebsd.org` | SHA-256 (`CHECKSUM.SHA256`) |
| `haiku` | Haiku | Latest release (`R1/betaN`) | `amd64` only (no official arm64 release ISO) | `haiku-os.org` / official CDN & mirrors | SHA-256 (`.iso.sha256`; `.minisig` also published) |
| `omarchy` | Omarchy (Arch-based) | Latest rolling ISO — **rolling distribution; no LTS exists** | `amd64`, `arm64` | `omarchy.org` / `iso.omarchy.org` | SHA-256 (`.iso.sha256`) + GPG (`.iso.sig`) |
| `windows` | Windows (`VERSION=11` default; supports every `dockur/windows` `VERSION`, plus `ltsc` / `iot-ltsc` aliases) | Official Microsoft endpoints (consumer ISO / ESD catalog / Evaluation Center) | `amd64` (all editions), `arm64` (Windows 10/11 ARM64 via `dockur/windows-arm`) | Microsoft official endpoints | Microsoft ESD SHA-1/SHA-256 (`VERIFY=Y` default) |
| *(unset + `BOOT=<url>`)* | Custom ISO / raw / qcow2 / vmdk / vhdx | User-supplied URL or bind-mounted `/boot.iso` / `/boot.img` | `amd64`, `arm64` | User-specified | User-managed |

> **Important note on Omarchy:** Omarchy is an Arch Linux–based **rolling** distribution. No Long-Term Support (LTS) track exists; `OS=omarchy` always resolves to the latest official Omarchy ISO.

## Supported architectures

Both `linux/amd64` and `linux/arm64` images are built natively in CI (`ubuntu-latest` and `ubuntu-24.04-arm`) and verified with real QEMU boot, noVNC/VNC healthcheck, and OS resolver tests:

- **`linux/amd64`** (`qemu-system-x86_64`, OVMF UEFI + Secure Boot + TPM 2.0 `swtpm`, SeaBIOS legacy): supports all 6 guest OSes (`debian` GNOME/KDE live, `ubuntu` Desktop LTS, `freebsd`, `haiku`, `omarchy`, and all `dockur/windows` editions including Windows 11/10/Server/legacy).
- **`linux/arm64`** (`qemu-system-aarch64`, AAVMF UEFI + Secure Boot + TPM 2.0 `swtpm`): supports `debian` (official DVD-1 installer where GNOME/KDE is chosen during setup), `ubuntu` Desktop LTS, `freebsd`, `omarchy` (`aarch64`), and `windows` (Windows 10/11 ARM64 via upstream `dockur/windows-arm` scripts; x86-only legacy Windows and Windows Server editions are rejected with a clear message). `haiku` is rejected cleanly on `arm64` because the Haiku Project does not publish official `arm64` release ISOs.

## Quick start

```bash
# Debian Desktop (GNOME live ISO — neutral default when OS is omitted)
docker run -it --rm \
  --device /dev/kvm --device /dev/net/tun --cap-add NET_ADMIN \
  -p 127.0.0.1:8006:8006 \
  -e OS=debian -e DESKTOP=gnome \
  -v fnxvm-debian:/storage \
  dgcosenza/fnxvm:latest

# Debian Desktop (KDE live ISO)
docker run -it --rm \
  --device /dev/kvm --device /dev/net/tun --cap-add NET_ADMIN \
  -p 127.0.0.1:8006:8006 \
  -e OS=debian -e DESKTOP=kde \
  -v fnxvm-debian-kde:/storage \
  dgcosenza/fnxvm:latest

# Ubuntu Desktop LTS (latest LTS point release)
docker run -it --rm \
  --device /dev/kvm --device /dev/net/tun --cap-add NET_ADMIN \
  -p 127.0.0.1:8006:8006 \
  -e OS=ubuntu \
  -v fnxvm-ubuntu:/storage \
  dgcosenza/fnxvm:latest

# FreeBSD (latest production -RELEASE)
docker run -it --rm \
  --device /dev/kvm --device /dev/net/tun --cap-add NET_ADMIN \
  -p 127.0.0.1:8006:8006 \
  -e OS=freebsd \
  -v fnxvm-freebsd:/storage \
  dgcosenza/fnxvm:latest

# Haiku (latest R1/betaN — amd64 only)
docker run -it --rm \
  --device /dev/kvm --device /dev/net/tun --cap-add NET_ADMIN \
  -p 127.0.0.1:8006:8006 \
  -e OS=haiku \
  -v fnxvm-haiku:/storage \
  dgcosenza/fnxvm:latest

# Omarchy (latest rolling ISO; no LTS exists)
docker run -it --rm \
  --device /dev/kvm --device /dev/net/tun --cap-add NET_ADMIN \
  -p 127.0.0.1:8006:8006 \
  -e OS=omarchy \
  -v fnxvm-omarchy:/storage \
  dgcosenza/fnxvm:latest

# Windows 11 (or VERSION=ltsc / iot-ltsc / 10 / 2025, etc.)
docker run -it --rm \
  --device /dev/kvm --device /dev/net/tun --cap-add NET_ADMIN \
  -p 127.0.0.1:8006:8006 -p 127.0.0.1:3389:3389 \
  -e OS=windows -e VERSION=11 \
  -v fnxvm-windows:/storage \
  dgcosenza/fnxvm:latest

# Custom ISO or disk image URL
docker run -it --rm \
  --device /dev/kvm --device /dev/net/tun --cap-add NET_ADMIN \
  -p 127.0.0.1:8006:8006 \
  -e BOOT="https://example.invalid/custom.iso" \
  -v fnxvm-custom:/storage \
  dgcosenza/fnxvm:latest

# Dry-run OS resolution without KVM or downloading any ISO
docker run --rm -e RESOLVE_ONLY=1 -e OS=debian -e DESKTOP=kde dgcosenza/fnxvm:latest
docker run --rm --user vmuser --entrypoint fnxvm-resolve dgcosenza/fnxvm:latest ubuntu --verify-urls
```

Open `http://127.0.0.1:8006` in your browser to view the guest console via noVNC.

## Compose example

```yaml
services:
  fnxvm:
    image: dgcosenza/fnxvm:latest
    container_name: fnxvm
    environment:
      OS: "debian"
      DESKTOP: "gnome"
      PROTECT: "Y"
      USERNAME: "vmadmin"
      PASSWORD: "change-me-before-starting"
      RAM_SIZE: "4G"
      CPU_CORES: "2"
      DISK_SIZE: "64G"
    devices:
      - /dev/kvm:/dev/kvm
      - /dev/net/tun:/dev/net/tun
    cap_drop:
      - ALL
    cap_add:
      - NET_ADMIN
      - CHOWN
      - DAC_OVERRIDE
      - FOWNER
      - SETGID
      - SETUID
      - NET_BIND_SERVICE
    security_opt:
      - no-new-privileges:true
    ports:
      - "127.0.0.1:8006:8006"
      - "127.0.0.1:5900:5900/tcp"
      - "127.0.0.1:3389:3389/tcp"
    volumes:
      - fnxvm_storage:/storage
    stop_grace_period: 2m
    restart: unless-stopped

volumes:
  fnxvm_storage:
```

A full annotated example is in [`docker-compose.example.yml`](docker-compose.example.yml).

## Configuration

### Environment variables

| Variable | Default | Description |
| --- | --- | --- |
| `OS` | *(empty -> `debian` unless `VERSION` or `BOOT` is set)* | Guest OS selector: `debian`, `ubuntu`, `freebsd`, `haiku`, `omarchy`, `windows`. Unknown values fail fast. |
| `DESKTOP` | `gnome` | Desktop flavor for `OS=debian`: `gnome` or `kde`. Unknown values fail fast. |
| `VERSION` | `11` (when `OS=windows`) | Windows edition selector (accepts every upstream `dockur/windows` value such as `11`, `11e`, `11l`, `11i`, `10`, `2025`, `2022`, `2019`, plus `ltsc` and `iot-ltsc` aliases). Setting `VERSION` with `OS` and `BOOT` unset automatically selects Windows mode for drop-in compatibility. |
| `BOOT` | *(empty)* | Custom HTTP(S) ISO/disk URL (when `OS` is unset) or any upstream `qemus/qemu` shorthand alias. |
| `RESOLVE_ONLY` | `N` | When set to `1`/`Y`/`true`, resolves and prints the guest OS version, ISO URL, checksum URL, and signature URL, then exits without starting QEMU. |
| `RAM_SIZE` | `4G` | Guest RAM allocation (e.g. `2G`, `4G`, `8G`). |
| `CPU_CORES` | `2` | Virtual CPU core count (or `half` / `max`). |
| `DISK_SIZE` | `64G` | Persistent virtual disk size under `/storage`. |
| `DISK_FMT` | `raw` | Managed disk format (`raw` or `qcow2`). |
| `BOOT_MODE` | *(auto / `uefi` / `windows`)* | Firmware mode (`uefi`, `secure`, `legacy`, `windows`, `windows_secure`, `windows_legacy`). |
| `KVM` | `Y` | Enable hardware KVM acceleration (`/dev/kvm`). Set `KVM=N` to fall back to software TCG emulation (slower). |
| `NETWORK` | `Y` | Guest networking mode (`Y`/`nat` via TAP+bridge, `user`/`passt` for rootless user-mode networking without `/dev/net/tun`, or `N` to disable). |
| `DHCP` | `N` | Attach guest directly to the container network via macvlan/DHCP. |
| `WEB` | `Y` | Enable embedded nginx + noVNC web viewer on `WEB_PORT`. Set `WEB=N` for headless VNC-only mode. |
| `WEB_PORT` | `8006` | Listening port for the noVNC web viewer. |
| `VNC_PORT` | `5900` | Listening TCP port for direct VNC clients. |
| `PROTECT` | `N` | Set `PROTECT=Y` to require HTTP Basic Authentication on the noVNC web viewer (uses `USERNAME` and `PASSWORD`). |
| `USERNAME` | `Docker` | Web auth username (when `PROTECT=Y`) and Windows guest account username. |
| `PASSWORD` | `admin` | Web auth password (when `PROTECT=Y`) and Windows guest account password. Always override before exposing on a network. |
| `VERIFY` | `Y` | Verify downloaded Windows ESD/catalog checksums (enabled by default; non-Windows `OS=` verification is always mandatory and fail-closed). |
| `AUDIO` | `N` | Stream guest audio to the browser (`Y`/`N`). |
| `SAMBA` | `Y` | Expose `/shared` over Samba inside Windows guests (non-Windows guests use VirtIO 9p). |
| `LANGUAGE` / `REGION` / `KEYBOARD` | `en` | Windows unattended install locale settings. |
| `ARGUMENTS` | *(empty)* | Extra arguments appended to the QEMU command line. |
| `DEBUG` | `N` | Enable verbose startup and networking diagnostics. |

### Ports, volumes, and users

| Setting | Value |
| --- | --- |
| Base image | `debian:13.8-slim` (pinned by digest, refreshed daily) |
| Ports | `8006/tcp` (noVNC web viewer), `5900/tcp` (VNC), `3389/tcp+udp` (RDP for Windows), `22/tcp` (forwarded SSH when configured) |
| Volumes | `/storage` (persistent VM disks, NVRAM, downloaded ISOs); optional `/shared` (host-guest file exchange) |
| User / UID / GID | Runs as `root` (UID 0) by default for `/dev/kvm`, `/dev/net/tun`, TAP/bridge networking, nginx, and Samba; non-root `vmuser` (UID/GID 1000) is included for non-root CLI invocations such as `fnxvm-resolve` |
| PID 1 | `tini` (`/usr/bin/tini -s /run/entry.sh`) for clean signal forwarding and graceful ACPI guest shutdown |

### Host requirements

- **Hardware virtualization (recommended):** `/dev/kvm` passed via `--device /dev/kvm` (Linux host with Intel VT-x, AMD-V, or ARMv8 KVM). Without `/dev/kvm`, pass `-e KVM=N` to use QEMU TCG emulation.
- **Networking:** `--device /dev/net/tun` and `--cap-add NET_ADMIN` for TAP/bridge NAT networking. For environments without TUN/NET_ADMIN, set `-e NETWORK=user` to use user-mode networking via `passt`.

## Healthcheck

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD ["/usr/local/bin/fnxvm-healthcheck"]
```

`/usr/local/bin/fnxvm-healthcheck` performs a real service probe:

1. Fails immediately if the container is shutting down (`/run/shm/qemu.end`).
2. In default web-viewer mode (`WEB=Y`), sends an HTTP request to `http://127.0.0.1:${WEB_PORT:-8006}/` (accepting `200` or `401` when `PROTECT=Y`) and verifies the `websocketd` status Unix socket (`/run/shm/status-ws.sock`) is active.
3. In headless mode (`WEB=N`), probes TCP port `127.0.0.1:${VNC_PORT:-5900}`.
4. Once QEMU has published `/run/shm/qemu.pid`, verifies the hypervisor process is alive.

CI starts the container on both `linux/amd64` and `linux/arm64`, waits until Docker reports `status=healthy`, checks HTTP 200 on port `8006` and an `RFB` handshake on port `5900`, and runs a negative healthcheck test verifying the probe fails when the service is down. Do not override or disable the image `HEALTHCHECK` in Compose files.

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

- **From `dockur/windows` or `dockurr/windows-arm`:** Replace the image reference with `dgcosenza/fnxvm:latest` (or pin by digest `dgcosenza/fnxvm@sha256:<digest>`). Existing `VERSION`, `RAM_SIZE`, `CPU_CORES`, `DISK_SIZE`, `LANGUAGE`, `USERNAME`, `PASSWORD`, and `/storage` volumes are drop-in compatible. You may optionally add `OS=windows` for clarity.
- **From `qemux/qemu` or `qemux/qemu-arm`:** Replace the image reference with `dgcosenza/fnxvm:latest`. Existing `BOOT`, `RAM_SIZE`, `CPU_CORES`, `DISK_SIZE`, `BOOT_MODE`, and `/storage` volumes remain compatible; or switch to `OS=debian` / `ubuntu` / `freebsd` / `haiku` / `omarchy` for automatic checksum- and GPG-verified official downloads.
- **Upgrading FNXVM:** Pull the new immutable digest published in the GitHub Release and recreate the container while preserving your `/storage` volume.

## Security

- **Zero fixable vulnerabilities of any severity:** Every build is gated by **Trivy** (`severity: UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL`, `--ignore-unfixed`, exit code 1) AND **Grype** on the Syft SPDX SBOM (`--only-fixed --fail-on negligible`) on both `linux/amd64` and `linux/arm64`.
- **Clean base and from-source helpers:** Built on pinned `debian:13.8-slim` with `apt-get upgrade` and Debian `main` packages only. Go helpers (`websocketd`, `boot-logo`) are compiled from SHA-256-verified source with the patched `golang:1.27.4-trixie` toolchain (eliminating CVEs in prebuilt upstream binaries). `udfread` is compiled natively from verified source. `python3-pip` is excluded from the final runtime image.
- **Supply-chain hardening:** Keyless Cosign OIDC signatures on both Docker Hub and GHCR, signed SPDX and CycloneDX SBOM attestations per architecture, SLSA Build L3 provenance via `actions/attest-build-provenance`, Hadolint (blocking on warning+), Gitleaks secret scanning, Dive image efficiency gate (`>= 95%`), OpenSSF Scorecard, Renovate, and Dependabot.
- **ISO provenance & fail-closed verification:** No guest OS media are stored in image layers. At runtime, Debian (`SHA256SUMS.sign`), Ubuntu (`SHA256SUMS.gpg`), and Omarchy (`.iso.sig`) are verified with offline-bundled vendor GPG public keys (`gpgv`) plus SHA-256; FreeBSD and Haiku are verified against official SHA-256 checksums; Windows ESD downloads default to `VERIFY=Y`. Any checksum or signature mismatch deletes the downloaded file and aborts startup.
- **Container privileges & network exposure:** Passing `/dev/kvm` and `/dev/net/tun` with `NET_ADMIN` grants access to host hardware virtualization and container-namespace network creation; do **not** run with `--privileged` unless strictly required, and use `cap_drop: [ALL]` with only the needed capabilities (see `docker-compose.example.yml`) or `NETWORK=user` when TUN is not needed. **Never expose port `8006` (noVNC), `5900` (VNC), or `3389` (RDP) directly to the public Internet without authentication and TLS** — bind to `127.0.0.1`, enable `PROTECT=Y` with a strong `PASSWORD`, or place behind an authenticating reverse proxy.
- **Unfixed upstream vulnerabilities:** Any upstream-unfixed CVEs (no vendor fix available) are documented in `versions.json` and the latest GitHub Release notes.

Verify a published digest with Cosign:

```bash
cosign verify \
  --certificate-identity-regexp='^https://github\.com/dgcosenza/fnxvm-docker/\.github/workflows/daily\.yml@refs/heads/main$' \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  ghcr.io/dgcosenza/fnxvm@sha256:<digest>
```

Verify SLSA Build L3 provenance:

```bash
gh attestation verify oci://ghcr.io/dgcosenza/fnxvm@sha256:<digest> --owner dgcosenza
```

Report security issues privately via [GitHub Security Advisories](https://github.com/dgcosenza/fnxvm-docker/security/advisories/new) (see [`SECURITY.md`](SECURITY.md)).

## Build locally

```bash
docker build -t fnxvm:local .
docker buildx build --platform linux/amd64,linux/arm64 -t fnxvm:multi .
./tests/smoke.sh fnxvm:local
```

## Update policy

Every day, `.github/workflows/daily.yml` runs a fully automated 7-step pipeline:

1. **Upstream check:** Queries the authenticated GitHub Releases API for `dockur/windows`, `qemus/qemu`, and helper tools, resolves current `debian:13.8-slim` and `golang:1.27.4-trixie` digests, resolves all 6 guest OS versions, and diffs against committed `versions.json`.
2. **No-cache rebuild:** Rebuilds both `linux/amd64` and `linux/arm64` natively with `--no-cache` on schedule, upgrading all Debian packages and recompiling helpers cleanly.
3. **Vulnerability gate:** Generates SPDX and CycloneDX SBOMs with Syft and enforces **0 fixable findings of any severity** in both Trivy (SARIF uploaded to GitHub Code Scanning) and Grype, plus a Dive efficiency check.
4. **Smoke & resolver tests:** Boots real QEMU in TCG mode on both architectures, waits for `HEALTHCHECK=healthy`, validates noVNC HTTP 200 and VNC RFB, runs negative and non-root tests, and verifies HTTP 200 for every supported `OS` resolver.
5. **Dual-registry signed publish:** Publishes identical multi-arch manifest digests to GHCR and Docker Hub (`latest`, `<version>`, `<version>-<YYYYMMDD>`, `sha-<short>`), signs index and per-arch digests with keyless Cosign, attaches SPDX/CycloneDX SBOM attestations, creates SLSA Build L3 provenance, and publishes a signed GitHub Release.
6. **Docs auto-update:** Commits updated `versions.json`, README `Current versions` block, and dated `CHANGELOG.md` entry, then syncs README and short description to Docker Hub.
7. **Alerting:** Opens or updates a `ci-failure` GitHub issue on any failure on `main` and automatically closes it on the next green run.

## Design decisions

- **Debian 13.8 `main` packages instead of upstream's frozen Debian Sid snapshot:** Upstream `qemus/qemu` installs QEMU/OVMF from a frozen Debian Sid snapshot and enables `non-free` for `7zip-rar`. FNXVM uses official Debian 13.8 (`trixie`) `main` packages (`qemu-system-x86`, `qemu-system-arm`, `ovmf`, `qemu-efi-aarch64`, `seabios`, `passt`, `swtpm`, `samba`, `wimtools`, `nginx`), guaranteeing continuous Debian Security Team updates and zero fixable CVEs.
- **From-source Go & C helpers:** Prebuilt upstream Go binaries (such as `boot-logo`) accumulate Go stdlib CVEs over time. Compiling `websocketd` and `boot-logo` from SHA-256-verified source with `golang:1.27.4-trixie` and `udfread` natively on Debian 13 eliminates all prebuilt binary CVEs and foreign container layer copies.
- **No `python3-pip` in the runtime image:** `qemu.qmp` is installed into an isolated directory in the builder stage and copied over, keeping `pip`, `setuptools`, and compilers out of the final image.
- **No experimental `qemu-render` / `dxvk` / `wsddn` third-party `.deb` bundles:** Standard Debian 13 QEMU provides full KVM, UEFI, Secure Boot, TPM 2.0, VirtIO, VNC/noVNC, audio, and Samba `/shared` support on both architectures without third-party unpatched packages. Optional WSD discovery (`wsddn`) and batch linting (`blinter`) degrade gracefully when absent; Samba shares remain directly reachable at `\\host.lan\Data`.
- **Neutral OS default:** Unlike `dockur/windows`, FNXVM is OS-neutral and defaults to `OS=debian` (`DESKTOP=gnome`) when neither `OS`, `VERSION`, nor `BOOT` is set, while preserving full drop-in `VERSION=` compatibility for Windows users.
- **Root runtime default with `vmuser` non-root option:** Virtual machine setup requires privileges for `/dev/kvm`, `/dev/net/tun`, bridge/TAP networking, nginx, and Samba. A dedicated non-root `vmuser` (UID/GID 1000) is included for non-root tool usage (`fnxvm-resolve`) and smoke-tested in CI.

## License

Packaging (Dockerfile, `fnxvm-resolve`, `fnxvm-healthcheck`, unified entrypoint, CI workflows, tests, and documentation) is licensed under the **MIT License**, Copyright (c) 2026 Daniel G. Cosenza from FNX Labs. See [`LICENSE`](LICENSE).

Reused upstream scripts and assets from `dockur/windows`, `dockur/windows-arm`, `qemus/qemu`, and `qemus/qemu-arm` are licensed under the **MIT License**. Other bundled open-source components retain their respective licenses; see [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) and `/usr/share/licenses/fnxvm/` inside the image. Guest operating system media downloaded at runtime are governed by their respective vendor licenses.

## Credits

Maintainer: **Daniel G. Cosenza from FNX Labs**.

Built upon the upstream work of [`dockur/windows`](https://github.com/dockur/windows) and [`qemus/qemu`](https://github.com/qemus/qemu), along with the QEMU, EDK2/OVMF, noVNC, Passt, Debian, Ubuntu, FreeBSD, Haiku, and Omarchy open-source communities.
