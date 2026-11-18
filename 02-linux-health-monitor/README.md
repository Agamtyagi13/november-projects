# Linux Server Health Monitor

A Bash script that checks **CPU, memory, disk and service health**, logs every run, and **alerts when configurable thresholds are exceeded** — by webhook (Slack/Discord/Teams), email, or any custom command. Runs from a **systemd timer** (or cron).

## Features
- Thresholds and monitored disks/services set in one config file
- One structured log line per run (`cpu=.. mem=.. disk[/]=.. svc[nginx]=up breaches=0`) with size-based rotation
- **Alert cooldown** (no spam) and a **RECOVERED** message when a problem clears
- Exit code `0` healthy / `1` breach — usable in other automation
- Falls back to `pgrep` when systemd is unavailable (containers, WSL)
- No dependencies beyond coreutils/procps (`curl` for webhooks, `mail` optional)

## Install
```bash
sudo ./install.sh            # systemd timer, every 5 minutes
sudo ./install.sh --cron     # or cron instead
sudo nano /etc/health-monitor/health-monitor.conf
sudo /usr/local/bin/health-monitor.sh      # run once to test
systemctl list-timers health-monitor.timer
journalctl -u health-monitor.service       # history;  tail -f /var/log/health-monitor.log
```

## Try it without installing
```bash
HM_CONFIG=config/health-monitor.conf LOG_FILE=./hm.log STATE_DIR=./state ./health-monitor.sh
# to see an alert, copy the config and set CPU_WARN=0, then re-run with HM_CONFIG pointing at the copy
```

## Test
```bash
./tests/test.sh
```
Covers: healthy run, CPU/memory/disk breaches, cooldown, recovery notice, stopped service, logging.

## Alert channels
| Setting | Example |
|---|---|
| `WEBHOOK_URL` | Slack/Teams incoming webhook; `WEBHOOK_FORMAT=discord` for Discord |
| `ALERT_EMAIL` | `ops@example.com` (needs `mailutils`) |
| `ALERT_CMD` | `logger -t health-monitor` or any script reading stdin |
