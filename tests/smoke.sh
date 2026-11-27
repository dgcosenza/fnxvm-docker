#!/usr/bin/env bash
# Smoke test suite for a built FNXVM candidate image.
# Verifies:
#   1. Container boots real QEMU (TCG mode against a tiny synthetic boot disk),
#      starts nginx + websocketd + VNC, and reaches Docker HEALTHCHECK=healthy.
#   2. Web viewer (noVNC/HTTP 8006) responds HTTP 200 and VNC (5900) emits RFB.
#   3. Required hypervisor, firmware, and verification binaries are installed.
#   4. Negative healthcheck check fails when the web viewer is not running.
#   5. Non-root execution of fnxvm-resolve works under vmuser (UID 1000).
#   6. Invalid OS and DESKTOP inputs fail fast with clear error messages.
#   7. Dynamic OS resolver (RESOLVE_ONLY=1 and fnxvm-resolve) resolves all 6 OS
#      values (+ Debian KDE + Windows LTSC) and asserts HTTP 200 on every ISO,
#      checksum, and signature URL.
#
# Maintainer: Daniel G. Cosenza from FNX Labs
set -euo pipefail

IMAGE="${1:-fnxvm:local}"
NAME="fnxvm-smoke-$$"
TMPDIR_SMOKE="$(mktemp -d)"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$TMPDIR_SMOKE"
}
trap cleanup EXIT

echo "==> smoke: image ${IMAGE}"

ARCH="$(docker run --rm --entrypoint dpkg "$IMAGE" --print-architecture | tr -d '\r\n')"
echo "Detected image architecture: ${ARCH}"

# Create a 1 MiB synthetic boot disk so the real entrypoint, nginx, websocketd,
# firmware loader, and QEMU process start cleanly without downloading a multi-GB ISO.
dd if=/dev/zero of="${TMPDIR_SMOKE}/boot.img" bs=1M count=1 status=none

docker run -d \
  --name "$NAME" \
  -p 127.0.0.1::8006 \
  -p 127.0.0.1::5900 \
  -v "${TMPDIR_SMOKE}/boot.img:/boot.img:ro" \
  -e KVM=N \
  -e NETWORK=user \
  -e RAM_SIZE=256M \
  -e CPU_CORES=1 \
  -e DISK_SIZE=1G \
  -e BOOT_MODE=uefi \
  "$IMAGE" >/dev/null

echo -n "healthcheck: "
for _ in $(seq 1 60); do
  state="$(docker inspect --format '{{.State.Health.Status}}' "$NAME" 2>/dev/null || echo missing)"
  case "$state" in
    healthy) echo "healthy"; break ;;
    unhealthy) echo "unhealthy"; docker logs "$NAME" || true; exit 1 ;;
    starting|missing) sleep 2 ;;
    *) echo "unexpected state: ${state}"; docker logs "$NAME" || true; exit 1 ;;
  esac
done

[ "$(docker inspect --format '{{.State.Health.Status}}' "$NAME")" = "healthy" ] || {
  echo "container never reached healthy" >&2
  docker logs "$NAME" || true
  exit 1
}

# Wait briefly for QEMU to publish its PID and open VNC port 5900.
for _ in $(seq 1 30); do
  if docker exec "$NAME" sh -c '[ -s /run/shm/qemu.pid ] && nc -z 127.0.0.1 5900' >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

WEB_HOST_PORT="$(docker port "$NAME" 8006/tcp | head -n 1 | awk -F: '{print $NF}')"
VNC_HOST_PORT="$(docker port "$NAME" 5900/tcp | head -n 1 | awk -F: '{print $NF}')"
[ -n "$WEB_HOST_PORT" ] && [ -n "$VNC_HOST_PORT" ] || {
  echo "failed to discover mapped web/VNC ports" >&2
  exit 1
}

# Verify web viewer (nginx + noVNC/status page) responds HTTP 200.
web_code="$(curl -fsS -o "${TMPDIR_SMOKE}/web.html" -w '%{http_code}' "http://127.0.0.1:${WEB_HOST_PORT}/")"
[ "$web_code" = "200" ] || { echo "web viewer returned HTTP ${web_code}" >&2; exit 1; }
grep -qi '<html' "${TMPDIR_SMOKE}/web.html" || { echo "web viewer response is not HTML" >&2; exit 1; }
echo "web viewer (HTTP 200 on port ${WEB_HOST_PORT}): ok"

# Verify VNC server emits an RFB protocol banner.
rfb_banner="$(timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/${VNC_HOST_PORT}; head -c 12 <&3" 2>/dev/null || true)"
case "$rfb_banner" in
  RFB\ *) echo "VNC RFB handshake (${rfb_banner}): ok" ;;
  *)
    echo "expected RFB handshake on VNC port ${VNC_HOST_PORT}, got: '${rfb_banner}'" >&2
    docker logs "$NAME" || true
    exit 1
    ;;
esac

# Verify required binaries, firmware, GPG keyrings, and live QEMU process.
docker exec "$NAME" bash -ceu '
  for t in tini nginx websocketd passt udfread swtpm wimlib-imagex aria2c curl wget jq python3 xorriso 7z smbd gpgv cabextract xmlstarlet fnxvm-resolve fnxvm-healthcheck; do
    command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }
  done
  test -x /run/boot-logo
  test -s /var/drivers.txz
  test -s /usr/share/novnc/vnc.html
  test -s /etc/fnxvm/keys/debian-cd.gpg
  test -s /etc/fnxvm/keys/ubuntu-cd.gpg
  test -s /etc/fnxvm/keys/omarchy.gpg
  python3 -c "import qemu.qmp"
  if [ "$(dpkg --print-architecture)" = "amd64" ]; then
    command -v qemu-system-x86_64 >/dev/null
    test -s /usr/share/OVMF/OVMF_CODE_4M.fd
    test -s /usr/share/OVMF/OVMF_VARS_4M.fd
  else
    command -v qemu-system-aarch64 >/dev/null
    test -s /usr/share/AAVMF/AAVMF_CODE.no-secboot.fd
    test -s /usr/share/AAVMF/AAVMF_VARS.fd
  fi
  qpid="$(tr -d "[:space:]" < /run/shm/qemu.pid)"
  kill -0 "$qpid"
'
echo "tools, firmware, keyrings, and live QEMU process: ok"

# Negative healthcheck test: healthcheck must fail when nginx is not running.
if docker run --rm --entrypoint /usr/local/bin/fnxvm-healthcheck "$IMAGE" >/dev/null 2>&1; then
  echo "negative healthcheck test failed: expected non-zero exit when web server is stopped" >&2
  exit 1
fi
echo "negative healthcheck test: ok"

# Non-root check: vmuser (UID 1000) can execute fnxvm-resolve cleanly.
nonroot_user="$(docker run --rm --user vmuser --entrypoint whoami "$IMAGE")"
[ "$nonroot_user" = "vmuser" ] || { echo "unexpected non-root user: ${nonroot_user}" >&2; exit 1; }
docker run --rm --user vmuser --entrypoint fnxvm-resolve "$IMAGE" --list >/dev/null
echo "non-root (vmuser) execution: ok"

# Negative OS / DESKTOP input tests: must fail fast with clear error messages.
if err_out="$(docker run --rm -e OS=not-a-valid-os "$IMAGE" 2>&1)"; then
  echo "expected unknown OS to fail fast" >&2
  exit 1
fi
echo "$err_out" | grep -qi "Valid OS values" || { echo "missing valid OS list in error: $err_out" >&2; exit 1; }
echo "negative unknown OS test: ok"

if err_out="$(docker run --rm -e OS=debian -e DESKTOP=invalid -e RESOLVE_ONLY=1 "$IMAGE" 2>&1)"; then
  echo "expected invalid DESKTOP to fail fast" >&2
  exit 1
fi
echo "$err_out" | grep -qi "gnome" || { echo "missing valid DESKTOP list in error: $err_out" >&2; exit 1; }
echo "negative invalid DESKTOP test: ok"

# Resolver dry-run via entrypoint (RESOLVE_ONLY=1) and custom BOOT URL.
docker run --rm -e RESOLVE_ONLY=1 -e OS=debian -e DESKTOP=gnome "$IMAGE" | grep -q "^ISO URL:"
docker run --rm -e RESOLVE_ONLY=1 -e BOOT="https://example.invalid/custom.iso" "$IMAGE" | grep -q "https://example.invalid/custom.iso"
echo "RESOLVE_ONLY=1 and custom BOOT: ok"

# Full dynamic OS resolver + HTTP 200 verification for all 6 supported guests (+ Debian KDE + Windows LTSC).
echo "==> resolver HTTP 200 verification (${ARCH})"
docker run --rm --entrypoint fnxvm-resolve "$IMAGE" debian --arch "$ARCH" --desktop gnome --verify-urls
docker run --rm --entrypoint fnxvm-resolve "$IMAGE" debian --arch "$ARCH" --desktop kde --verify-urls
docker run --rm --entrypoint fnxvm-resolve "$IMAGE" ubuntu --arch "$ARCH" --verify-urls
docker run --rm --entrypoint fnxvm-resolve "$IMAGE" freebsd --arch "$ARCH" --verify-urls
docker run --rm --entrypoint fnxvm-resolve "$IMAGE" omarchy --arch "$ARCH" --verify-urls
docker run --rm --entrypoint fnxvm-resolve "$IMAGE" windows --arch "$ARCH" --version 11 --verify-urls
docker run --rm --entrypoint fnxvm-resolve "$IMAGE" windows --arch "$ARCH" --version ltsc --verify-urls

if [ "$ARCH" = "amd64" ]; then
  docker run --rm --entrypoint fnxvm-resolve "$IMAGE" haiku --arch amd64 --verify-urls
else
  # On arm64, verify Haiku fails fast with a clear arch-unsupported message, and
  # still verify Haiku's amd64 URLs return HTTP 200.
  if docker run --rm --entrypoint fnxvm-resolve "$IMAGE" haiku --arch arm64 >/dev/null 2>&1; then
    echo "expected Haiku on arm64 to fail fast" >&2
    exit 1
  fi
  docker run --rm --entrypoint fnxvm-resolve "$IMAGE" haiku --arch amd64 --verify-urls
fi

echo "==> smoke: PASS"
