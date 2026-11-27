#!/usr/bin/env bash
set -Eeuo pipefail

: "${VNC_PORT:="5900"}"    # VNC port
: "${WEB_PORT:="8006"}"    # Webserver port
: "${WEB_AUTH:="Y"}"       # Require HTTP Basic Auth on WEB_PORT (default Y)
: "${WEB_USER:="fnxvm"}"   # HTTP Basic Auth username (separate from Windows USERNAME)

# Sanitize variables
VNC_PORT=$(strip "$VNC_PORT")
WEB_PORT=$(strip "$WEB_PORT")
WEB_AUTH=$(strip "$WEB_AUTH")
WEB_USER=$(strip "$WEB_USER")
[ -z "$WEB_USER" ] && WEB_USER="fnxvm"

# Preserve root storage directory before OS-specific install scripts namespace STORAGE.
AUTH_STORAGE="${STORAGE:-/storage}"
HTPASSWD_PERSIST="${AUTH_STORAGE}/.fnxvm-web.htpasswd"
HTPASSWD_RUNTIME="/etc/nginx/.htpasswd"
VNC_PASSWORD_TMP="${QEMU_DIR}/.vnc-password"
HEALTH_SOCKET="${QEMU_DIR}/nginx-health.sock"

WEB_PID="/run/nginx.pid"
WSD_PID="$QEMU_DIR/websocketd.pid"
AUX_PID="$QEMU_DIR/audio-websocketd.pid"

export WSS_SOCKET="$QEMU_DIR/vnc-ws.sock"
AUX_SOCKET="$QEMU_DIR/audio-ws.sock"
WSD_SOCKET="$QEMU_DIR/status-ws.sock"

WSD_LOG="/var/log/websocketd.log"
AUX_LOG="/var/log/audio-socket.log"

WSD_COMMAND="$QEMU_DIR/status.cmd"

GENERATED_SECRET=""
RESOLVED_WEB_PASSWORD=""

generateRandomSecret() {

  local length="${1:-24}"
  python3 -c '
import secrets, string, sys
n = int(sys.argv[1])
alphabet = string.ascii_letters + string.digits
print("".join(secrets.choice(alphabet) for _ in range(n)), end="")
' "$length"
}

readSecretFile() {

  local var_name="$1"
  local file_path="$2"

  if [ ! -f "$file_path" ] || [ ! -r "$file_path" ]; then
    error "${var_name} points to '${file_path}', which does not exist or is unreadable."
    exit 2
  fi

  local value
  value="$(tr -d '\r' < "$file_path")"
  # Strip trailing newlines while preserving internal whitespace.
  while [[ "$value" == *$'\n' ]]; do
    value="${value%$'\n'}"
  done

  if [ -z "$value" ]; then
    error "${var_name} ('${file_path}') is empty."
    exit 2
  fi

  printf '%s' "$value"
}

writeHtpasswdAtomic() {

  local dest="$1"
  local content="$2"
  local tmp="${dest}.tmp.$$"

  (
    umask 077
    printf '%s\n' "$content" > "$tmp"
    chmod 0600 "$tmp"
    mv -f -- "$tmp" "$dest"
  )
}

configureWebServer() {

  configureNginx || return 1
  configureAuthentication || return 1
  configureWebPorts || return 1
  configureIpv6Listen || return 1

  return 0
}

configureNginx() {

  mkdir -p /etc/nginx/sites-enabled || return 1
  rm -f /etc/nginx/sites-enabled/default || return 1

  # TODO: Use setfacl to grant www-data access to the Unix sockets
  # and restore unprivileged nginx workers.
  if ! sed -i \
    -e 's/^user .*/user root;/' \
    -e 's/^worker_processes.*/worker_processes 1;/' \
    /etc/nginx/nginx.conf; then
    error "Failed to configure nginx!"
    return 1
  fi

  if ! cp /etc/nginx/default.conf /etc/nginx/sites-enabled/web.conf; then
    error "Failed to copy nginx config!"
    return 1
  fi

  return 0
}

configureWebPorts() {

  if ! sed -i \
    -E "s|listen [0-9]+ default_server;|listen $WEB_PORT default_server;|g" \
    /etc/nginx/sites-enabled/web.conf; then
    error "Failed to configure webserver port!"
    return 1
  fi

  return 0
}

configureIpv6Listen() {

  if [ -f /proc/net/if_inet6 ] && [[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)" != "1" ]]; then

    # Use one dual-stack socket when IPv6 is available; ipv6only=off keeps IPv4
    # clients working on the same configured WEB_PORT.
    if ! sed -i \
      "s/listen $WEB_PORT default_server;/listen [::]:$WEB_PORT default_server ipv6only=off;/g" \
      /etc/nginx/sites-enabled/web.conf; then
      error "Failed to configure IPv6 webserver listener!"
      return 1
    fi

  fi

  return 0
}

configureAuthentication() {

  if [ -n "${PROTECT:-}" ] || [ -n "${PASS:-}" ]; then
    warn "Legacy PROTECT/PASS environment variables are deprecated; use WEB_AUTH, WEB_USER, WEB_PASSWORD, or WEB_PASSWORD_FILE."
  fi

  if disabled "$WEB_AUTH"; then
    {
      echo "======================================================================"
      echo "WARNING: WEB_AUTH=N — Web UI HTTP Basic Authentication is DISABLED!"
      echo "Port ${WEB_PORT} (including /websockify) is accessible WITHOUT credentials."
      echo "Do NOT expose port ${WEB_PORT} to untrusted networks without an"
      echo "external authenticating reverse proxy."
      echo "======================================================================"
    } >&2

    if ! sed -i 's/auth_basic "FNXVM";/auth_basic off;/g' /etc/nginx/sites-enabled/web.conf; then
      error "Failed to disable web authentication!"
      return 1
    fi
    return 0
  fi

  if [[ "$WEB_USER" == *:* || "$WEB_USER" == *$'\n'* ]]; then
    error "WEB_USER must not contain colons or newlines."
    exit 2
  fi

  local explicit_pw=""
  if [ -n "${WEB_PASSWORD_FILE:-}" ]; then
    explicit_pw="$(readSecretFile "WEB_PASSWORD_FILE" "$WEB_PASSWORD_FILE")"
  elif [ -n "${WEB_PASSWORD:-}" ]; then
    explicit_pw="$WEB_PASSWORD"
  fi

  if [ -n "$explicit_pw" ]; then
    RESOLVED_WEB_PASSWORD="$explicit_pw"
    local entry
    if ! entry="$(printf '%s' "$explicit_pw" | htpasswd -niB -C 10 "$WEB_USER" 2>/dev/null)"; then
      error "Failed to generate bcrypt htpasswd entry!"
      return 1
    fi
    writeHtpasswdAtomic "$HTPASSWD_RUNTIME" "$entry" || {
      error "Failed to write ${HTPASSWD_RUNTIME}!"
      return 1
    }
    writeHtpasswdAtomic "$HTPASSWD_PERSIST" "$entry" || {
      error "Failed to persist bcrypt hash to ${HTPASSWD_PERSIST}!"
      return 1
    }
    setOwner "$HTPASSWD_PERSIST" || true
    info "Web UI authentication enabled (HTTP Basic + bcrypt) for user '${WEB_USER}'."
    return 0
  fi

  # No explicit WEB_PASSWORD / WEB_PASSWORD_FILE: reuse persisted bcrypt hash if present.
  if [ -s "$HTPASSWD_PERSIST" ] && grep -Eq '^[^:]+:\$2[aby]\$[0-9]{2}\$' "$HTPASSWD_PERSIST"; then
    (
      umask 077
      cp -f -- "$HTPASSWD_PERSIST" "$HTPASSWD_RUNTIME"
      chmod 0600 "$HTPASSWD_RUNTIME"
    ) || {
      error "Failed to load persisted web credentials from ${HTPASSWD_PERSIST}!"
      return 1
    }
    local persisted_user
    persisted_user="$(cut -d: -f1 "$HTPASSWD_PERSIST" | head -n 1)"
    info "Web UI authentication enabled using persisted bcrypt hash for user '${persisted_user}' (${HTPASSWD_PERSIST})."
    info "To rotate credentials, remove ${HTPASSWD_PERSIST} and restart, or set WEB_PASSWORD_FILE / WEB_PASSWORD."
    return 0
  fi

  # First start with no explicit password: generate a strong random password,
  # persist ONLY its bcrypt hash under /storage, and print plaintext once.
  GENERATED_SECRET="$(generateRandomSecret 24)"
  RESOLVED_WEB_PASSWORD="$GENERATED_SECRET"

  local entry
  if ! entry="$(printf '%s' "$GENERATED_SECRET" | htpasswd -niB -C 10 "$WEB_USER" 2>/dev/null)"; then
    error "Failed to generate bcrypt htpasswd entry for first-start password!"
    return 1
  fi

  writeHtpasswdAtomic "$HTPASSWD_RUNTIME" "$entry" || {
    error "Failed to write ${HTPASSWD_RUNTIME}!"
    return 1
  }
  writeHtpasswdAtomic "$HTPASSWD_PERSIST" "$entry" || {
    error "Failed to persist bcrypt hash to ${HTPASSWD_PERSIST}!"
    return 1
  }
  setOwner "$HTPASSWD_PERSIST" || true

  return 0
}

configureVncPassword() {

  local vnc_pw=""
  local vnc_source=""

  if [ -n "${VNC_PASSWORD_FILE:-}" ]; then
    vnc_pw="$(readSecretFile "VNC_PASSWORD_FILE" "$VNC_PASSWORD_FILE")"
    vnc_source="explicit"
  elif [ -n "${VNC_PASSWORD:-}" ]; then
    vnc_pw="$VNC_PASSWORD"
    vnc_source="explicit"
  elif [ -n "$GENERATED_SECRET" ]; then
    vnc_pw="${GENERATED_SECRET:0:8}"
    vnc_source="generated_shared"
  elif [ -n "$RESOLVED_WEB_PASSWORD" ]; then
    vnc_pw="${RESOLVED_WEB_PASSWORD:0:8}"
    vnc_source="web_shared"
  else
    vnc_pw="$(generateRandomSecret 8)"
    vnc_source="ephemeral"
  fi

  if [ "${#vnc_pw}" -gt 8 ]; then
    warn "VNC RFB protocol supports at most 8 characters; using the first 8 characters of VNC password."
    vnc_pw="${vnc_pw:0:8}"
  fi

  # Store ephemeral VNC password on tmpfs (mode 0600); /run/set-vnc-password.py
  # reads it, unlinks it immediately, and applies it to QEMU via QMP set_password.
  writeHtpasswdAtomic "$VNC_PASSWORD_TMP" "$vnc_pw" || {
    error "Failed to stage ephemeral VNC password!"
    return 1
  }
  export VNC_PASSWORD_TMP

  if [ -n "$GENERATED_SECRET" ]; then
    echo
    echo "======================================================================"
    echo "FNXVM first-start credentials (printed ONCE — save now!):"
    echo "  Web UI (port ${WEB_PORT}, HTTP Basic Auth):"
    echo "    Username: ${WEB_USER}"
    echo "    Password: ${GENERATED_SECRET}"
    if [ "$vnc_source" = "generated_shared" ]; then
      echo "  VNC (port ${VNC_PORT}, RFB max 8 chars, derived from generated secret):"
      echo "    Password: ${vnc_pw}"
    else
      echo "  VNC (port ${VNC_PORT}): using configured VNC_PASSWORD / VNC_PASSWORD_FILE."
    fi
    echo "  Only the Web UI bcrypt hash is persisted in ${HTPASSWD_PERSIST}."
    echo "  To rotate: delete ${HTPASSWD_PERSIST} and restart, or set"
    echo "  WEB_PASSWORD_FILE / WEB_PASSWORD (and VNC_PASSWORD_FILE / VNC_PASSWORD)."
    echo "======================================================================"
    echo
  else
    case "$vnc_source" in
      "explicit" )
        info "VNC authentication enabled on port ${VNC_PORT} (using configured VNC password)." ;;
      "web_shared" )
        info "VNC authentication enabled on port ${VNC_PORT} (using first 8 characters of WEB_PASSWORD; RFB limit is 8 chars)." ;;
      "ephemeral" )
        echo "❯ VNC authentication (port ${VNC_PORT}): no VNC_PASSWORD set and persisted web credentials are hash-only."
        echo "❯ Ephemeral VNC session password (RFB max 8 chars): ${vnc_pw}"
        echo "❯ Set VNC_PASSWORD_FILE or VNC_PASSWORD for a fixed VNC password." ;;
    esac
  fi

  # Clear plaintext secrets from shell environment immediately.
  GENERATED_SECRET=""
  RESOLVED_WEB_PASSWORD=""
  vnc_pw=""

  return 0
}

startWebServer() {

  # Start webserver
  nginx -e stderr || return 1

  return 0
}

stopWebServer() {

  local pid

  if readPidFile pid "$WEB_PID"; then

    pKill "$pid" 2

    if isAlive "$pid"; then
      kill -9 -- "$pid" 2>/dev/null || :
    fi

  fi

  rm -f -- "$WEB_PID" "$HEALTH_SOCKET"
  return 0
}

startWebsocketServer() {

  # Start websocket server
  websocketd \
    --unixsocket="$WSD_SOCKET" \
    /run/socket.sh \
    >"$WSD_LOG" 2>&1 &

  local pid=$!

  if ! echo "$pid" > "$WSD_PID"; then
    kill "$pid" 2>/dev/null || :
    rm -f -- "$WSD_PID"
    return 1
  fi

  local i
  for (( i = 1; i <= 50; i++ )); do

    if ! isAlive "$pid"; then
      rm -f -- "$WSD_PID" "$WSD_SOCKET"
      [ -s "$WSD_LOG" ] && cat "$WSD_LOG" >&2
      error "Failed to start websocket server!"
      return 1
    fi

    [ -S "$WSD_SOCKET" ] && return 0

    sleep 0.1

  done

  pKill "$pid" 2

  if isAlive "$pid"; then
    kill -9 -- "$pid" 2>/dev/null || :
  fi

  rm -f -- "$WSD_PID" "$WSD_SOCKET"
  [ -s "$WSD_LOG" ] && cat "$WSD_LOG" >&2

  error "Websocket server did not create its socket!"
  return 1
}

stopWebsocketServer() {

  local pid

  if readPidFile pid "$WSD_PID"; then

    pKill "$pid" 2

    if isAlive "$pid"; then
      kill -9 -- "$pid" 2>/dev/null || :
    fi

  fi

  rm -f -- "$WSD_PID" "$WSD_SOCKET"
  return 0
}

startAudioServer() {

  # Start audio websocket server
  websocketd \
    --unixsocket="$AUX_SOCKET" \
    --binary=true \
    nc -U "$AUDIO_SOCKET" \
    >"$AUX_LOG" 2>&1 &

  local pid=$!

  if ! echo "$pid" > "$AUX_PID"; then
    kill "$pid" 2>/dev/null || :
    rm -f -- "$AUX_PID"
    return 1
  fi

  local i
  for (( i = 1; i <= 50; i++ )); do

    if ! isAlive "$pid"; then
      rm -f -- "$AUX_PID" "$AUX_SOCKET"
      [ -s "$AUX_LOG" ] && cat "$AUX_LOG" >&2
      error "Failed to start audio websocket server!"
      return 1
    fi

    [ -S "$AUX_SOCKET" ] && return 0

    sleep 0.1

  done

  pKill "$pid" 2

  if isAlive "$pid"; then
    kill -9 -- "$pid" 2>/dev/null || :
  fi

  rm -f -- "$AUX_PID" "$AUX_SOCKET"
  [ -s "$AUX_LOG" ] && cat "$AUX_LOG" >&2

  error "Audio websocket server did not create its socket!"
  return 1
}

stopAudioServer() {

  local pid

  if readPidFile pid "$AUX_PID"; then

    pKill "$pid" 2

    if isAlive "$pid"; then
      kill -9 -- "$pid" 2>/dev/null || :
    fi

  fi

  rm -f -- "$AUX_PID" "$AUX_SOCKET"
  return 0
}

cleanupServers() {

  rm -f -- \
    "$WSD_PID" "$AUX_PID" "$WEB_PID" \
    "$WSD_SOCKET" "$WSD_COMMAND" "$AUX_SOCKET" \
    "$HEALTH_SOCKET" "$VNC_PASSWORD_TMP" \
    "$WSD_LOG" "$AUX_LOG" || :

  return 0
}

stopAllServers() {

  local pids=( "${WEB_PID:-}" "${WSD_PID:-}" "${AUX_PID:-}")

  mKill "${pids[@]}"

  cleanupServers

  return 0
}

prepareWebFiles() {

  cleanupServers

  cp -r /var/www/* "$QEMU_DIR" || return 1

  return 0
}

validateVncPort() {

  if (( VNC_PORT < 5900 )); then
    warn "VNC port cannot be set lower than 5900, ignoring value $VNC_PORT."
    VNC_PORT="5900"
  fi

  return 0
}

validateVncPort
prepareWebFiles

html "Starting $APP for $ENGINE..."

if disabled "${WEB:-}"; then
  configureVncPassword || return 1
  return 0
fi

configureWebServer
configureVncPassword || return 1

if ! startWebServer || ! startWebsocketServer; then
  stopAllServers || return $?
  return 1
fi

return 0
