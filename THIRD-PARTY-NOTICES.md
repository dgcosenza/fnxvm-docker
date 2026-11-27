# Third-Party Notices

This container image packaging (Dockerfile, FNXVM entry/resolver/healthcheck scripts, CI workflows, and documentation) is licensed under the MIT License — Copyright (c) 2026 Daniel G. Cosenza from FNX Labs.

FNXVM reuses and adapts scripts and assets from the following upstream open-source projects, and installs official Debian 13 (trixie) packages. All third-party components remain under their respective licenses.

**Guest operating system media are NEVER bundled or redistributed in this image.** When started, the container downloads guest installation media directly from the respective official vendor endpoints (Microsoft, Haiku Project, FreeBSD Project, Debian Project, Canonical / Ubuntu, and Omarchy) and verifies vendor-published checksums and cryptographic signatures before booting. Guest operating systems are governed by their own vendor licenses and terms.

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
- **Debian 13 (trixie) packages** — QEMU (`GPL-2.0-or-later`), OVMF / AAVMF EDK2 (`BSD-2-Clause-Patent`), SeaBIOS (`LGPL-3.0-or-later`), Passt (`GPL-2.0-or-later` / `BSD-3-Clause`), swtpm (`BSD-3-Clause`), nginx (`BSD-2-Clause`), Samba (`GPL-3.0-or-later`), wimtools (`GPL-3.0-or-later` / `LGPL-3.0-or-later`), aria2 (`GPL-2.0-or-later`), tini (`MIT`), and supporting utilities. Full Debian package copyrights are located in `/usr/share/doc/*/copyright` inside the image.

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
