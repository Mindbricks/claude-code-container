#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMAGE_NAME="${CLAUDE_DOCKER_IMAGE:-claude-code}"
IMAGE_TAG="${1:-latest}"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building Docker image: ${FULL_IMAGE}"

BUILD_ARGS=()
if [ -n "${CLAUDE_VERSION:-}" ]; then
    BUILD_ARGS+=("--build-arg" "CLAUDE_VERSION=${CLAUDE_VERSION}")
fi

_old_id=$(docker inspect --format='{{.Id}}' "$FULL_IMAGE" 2>/dev/null || true)

docker build \
    --tag "$FULL_IMAGE" \
    "${BUILD_ARGS[@]}" \
    "$SCRIPT_DIR"

if [[ -n "$_old_id" ]] && [[ -z "$(docker ps -q --filter ancestor="$_old_id")" ]]; then
    docker rmi "$_old_id" &>/dev/null || true
fi

echo ""
echo "Build complete: ${FULL_IMAGE}"
echo "Run:  ${SCRIPT_DIR}/run.sh [args]"
echo "Or install globally: ${SCRIPT_DIR}/install.sh"
