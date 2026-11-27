# Third-Party Notices

This container image packaging (Dockerfile, FNXVM entry/resolver/healthcheck scripts, CI workflows, and documentation) is licensed under the MIT License — Copyright (c) 2026 Daniel G. Cosenza from FNX Labs.

FNXVM reuses and adapts scripts and assets from the following upstream open-source projects, and installs official Debian 13 (trixie) packages. All third-party components remain under their respective licenses.

**Guest operating system media and optional Windows guest agents are NEVER bundled or redistributed in this image.** When started, the container downloads guest installation media directly from the respective official vendor endpoints (Microsoft, Haiku Project, FreeBSD Project, Daemonarchy / Jordan Hubbard, Debian Project, Canonical / Ubuntu, and Omarchy) — and optionally the official `spice-vdagent` Windows MSI from `spice-space.org` (GPL-2.0-or-later) during x64/x86 Windows unattended setup — and verifies vendor-published checksums and cryptographic signatures before booting. Guest operating systems and agents are governed by their own vendor licenses and terms (e.g., Daemonarchy original work is BSD-2-Clause and is not affiliated with Omarchy).

## Upstream Projects Adapted in Packaging

### dockur/windows & dockur/windows-arm
- Upstream: https://github.com/dockur/windows and https://github.com/dockur/windows-arm
- License: MIT License
- Components reused: Windows unattended answer files (`src/windows/*/assets/`), Windows download/preparation scripts (`src/windows/`).

### qemus/qemu & qemus/qemu-arm
- Upstream: https://github.com/qemus/qemu and https://github.com/qemus/qemu-arm
- License: MIT License
- Components reused: QEMU container runtime scripts (`src/common/`, `src/arch/`, `src/generic/`), web status page and noVNC configuration overrides (`web/`).

## Compiled and Bundled Open-Source Components

- **qemus/websocketd** (https://github.com/qemus/websocketd) — BSD-2-Clause License (compiled from source).
- **qemus/boot-logo** (https://github.com/qemus/boot-logo) — MIT License (compiled from source).
- **qemus/udfread** (https://github.com/qemus/udfread) — MIT License, statically linked against **VideoLAN libudfread** (LGPL-2.1-or-later, https://code.videolan.org/videolan/libudfread).
- **noVNC** (https://github.com/novnc/noVNC) — MPL-2.0 License.
- **qemu.qmp** (https://gitlab.com/qemu-project/python-qemu-qmp) — LGPL-2.0-or-later License.
- **VirtIO Windows Drivers** (`qemus/virtiso-whql` and `qemus/virtiso-arm`, derived from Fedora `virtio-win`) — BSD-3-Clause License.
- **Debian 13 (trixie) packages** — QEMU, `qemu-system-modules-opengl`, and `qemu-system-modules-spice` (`GPL-2.0-or-later`), Mesa `libegl-mesa0` (`MIT`), OVMF / AAVMF EDK2 (`BSD-2-Clause-Patent`), SeaBIOS (`LGPL-3.0-or-later`), Passt (`GPL-2.0-or-later` / `BSD-3-Clause`), swtpm (`BSD-3-Clause`), nginx (`BSD-2-Clause`), `apache2-utils` (`Apache-2.0`), Samba (`GPL-3.0-or-later`), wimtools (`GPL-3.0-or-later` / `LGPL-3.0-or-later`), aria2 (`GPL-2.0-or-later`), tini (`MIT`), and supporting utilities. Full Debian package copyrights are located in `/usr/share/doc/*/copyright` inside the image.

## Bundled Vendor OpenPGP Public Keys

FNXVM bundles only official vendor public signing keys (dearmored into `/etc/fnxvm/keys/*.gpg`) for offline fail-closed `gpgv` verification of downloaded guest checksum manifests and ISOs:

| Keyring | Primary Key Fingerprint | User ID | Official Source |
| --- | --- | --- | --- |
| `keys/debian-cd.asc` | `1046 0DAD 7616 5AD8 1FBC 0CE9 9880 21A9 64E6 EA7D` | `Debian CD signing key <debian-cd@lists.debian.org>` | `hkps://keyring.debian.org` / https://www.debian.org/CD/verify |
| `keys/debian-cd.asc` | `DF9B 9C49 EAA9 2984 3258 9D76 DA87 E80D 6294 BE9B` | `Debian CD signing key <debian-cd@lists.debian.org>` | `hkps://keyring.debian.org` / https://www.debian.org/CD/verify |
| `keys/debian-cd.asc` | `F41D 3034 2F35 4669 5F65 C669 4246 8F40 09EA 8AC3` | `Debian Testing CDs Automatic Signing Key <debian-cd@lists.debian.org>` | `hkps://keyring.debian.org` / https://www.debian.org/CD/verify |
| `keys/ubuntu-cd.asc` | `8439 38DF 228D 22F7 B374 2BC0 D94A A3F0 EFE2 1092` | `Ubuntu CD Image Automatic Signing Key (2012) <cdimage@ubuntu.com>` | `hkps://keyserver.ubuntu.com` / https://ubuntu.com/tutorials/how-to-verify-ubuntu |
| `keys/omarchy.asc` | `40DF B630 FF42 BCFF B047 046C F013 4EE6 80CA C571` | `Omarchy <pkgs@omarchy.org>` | https://keys.openpgp.org (`pkgs@omarchy.org`) / https://github.com/omacom/omarchy (`manual/48-security.md`) |

## Upstream MIT License Text (dockur/windows & qemus/qemu)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
