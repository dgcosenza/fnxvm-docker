#!/usr/bin/env bash
# Smoke test suite for a built FNXVM candidate image.
# Verifies:
#   1. Default authenticated startup: generates strong first-start credentials,
#      prints plaintext once, persists bcrypt hash ONLY under /storage, and
#      reaches Docker HEALTHCHECK=healthy with real QEMU (TCG mode).
#   2. Web UI (8006) and WebSocket upgrade (/websockify) enforce HTTP Basic Auth:
#      401 without creds, 401 with wrong creds, 200 / 101 with valid creds.
#   3. VNC (5900) enforces RFB VNC Authentication (security type 2, never None).
#   4. Persistence across restart: second container reusing /storage does NOT
#      re-print the web password and still accepts the persisted credentials.
#   5. Clipboard host<->guest devices (virtio-serial-pci, qemu-vdagent,
#      clipboard=on, com.redhat.spice.0) present in QEMU args and QMP query-chardev.
#   6. GPU modes: unset/auto -> safe device (VGA/ramfb); GPU=virtio -> virtio GPU;
#      GPU=virgl without /dev/dri -> clear fallback warning, healthy (no crash).
#   7. Secret-file auth (WEB_PASSWORD_FILE / VNC_PASSWORD_FILE), CLIPBOARD=N,
#      and WEB_AUTH=N escape hatch (with loud warning, VNC still authenticated).
#   8. Required tools/modules/firmware/keyrings, negative healthcheck, non-root
#      vmuser execution, and fail-fast validation on unknown OS/DESKTOP/GPU.
#   9. Dynamic OS resolver HTTP 200 verification for all 7 supported OS values
#      (windows, haiku, freebsd, daemonarchy, debian gnome/kde, ubuntu, omarchy).
#
# Maintainer: Daniel G. Cosenza from FNX Labs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${1:-fnxvm:local}"
TAG_PID="$$"
TMPDIR_SMOKE="$(mktemp -d)"
CONTAINERS=()

PLAYWRIGHT_PY="${PLAYWRIGHT_PYTHON:-}"
if [ -z "$PLAYWRIGHT_PY" ] && python3 -c "import playwright" >/dev/null 2>&1; then
  PLAYWRIGHT_PY="python3"
fi
if [ "${REQUIRE_PLAYWRIGHT:-0}" = "1" ] && [ -z "$PLAYWRIGHT_PY" ]; then
  echo "ERROR: REQUIRE_PLAYWRIGHT=1 but Playwright Python is unavailable" >&2
  exit 1
fi

cleanup() {
  for c in "${CONTAINERS[@]:-}"; do
    docker rm -f "$c" >/dev/null 2>&1 || true
  done
  rm -rf "$TMPDIR_SMOKE"
}
trap cleanup EXIT

wait_healthy() {
  local cname="$1"
  local state="missing"
  for _ in $(seq 1 60); do
    state="$(docker inspect --format '{{.State.Health.Status}}' "$cname" 2>/dev/null || echo missing)"
    case "$state" in
      healthy) return 0 ;;
      unhealthy)
        echo "container ${cname} became unhealthy" >&2
        docker logs "$cname" || true
        return 1 ;;
      starting|missing) sleep 2 ;;
      *)
        echo "unexpected health state for ${cname}: ${state}" >&2
        docker logs "$cname" || true
        return 1 ;;
    esac
  done
  echo "container ${cname} never reached healthy (last=${state})" >&2
  docker logs "$cname" || true
  return 1
}

wait_qemu_ready() {
  local cname="$1"
  for _ in $(seq 1 40); do
    if docker exec "$cname" sh -c '[ -s /run/shm/qemu.pid ] && [ -S /run/shm/qmp.sock ] && [ -f /run/shm/vnc-auth.ready ] && [ ! -e /run/shm/.vnc-password ] && nc -z 127.0.0.1 5900' >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "QEMU/QMP/VNC did not become ready in ${cname}" >&2
  docker logs "$cname" || true
  return 1
}

check_ws_upgrade() {
  local port="$1"
  local user="$2"
  local pass="$3"
  local expected_code="$4"
  local use_tls="${5:-0}"
  python3 - "$port" "$user" "$pass" "$expected_code" "$use_tls" <<'PY'
import base64, os, socket, ssl, sys
port = int(sys.argv[1])
user, pw, expected = sys.argv[2], sys.argv[3], sys.argv[4]
use_tls = sys.argv[5] == "1"
ws_nonce = base64.b64encode(os.urandom(16)).decode()
headers = [
    "GET /websockify HTTP/1.1",
    f"Host: 127.0.0.1:{port}",
    "Connection: Upgrade",
    "Upgrade: websocket",
    "Sec-WebSocket-Version: 13",
    f"Sec-WebSocket-Key: {ws_nonce}",
]
if user or pw:
    tok = base64.b64encode(f"{user}:{pw}".encode()).decode()
    headers.append(f"Authorization: Basic {tok}")
req = ("\r\n".join(headers) + "\r\n\r\n").encode()
raw = socket.create_connection(("127.0.0.1", port), timeout=5)
if use_tls:
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    conn = ctx.wrap_socket(raw, server_hostname="127.0.0.1")
else:
    conn = raw
with conn as s:
    s.sendall(req)
    data = b""
    while b"\r\n" not in data:
        chunk = s.recv(1024)
        if not chunk:
            break
        data += chunk
status_line = data.split(b"\r\n", 1)[0].decode("latin1", errors="replace")
parts = status_line.split()
code = parts[1] if len(parts) >= 2 else "000"
if code != expected:
    print(f"ERROR: /websockify returned HTTP {code} (expected {expected}); line={status_line!r}", file=sys.stderr)
    sys.exit(1)
PY
}

check_vnc_requires_auth() {
  local port="$1"
  python3 - "$port" <<'PY'
import socket, sys
port = int(sys.argv[1])
with socket.create_connection(("127.0.0.1", port), timeout=5) as s:
    banner = b""
    while len(banner) < 12:
        chunk = s.recv(12 - len(banner))
        if not chunk:
            break
        banner += chunk
    if not banner.startswith(b"RFB "):
        print(f"ERROR: expected RFB banner, got {banner!r}", file=sys.stderr)
        sys.exit(1)
    s.sendall(b"RFB 003.008\n")
    count_b = s.recv(1)
    if not count_b or count_b[0] == 0:
        print(f"ERROR: RFB server offered 0 security types (banner={banner!r})", file=sys.stderr)
        sys.exit(1)
    n = count_b[0]
    types = b""
    while len(types) < n:
        chunk = s.recv(n - len(types))
        if not chunk:
            break
        types += chunk
    sec_types = list(types)
    if 1 in sec_types:
        print(f"ERROR: VNC allows unauthenticated security type None (1): {sec_types}", file=sys.stderr)
        sys.exit(1)
    if 2 not in sec_types:
        print(f"ERROR: VNC did not advertise VNC Authentication (2): {sec_types}", file=sys.stderr)
        sys.exit(1)
    print(f"VNC RFB handshake ({banner.decode().strip()}, security_types={sec_types}): ok")
PY
}

echo "==> smoke: image ${IMAGE}"

ARCH="$(docker run --rm --entrypoint dpkg "$IMAGE" --print-architecture | tr -d '\r\n')"
echo "Detected image architecture: ${ARCH}"

# Create a 1 MiB synthetic boot disk so the real entrypoint, nginx, websocketd,
# firmware loader, and QEMU process start cleanly without downloading a multi-GB ISO.
dd if=/dev/zero of="${TMPDIR_SMOKE}/boot.img" bs=1M count=1 status=none
mkdir -p "${TMPDIR_SMOKE}/storage-persist" "${TMPDIR_SMOKE}/secrets"

# ==============================================================================
# 1. First start with default auth (no WEB_PASSWORD / VNC_PASSWORD):
#    generated password printed once, bcrypt hash persisted, auth enforced,
#    safe GPU (auto), clipboard vdagent + QMP verified.
# ==============================================================================
C1="fnxvm-smoke-c1-${TAG_PID}"
CONTAINERS+=("$C1")
docker run -d \
  --name "$C1" \
  -p 127.0.0.1::8006 \
  -p 127.0.0.1::5900 \
  -v "${TMPDIR_SMOKE}/boot.img:/boot.img" \
  -v "${TMPDIR_SMOKE}/storage-persist:/storage" \
  -e KVM=N \
  -e NETWORK=user \
  -e RAM_SIZE=256M \
  -e CPU_CORES=1 \
  -e DISK_SIZE=1G \
  -e BOOT_MODE=uefi \
  "$IMAGE" >/dev/null

echo -n "healthcheck (default auth + safe GPU + clipboard): "
wait_healthy "$C1"
echo "healthy"
wait_qemu_ready "$C1"

C1_LOGS="$(docker logs "$C1" 2>&1)"
echo "$C1_LOGS" | grep -q "printed ONCE" || {
  echo "missing first-start credential banner in logs" >&2
  echo "$C1_LOGS" >&2
  exit 1
}

GEN_USER="$(printf '%s\n' "$C1_LOGS" | awk '/^[[:space:]]*Username:/ {print $2; exit}')"
GEN_PASS="$(printf '%s\n' "$C1_LOGS" | awk '/^[[:space:]]*Password:/ {print $2; exit}')"
[ "$GEN_USER" = "fnxvm" ] && [ "${#GEN_PASS}" -ge 16 ] || {
  echo "failed to parse generated credentials (user='${GEN_USER}', len=${#GEN_PASS})" >&2
  exit 1
}

# Verify persisted bcrypt hash exists (mode 0600) and never stores plaintext.
HTPASSWD_FILE="${TMPDIR_SMOKE}/storage-persist/.fnxvm-web.htpasswd"
test -s "$HTPASSWD_FILE" || { echo "missing persisted ${HTPASSWD_FILE}" >&2; exit 1; }
ht_mode="$(stat -c '%a' "$HTPASSWD_FILE")"
[ "$ht_mode" = "600" ] || { echo "expected 0600 on ${HTPASSWD_FILE}, got ${ht_mode}" >&2; exit 1; }
grep -Eq '^fnxvm:\$2[aby]\$[0-9]{2}\$' "$HTPASSWD_FILE" || {
  echo "persisted htpasswd is not a bcrypt hash" >&2
  exit 1
}
if grep -Fq "$GEN_PASS" "$HTPASSWD_FILE"; then
  echo "ERROR: plaintext password found in persisted htpasswd!" >&2
  exit 1
fi
echo "first-start generated password + bcrypt persistence: ok"
# Independent VNC secret: printed once, persisted 0600, never a prefix of the web password.
GEN_VNC="$(printf '%s\n' "$C1_LOGS" | awk '/^[[:space:]]*Password:/ {n++; if (n==2) {print $2; exit}}')"
VNC_SECRET_FILE="${TMPDIR_SMOKE}/storage-persist/.fnxvm-vnc.secret"
[ "${#GEN_VNC}" -eq 8 ] || { echo "failed to parse generated VNC password (len=${#GEN_VNC})" >&2; exit 1; }
test -s "$VNC_SECRET_FILE" || { echo "missing persisted ${VNC_SECRET_FILE}" >&2; exit 1; }
[ "$(stat -c '%a' "$VNC_SECRET_FILE")" = "600" ] || { echo "expected 0600 on ${VNC_SECRET_FILE}" >&2; exit 1; }
case "$GEN_PASS" in
  "$GEN_VNC"*) echo "ERROR: VNC password is derived from the web password!" >&2; exit 1 ;;
esac
echo "independent VNC secret (printed once, persisted 0600): ok"


WEB_PORT_1="$(docker port "$C1" 8006/tcp | head -n 1 | awk -F: '{print $NF}')"
VNC_PORT_1="$(docker port "$C1" 5900/tcp | head -n 1 | awk -F: '{print $NF}')"

# HTTP Basic Auth tests on 8006 (/)
BAD_PW="invalid"
c_noauth="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${WEB_PORT_1}/")"
[ "$c_noauth" = "401" ] || { echo "expected 401 without creds, got ${c_noauth}" >&2; exit 1; }

c_wrong="$(curl -sS -u "fnxvm:${BAD_PW}" -o /dev/null -w '%{http_code}' "http://127.0.0.1:${WEB_PORT_1}/")"
[ "$c_wrong" = "401" ] || { echo "expected 401 with wrong creds, got ${c_wrong}" >&2; exit 1; }

c_ok="$(curl -fsS -u "${GEN_USER}:${GEN_PASS}" -o "${TMPDIR_SMOKE}/web.html" -w '%{http_code}' "http://127.0.0.1:${WEB_PORT_1}/")"
[ "$c_ok" = "200" ] || { echo "expected 200 with valid creds, got ${c_ok}" >&2; exit 1; }
grep -qi '<html' "${TMPDIR_SMOKE}/web.html" || { echo "web viewer response is not HTML" >&2; exit 1; }

# WebSocket /websockify auth checks (401 unauth, 401 wrong, 101 valid)
check_ws_upgrade "$WEB_PORT_1" "" "" "401"
check_ws_upgrade "$WEB_PORT_1" "fnxvm" "$BAD_PW" "401"
check_ws_upgrade "$WEB_PORT_1" "$GEN_USER" "$GEN_PASS" "101"
echo "web UI (401/401/200) and /websockify (401/401/101) auth: ok"

# VNC RFB auth check (security type 2, never None) + full Extended Clipboard & legacy CutText protocol suite
check_vnc_requires_auth "$VNC_PORT_1"
python3 "${SCRIPT_DIR}/test_rfb_clipboard.py" --host 127.0.0.1 --port "$VNC_PORT_1" --password "$GEN_VNC"

# Headless Chromium (Playwright) noVNC Basic Auth + VNC Auth + live bidirectional clipboard test
if [ -n "$PLAYWRIGHT_PY" ]; then
  "$PLAYWRIGHT_PY" "${SCRIPT_DIR}/test_novnc_playwright.py" \
    --web-url "http://127.0.0.1:${WEB_PORT_1}" \
    --web-user "$GEN_USER" \
    --web-password "$GEN_PASS" \
    --vnc-host 127.0.0.1 \
    --vnc-port "$VNC_PORT_1" \
    --vnc-password "$GEN_VNC"
else
  echo "Playwright not installed locally; skipping browser noVNC test (mandatory in CI)."
fi

# Verify QEMU args (safe GPU, password=on, virtio-serial, qemu-vdagent, com.redhat.spice.0),
# live QMP query-chardev, required binaries/modules/keyrings, and noVNC clipboard UI.
docker exec "$C1" bash -ceu '
  for t in tini nginx websocketd passt udfread swtpm wimlib-imagex aria2c curl wget jq python3 xorriso 7z smbd gpgv cabextract xmlstarlet xz htpasswd fnxvm-resolve fnxvm-healthcheck; do
    command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }
  done
  test -x /run/boot-logo
  test -x /run/set-vnc-password.py
  test -s /var/drivers.txz
  test -s /usr/share/novnc/vnc.html
  grep -q "noVNC_clipboard_send_button" /usr/share/novnc/vnc.html
  grep -q "noVNC_clipboard_read_button" /usr/share/novnc/vnc.html
  grep -q "noVNC_clipboard_copy_button" /usr/share/novnc/vnc.html
  grep -q "noVNC_clipboard_status" /usr/share/novnc/vnc.html
  grep -q "noVNC_setting_clipboard_sync" /usr/share/novnc/vnc.html
  grep -q "clipboardPasteFrom" /usr/share/novnc/app/ui.js
  grep -q "clipboardReadFromDevice" /usr/share/novnc/app/ui.js
  grep -q "handleCanvasClipboardKeydown" /usr/share/novnc/app/ui.js
  grep -q "extendedClipboardSupported" /usr/share/novnc/core/rfb.js
  test -s /etc/fnxvm/keys/debian-cd.gpg
  test -s /etc/fnxvm/keys/ubuntu-cd.gpg
  test -s /etc/fnxvm/keys/omarchy.gpg
  python3 -c "import qemu.qmp"

  qpid="$(tr -d "[:space:]" < /run/shm/qemu.pid)"
  kill -0 "$qpid"
  cmdline="$(tr "\0" " " < "/proc/${qpid}/cmdline")"

  # Clipboard & VNC auth args
  for needle in "virtio-serial-pci" "qemu-vdagent" "clipboard=on" "com.redhat.spice.0" "password=on"; do
    if ! grep -Fq -- "$needle" <<< "$cmdline"; then
      echo "ERROR: expected ${needle} in QEMU cmdline: ${cmdline}" >&2
      exit 1
    fi
  done

  # Safe default GPU device (GPU unset / auto without /dev/dri) + OpenGL/SPICE module availability
  if [ "$(dpkg --print-architecture)" = "amd64" ]; then
    qbin="qemu-system-x86_64"
    mach="q35"
    command -v "$qbin" >/dev/null
    test -s /usr/share/OVMF/OVMF_CODE_4M.fd
    test -s /usr/share/OVMF/OVMF_VARS_4M.fd
    grep -Fq -- "-device VGA" <<< "$cmdline" || { echo "ERROR: expected -device VGA in cmdline: $cmdline" >&2; exit 1; }
    disp_help="$("$qbin" -M none -display help 2>&1 || true)"
    dev_help="$("$qbin" -M "$mach" -device help 2>&1 || true)"
    chr_help="$("$qbin" -M none -chardev help 2>&1 || true)"
    grep -qw "egl-headless" <<< "$disp_help" || { echo "ERROR: egl-headless missing from -display help: $disp_help" >&2; exit 1; }
    grep -Fq "name \"virtio-vga-gl\"" <<< "$dev_help" || { echo "ERROR: virtio-vga-gl missing from -device help" >&2; exit 1; }
    grep -Fq "name \"qxl-vga\"" <<< "$dev_help" || { echo "ERROR: qxl-vga missing from -device help" >&2; exit 1; }
    grep -qw "qemu-vdagent" <<< "$chr_help" || { echo "ERROR: qemu-vdagent missing from -chardev help: $chr_help" >&2; exit 1; }
    test -s /usr/lib/x86_64-linux-gnu/qemu/chardev-spice.so || { echo "ERROR: chardev-spice.so missing" >&2; exit 1; }
    test -s /usr/lib/x86_64-linux-gnu/qemu/ui-spice-core.so || { echo "ERROR: ui-spice-core.so missing" >&2; exit 1; }
    test -s /usr/lib/x86_64-linux-gnu/qemu/ui-egl-headless.so || { echo "ERROR: ui-egl-headless.so missing" >&2; exit 1; }
  else
    qbin="qemu-system-aarch64"
    mach="virt"
    command -v "$qbin" >/dev/null
    test -s /usr/share/AAVMF/AAVMF_CODE.no-secboot.fd
    test -s /usr/share/AAVMF/AAVMF_VARS.fd
    grep -Fq -- "-device ramfb" <<< "$cmdline" || { echo "ERROR: expected -device ramfb in cmdline: $cmdline" >&2; exit 1; }
    disp_help="$("$qbin" -M none -display help 2>&1 || true)"
    dev_help="$("$qbin" -M "$mach" -device help 2>&1 || true)"
    chr_help="$("$qbin" -M none -chardev help 2>&1 || true)"
    grep -qw "egl-headless" <<< "$disp_help" || { echo "ERROR: egl-headless missing from -display help: $disp_help" >&2; exit 1; }
    grep -Fq "name \"virtio-gpu-gl-pci\"" <<< "$dev_help" || { echo "ERROR: virtio-gpu-gl-pci missing from -device help" >&2; exit 1; }
    grep -qw "qemu-vdagent" <<< "$chr_help" || { echo "ERROR: qemu-vdagent missing from -chardev help: $chr_help" >&2; exit 1; }
    test -s /usr/lib/aarch64-linux-gnu/qemu/chardev-spice.so || { echo "ERROR: chardev-spice.so missing" >&2; exit 1; }
    test -s /usr/lib/aarch64-linux-gnu/qemu/ui-spice-core.so || { echo "ERROR: ui-spice-core.so missing" >&2; exit 1; }
    test -s /usr/lib/aarch64-linux-gnu/qemu/ui-egl-headless.so || { echo "ERROR: ui-egl-headless.so missing" >&2; exit 1; }
  fi

  # Live QMP query-chardev assertion for vdagent
  python3 - <<PY
import asyncio, json, sys
from qemu.qmp import QMPClient

async def main():
    qmp = QMPClient("smoke-probe")
    await qmp.connect("/run/shm/qmp.sock")
    chardevs = await qmp.execute("query-chardev")
    await qmp.disconnect()
    vd = [c for c in chardevs if c.get("label") == "vdagent"]
    if not vd:
        print("ERROR: vdagent not found in QMP query-chardev:", chardevs, file=sys.stderr)
        sys.exit(1)
    print("QMP query-chardev vdagent:", json.dumps(vd[0]))
    if "qemu-vdagent" not in str(vd[0].get("filename", "")):
        print("ERROR: vdagent chardev is not qemu-vdagent:", vd[0], file=sys.stderr)
        sys.exit(1)

asyncio.run(main())
PY
'
echo "tools, firmware, keyrings, safe GPU, clipboard args + live QMP query-chardev: ok"

# ==============================================================================
# 2. Restart persistence check: reuse /storage without WEB_PASSWORD; password
#    must NOT be printed again and original generated credentials must still work.
# ==============================================================================
docker rm -f "$C1" >/dev/null

C2="fnxvm-smoke-c2-${TAG_PID}"
CONTAINERS+=("$C2")
docker run -d \
  --name "$C2" \
  -p 127.0.0.1::8006 \
  -p 127.0.0.1::5900 \
  -v "${TMPDIR_SMOKE}/boot.img:/boot.img" \
  -v "${TMPDIR_SMOKE}/storage-persist:/storage" \
  -e KVM=N \
  -e NETWORK=user \
  -e RAM_SIZE=256M \
  -e CPU_CORES=1 \
  -e DISK_SIZE=1G \
  -e BOOT_MODE=uefi \
  "$IMAGE" >/dev/null

wait_healthy "$C2"
wait_qemu_ready "$C2"

C2_LOGS="$(docker logs "$C2" 2>&1)"
if echo "$C2_LOGS" | grep -q "printed ONCE"; then
  echo "ERROR: restart printed first-start password banner again!" >&2
  exit 1
fi
if echo "$C2_LOGS" | grep -Fq "$GEN_PASS"; then
  echo "ERROR: restart leaked persisted web password!" >&2
  exit 1
fi
if echo "$C2_LOGS" | grep -Fq "$GEN_VNC"; then
  echo "ERROR: restart reprinted the persisted VNC password!" >&2
  exit 1
fi
echo "$C2_LOGS" | grep -q "persisted bcrypt hash" || {
  echo "expected persisted bcrypt hash notice on restart" >&2
  echo "$C2_LOGS" >&2
  exit 1
}

WEB_PORT_2="$(docker port "$C2" 8006/tcp | head -n 1 | awk -F: '{print $NF}')"
VNC_PORT_2="$(docker port "$C2" 5900/tcp | head -n 1 | awk -F: '{print $NF}')"
[ "$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${WEB_PORT_2}/")" = "401" ]
[ "$(curl -sS -u "${GEN_USER}:${GEN_PASS}" -o /dev/null -w '%{http_code}' "http://127.0.0.1:${WEB_PORT_2}/")" = "200" ]
check_vnc_requires_auth "$VNC_PORT_2"
echo "restart credential persistence (printed once, hash reused, 401/200): ok"
docker rm -f "$C2" >/dev/null

# ==============================================================================
# 3. Secret-file auth (WEB_PASSWORD_FILE + VNC_PASSWORD_FILE) + GPU=virtio
# ==============================================================================
SMOKE_WEB_PW="$(python3 -c 'import secrets; print(secrets.token_hex(12), end="")')"
SMOKE_VNC_PW="$(python3 -c 'import secrets; print(secrets.token_hex(4), end="")')"
printf '%s\n' "$SMOKE_WEB_PW" > "${TMPDIR_SMOKE}/secrets/web_pw"
printf '%s\n' "$SMOKE_VNC_PW" > "${TMPDIR_SMOKE}/secrets/vnc_pw"

C3="fnxvm-smoke-c3-${TAG_PID}"
CONTAINERS+=("$C3")
docker run -d \
  --name "$C3" \
  -p 127.0.0.1::8006 \
  -p 127.0.0.1::5900 \
  -v "${TMPDIR_SMOKE}/boot.img:/boot.img" \
  -v "${TMPDIR_SMOKE}/secrets/web_pw:/run/secrets/web_pw:ro" \
  -v "${TMPDIR_SMOKE}/secrets/vnc_pw:/run/secrets/vnc_pw:ro" \
  -e WEB_USER=opsadmin \
  -e WEB_PASSWORD_FILE=/run/secrets/web_pw \
  -e VNC_PASSWORD_FILE=/run/secrets/vnc_pw \
  -e GPU=virtio \
  -e RDP=Y \
  -e KVM=N \
  -e NETWORK=user \
  -e RAM_SIZE=256M \
  -e CPU_CORES=1 \
  -e DISK_SIZE=1G \
  -e BOOT_MODE=uefi \
  "$IMAGE" >/dev/null

wait_healthy "$C3"
wait_qemu_ready "$C3"

C3_LOGS="$(docker logs "$C3" 2>&1)"
if echo "$C3_LOGS" | grep -Fq "$SMOKE_WEB_PW" || echo "$C3_LOGS" | grep -Fq "$SMOKE_VNC_PW"; then
  echo "ERROR: secret-file password leaked into container logs!" >&2
  exit 1
fi

WEB_PORT_3="$(docker port "$C3" 8006/tcp | head -n 1 | awk -F: '{print $NF}')"
VNC_PORT_3="$(docker port "$C3" 5900/tcp | head -n 1 | awk -F: '{print $NF}')"
[ "$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${WEB_PORT_3}/")" = "401" ]
[ "$(curl -sS -u "opsadmin:${SMOKE_WEB_PW}" -o /dev/null -w '%{http_code}' "http://127.0.0.1:${WEB_PORT_3}/")" = "200" ]
check_vnc_requires_auth "$VNC_PORT_3"

docker exec -e SMOKE_VNC_PW="$SMOKE_VNC_PW" "$C3" bash -ceu '
  qpid="$(tr -d "[:space:]" < /run/shm/qemu.pid)"
  cmdline="$(tr "\0" " " < "/proc/${qpid}/cmdline")"
  if echo "$cmdline" | grep -Fq "$SMOKE_VNC_PW"; then
    echo "ERROR: VNC password leaked in QEMU cmdline!" >&2
    exit 1
  fi
  if [ "$(dpkg --print-architecture)" = "amd64" ]; then
    echo "$cmdline" | grep -q -- "-device virtio-vga"
  else
    echo "$cmdline" | grep -q -- "-device virtio-gpu-pci"
  fi
  # Verify RDP=Y forwards 3389 TCP and UDP in user-mode networking (passt or slirp)
  if ! echo "$cmdline" | grep -q "hostfwd=tcp::3389-"; then
    if ! ps -ef | grep -E "passt.*-t [^ ]*3389" | grep -vq grep; then
      echo "ERROR: expected RDP=Y to forward 3389/tcp in user-mode networking" >&2
      echo "cmdline: $cmdline" >&2
      ps -ef >&2
      exit 1
    fi
  fi
'
echo "WEB_PASSWORD_FILE + VNC_PASSWORD_FILE + GPU=virtio + RDP=Y: ok"
docker rm -f "$C3" >/dev/null

# ==============================================================================
# 3b. Built-in HTTPS/WSS (WEB_TLS=Y) + persisted self-signed ECDSA cert + WSS
# ==============================================================================
mkdir -p "${TMPDIR_SMOKE}/storage-tls"
C5="fnxvm-smoke-c5-${TAG_PID}"
CONTAINERS+=("$C5")
docker run -d \
  --name "$C5" \
  -p 127.0.0.1::8006 \
  -p 127.0.0.1::5900 \
  -v "${TMPDIR_SMOKE}/boot.img:/boot.img" \
  -v "${TMPDIR_SMOKE}/storage-tls:/storage" \
  -v "${TMPDIR_SMOKE}/secrets/web_pw:/run/secrets/web_pw:ro" \
  -v "${TMPDIR_SMOKE}/secrets/vnc_pw:/run/secrets/vnc_pw:ro" \
  -e WEB_TLS=Y \
  -e WEB_TLS_SAN="DNS:vm.example.test,IP:192.0.2.10" \
  -e WEB_USER=tlsadmin \
  -e WEB_PASSWORD_FILE=/run/secrets/web_pw \
  -e VNC_PASSWORD_FILE=/run/secrets/vnc_pw \
  -e KVM=N \
  -e NETWORK=user \
  -e RAM_SIZE=256M \
  -e CPU_CORES=1 \
  -e DISK_SIZE=1G \
  -e BOOT_MODE=uefi \
  "$IMAGE" >/dev/null

echo -n "healthcheck (WEB_TLS=Y self-signed HTTPS/WSS): "
wait_healthy "$C5"
echo "healthy"
wait_qemu_ready "$C5"

TLS_CRT="${TMPDIR_SMOKE}/storage-tls/.fnxvm-tls.crt"
TLS_KEY="${TMPDIR_SMOKE}/storage-tls/.fnxvm-tls.key"
test -s "$TLS_CRT" && test -s "$TLS_KEY" || { echo "missing persisted TLS cert/key" >&2; exit 1; }
[ "$(stat -c '%a' "$TLS_KEY")" = "600" ] || { echo "expected 0600 on ${TLS_KEY}" >&2; exit 1; }
TLS_TEXT="$(openssl x509 -in "$TLS_CRT" -noout -text)"
echo "$TLS_TEXT" | grep -q "DNS:vm.example.test" || { echo "missing custom DNS SAN in TLS cert" >&2; exit 1; }
echo "$TLS_TEXT" | grep -q "IP Address:192.0.2.10" || { echo "missing custom IP SAN in TLS cert" >&2; exit 1; }
TLS_FP_1="$(openssl x509 -in "$TLS_CRT" -noout -fingerprint -sha256)"

WEB_PORT_5="$(docker port "$C5" 8006/tcp | head -n 1 | awk -F: '{print $NF}')"
VNC_PORT_5="$(docker port "$C5" 5900/tcp | head -n 1 | awk -F: '{print $NF}')"
[ "$(curl -ksS -o /dev/null -w '%{http_code}' "https://127.0.0.1:${WEB_PORT_5}/")" = "401" ]
[ "$(curl -ksS -u "tlsadmin:invalid" -o /dev/null -w '%{http_code}' "https://127.0.0.1:${WEB_PORT_5}/")" = "401" ]
[ "$(curl -ksS -u "tlsadmin:${SMOKE_WEB_PW}" -o /dev/null -w '%{http_code}' "https://127.0.0.1:${WEB_PORT_5}/")" = "200" ]
check_ws_upgrade "$WEB_PORT_5" "" "" "401" "1"
check_ws_upgrade "$WEB_PORT_5" "tlsadmin" "$SMOKE_WEB_PW" "101" "1"

if [ -n "$PLAYWRIGHT_PY" ]; then
  "$PLAYWRIGHT_PY" "${SCRIPT_DIR}/test_novnc_playwright.py" \
    --web-url "https://127.0.0.1:${WEB_PORT_5}" \
    --web-user tlsadmin \
    --web-password "$SMOKE_WEB_PW" \
    --vnc-host 127.0.0.1 \
    --vnc-port "$VNC_PORT_5" \
    --vnc-password "$SMOKE_VNC_PW" \
    --tls-only
fi
docker rm -f "$C5" >/dev/null

# Verify persisted TLS certificate is reused across restarts
C5B="fnxvm-smoke-c5b-${TAG_PID}"
CONTAINERS+=("$C5B")
docker run -d \
  --name "$C5B" \
  -p 127.0.0.1::8006 \
  -v "${TMPDIR_SMOKE}/boot.img:/boot.img" \
  -v "${TMPDIR_SMOKE}/storage-tls:/storage" \
  -v "${TMPDIR_SMOKE}/secrets/web_pw:/run/secrets/web_pw:ro" \
  -v "${TMPDIR_SMOKE}/secrets/vnc_pw:/run/secrets/vnc_pw:ro" \
  -e WEB_TLS=Y \
  -e WEB_USER=tlsadmin \
  -e WEB_PASSWORD_FILE=/run/secrets/web_pw \
  -e VNC_PASSWORD_FILE=/run/secrets/vnc_pw \
  -e KVM=N \
  -e NETWORK=user \
  -e RAM_SIZE=256M \
  -e CPU_CORES=1 \
  -e DISK_SIZE=1G \
  -e BOOT_MODE=uefi \
  "$IMAGE" >/dev/null
wait_healthy "$C5B"
TLS_FP_2="$(openssl x509 -in "$TLS_CRT" -noout -fingerprint -sha256)"
[ "$TLS_FP_1" = "$TLS_FP_2" ] || { echo "TLS cert changed across restart!" >&2; exit 1; }
echo "WEB_TLS=Y (HTTPS/WSS 401/200/101, SAN, 0600 key, cert persistence): ok"
docker rm -f "$C5B" >/dev/null

# ==============================================================================
# 4. GPU=virgl without /dev/dri (graceful fallback, no crash) + CLIPBOARD=N + WEB_AUTH=N
# ==============================================================================
C4="fnxvm-smoke-c4-${TAG_PID}"
CONTAINERS+=("$C4")
docker run -d \
  --name "$C4" \
  -p 127.0.0.1::8006 \
  -p 127.0.0.1::5900 \
  -v "${TMPDIR_SMOKE}/boot.img:/boot.img" \
  -e GPU=virgl \
  -e CLIPBOARD=N \
  -e WEB_AUTH=N \
  -e KVM=N \
  -e NETWORK=user \
  -e RAM_SIZE=256M \
  -e CPU_CORES=1 \
  -e DISK_SIZE=1G \
  -e BOOT_MODE=uefi \
  "$IMAGE" >/dev/null

wait_healthy "$C4"
wait_qemu_ready "$C4"

C4_LOGS="$(docker logs "$C4" 2>&1)"
echo "$C4_LOGS" | grep -qi "falling back to software rendering" || {
  echo "expected VirGL fallback warning in logs" >&2
  echo "$C4_LOGS" >&2
  exit 1
}
echo "$C4_LOGS" | grep -qi "WEB_AUTH=N" || {
  echo "expected loud WEB_AUTH=N warning in logs" >&2
  echo "$C4_LOGS" >&2
  exit 1
}

WEB_PORT_4="$(docker port "$C4" 8006/tcp | head -n 1 | awk -F: '{print $NF}')"
VNC_PORT_4="$(docker port "$C4" 5900/tcp | head -n 1 | awk -F: '{print $NF}')"
[ "$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${WEB_PORT_4}/")" = "200" ]
check_vnc_requires_auth "$VNC_PORT_4"

docker exec "$C4" bash -ceu '
  qpid="$(tr -d "[:space:]" < /run/shm/qemu.pid)"
  cmdline="$(tr "\0" " " < "/proc/${qpid}/cmdline")"
  if echo "$cmdline" | grep -q "qemu-vdagent" || echo "$cmdline" | grep -q "com.redhat.spice.0"; then
    echo "ERROR: clipboard devices present despite CLIPBOARD=N" >&2
    exit 1
  fi
'
echo "GPU=virgl fallback without /dev/dri + CLIPBOARD=N + WEB_AUTH=N: ok"
docker rm -f "$C4" >/dev/null

# ==============================================================================
# 5. Negative healthcheck, non-root vmuser, and fail-fast input validation
# ==============================================================================
if docker run --rm --entrypoint /usr/local/bin/fnxvm-healthcheck "$IMAGE" >/dev/null 2>&1; then
  echo "negative healthcheck test failed: expected non-zero exit when web server is stopped" >&2
  exit 1
fi
echo "negative healthcheck test: ok"

nonroot_user="$(docker run --rm --user vmuser --entrypoint whoami "$IMAGE")"
[ "$nonroot_user" = "vmuser" ] || { echo "unexpected non-root user: ${nonroot_user}" >&2; exit 1; }
docker run --rm --user vmuser --entrypoint fnxvm-resolve "$IMAGE" --list | grep -q "daemonarchy"
echo "non-root (vmuser) execution: ok"

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

if err_out="$(docker run --rm -e GPU=not-a-valid-gpu "$IMAGE" 2>&1)"; then
  echo "expected invalid GPU to fail fast" >&2
  exit 1
fi
echo "$err_out" | grep -qi "Valid GPU values" || { echo "missing valid GPU list in error: $err_out" >&2; exit 1; }
echo "negative invalid GPU test: ok"

# Resolver dry-run via entrypoint (RESOLVE_ONLY=1) and custom BOOT URL.
docker run --rm -e RESOLVE_ONLY=1 -e OS=debian -e DESKTOP=gnome "$IMAGE" | grep -q "^ISO URL:"
docker run --rm -e RESOLVE_ONLY=1 -e BOOT="https://example.invalid/custom.iso" "$IMAGE" | grep -q "https://example.invalid/custom.iso"
echo "RESOLVE_ONLY=1 and custom BOOT: ok"

# Windows unattended spice-vdagent staging helper: live official SHA-256 verify + fail-closed mismatch test
docker run --rm --entrypoint bash "$IMAGE" -ceu '
  . /run/utils.sh
  . /run/windows/answer.sh
  stage="$(mktemp -d)"
  trap "rm -rf \"$stage\"" EXIT
  stageWindowsVdagent "/run/assets/win11x64.xml" "$stage"
  test -s "$stage/\$OEM\$/\$\$/Setup/Scripts/spice-vdagent.msi"
  stageSetupCompleteWrapper "$stage"
  grep -q "spice-vdagent.msi" "$stage/\$OEM\$/\$\$/Setup/Scripts/SetupComplete.cmd"
  # Negative test: corrupted payload must fail closed
  bad="$stage/bad.msi"
  printf "corrupted" > "$bad"
  if verifyWindowsVdagentSha256 "$bad" "spice-vdagent-x64-0.10.0.msi" "77629435705bc27dd7d2525e9d2084f72dbab5fdbf310e812f91332fe18d00eb" "" 2>/dev/null; then
    echo "ERROR: verifyWindowsVdagentSha256 accepted corrupted file!" >&2
    exit 1
  fi
'
echo "Windows unattended spice-vdagent MSI staging + fail-closed SHA-256 test: ok"

# ==============================================================================
# 6. Bundled vendor GPG keyrings + live signature & checksum verification
# ==============================================================================
echo "==> vendor GPG keyring & live signature/checksum verification (${ARCH})"
GH_ENV_ARGS=()
if [ -n "${GH_TOKEN:-}" ]; then
  GH_ENV_ARGS=(-e GH_TOKEN)
fi

# Cross-check extracted binary keyrings with host gpg --import (if installed) to
# confirm GnuPG itself imports every pinned primary key with a valid User ID.
if command -v gpg >/dev/null 2>&1; then
  for spec in \
    "debian-cd.gpg:10460DAD76165AD81FBC0CE9988021A964E6EA7D,DF9B9C49EAA9298432589D76DA87E80D6294BE9B,F41D30342F3546695F65C66942468F4009EA8AC3" \
    "ubuntu-cd.gpg:843938DF228D22F7B3742BC0D94AA3F0EFE21092" \
    "omarchy.gpg:40DFB630FF42BCFFB047046CF0134EE680CAC571"; do
    kfile="${spec%%:*}"
    fprs="${spec#*:}"
    khome="$(mktemp -d "${TMPDIR_SMOKE}/gnupg-${kfile}.XXXXXX")"
    chmod 700 "$khome"
    docker run --rm --entrypoint cat "$IMAGE" "/etc/fnxvm/keys/${kfile}" > "${khome}/${kfile}"
    GNUPGHOME="$khome" gpg --batch --import "${khome}/${kfile}"
    klist="$(GNUPGHOME="$khome" gpg --batch --list-keys --with-colons --with-fingerprint)"
    grep -q '^uid:' <<< "$klist" || { echo "ERROR: ${kfile} has no UID after gpg --import!" >&2; exit 1; }
    IFS=',' read -r -a fpr_arr <<< "$fprs"
    for fpr in "${fpr_arr[@]}"; do
      grep -q "^fpr:::::::::${fpr}:$" <<< "$klist" || {
        echo "ERROR: expected fingerprint ${fpr} missing from ${kfile}!" >&2
        echo "$klist" >&2
        exit 1
      }
    done
    echo "host gpg --import cross-check (${kfile}): ok"
  done
fi

# Execute full keyring + live gpgv (Debian amd64/arm64, Ubuntu amd64/arm64,
# Omarchy) + Daemonarchy/FreeBSD/Haiku checksum-file verification INSIDE the image.
docker run --rm -i "${GH_ENV_ARGS[@]}" --entrypoint python3 "$IMAGE" - < "${SCRIPT_DIR}/test_verify_keyrings.py"

# Execute redirect pre-resolution, mirror fallback, and non-Range downgrade tests INSIDE the image.
docker run --rm -i --entrypoint python3 "$IMAGE" - < "${SCRIPT_DIR}/test_download_redirects.py"

# ==============================================================================
# 7. Full dynamic OS resolver + HTTP 200 verification for all 7 supported guests
# ==============================================================================
echo "==> resolver HTTP 200 verification (${ARCH})"

docker run --rm "${GH_ENV_ARGS[@]}" --entrypoint fnxvm-resolve "$IMAGE" debian --arch "$ARCH" --desktop gnome --verify-urls
docker run --rm "${GH_ENV_ARGS[@]}" --entrypoint fnxvm-resolve "$IMAGE" debian --arch "$ARCH" --desktop kde --verify-urls
docker run --rm "${GH_ENV_ARGS[@]}" --entrypoint fnxvm-resolve "$IMAGE" ubuntu --arch "$ARCH" --verify-urls
docker run --rm "${GH_ENV_ARGS[@]}" --entrypoint fnxvm-resolve "$IMAGE" freebsd --arch "$ARCH" --verify-urls
docker run --rm "${GH_ENV_ARGS[@]}" --entrypoint fnxvm-resolve "$IMAGE" daemonarchy --arch "$ARCH" --verify-urls
docker run --rm "${GH_ENV_ARGS[@]}" --entrypoint fnxvm-resolve "$IMAGE" omarchy --arch "$ARCH" --verify-urls
docker run --rm "${GH_ENV_ARGS[@]}" --entrypoint fnxvm-resolve "$IMAGE" windows --arch "$ARCH" --version 11 --verify-urls
docker run --rm "${GH_ENV_ARGS[@]}" --entrypoint fnxvm-resolve "$IMAGE" windows --arch "$ARCH" --version ltsc --verify-urls

if [ "$ARCH" = "amd64" ]; then
  docker run --rm "${GH_ENV_ARGS[@]}" --entrypoint fnxvm-resolve "$IMAGE" haiku --arch amd64 --verify-urls
else
  if docker run --rm "${GH_ENV_ARGS[@]}" --entrypoint fnxvm-resolve "$IMAGE" haiku --arch arm64 >/dev/null 2>&1; then
    echo "expected Haiku on arm64 to fail fast" >&2
    exit 1
  fi
  docker run --rm "${GH_ENV_ARGS[@]}" --entrypoint fnxvm-resolve "$IMAGE" haiku --arch amd64 --verify-urls
fi

echo "==> smoke: PASS"
