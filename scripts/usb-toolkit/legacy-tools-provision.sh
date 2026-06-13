#!/bin/bash
# legacy-tools-provision.sh — 32-bit (i386) runtime for legacy vendor recovery tools.
#
# Runs INSIDE the chroot during remaster (make-remaster-iso.sh, via livefs-edit
# --python chroot-exec). Goal: let the Kintsugi rescue drive run legacy 32-bit
# vendor recovery binaries OFFLINE, out of the box — no apt/network dance in the
# field (rescue scenarios are frequently airgapped, and the live boot may have no
# persistence to install into).
#
# Motivating case: the Imation/IronKey legacy USB unlocker. The drive's launcher
# partition ships `linux/ironkey.exe` — an ELF 32-bit (i386) CLI whose full
# dependency set (ldd) is just linux-gate.so.1 + libdl + libc + /lib/ld-linux.so.2,
# all provided by `libc6:i386`. It needs NO Qt (the Qt frameworks on the device are
# for the macOS GUI only). On a clean 64-bit Ubuntu 24.04 there is no i386 foreign
# architecture and no 32-bit loader, so the binary can't even start (the misleading
# `No such file or directory` — the file is there, its ELF interpreter isn't).
# See docs/legacy-device-unlock.md and issue #45.
#
# What this installs (build-time, baked into the squashfs):
#   - libc6:i386      : the 32-bit loader + libc/libdl. REQUIRED — this alone makes
#                       the IronKey CLI unlocker (and most minimal 32-bit binaries) run.
#   - libstdc++6:i386 : best-effort. Common dependency of other legacy C++ vendor tools.
#   - zlib1g:i386     : best-effort. Common dependency of legacy compressed-payload tools.
#
# Always-on (like desktop-provision.sh): running vendor unlockers is core to a
# recovery drive's purpose, the footprint is a few MB, and it must work offline.
#
# NOTE: full Qt4-based 32-bit GUI unlockers are NOT supported — Qt4 is gone from
# 24.04 and is not satisfiable. The IronKey *CLI* unlocker does not need it.

set -u
export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
LOG=/etc/kintsugi/legacy-tools-install.log
mkdir -p /etc/kintsugi; : > "$LOG"
log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG" >&2; }

log "=== Kintsugi legacy-tools / 32-bit (i386) runtime provisioning ==="

# Enable the i386 foreign architecture (idempotent — no-op if already added).
if dpkg --add-architecture i386 >>"$LOG" 2>&1; then
    log "  ✓ i386 foreign architecture enabled ($(dpkg --print-foreign-architectures | tr '\n' ' '))"
else
    log "  ✗ failed to enable i386 architecture (see log)"
fi

apt-get update >>"$LOG" 2>&1 || true

# Core 32-bit runtime — MUST succeed for legacy vendor unlockers (e.g. IronKey) to run.
if apt-get install -y --no-install-recommends libc6:i386 >>"$LOG" 2>&1; then
    log "  ✓ libc6:i386 installed (32-bit loader + libc/libdl — IronKey CLI unlocker now runs)"
else
    log "  ✗ libc6:i386 FAILED — 32-bit vendor unlockers will NOT run (see log)"
fi

# Optional common 32-bit deps for *other* legacy vendor tools. Separate call so a
# name miss can't break the core libc6:i386 above. The IronKey CLI needs neither.
if apt-get install -y --no-install-recommends libstdc++6:i386 zlib1g:i386 >>"$LOG" 2>&1; then
    log "  ✓ libstdc++6:i386 + zlib1g:i386 installed (broader legacy 32-bit tool support)"
else
    log "  ~ libstdc++6:i386 / zlib1g:i386 unavailable — IronKey CLI still works; other C++ tools may not"
fi

log "=== done ==="
apt-get clean >>"$LOG" 2>&1 || true
rm -rf /var/lib/apt/lists/* 2>/dev/null || true
exit 0
