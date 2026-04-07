# claude-code-container

A minimalist solution to run [Claude Code](https://github.com/anthropics/claude-code) in a sandboxed throwaway container, safely isolated from your host system while still having access to your project and necessary credentials.

- Supports **multiple simultaneous sessions** on the same project.
- **Telemetry is disabled** (via `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`).
- **Clipboard image paste** works inside the container (macOS only) — use Ctrl+V to paste screenshots, images copied from a browser, or image files copied from Finder.

## Requirements

- Docker or Podman

**For clipboard image paste:**

- macOS (the clipboard bridge relies on macOS-specific APIs)
- Python 3 (pre-installed on macOS; used to run the clipboard bridge server)
- [`pngpaste`](https://github.com/jcsalterego/pngpaste) _(recommended)_ — improves clipboard compatibility:

    ```bash
    brew install pngpaste
    ```

    Without it, the bridge falls back to AppleScript, which works but may be slower.

## Setup

**1. Build the image** (once):

```bash
./build.sh
```

To pin a specific Claude Code version or tag the image:

```bash
CLAUDE_VERSION=1.2.3 ./build.sh         # pin Claude Code version
./build.sh staging                      # tag image as claude-code:staging
```

**2. Install the launcher** (once):

```bash
./install.sh
```

This symlinks `run.sh` to `~/.local/bin/claude`.

To use a different command name (e.g. to keep a local `claude` install):

```bash
INSTALL_AS=claude-docker ./install.sh
```

## Usage

```bash
# From any project directory:
claude

# Pass arguments directly:
claude --version
claude "explain this codebase"

# Start a named session (useful when returning back to it later via --resume):
claude --name "Add necessary tests"
```

## What Gets Mounted

|          Path         |    Mode    |               Notes               |
|-----------------------|------------|-----------------------------------|
| Current directory     | read/write | Mounted at the same absolute path |
| `~/.claude/`          | read/write | Claude state and auth             |
| `~/.claude.json`      | read/write | Claude settings                   |
| `~/.cache/`           | read/write | Shared cache across sessions      |
| `~/.gitconfig`        | read-only  | If it exists                      |
| `~/.gitignore.global` | read-only  | If it exists                      |
| `~/.ssh/`             | read-only  | If it exists                      |
| `~/.npmrc`            | read-only  | If it exists                      |
| `~/.config/gh`        | read-only  | If it exists                      |

## Configuration

|  Environment variable |        Default         |                             Description                             |
|-----------------------|------------------------|---------------------------------------------------------------------|
| `CLAUDE_DOCKER_IMAGE` | `claude-code:latest`   | Image name to use                                                   |
| `CLAUDE_CONFIG_DIR`   | `~/.claude`            | Path to Claude config/state dir on host                             |
| `INSTALL_DIR`         | `~/.local/bin`         | Where `install.sh` places the symlink                               |
| `INSTALL_AS`          | `claude`               | Command name created by `install.sh`                                |
| `CLIPBOARD_HOST`      | `host.docker.internal` | Hostname used by the container to reach the clipboard bridge server |
| `CLIPBOARD_PORT`      | `18256`                | TCP port used by the clipboard bridge server                        |
| `CLIPBOARD_DEBUG`     | _(unset)_              | Set to any value to enable clipboard debug logging                  |

## Pasting Images

Claude Code's Ctrl+V image paste is bridged to the macOS clipboard automatically. A lightweight Python server starts in the background on the host and exposes clipboard image data over TCP; shim scripts inside the container intercept `xclip`/`wl-paste` calls and forward them to it.

**Supported sources:**

- Screenshots (Cmd+Shift+3 / Cmd+Shift+4 / etc.)
- Images copied from a browser or any app
- Image files copied from Finder (PNG, JPG, GIF, WebP, TIFF)

**Not supported:** non-image files — pasting a `.txt`, etc. does nothing. For PDFs, use Claude Code's `@`-mention syntax instead: type `@/path/to/file.pdf` to bring a PDF into context.

See [Requirements](#requirements) for host-side dependencies.

## Development

To enable verbose logging for the clipboard bridge, set `CLIPBOARD_DEBUG`:

```bash
CLIPBOARD_DEBUG=1 claude
```

Logs are written to:

- `~/.claude/clipboard-server.log` — host-side server
- `~/.claude/clipboard-client.log` — container-side shim

When modifying `clipboard-server.py`, the already-running server process won't pick up your changes automatically. Kill it so the next `claude` invocation starts a fresh instance:

```bash
pkill -f clipboard-server.py 2>/dev/null && echo "killed" || echo "not running"
```

## Design Decisions

- **Single image** — one image is built once and reused for every project, keeping disk usage low.
- **Same-path mounts** — the project directory and home paths are mounted at their exact host paths inside the container. This keeps file references, git context, and symlinks valid without any translation.
- **Throwaway containers** — each invocation starts a fresh container (`--rm`). No state is left behind between sessions beyond what is explicitly mounted.
- **Selective mounts** — only the minimum set of host paths needed for Claude Code to function are exposed. Optional paths (git config, SSH keys, etc.) are mounted read-only and only if they exist.
- **No Node.js on the host** — Claude Code and its dependencies live entirely inside the image.
