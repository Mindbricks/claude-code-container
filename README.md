# claude-code-container

A minimalist solution to run [Claude Code](https://github.com/anthropics/claude-code) in a sandboxed throwaway container, safely isolated from your host system while still having access to your project and necessary credentials.

- Supports **multiple simultaneous sessions** on the same project.
- **Telemetry is disabled** (via `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`).

## Requirements

- Docker or Podman

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

## What gets mounted

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

|  Environment variable |       Default        |               Description               |
|-----------------------|----------------------|-----------------------------------------|
| `CLAUDE_DOCKER_IMAGE` | `claude-code:latest` | Image name to use                       |
| `CLAUDE_CONFIG_DIR`   | `~/.claude`          | Path to Claude config/state dir on host |
| `INSTALL_DIR`         | `~/.local/bin`       | Where `install.sh` places the symlink   |
| `INSTALL_AS`          | `claude`             | Command name created by `install.sh`    |

## Design decisions

- **Single image** — one image is built once and reused for every project, keeping disk usage low.
- **Same-path mounts** — the project directory and home paths are mounted at their exact host paths inside the container. This keeps file references, git context, and symlinks valid without any translation.
- **Throwaway containers** — each invocation starts a fresh container (`--rm`). No state is left behind between sessions beyond what is explicitly mounted.
- **Selective mounts** — only the minimum set of host paths needed for Claude Code to function are exposed. Optional paths (git config, SSH keys, etc.) are mounted read-only and only if they exist.
- **No Node.js on the host** — Claude Code and its dependencies live entirely inside the image.
