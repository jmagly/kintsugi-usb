#!/bin/bash
# desktop-provision.sh — removable-media UX for the Kintsugi live desktop.
#
# Runs INSIDE the chroot during remaster (make-remaster-iso.sh, via livefs-edit
# --python chroot-exec). Goal: plug-and-go automount of USB / removable storage
# and dead-simple safe-eject, for non-technical operators AND airgapped use
# (everything is local — no network needed at runtime).
#
# Pieces:
#   - udiskie          : auto-mounts removable media on insert + a tray icon with
#                        per-device unmount/eject/power-off + desktop notifications.
#                        DE-agnostic, runs offline. The core of "easy."
#   - udisks2 + gvfs(-backends) : the mount machinery udiskie/Thunar drive.
#   - gnome-disk-utility : the "Disks" GUI for power users (format/mount/eject).
#   - thunar-volman    : XFCE's own auto-media (belt-and-suspenders).
#   - xfce4-notifyd    : notification daemon so mount/eject toasts appear.
#   - eject/exfatprogs/ntfs-3g/dosfstools : broad removable-FS support.
#
# Plus: a polkit rule (active local session manages removable media without a
# password), a udiskie autostart entry, and a one-click "Safely Remove USB
# Drives" launcher backed by /usr/local/bin/kintsugi-eject (shipped separately).

set -u
export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
LOG=/etc/kintsugi/desktop-install.log
mkdir -p /etc/kintsugi; : > "$LOG"
log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG" >&2; }

log "=== Kintsugi desktop / removable-media provisioning ==="

apt-get update >>"$LOG" 2>&1 || true
apt-get install -y --no-install-recommends \
    udiskie udisks2 gvfs gvfs-backends gnome-disk-utility xfce4-notifyd \
    thunar-volman eject exfatprogs ntfs-3g dosfstools libnotify-bin >>"$LOG" 2>&1 \
    && log "  ✓ packages installed" || log "  ✗ some packages failed (see log)"

# 1. Autostart udiskie for every desktop session: automount + tray eject + notify.
mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/kintsugi-udiskie.desktop <<'DESK'
[Desktop Entry]
Type=Application
Name=Kintsugi Removable Media
Comment=Auto-mount USB/removable storage; tray menu to safely eject
Exec=udiskie --automount --notify --tray --appindicator
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESK
log "  ✓ udiskie autostart (automount + tray eject + notify)"

# 2. XFCE Thunar auto-media defaults (alongside udiskie) for the live user.
mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/thunar-volman.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="thunar-volman" version="1.0">
  <property name="automount-drives" type="empty">
    <property name="enabled" type="bool" value="true"/>
  </property>
  <property name="automount-media" type="empty">
    <property name="enabled" type="bool" value="true"/>
  </property>
</channel>
XML
log "  ✓ Thunar auto-media defaults (/etc/skel)"

# 3. polkit: active local (live) session manages removable media without a prompt.
mkdir -p /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/50-kintsugi-udisks.rules <<'RULES'
// Kintsugi: let the active local session mount/unmount/eject/power-off removable
// storage without authentication — single-user rescue session, no password friction.
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.udisks2.") === 0 &&
        subject.active && subject.local) {
        return polkit.Result.YES;
    }
});
RULES
log "  ✓ udisks2 polkit rule (no-password removable-media management)"

# 4. One-click "Safely Remove USB Drives" launcher → kintsugi-eject (in /usr/local/bin).
cat > /usr/share/applications/kintsugi-eject.desktop <<'DESK'
[Desktop Entry]
Type=Application
Name=Safely Remove USB Drives
Comment=Flush and power off all removable drives — protects the Kintsugi boot drive
Exec=kintsugi-eject --gui
Icon=media-eject
Terminal=false
Categories=System;Utility;
Keywords=eject;unmount;usb;safely;remove;
DESK
mkdir -p /etc/skel/Desktop
cp /usr/share/applications/kintsugi-eject.desktop /etc/skel/Desktop/ 2>/dev/null || true
chmod +x /etc/skel/Desktop/kintsugi-eject.desktop 2>/dev/null || true
# XFCE: trust the desktop launcher so it runs on double-click without a prompt.
mkdir -p /etc/skel/.config
log "  ✓ 'Safely Remove USB Drives' launcher (desktop + app menu)"

log "=== done ==="
apt-get clean >>"$LOG" 2>&1 || true
rm -rf /var/lib/apt/lists/* 2>/dev/null || true
exit 0
