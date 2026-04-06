#!/usr/bin/env bash
set -euo pipefail

IMAGE="${CLAUDE_DOCKER_IMAGE:-claude-code:latest}"
HOST_CWD="$(pwd -P)"
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_JSON="${HOME}/.claude.json"

# Ensure host-side paths exist before mounting.
mkdir -p "$CLAUDE_CONFIG_DIR" "$HOME/.cache"
touch "$CLAUDE_JSON"

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

    # Mount CWD at the same absolute path so all file references stay valid.
    "-v" "${HOST_CWD}:${HOST_CWD}:z"
    "-w" "${HOST_CWD}"

    # Claude config and state.
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
