#!/usr/bin/env bash
# Usage: sudo ./install.sh [--cron]
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root (sudo)"; exit 1; }
cd "$(dirname "$0")"
install -m 0755 health-monitor.sh /usr/local/bin/health-monitor.sh
install -d /etc/health-monitor
[[ -f /etc/health-monitor/health-monitor.conf ]] || install -m 0640 config/health-monitor.conf /etc/health-monitor/health-monitor.conf
if [[ "${1:-}" == "--cron" ]]; then
  install -m 0644 systemd/cron.example /etc/cron.d/health-monitor
  echo "Installed cron job (every 5 min)."
else
  install -m 0644 systemd/health-monitor.service systemd/health-monitor.timer /etc/systemd/system/
  systemctl daemon-reload && systemctl enable --now health-monitor.timer
  echo "Installed systemd timer. Check: systemctl list-timers health-monitor.timer"
fi
echo "Edit /etc/health-monitor/health-monitor.conf, then test: sudo /usr/local/bin/health-monitor.sh"
