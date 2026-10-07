#!/bin/bash
# Install sysmon. Run with: sudo ./install.sh
# Touches only: /usr/local/bin/sysmon(-status), /etc/sysmon.conf,
# /etc/systemd/system/sysmon.service, /etc/systemd/user/sysmon-notify.service,
# /usr/local/share/doc/sysmon/, and creates /var/log/sysmon (via systemd).
set -euo pipefail
cd "$(dirname "$0")"

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run with sudo: sudo $0" >&2
    exit 1
fi
TARGET_USER="${SUDO_USER:-}"

echo "== self-test (simulated, no load)"
./sysmon --config ./sysmon.conf selftest | tail -1

echo "== installing files"
install -m 0755 sysmon /usr/local/bin/sysmon
ln -sf sysmon /usr/local/bin/sysmon-status
if [ -e /etc/sysmon.conf ]; then
    install -m 0644 sysmon.conf /etc/sysmon.conf.new
    echo "   /etc/sysmon.conf exists - kept it; new default saved as /etc/sysmon.conf.new"
else
    install -m 0644 sysmon.conf /etc/sysmon.conf
fi
install -m 0644 sysmon.service /etc/systemd/system/sysmon.service
install -d /etc/systemd/user
install -m 0644 sysmon-notify.service /etc/systemd/user/sysmon-notify.service
install -d /usr/local/share/doc/sysmon
install -m 0644 README.md /usr/local/share/doc/sysmon/README.md

echo "== enabling system service"
systemctl daemon-reload
systemctl enable --now sysmon.service

echo "== enabling desktop notifier (user service)"
systemctl --global enable sysmon-notify.service
if [ -n "$TARGET_USER" ]; then
    uid=$(id -u "$TARGET_USER")
    if [ -S "/run/user/$uid/bus" ]; then
        runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            sh -c 'systemctl --user daemon-reload && systemctl --user restart sysmon-notify.service'
        echo "   started for $TARGET_USER"
    fi
fi

sleep 7
echo
systemctl --no-pager --lines=5 status sysmon.service || true
echo
/usr/local/bin/sysmon status || true
echo
echo "Installed. Useful commands: sysmon status | sysmon history --since 30m | sysmon events | sysmon snapshots"
