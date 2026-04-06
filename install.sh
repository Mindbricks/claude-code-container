#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
INSTALL_AS="${INSTALL_AS:-claude}"
TARGET="${INSTALL_DIR}/${INSTALL_AS}"

mkdir -p "$INSTALL_DIR"

# Symlink back to the repo so updates to run.sh propagate automatically.
ln -sf "${SCRIPT_DIR}/run.sh" "$TARGET"
chmod +x "${SCRIPT_DIR}/run.sh"

echo "Installed: ${TARGET} -> ${SCRIPT_DIR}/run.sh"

# Warn if the install directory isn't on PATH.
if ! printf '%s\n' "${PATH//:/$'\n'}" | grep -qx "$INSTALL_DIR"; then
    echo ""
    echo "WARNING: ${INSTALL_DIR} is not in your PATH."
    echo "Add this to your shell config (~/.bashrc, ~/.zshrc, etc.):"
    echo ""
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
