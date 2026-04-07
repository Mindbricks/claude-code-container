#!/usr/bin/env node
/**
 * Clipboard bridge client for claude-code-container.
 *
 * Connects to the macOS host clipboard bridge server over TCP and acts as a
 * drop-in replacement for the clipboard tools Claude Code calls on Linux:
 *
 *     xclip, xsel, wl-paste, wl-copy
 *
 * Only image paste is supported; requests for other formats exit immediately with
 * code 1.
 *
 * Host: $CLIPBOARD_HOST (default: host.docker.internal)
 * Port: $CLIPBOARD_PORT (default: 18256)
 *
 * Install by symlinking this file to each tool name in /usr/local/bin.
 */
"use strict";

const net = require("net");
const fs = require("fs");
const path = require("path");

const HOST = process.env.CLIPBOARD_HOST || "host.docker.internal";
const PORT = parseInt(process.env.CLIPBOARD_PORT || "18256", 10);

// Debug log — written to a file visible on the host for diagnosis.
// Enabled only when $CLIPBOARD_DEBUG is set.
const DEBUG = !! process.env.CLIPBOARD_DEBUG;
const LOG_FILE = path.join(process.env.HOME || "/root", ".claude", "clipboard-client.log");

function log(msg) {
    if (! DEBUG) return;
    const ts = new Date().toLocaleString("sv").replace("T", " ").slice(0, 19);
    const line = `[${ts}] clipboard-client: ${path.basename(process.argv[1])} ${process.argv.slice(2).join(" ")}: ${msg}\n`;
    try { fs.appendFileSync(LOG_FILE, line); } catch (_) {}
}

const argv = process.argv.slice(2);
const cmd = path.basename(process.argv[1]);
log(`invoked cmd=${cmd} argv=${JSON.stringify(argv)} HOST=${HOST} PORT=${PORT}`);

// ── Argument parsing ──────────────────────────────────────────────────────────

function hasArg(...flags) {
    return flags.some(f => argv.includes(f));
}

function getArg(...flags) {
    for (const f of flags) {
        const i = argv.indexOf(f);
        if (i !== -1 && i + 1 < argv.length) return argv[i + 1];
    }
    return null;
}

function drainAndExit() {
    process.stdin.resume();
    process.stdin.on("data", () => {});
    process.stdin.on("end", () => process.exit(0));
    process.stdin.on("error", () => process.exit(0));
    setTimeout(() => process.exit(0), 3000);
}

// ── Determine request type ────────────────────────────────────────────────────

let request;

if (cmd === "xclip") {
    if (! hasArg("-o", "-out")) {
        drainAndExit();
        return;
    }
    const mime = getArg("-t", "-target") || "text/plain";
    if (mime === "TARGETS") {
        request = "TARGETS";
    } else if (mime === "image/png") {
        request = "IMAGE_PNG";
    } else {
        log(`text request ignored (${mime})`);
        process.exit(1);
    }

} else if (cmd === "xsel") {
    if (! hasArg("-o", "--output")) {
        drainAndExit();
        return;
    }
    log("text request ignored");
    process.exit(1);

} else if (cmd === "wl-paste") {
    if (hasArg("-l", "--list-types")) {
        request = "TARGETS";
    } else {
        const mime = getArg("-t", "--type") || "text/plain";
        if (mime === "image/png") {
            request = "IMAGE_PNG";
        } else {
            log(`text request ignored (${mime})`);
            process.exit(1);
        }
    }

} else if (cmd === "wl-copy") {
    drainAndExit();
    return;

} else {
    log(`unknown tool ${cmd}`);
    process.exit(1);
}

log(`connecting to ${HOST}:${PORT} request=${request}`);

// ── TCP connection ────────────────────────────────────────────────────────────

const client = net.createConnection({ host: HOST, port: PORT });
client.setTimeout(5000);

let headerBuf = Buffer.alloc(0);
let headerDone = false;
let dataLen = 0;
let received = 0;
const chunks = [];

client.on("connect", () => {
    log("connected");
    client.write(request + "\n");
});

client.on("data", chunk => {
    if (! headerDone) {
        headerBuf = Buffer.concat([headerBuf, chunk]);
        const nl = headerBuf.indexOf(0x0a);
        if (nl === -1) return;

        const headerLine = headerBuf.slice(0, nl).toString().trim();
        const rest = headerBuf.slice(nl + 1);
        log(`header: ${headerLine}`);

        if (headerLine === "NONE") {
            client.destroy();
            process.exit(1);
        }

        const m = headerLine.match(/^OK (\d+)$/);
        if (! m) {
            log(`unexpected header: ${headerLine}`);
            client.destroy();
            process.exit(1);
        }

        dataLen = parseInt(m[1], 10);
        headerDone = true;

        if (rest.length > 0) {
            chunks.push(rest);
            received += rest.length;
        }
    } else {
        chunks.push(chunk);
        received += chunk.length;
    }

    if (headerDone && received >= dataLen) {
        flush();
    }
});

function flush() {
    const all = Buffer.concat(chunks).slice(0, dataLen);
    log(`flushing ${all.length} bytes to stdout`);
    process.stdout.write(all);
    client.destroy();
    process.exit(0);
}

client.on("end", () => {
    if (headerDone && chunks.length > 0) {
        flush();
    } else {
        process.exit(headerDone ? 0 : 1);
    }
});

client.on("timeout", () => {
    log("timeout");
    client.destroy();
    process.exit(1);
});

client.on("error", err => {
    log(`error: ${err.message}`);
    process.exit(1);
});
