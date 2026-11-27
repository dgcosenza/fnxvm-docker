#!/usr/bin/env bash
set -Eeuo pipefail

# FNXVM arm64 display and video acceleration configuration.
# Supports GPU=auto|virtio|virgl|qxl|std (plus upstream GPU=Y|N and VGA= overrides),
# VNC authentication (password=on), and optional SPICE transport (SPICE=Y).

: "${GPU:="auto"}"            # GPU mode: auto | virtio | virgl | qxl | std | Y | N
: "${VGA:=""}"                # Optional explicit VGA adapter override
: "${DISPLAY:="web"}"         # Display type: web | vnc | ramfb | disabled | none
: "${LOSSY:="N"}"             # Lossy VNC compression
: "${VNC_PORT:="5900"}"       # VNC port
: "${RENDERNODE:=""}"         # Optional DRM render node (e.g. /dev/dri/renderD128)
: "${SPICE:="N"}"             # Optional SPICE server (authenticated via QMP)
: "${SPICE_PORT:="5901"}"     # SPICE TCP port when SPICE=Y

# Sanitize variables
GPU=$(strip "$GPU")
VGA=$(strip "$VGA")
LOSSY=$(strip "$LOSSY")
DISPLAY=$(strip "$DISPLAY")
VNC_PORT=$(strip "$VNC_PORT")
RENDERNODE=$(strip "$RENDERNODE")
SPICE=$(strip "$SPICE")
SPICE_PORT=$(strip "$SPICE_PORT")
WSS_SOCKET="${WSS_SOCKET:-$QEMU_DIR/vnc-ws.sock}"
QEMU_BIN="${QEMU_BIN:-qemu-system-aarch64}"

USER_VGA="$VGA"
FNXVM_VNC_ACTIVE="N"
FNXVM_SPICE_ACTIVE="N"

qemuHasDevice() {
  "$QEMU_BIN" -device help 2>/dev/null | grep -Fq "name \"$1\""
}

qemuHasDisplay() {
  "$QEMU_BIN" -display help 2>/dev/null | grep -qx "$1"
}

# Normalize GPU mode
case "${GPU,,}" in
  "" | "auto" )                     GPU_MODE="auto" ;;
  "virtio" | "virtio-gpu" | "virtio-vga" ) GPU_MODE="virtio" ;;
  "virgl" | "gl" | "y" | "yes" | "true" | "1" | "on" ) GPU_MODE="virgl" ;;
  "qxl" )                           GPU_MODE="qxl" ;;
  "std" | "vga" )                   GPU_MODE="std" ;;
  "n" | "no" | "none" | "false" | "0" | "off" ) GPU_MODE="off" ;;
  * )
    error "Invalid GPU value '${GPU}'. Valid values: auto, virtio, virgl, qxl, std."
    exit 2 ;;
esac

SAFE_VGA="${USER_VGA:-ramfb}"

gpuNodeUsable() {

  local node="$1"
  local render_name="${node##*/}"
  [[ "$render_name" =~ ^renderD[0-9]{3}$ ]] || return 1

  local render_number="${render_name#renderD}"
  (( 10#$render_number >= 128 )) || return 1
  [ -c "$node" ] || return 1

  local gpu_fd
  if ! { exec {gpu_fd}<>"$node"; } 2>/dev/null; then
    return 1
  fi
  { exec {gpu_fd}>&-; } 2>/dev/null || true

  return 0
}

detectRenderNode() {

  VIRGL_REASON=""
  local found_any="N"

  if ! qemuHasDisplay "egl-headless"; then
    VIRGL_REASON="QEMU egl-headless OpenGL module is not available"
    return 1
  fi

  if ! qemuHasDevice "virtio-gpu-gl-pci"; then
    VIRGL_REASON="QEMU virtio-gpu-gl-pci device module is not available"
    return 1
  fi

  if [ -n "$RENDERNODE" ]; then
    if ! gpuNodeUsable "$RENDERNODE"; then
      VIRGL_REASON="DRM render node '${RENDERNODE}' is missing or inaccessible (check --device /dev/dri and render group GID)"
      return 1
    fi
    return 0
  fi

  if [ ! -d /dev/dri ]; then
    VIRGL_REASON="'/dev/dri' is not present in the container (pass --device /dev/dri)"
    return 1
  fi

  local node
  for node in /dev/dri/renderD*; do
    [ -e "$node" ] || continue
    found_any="Y"
    if gpuNodeUsable "$node"; then
      RENDERNODE="$node"
      return 0
    fi
  done

  if [ "$found_any" != "Y" ]; then
    VIRGL_REASON="'/dev/dri' contains no renderD* nodes"
  else
    VIRGL_REASON="no accessible /dev/dri/renderD* node found (check render group permissions)"
  fi

  return 1
}

USE_VIRGL="N"

case "$GPU_MODE" in
  "off" )
    VGA="$SAFE_VGA" ;;
  "std" )
    # ARM64 virt machine has no legacy VGA I/O ports; ramfb is the universal UEFI framebuffer.
    VGA="ramfb" ;;
  "virtio" )
    VGA="virtio" ;;
  "qxl" )
    if qemuHasDevice "qxl-vga"; then
      VGA="qxl-vga"
    else
      warn "GPU=qxl is not available on arm64 QEMU; falling back to virtio-gpu-pci."
      VGA="virtio"
    fi ;;
  "virgl" )
    if detectRenderNode; then
      USE_VIRGL="Y"
      VGA="virtio-gpu-gl-pci"
    else
      warn "GPU=virgl requested, but ${VIRGL_REASON}; falling back to software rendering (virtio-gpu-pci)."
      VGA="virtio"
    fi ;;
  "auto" )
    if [ -z "$USER_VGA" ] && \
       [ "${FNXVM_MODE:-generic}" != "windows" ] && \
       [[ "${BOOT_MODE,,}" != "windows"* ]] && \
       [[ "${FNXVM_OS:-}" != "freebsd" ]] && \
       [[ "${FNXVM_OS:-}" != "daemonarchy" ]] && \
       detectRenderNode; then
      USE_VIRGL="Y"
      VGA="virtio-gpu-gl-pci"
    else
      VGA="$SAFE_VGA"
    fi ;;
esac

VGA_DEVICE="${VGA%%,*}"
VGA_OPTIONS="${VGA#"$VGA_DEVICE"}"

# Resolve friendly VirtIO aliases to the PCI device and place it
# on the machine-specific bus selected by the shared QEMU helpers.
case "${VGA_DEVICE,,}" in
  "virtio-gpu-gl-pci" )
    VGA_DEVICE="virtio-gpu-gl-pci"
    VGA_OPTIONS+=",bus=$(getPciBus)"
    VGA_ARG="-device" ;;
  "virtio" | "virtio-"* | "viogpu" )
    VGA_DEVICE="virtio-gpu-pci"
    VGA_OPTIONS+=",bus=$(getPciBus)"
    VGA_ARG="-device" ;;
  "qxl" | "qxl-vga" )
    VGA_DEVICE="qxl-vga"
    VGA_ARG="-device" ;;
  "ramfb" | "std" | "vga" )
    VGA_DEVICE="ramfb"
    VGA_ARG="-device" ;;
  * )
    VGA_ARG="-vga" ;;
esac

VGA="${VGA_DEVICE}${VGA_OPTIONS}"
VGA_ARG+=" ${VGA}"

# QEMU accepts a VNC display number rather than a TCP port,
# so translate the configured port back to its :N display index.
port=$(( VNC_PORT - 5900 ))

LOSSY_OPT=""
enabled "$LOSSY" && LOSSY_OPT=",lossy=on"

# Preserve the historic :0 setting as an alias for the managed web display.
[[ "$DISPLAY" == ":0" ]] && DISPLAY="web"

SPICE_OPTS=""
if enabled "$SPICE"; then
  if compgen -G '/usr/lib/*/qemu/ui-spice-core.so' >/dev/null 2>&1 || \
     "$QEMU_BIN" -spice help >/dev/null 2>&1; then
    SPICE_GL_OPT=""
    if [ "$USE_VIRGL" = "Y" ]; then
      SPICE_GL_OPT=",gl=on,rendernode=${RENDERNODE}"
    fi
    SPICE_OPTS=" -spice port=${SPICE_PORT},addr=0.0.0.0,agent-mouse=on${SPICE_GL_OPT}"
    FNXVM_SPICE_ACTIVE="Y"
  else
    warn "SPICE=Y requested, but QEMU SPICE module is unavailable; continuing with VNC/noVNC."
  fi
fi

if [ "$USE_VIRGL" = "Y" ]; then
  info "Hardware OpenGL (VirGL) enabled on ${RENDERNODE} using ${VGA_DEVICE}."
  DISPLAY_OPTS="-display egl-headless,rendernode=${RENDERNODE} ${VGA_ARG}"
  case "${DISPLAY,,}" in
    "vnc" )
      DISPLAY_OPTS+=" -vnc :${port},password=on${LOSSY_OPT}"
      FNXVM_VNC_ACTIVE="Y" ;;
    "web" | "ramfb" )
      DISPLAY_OPTS+=" -vnc :${port},websocket=unix:${WSS_SOCKET},password=on${LOSSY_OPT}"
      FNXVM_VNC_ACTIVE="Y" ;;
  esac
else
  case "${DISPLAY,,}" in
    "vnc" )
      DISPLAY_OPTS="-display vnc=:${port},password=on${LOSSY_OPT} ${VGA_ARG}"
      FNXVM_VNC_ACTIVE="Y" ;;
    "web" )
      DISPLAY_OPTS="-display vnc=:${port},websocket=unix:${WSS_SOCKET},password=on${LOSSY_OPT} ${VGA_ARG}"
      FNXVM_VNC_ACTIVE="Y" ;;
    "ramfb" )
      DISPLAY_OPTS="-display vnc=:${port},websocket=unix:${WSS_SOCKET},password=on${LOSSY_OPT} -device ramfb"
      FNXVM_VNC_ACTIVE="Y" ;;
    "disabled" )
      DISPLAY_OPTS="-display none ${VGA_ARG}" ;;
    "none" )
      DISPLAY_OPTS="-display none -vga none" ;;
    * )
      DISPLAY_OPTS="-display ${DISPLAY} ${VGA_ARG}" ;;
  esac
fi

DISPLAY_OPTS+="${SPICE_OPTS}"
export FNXVM_VNC_ACTIVE FNXVM_SPICE_ACTIVE

return 0
