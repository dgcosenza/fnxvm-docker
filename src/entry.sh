#!/usr/bin/env bash
# FNXVM unified multi-OS VM container entrypoint.
# Derived from qemus/qemu (MIT) and dockur/windows (MIT).
# Maintainer: Daniel G. Cosenza from FNX Labs
set -Eeuo pipefail

VALID_OS_LIST="windows, haiku, freebsd, daemonarchy, debian, ubuntu, omarchy"
VALID_GPU_LIST="auto, virtio, virgl, qxl, std"

fnxvm_enabled() {
  case "${1,,}" in
    y|yes|true|1|on|enable|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

fnxvm_strip() {
  local v="${1:-}"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  v="${v%\"}"
  v="${v#\"}"
  v="${v%\'}"
  v="${v#\'}"
  printf '%s' "$v"
}

OS="$(fnxvm_strip "${OS:-}")"
DESKTOP="$(fnxvm_strip "${DESKTOP:-gnome}")"
VERSION="$(fnxvm_strip "${VERSION:-}")"
BOOT="$(fnxvm_strip "${BOOT:-}")"
GPU="$(fnxvm_strip "${GPU:-auto}")"
RESOLVE_ONLY="$(fnxvm_strip "${RESOLVE_ONLY:-}")"

# Auto-detect container architecture unless explicitly overridden.
HOST_ARCH="$(dpkg --print-architecture)"
case "$HOST_ARCH" in
  amd64)
    : "${PLATFORM:="x64"}"
    QEMU_BIN="qemu-system-x86_64"
    ;;
  arm64)
    : "${PLATFORM:="arm64"}"
    : "${MACHINE:="virt"}"
    QEMU_BIN="qemu-system-aarch64"
    ;;
  *)
    echo "ERROR: Unsupported container architecture: ${HOST_ARCH}" >&2
    exit 2
    ;;
esac

# Validate OS early (fail fast on unknown values).
OS_LOWER="${OS,,}"
if [ -n "$OS_LOWER" ]; then
  case "$OS_LOWER" in
    windows|haiku|freebsd|daemonarchy|debian|ubuntu|omarchy) ;;
    *)
      echo "ERROR: Unknown OS '${OS}'. Valid OS values: ${VALID_OS_LIST}." >&2
      echo "       For a custom ISO or disk image URL, leave OS unset and set BOOT=https://..." >&2
      exit 2
      ;;
  esac
fi

if [ "$OS_LOWER" = "debian" ]; then
  case "${DESKTOP,,}" in
    gnome|kde) DESKTOP="${DESKTOP,,}" ;;
    *)
      echo "ERROR: Invalid DESKTOP '${DESKTOP}' for OS=debian. Valid values: gnome, kde." >&2
      exit 2
      ;;
  esac
fi

# Validate GPU early (fail fast on unknown values; accept upstream Y/N aliases too).
case "${GPU,,}" in
  ""|auto|virtio|virtio-gpu|virtio-vga|virgl|gl|qxl|std|vga|y|yes|true|1|on|n|no|none|false|0|off) ;;
  *)
    echo "ERROR: Invalid GPU '${GPU}'. Valid GPU values: ${VALID_GPU_LIST}." >&2
    exit 2
    ;;
esac

# Dry-run resolve mode: print resolved version, ISO URL, and checksum URL without starting QEMU.
if fnxvm_enabled "$RESOLVE_ONLY"; then
  export OS="$OS_LOWER"
  export DESKTOP
  export VERSION
  export BOOT
  exec /usr/local/bin/fnxvm-resolve
fi

# Select guest mode:
# - Explicit OS=windows, or upstream dockur/windows compatibility (VERSION set with OS & BOOT unset) -> Windows mode
# - Explicit OS in {haiku, freebsd, daemonarchy, debian, ubuntu, omarchy}, or custom BOOT, or neutral default (debian) -> Generic mode
MODE="generic"
if [ "$OS_LOWER" = "windows" ]; then
  MODE="windows"
elif [ -z "$OS_LOWER" ] && [ -z "$BOOT" ] && [ -n "$VERSION" ]; then
  MODE="windows"
  OS_LOWER="windows"
fi

# Normalize convenient Windows aliases before passing to upstream dockur/windows define.sh.
if [ "$MODE" = "windows" ]; then
  case "${VERSION,,}" in
    "ltsc") VERSION="11l" ;;
    "iot-ltsc") VERSION="11i" ;;
  esac
  export VERSION
  # Enable checksum verification by default so mismatches fail closed.
  : "${VERIFY:="Y"}"
  export VERIFY
  : "${APP:="FNXVM Windows"}"
  : "${BOOT_MODE:="windows"}"
else
  # If neither OS nor BOOT nor local bind-mounted /boot.* exists, default to Debian Desktop.
  if [ -z "$OS_LOWER" ] && [ -z "$BOOT" ]; then
    OS_LOWER="debian"
  fi
  export FNXVM_OS="$OS_LOWER"
  export FNXVM_DESKTOP="$DESKTOP"
  : "${APP:="FNXVM"}"
  if [ "$HOST_ARCH" = "arm64" ]; then
    : "${BOOT_MODE:="uefi"}"
  fi
fi

: "${SUPPORT:="https://github.com/dgcosenza/fnxvm-docker"}"
export APP PLATFORM SUPPORT BOOT_MODE GPU QEMU_BIN FNXVM_MODE="$MODE"

applyVncPassword() {
  local qemu_pid="${1:-0}"
  local pw_file="${VNC_PASSWORD_TMP:-}"
  local qmp_sock="${FNXVM_QMP_SOCKET:-}"
  local protos=""

  [ -n "$pw_file" ] && [ -f "$pw_file" ] || return 0

  if [ "${FNXVM_VNC_ACTIVE:-N}" = "Y" ]; then
    protos="vnc"
  fi
  if [ "${FNXVM_SPICE_ACTIVE:-N}" = "Y" ]; then
    protos="${protos:+${protos},}spice"
  fi

  if [ -z "$protos" ] || [ -z "$qmp_sock" ]; then
    rm -f -- "$pw_file"
    return 0
  fi

  (
    if python3 /run/set-vnc-password.py \
        --qmp-sock "$qmp_sock" \
        --password-file "$pw_file" \
        --protocols "$protos" \
        --qemu-pid "$qemu_pid"; then
      info "VNC authentication configured via QMP (protocols: ${protos})."
    else
      error "Failed to configure QEMU password via QMP (connections remain rejected)."
    fi
  ) &
}

cd /run

# Common initialization
. /run/start.sh      # Startup hook
. /run/utils.sh      # Load functions
. /run/init.sh       # Initialize system
. /run/memory.sh     # Check memory
. /run/server.sh     # Start webserver (nginx + websocketd) and prepare auth
. /run/download.sh   # Load download helpers

if [ "$MODE" = "windows" ]; then
  . /run/windows/define.sh    # Define Windows versions
  . /run/windows/mido.sh      # Resolve/download Windows from Microsoft
  . /run/windows/answer.sh    # Modern unattended setup
  if [ "$HOST_ARCH" = "amd64" ]; then
    . /run/windows/batch.sh   # Win9x unattended setup
    . /run/windows/sif.sh     # NT5 unattended setup
  fi
  . /run/windows/legacy.sh    # Legacy installs
  . /run/windows/image.sh     # Detect image files
  . /run/windows/install.sh   # Run Windows preparation
  . /run/disk.sh              # Initialize disks
  . /run/display.sh           # Initialize graphics
  . /run/audio.sh             # Initialize audio
  . /run/network.sh           # Initialize network
  . /run/windows/samba.sh     # Configure samba shared folder
  . /run/boot.sh              # Configure boot firmware
  . /run/proc.sh              # Initialize processor
  . /run/windows/power.sh     # Configure shutdown & Windows boot helper
  . /run/balloon.sh           # Initialize ballooning
  . /run/config.sh            # Configure QEMU arguments
  . /run/finish.sh            # Finish initialization

  trap - ERR

  cmd=("$QEMU_BIN")
  version=$("${cmd[@]}" --version | awk 'NR==1 { print $4 }')
  info "Booting ${APP}${BOOT_DESC} using QEMU v$version..." && echo

  # shellcheck disable=SC2153
  pipe="$QEMU_DIR/qemu.pipe"
  rm -f "$pipe" && mkfifo "$pipe"

  tee "$QEMU_PTY" <"$pipe" |
  sed -u \
    -e 's/\x1B\[[=0-9;]*[a-z]//gi' \
    -e 's/\x1B\x63//g' \
    -e 's/\x1B\[[=?]7l//g' \
    -e '/^$/d' \
    -e 's/\x44\x53\x73//g' \
    -e 's/failed to load Boot/skipped Boot/g' \
    -e 's/0): Not Found/0)/g' &

  output=$!

  if [ -n "${CPU_PIN:-}" ]; then
    cmd=(taskset -c "$CPU_PIN" "${cmd[@]}")
  fi

  if ! enabled "$SHUTDOWN"; then
    applyVncPassword 0
    # shellcheck disable=SC2086
    exec "${cmd[@]}" ${ARGS:+ $ARGS} >"$pipe" 2>&1
  fi

  if ! interactive; then
    # shellcheck disable=SC2086
    "${cmd[@]}" ${ARGS:+ $ARGS} >"$pipe" 2>&1 &
    pid=$!
    applyVncPassword "$pid"
  else
    startConsole "$pipe"
    # shellcheck disable=SC2086
    startQemu "${cmd[@]}" ${ARGS:+ $ARGS} >"$pipe" 2>&1
    pid=$!
    applyVncPassword 0
  fi

  waitForBoot "$pid" 30 &

  rc=0
  wait "$pid" || rc=$?
  interactive && stopConsole
  wait "$output" || :

  [ -f "$QEMU_END" ] && exit "$rc"

  sleep 1 & wait $!
  finish "$rc"
else
  . /run/generic/define.sh    # Upstream QEMU aliases
  . /run/generic/install.sh   # FNXVM dynamic OS resolver + verified download + upstream install
  . /run/disk.sh              # Initialize disks
  . /run/display.sh           # Initialize graphics
  . /run/audio.sh             # Initialize audio
  . /run/network.sh           # Initialize network
  . /run/boot.sh              # Configure boot firmware
  . /run/proc.sh              # Initialize processor
  . /run/generic/power.sh     # Configure shutdown
  . /run/balloon.sh           # Initialize ballooning
  . /run/config.sh            # Configure QEMU arguments
  . /run/finish.sh            # Finish initialization

  trap - ERR

  cmd=("$QEMU_BIN")
  version=$("${cmd[@]}" --version | awk 'NR==1 { print $4 }')
  info "Booting ${APP}${BOOT_DESC} using QEMU v$version..." && echo

  if [ -n "${CPU_PIN:-}" ]; then
    cmd=(taskset -c "$CPU_PIN" "${cmd[@]}")
  fi

  if ! enabled "$SHUTDOWN"; then
    applyVncPassword 0
    # shellcheck disable=SC2086
    exec "${cmd[@]}" ${ARGS:+ $ARGS}
  fi

  if ! interactive; then
    # shellcheck disable=SC2086
    "${cmd[@]}" ${ARGS:+ $ARGS} &
    pid=$!
    applyVncPassword "$pid"
  else
    startConsole
    # shellcheck disable=SC2086
    startQemu "${cmd[@]}" ${ARGS:+ $ARGS}
    pid=$!
    applyVncPassword 0
  fi

  rc=0

  wait "$pid" || rc=$?
  [ -f "$QEMU_END" ] && exit "$rc"

  sleep 1 & wait $!
  finish "$rc"
fi
