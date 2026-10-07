#!/bin/bash
# Remove sysmon. Run with: sudo ./uninstall.sh [--purge]
# --purge also deletes recorded history/snapshots (/var/log/sysmon) and /etc/sysmon.conf.
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then echo "Please run with sudo" >&2; exit 1; fi

systemctl disable --now sysmon.service 2>/dev/null || true
systemctl --global disable sysmon-notify.service 2>/dev/null || true
if [ -n "${SUDO_USER:-}" ]; then
    uid=$(id -u "$SUDO_USER")
    runuser -u "$SUDO_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
        systemctl --user stop sysmon-notify.service 2>/dev/null || true
fi
rm -f /etc/systemd/system/sysmon.service /etc/systemd/user/sysmon-notify.service
rm -f /usr/local/bin/sysmon /usr/local/bin/sysmon-status
rm -rf /usr/local/share/doc/sysmon
systemctl daemon-reload
if [ "${1:-}" = "--purge" ]; then
    rm -rf /var/log/sysmon /etc/sysmon.conf /etc/sysmon.conf.new
    echo "sysmon removed, including history and config."
else
    echo "sysmon removed. History kept in /var/log/sysmon, config in /etc/sysmon.conf (use --purge to delete)."
fi
