# syntax=docker/dockerfile:1.7
# FNXVM — Multi-OS VM-in-a-container via QEMU/KVM with noVNC web viewer, VNC, and RDP.
# Derived from qemus/qemu (MIT) and dockur/windows (MIT), rebased onto Debian 13.8 slim.
# Never redistributes OS media; downloads and verifies official vendor ISOs at runtime.
# Maintainer: Daniel G. Cosenza from FNX Labs

ARG GO_BASE=golang:1.27.4-trixie@sha256:430985542100b871e108ccc00e8dcc5eef08ca14ee5825e98ebf563d8ffec4ee
ARG DEBIAN_BASE=debian:13.8-slim@sha256:8aa5a7bf5a1955bddbe7d74fcdd0b91ab30e74362a8b73af672b0481b35b44a0
ARG FNXVM_VERSION=6.06.4
ARG FNXVM_RELEASE=4
ARG WINDOWS_VERSION=6.06
ARG QEMU_VERSION=7.50
ARG WEBSOCKETD_VERSION=0.4.2
ARG WEBSOCKETD_SHA256=9980efa9f4f74438ff230875e04f7ffe253af703908fb538b5e5b1a270791ccf
ARG BOOT_LOGO_VERSION=1.3.0
ARG BOOT_LOGO_SHA256=52b1ddf65481485c3326af762971ddd35c3b5afbeab3c9fdcf70a8562ee98f7a
ARG UDFREAD_VERSION=1.2.0
ARG UDFREAD_SHA256=fdb584bc2ac968f6d87de1ec0406e40b1c500b0337e722bd3f5c29078d99fa31
ARG LIBUDFREAD_VERSION=1.2.0
ARG NOVNC_VERSION=1.7.0
ARG NOVNC_SHA256=b1003a11b6e6e8d8f7f5e5586daae7f8ca651d8aee0aa155ff9ac841c48f52c6
ARG QMP_VERSION=0.0.6
ARG VIRTIO_AMD64_VERSION=1.9.62
ARG VIRTIO_AMD64_RELEASE=v1.9.62-0
ARG VIRTIO_AMD64_SHA256=442f145ba1b96097e88ee2028288d8846ae8eddeeb07f8d548540af01ac852ec
ARG VIRTIO_ARM64_VERSION=0.1.302
ARG VIRTIO_ARM64_RELEASE=v0.1.302-1
ARG VIRTIO_ARM64_SHA256=2f8b5389336f43f389191d8ddc7e1d0aad9bf09ec50b1cc7189a86f031a6eda5
ARG IMAGE_CREATED=1970-01-01T00:00:00Z
ARG IMAGE_REVISION=dev
ARG IMAGE_SOURCE=https://github.com/dgcosenza/fnxvm-docker

# ==============================================================================
# Stage 1: Build Go helpers (websocketd, boot-logo) with the patched Go toolchain
# ==============================================================================
FROM ${GO_BASE} AS go-builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
ARG WEBSOCKETD_VERSION
ARG WEBSOCKETD_SHA256
ARG BOOT_LOGO_VERSION
ARG BOOT_LOGO_SHA256

WORKDIR /src

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    set -eu \
    && mkdir -p /out \
    && curl -fsSL "https://github.com/qemus/websocketd/archive/refs/tags/v${WEBSOCKETD_VERSION}.tar.gz" -o /tmp/websocketd.tar.gz \
    && echo "${WEBSOCKETD_SHA256}  /tmp/websocketd.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/websocketd.tar.gz -C /src \
    && CGO_ENABLED=0 GOOS=linux GOARCH="${TARGETARCH}" \
       go -C "/src/websocketd-${WEBSOCKETD_VERSION}" build \
         -trimpath -ldflags="-s -w -X main.version=${WEBSOCKETD_VERSION}" -o /out/websocketd . \
    && curl -fsSL "https://github.com/qemus/boot-logo/archive/refs/tags/v${BOOT_LOGO_VERSION}.tar.gz" -o /tmp/boot-logo.tar.gz \
    && echo "${BOOT_LOGO_SHA256}  /tmp/boot-logo.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/boot-logo.tar.gz -C /src \
    && go -C "/src/boot-logo-${BOOT_LOGO_VERSION}/src" get \
         github.com/ulikunitz/xz@v0.5.15 \
         golang.org/x/image@v0.45.0 \
         golang.org/x/text@v0.41.0 \
    && go -C "/src/boot-logo-${BOOT_LOGO_VERSION}/src" mod tidy \
    && CGO_ENABLED=0 GOOS=linux GOARCH="${TARGETARCH}" \
       go -C "/src/boot-logo-${BOOT_LOGO_VERSION}/src" build \
         -trimpath -ldflags="-s -w -X main.Version=${BOOT_LOGO_VERSION}" -o /out/boot-logo . \
    && rm -rf /tmp/websocketd.tar.gz /tmp/boot-logo.tar.gz

# ==============================================================================
# Stage 2: Build C helper (udfread), prepare verified noVNC, qemu.qmp, GPG keys,
#          and VirtIO Windows driver archive (keeps compilers and pip out of runtime)
# ==============================================================================
FROM ${DEBIAN_BASE} AS asset-builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive
ARG FNXVM_VERSION
ARG UDFREAD_VERSION
ARG UDFREAD_SHA256
ARG LIBUDFREAD_VERSION
ARG NOVNC_VERSION
ARG NOVNC_SHA256
ARG QMP_VERSION
ARG VIRTIO_AMD64_VERSION
ARG VIRTIO_AMD64_RELEASE
ARG VIRTIO_AMD64_SHA256
ARG VIRTIO_ARM64_VERSION
ARG VIRTIO_ARM64_RELEASE
ARG VIRTIO_ARM64_SHA256

# hadolint ignore=DL3008
RUN apt-get -o Acquire::Retries=5 update \
    && apt-get -o Acquire::Retries=5 -y upgrade \
    && apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
       ca-certificates curl gcc git gnupg libc6-dev make meson ninja-build pkg-config python3 python3-pip tar xz-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY web/vnc /build/novnc-override
COPY web/img/favicon.svg /build/favicon.svg
COPY keys /build/keys

RUN set -eu \
    && mkdir -p /out/bin /out/novnc /out/python /out/keys \
    # 1. Build udfread natively from verified source with pinned libudfread
    && curl -fsSL "https://github.com/qemus/udfread/archive/refs/tags/v${UDFREAD_VERSION}.tar.gz" -o /tmp/udfread.tar.gz \
    && echo "${UDFREAD_SHA256}  /tmp/udfread.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/udfread.tar.gz -C /build \
    && make -C "/build/udfread-${UDFREAD_VERSION}" \
         VERSION="${UDFREAD_VERSION}" \
         LIBUDFREAD_REF="${LIBUDFREAD_VERSION}" \
    && install -m 0755 "/build/udfread-${UDFREAD_VERSION}/udfread" /out/bin/udfread \
    # 2. Prepare verified noVNC web client with upstream qemus/qemu overrides
    && curl -fsSL "https://github.com/novnc/noVNC/archive/refs/tags/v${NOVNC_VERSION}.tar.gz" -o /tmp/novnc.tar.gz \
    && echo "${NOVNC_SHA256}  /tmp/novnc.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/novnc.tar.gz -C /tmp \
    && mv "/tmp/noVNC-${NOVNC_VERSION}/app" \
          "/tmp/noVNC-${NOVNC_VERSION}/core" \
          "/tmp/noVNC-${NOVNC_VERSION}/vendor" \
          "/tmp/noVNC-${NOVNC_VERSION}"/*.html /out/novnc/ \
    && cp /build/novnc-override/defaults.json /build/novnc-override/mandatory.json /build/novnc-override/vnc.html /out/novnc/ \
    && for d in /build/novnc-override/*/; do [ -d "$d" ] && cp -a "$d" /out/novnc/; done \
    && cp /build/favicon.svg /out/novnc/app/images/favicon.svg \
    && printf '%s\n' "${FNXVM_VERSION}" > /out/novnc/version \
    # 3. Install pure-Python qemu.qmp into isolated target (no pip in runtime image)
    && python3 -m pip install --no-cache-dir --break-system-packages --root-user-action=ignore \
         --target /out/python "qemu.qmp==${QMP_VERSION}" \
    # 4. Dearmor vendor GPG public keys for offline gpgv verification and assert
    #    every keyring imports cleanly with at least one public key and user ID
    && for asc in /build/keys/*.asc; do \
         base="$(basename "$asc" .asc)"; \
         gpg --batch --dearmor -o "/out/keys/${base}.gpg" "$asc"; \
         gnupg_tmp="$(mktemp -d)"; \
         chmod 700 "$gnupg_tmp"; \
         GNUPGHOME="$gnupg_tmp" gpg --batch --import "/out/keys/${base}.gpg"; \
         key_info="$(GNUPGHOME="$gnupg_tmp" gpg --batch --list-keys --with-colons --with-fingerprint)"; \
         rm -rf "$gnupg_tmp"; \
         printf '%s\n' "$key_info" | grep -q '^pub:' \
           && printf '%s\n' "$key_info" | grep -q '^uid:' \
           && printf '%s\n' "$key_info" | grep -q '^fpr:' \
           || { echo "ERROR: keyring ${base}.gpg is missing a valid public key or user ID!" >&2; exit 1; }; \
       done \
    # 5. Download & verify arch-specific VirtIO Windows drivers
    && if [ "${TARGETARCH}" = "amd64" ]; then \
         curl -fsSL "https://github.com/qemus/virtiso-whql/releases/download/${VIRTIO_AMD64_RELEASE}/virtio-win-${VIRTIO_AMD64_VERSION}.tar.xz" -o /out/drivers.txz; \
         echo "${VIRTIO_AMD64_SHA256}  /out/drivers.txz" | sha256sum -c -; \
       else \
         curl -fsSL "https://github.com/qemus/virtiso-arm/releases/download/${VIRTIO_ARM64_RELEASE}/virtio-win-${VIRTIO_ARM64_VERSION}.tar.xz" -o /out/drivers.txz; \
         echo "${VIRTIO_ARM64_SHA256}  /out/drivers.txz" | sha256sum -c -; \
       fi \
    && chmod 0644 /out/drivers.txz \
    && rm -rf /tmp/* /var/tmp/*

# ==============================================================================
# Stage 3: Final Debian 13.8 slim runtime (multi-arch: linux/amd64 + linux/arm64)
# ==============================================================================
FROM ${DEBIAN_BASE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive
ARG DEBCONF_NOWARNINGS=yes
ARG DEBCONF_NONINTERACTIVE_SEEN=true
ARG FNXVM_VERSION
ARG WINDOWS_VERSION
ARG QEMU_VERSION
ARG IMAGE_CREATED
ARG IMAGE_REVISION
ARG IMAGE_SOURCE

LABEL maintainer="Daniel G. Cosenza from FNX Labs" \
      org.opencontainers.image.title="FNXVM multi-OS VM container" \
      org.opencontainers.image.description="Multi-OS QEMU/KVM virtual machine container with noVNC web viewer, VNC, RDP, and dynamic verified official OS downloads, maintained by Daniel G. Cosenza from FNX Labs." \
      org.opencontainers.image.vendor="Daniel G. Cosenza from FNX Labs" \
      org.opencontainers.image.authors="Daniel G. Cosenza from FNX Labs" \
      org.opencontainers.image.version="${FNXVM_VERSION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      org.opencontainers.image.url="https://hub.docker.com/r/dgcosenza/fnxvm" \
      org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.documentation="${IMAGE_SOURCE}#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.base.name="debian:13.8-slim" \
      io.github.dgcosenza.fnxvm.version="${FNXVM_VERSION}" \
      io.github.dgcosenza.fnxvm.upstream-windows="${WINDOWS_VERSION}" \
      io.github.dgcosenza.fnxvm.upstream-qemu="${QEMU_VERSION}"

# hadolint ignore=DL3008
RUN set -eu \
    && apt-get -o Acquire::Retries=5 update \
    && apt-get -o Acquire::Retries=5 -y upgrade \
    && if [ "${TARGETARCH}" = "amd64" ]; then \
         set -- qemu-system-x86 ovmf seabios; \
       elif [ "${TARGETARCH}" = "arm64" ]; then \
         set -- qemu-system-arm qemu-efi-aarch64; \
       else \
         echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1; \
       fi \
    && apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
       "$@" \
       7zip \
       apache2-utils \
       aria2 \
       bc \
       ca-certificates \
       cabextract \
       curl \
       diffutils \
       dnsmasq \
       dos2unix \
       e2fsprogs \
       ethtool \
       fdisk \
       gcab \
       genisoimage \
       gpgv \
       icu-devtools \
       inotify-tools \
       ipcalc \
       iproute2 \
       iptables \
       iputils-ping \
       jq \
       libarchive-tools \
       libegl-mesa0 \
       libxml2-utils \
       mtools \
       net-tools \
       netcat-openbsd \
       nginx \
       passt \
       pciutils \
       procps \
       python3 \
       qemu-system-modules-opengl \
       qemu-system-modules-spice \
       qemu-utils \
       samba \
       swtpm \
       tini \
       unzip \
       util-linux \
       wget \
       wimtools \
       xmlstarlet \
       xorriso \
       xxd \
       xz-utils \
    && if [ "${TARGETARCH}" = "amd64" ]; then \
         test -s /usr/share/OVMF/OVMF_CODE_4M.fd \
         && test -s /usr/share/OVMF/OVMF_VARS_4M.fd; \
       else \
         test -s /usr/share/AAVMF/AAVMF_CODE.no-secboot.fd \
         && test -s /usr/share/AAVMF/AAVMF_VARS.fd; \
       fi \
    && groupadd --gid 1000 vmuser \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash vmuser \
    && printf '%s\n' "${FNXVM_VERSION}" > /etc/version \
    && mkdir -p /storage /var/www /etc/fnxvm/keys /usr/share/licenses/fnxvm \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --from=go-builder --chmod=755 /out/websocketd /usr/local/bin/websocketd
COPY --from=go-builder --chmod=755 /out/boot-logo /run/boot-logo
COPY --from=asset-builder --chmod=755 /out/bin/udfread /usr/bin/udfread
COPY --from=asset-builder /out/novnc /usr/share/novnc
COPY --from=asset-builder /out/python /usr/local/lib/fnxvm-python
COPY --from=asset-builder /out/keys /etc/fnxvm/keys
COPY --from=asset-builder --chmod=644 /out/drivers.txz /var/drivers.txz

COPY --chmod=755 src/common/ /run/
COPY --chmod=755 src/arch/${TARGETARCH}/ /run/
COPY --chmod=755 src/generic/ /run/generic/
COPY --chmod=755 src/windows/common/ /run/windows/
COPY --chmod=755 src/windows/${TARGETARCH}/define.sh /run/windows/define.sh
COPY --chmod=755 src/windows/${TARGETARCH}/assets/ /run/assets/
COPY --chmod=755 src/entry.sh /run/entry.sh
COPY --chmod=755 src/fnxvm-resolve /usr/local/bin/fnxvm-resolve
COPY --chmod=755 src/fnxvm-healthcheck /usr/local/bin/fnxvm-healthcheck

COPY --chmod=755 web/index.html /var/www/index.html
COPY --chmod=755 web/css/ /var/www/css/
COPY --chmod=755 web/img/ /var/www/img/
COPY --chmod=755 web/js/ /var/www/js/
COPY --chmod=644 web/conf/nginx.conf /etc/nginx/default.conf

COPY --chmod=644 LICENSE THIRD-PARTY-NOTICES.md /usr/share/licenses/fnxvm/

ENV PYTHONPATH="/usr/local/lib/fnxvm-python" \
    OS="" \
    DESKTOP="gnome" \
    VERSION="" \
    BOOT="" \
    GPU="auto" \
    CLIPBOARD="Y" \
    WINDOWS_VDAGENT="Y" \
    RDP="N" \
    RAM_SIZE="4G" \
    CPU_CORES="2" \
    DISK_SIZE="64G" \
    WEB_PORT="8006" \
    WEB_TLS="N" \
    WEB_AUTH="Y" \
    WEB_USER="fnxvm" \
    VNC_PORT="5900"

VOLUME /storage
EXPOSE 22 3389 5900 8006

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD ["/usr/local/bin/fnxvm-healthcheck"]

ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]
