#!/usr/bin/env python3
"""
Clipboard bridge server for claude-code-container.

Runs on the macOS host, listens on TCP 127.0.0.1:PORT.
Containers reach it via host.docker.internal:PORT.

Protocol (one request per connection):
  PING        → PONG\n
  IMAGE_PNG   → OK <len>\n<data>   or  NONE\n
  TARGETS     → OK <len>\n<newline-separated MIME list>

Port: $CLIPBOARD_PORT (default 18256)
"""

import os
import socket
import subprocess
import sys
import tempfile
import time

PORT = int(os.environ.get("CLIPBOARD_PORT", "18256"))
DEBUG = bool(os.environ.get("CLIPBOARD_DEBUG"))
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".tiff", ".tif"}

def log(msg, force=False):
    if not DEBUG and not force:
        return

    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] clipboard-server: {msg}", file=sys.stderr, flush=True)

def _run(*cmd, timeout=5):
    return subprocess.run(list(cmd), capture_output=True, timeout=timeout)

def _clipboard_file_path():
    """Return the POSIX path if the clipboard holds a single file URL, else None."""

    try:
        script = (
            "try\n"
            "    set f to (the clipboard as \u00abclass furl\u00bb)\n"
            "    return POSIX path of f\n"
            "on error\n"
            '    return ""\n'
            "end try"
        )
        r = subprocess.run(["osascript", "-e", script], capture_output=True, timeout=3)
        path = r.stdout.decode().strip()
        return path if path else None
    except Exception:
        return None

def get_targets():
    types = [
        "TARGETS",
        "MULTIPLE",
        "TIMESTAMP",
        "STRING",
        "UTF8_STRING",
        "text/plain",
        "text/plain;charset=utf-8",
    ]

    if get_image_png():
        types = ["image/png"] + types

    log(f"get_targets: {types}")
    return "\n".join(types).encode()

def get_image_png():
    # Priority 1: file copied from Finder.
    # pngpaste/osascript render a thumbnail for ANY file, so check the file URL
    # first — return the actual file bytes for images, Nothing for non-images.
    filepath = _clipboard_file_path()
    if filepath:
        ext = os.path.splitext(filepath)[1].lower()
        log(f"get_image_png: clipboard file reference {filepath!r} ext={ext}")
        if ext not in IMAGE_EXTENSIONS or not os.path.isfile(filepath):
            return None
        with open(filepath, "rb") as f:
            return f.read()

    # Priority 2: pngpaste — fast, handles screenshots and in-browser copies.
    try:
        r = _run("pngpaste", "-")
        log(f"get_image_png pngpaste: returncode={r.returncode} len={len(r.stdout)}")
        if r.returncode == 0 and r.stdout:
            return r.stdout
    except FileNotFoundError:
        log("get_image_png: pngpaste not found, trying osascript")
    except Exception as e:
        log(f"get_image_png pngpaste error: {e}")

    # Priority 3: osascript — no extra dependency required.
    tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    tmp.close()
    try:
        script = "\n".join([
            "try",
            "    set imgData to (the clipboard as \u00abclass PNGf\u00bb)",
            f'    set f to open for access POSIX file "{tmp.name}" with write permission',
            "    write imgData to f",
            "    close access f",
            "on error",
            "    try",
            f'        close access POSIX file "{tmp.name}"',
            "    end try",
            "end try",
        ])
        r = subprocess.run(["osascript", "-e", script], capture_output=True, timeout=5)
        size = os.path.getsize(tmp.name)
        log(f"get_image_png osascript: returncode={r.returncode} file_size={size}")
        if size > 0:
            with open(tmp.name, "rb") as f:
                return f.read()
    except Exception as e:
        log(f"get_image_png osascript error: {e}")
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    return None

def handle(conn, addr):
    try:
        buf = b""
        while b"\n" not in buf:
            chunk = conn.recv(256)
            if not chunk:
                return
            buf += chunk
        cmd = buf.split(b"\n")[0].decode().strip()
        log(f"request from {addr}: {cmd!r}")

        if cmd == "PING":
            conn.sendall(b"PONG\n")
            return

        if cmd == "TARGETS":
            data = get_targets()
        elif cmd == "IMAGE_PNG":
            data = get_image_png()
        else:
            log(f"unknown command: {cmd!r}")
            conn.sendall(b"NONE\n")
            return

        if data:
            log(f"responding OK {len(data)} bytes")
            conn.sendall(f"OK {len(data)}\n".encode())
            conn.sendall(data)
        else:
            log("responding NONE")
            conn.sendall(b"NONE\n")
    except Exception as exc:
        log(f"handle error: {exc}")
        try:
            conn.sendall(b"NONE\n")
        except Exception:
            pass

def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    try:
        srv.bind(("127.0.0.1", PORT))
    except OSError as e:
        log(f"failed to bind 127.0.0.1:{PORT} — {e}")
        sys.exit(1)

    srv.listen(10)
    log(f"listening on 127.0.0.1:{PORT}", force=True)

    with srv:
        while True:
            try:
                conn, addr = srv.accept()
                with conn:
                    handle(conn, addr)
            except KeyboardInterrupt:
                break
            except Exception as exc:
                log(f"accept error: {exc}")

if __name__ == "__main__":
    main()
