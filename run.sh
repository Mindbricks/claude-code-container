#!/usr/bin/env bash
set -euo pipefail

_script="${BASH_SOURCE[0]}"
[[ -L "$_script" ]] && _script="$(readlink "$_script")"
SCRIPT_DIR="$(cd "$(dirname "$_script")" && pwd)"
IMAGE="${CLAUDE_DOCKER_IMAGE:-claude-code:latest}"
HOST_CWD="$(pwd -P)"
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_JSON="${HOME}/.claude.json"
CLIPBOARD_HOST="${CLIPBOARD_HOST:-host.docker.internal}"
CLIPBOARD_PORT="${CLIPBOARD_PORT:-18256}"
CLIPBOARD_SERVER="${SCRIPT_DIR}/clipboard-server.py"
CLIPBOARD_DEBUG="${CLIPBOARD_DEBUG:-}"
CLIPBOARD_LOG="${CLAUDE_CONFIG_DIR}/clipboard-server.log"

# Derive timezone from the host symlink, e.g. /var/db/timezone/zoneinfo/Europe/Istanbul.
_tz="$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')"

# Ensure host-side paths exist before mounting.
mkdir -p "$CLAUDE_CONFIG_DIR" "$HOME/.cache"
touch "$CLAUDE_JSON"

# ── Clipboard bridge ──────────────────────────────────────────────────────────
# Start a background server on the host that exposes the macOS clipboard over TCP 127.0.0.1:PORT.
# Containers reach it via host.docker.internal:PORT.

_clipboard_server_alive() {
    python3 - <<EOF 2>/dev/null
import socket, sys
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(1)
    s.connect(("127.0.0.1", ${CLIPBOARD_PORT}))
    s.sendall(b"PING\n")
    data = s.recv(16)
    s.close()
    sys.exit(0 if data.strip() == b"PONG" else 1)
except Exception:
    sys.exit(1)
EOF
}

if [[ -f "$CLIPBOARD_SERVER" ]] && command -v python3 &>/dev/null; then
    if ! _clipboard_server_alive; then
        echo "[clipboard] starting server on port ${CLIPBOARD_PORT}" >> "$CLIPBOARD_LOG"
        CLIPBOARD_PORT="$CLIPBOARD_PORT" CLIPBOARD_DEBUG="$CLIPBOARD_DEBUG" \
            python3 "$CLIPBOARD_SERVER" >>"$CLIPBOARD_LOG" 2>&1 &
        _srv_pid=$!
        disown "$_srv_pid" 2>/dev/null || true
        # Wait up to 1 s for the server to be ready.
        for _i in $(seq 1 10); do
            sleep 0.1
            _clipboard_server_alive && break
        done
    fi

    if _clipboard_server_alive; then
        echo "[clipboard] server alive on port ${CLIPBOARD_PORT}" >> "$CLIPBOARD_LOG"
    else
        echo "[clipboard] server failed to start — image paste unavailable" >> "$CLIPBOARD_LOG"
        echo "clipboard-server: could not start, image paste will be unavailable" >&2
    fi
else
    [[ -f "$CLIPBOARD_SERVER" ]] || echo "[clipboard] server script not found: ${CLIPBOARD_SERVER}" >> "$CLIPBOARD_LOG"
    command -v python3 &>/dev/null || echo "[clipboard] python3 not found" >> "$CLIPBOARD_LOG"
fi
# ─────────────────────────────────────────────────────────────────────────────

DOCKER_FLAGS=("--rm")

# Container name: claude-<normalized_relative_path>-m.d.H.M
# Strip $HOME prefix (static across all sessions), normalize remaining path.
_raw="${HOST_CWD#"$HOME/"}"         # strip $HOME/ prefix if present
_raw="${_raw#/}"                    # strip any remaining leading /
_raw="${_raw//\//_}"                # / → _
_raw="${_raw//[^a-zA-Z0-9_]/}"      # remove everything else (hyphens, dots, etc.)
[[ ${#_raw} -gt 40 ]] && _raw="${_raw: -40}"  # keep rightmost 40 chars if too long
_raw="${_raw#_}"                    # drop leading _ from truncation
[[ -z "$_raw" ]] && _raw="$(basename "$HOST_CWD")"  # fallback for root or edge cases
_ts="$(date '+%m.%d.%H.%M')"
CONTAINER_NAME="claude-${_raw}-${_ts}"
DOCKER_FLAGS+=("--name" "$CONTAINER_NAME")

# Only attach a TTY when stdin and stdout are both terminals.
if [ -t 0 ] && [ -t 1 ]; then
    DOCKER_FLAGS+=("-it")
elif [ -t 0 ]; then
    DOCKER_FLAGS+=("-i")
fi

DOCKER_FLAGS+=(
    "-e" "HOME=${HOME}"
    "-e" "USER=${USER:-user}"
    "-e" "TERM=${TERM:-xterm-256color}"
    "-e" "CLIPBOARD_HOST=${CLIPBOARD_HOST}"
    "-e" "CLIPBOARD_PORT=${CLIPBOARD_PORT}"
    "-e" "CLIPBOARD_DEBUG=${CLIPBOARD_DEBUG}"
    ${_tz:+"-e" "TZ=${_tz}"}

    # Mount CWD at the same absolute path so all file references stay valid.
    "-v" "${HOST_CWD}:${HOST_CWD}:z"
    "-w" "${HOST_CWD}"

    # Claude config and state (clipboard logs also land here).
    "-v" "${CLAUDE_CONFIG_DIR}:${CLAUDE_CONFIG_DIR}:z"
    "-v" "${CLAUDE_JSON}:${CLAUDE_JSON}:z"

    # Cache (shared across sessions for performance).
    "-v" "${HOME}/.cache:${HOME}/.cache:z"
)

# Optional read-only mounts — skipped silently if the path doesn't exist.
for OPTIONAL in \
    "$HOME/.gitconfig" \
    "$HOME/.gitignore.global" \
    "$HOME/.ssh" \
    "$HOME/.npmrc" \
    "$HOME/.config/gh"
do
    if [ -e "$OPTIONAL" ]; then
        DOCKER_FLAGS+=("-v" "${OPTIONAL}:${OPTIONAL}:ro,z")
    fi
done

docker run "${DOCKER_FLAGS[@]}" "$IMAGE" "$@"
