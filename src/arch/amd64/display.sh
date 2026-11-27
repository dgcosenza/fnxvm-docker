#!/usr/bin/env bash
set -Eeuo pipefail

# FNXVM amd64 display and video acceleration configuration.
# Supports GPU=auto|virtio|virgl|qxl|std (plus upstream GPU=Y|N and VGA= overrides),
# VNC authentication (password=on), and optional SPICE transport (SPICE=Y).

: "${GPU:="auto"}"            # GPU mode: auto | virtio | virgl | qxl | std | Y | N
: "${VGA:=""}"                # Optional explicit VGA adapter override
: "${DISPLAY:="web"}"         # Display type: web | vnc | disabled | none
: "${LOSSY:="N"}"             # Lossy VNC compression
: "${VNC_PORT:="5900"}"       # VNC port
: "${RENDERNODE:=""}"         # Optional DRM render node (e.g. /dev/dri/renderD128)
: "${VRAM_SIZE:="4G"}"        # VirtIO GPU memory budget
: "${SPICE:="N"}"             # Optional SPICE server (authenticated via QMP)
: "${SPICE_PORT:="5901"}"     # SPICE TCP port when SPICE=Y

# Sanitize variables
GPU=$(strip "$GPU")
VGA=$(strip "$VGA")
LOSSY=$(strip "$LOSSY")
DISPLAY=$(strip "$DISPLAY")
VNC_PORT=$(strip "$VNC_PORT")
RENDERNODE=$(strip "$RENDERNODE")
VRAM_SIZE=$(strip "$VRAM_SIZE")
SPICE=$(strip "$SPICE")
SPICE_PORT=$(strip "$SPICE_PORT")
WSS_SOCKET="${WSS_SOCKET:-$QEMU_DIR/vnc-ws.sock}"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"

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

# Per-guest safe software display defaults:
# - Windows preserves upstream dockur/windows defaults (virtio-vga, or legacy VGA from define/legacy.sh).
# - Haiku requires standard VESA/VGA.
# - Generic Linux/BSD/custom guests default to safe std VGA when no /dev/dri render node is active.
if [ -n "$USER_VGA" ]; then
  SAFE_VGA="$USER_VGA"
elif [ "${FNXVM_MODE:-generic}" = "windows" ] || [[ "${BOOT_MODE,,}" == "windows"* ]]; then
  SAFE_VGA="virtio"
else
  SAFE_VGA="std"
fi

# Fallback when GPU=virgl cannot activate hardware OpenGL (never crash).
if [ "${FNXVM_OS:-}" = "haiku" ]; then
  VIRGL_FALLBACK_VGA="std"
else
  VIRGL_FALLBACK_VGA="virtio"
fi

# Probe for a usable DRM render node (/dev/dri/renderD*).
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

  local vendor_file="/sys/class/drm/${render_name}/device/vendor"
  if [ -r "$vendor_file" ]; then
    IFS= read -r GPU_VENDOR < "$vendor_file" || GPU_VENDOR=""
    GPU_VENDOR="${GPU_VENDOR,,}"
  else
    GPU_VENDOR=""
  fi

  return 0
}

detectRenderNode() {

  VIRGL_REASON=""
  GPU_VENDOR=""
  local found_any="N"

  if ! qemuHasDisplay "egl-headless"; then
    VIRGL_REASON="QEMU egl-headless OpenGL module is not available"
    return 1
  fi

  if ! qemuHasDevice "virtio-vga-gl"; then
    VIRGL_REASON="QEMU virtio-vga-gl device module is not available"
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
    VGA="std" ;;
  "virtio" )
    VGA="virtio" ;;
  "qxl" )
    if qemuHasDevice "qxl-vga"; then
      VGA="qxl-vga"
    else
      warn "GPU=qxl requested, but QEMU qxl-vga module is unavailable; falling back to '${SAFE_VGA}'."
      VGA="$SAFE_VGA"
    fi ;;
  "virgl" )
    if detectRenderNode; then
      USE_VIRGL="Y"
      VGA="virtio-vga-gl"
    else
      warn "GPU=virgl requested, but ${VIRGL_REASON}; falling back to software rendering (${VIRGL_FALLBACK_VGA})."
      VGA="$VIRGL_FALLBACK_VGA"
    fi ;;
  "auto" )
    # In auto mode, only probe VirGL for guests with native Mesa VirGL support
    # when no explicit VGA override was supplied; Windows, Haiku, and BSD keep safe defaults.
    if [ -z "$USER_VGA" ] && \
       [ "${FNXVM_MODE:-generic}" != "windows" ] && \
       [[ "${BOOT_MODE,,}" != "windows"* ]] && \
       [[ "${FNXVM_OS:-}" != "haiku" ]] && \
       [[ "${FNXVM_OS:-}" != "freebsd" ]] && \
       [[ "${FNXVM_OS:-}" != "daemonarchy" ]] && \
       detectRenderNode; then
      USE_VIRGL="Y"
      VGA="virtio-vga-gl"
    else
      VGA="$SAFE_VGA"
    fi ;;
esac

VGA_DEVICE="${VGA%%,*}"
VGA_OPTIONS="${VGA#"$VGA_DEVICE"}"

case "${VGA_DEVICE,,}" in
  "std" | "vga" )
    VGA_DEVICE="VGA"
    VGA_ARG="-device" ;;
  "vmware" | "vmware-svga" )
    VGA_DEVICE="vmware-svga"
    VGA_ARG="-device" ;;
  "qxl" | "qxl-vga" )
    VGA_DEVICE="qxl-vga"
    VGA_ARG="-device" ;;
  "virtio" )
    VGA_DEVICE="virtio-vga"
    VGA_ARG="-device" ;;
  "virtio-"* )
    VGA_DEVICE="${VGA_DEVICE,,}"
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
    "web" )
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
