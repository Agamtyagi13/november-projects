#!/usr/bin/env bash
# Linux Server Health Monitor: checks CPU, memory, disk and services; logs results; alerts on thresholds.
# Exit codes: 0 = healthy, 1 = at least one threshold breached
set -uo pipefail

CONFIG="${HM_CONFIG:-/etc/health-monitor/health-monitor.conf}"
# shellcheck source=/dev/null
[[ -f "$CONFIG" ]] && source "$CONFIG"

: "${CPU_WARN:=80}"; : "${MEM_WARN:=85}"; : "${DISK_WARN:=90}"
: "${DISK_PATHS:=/}"; : "${SERVICES:=}"
: "${LOG_FILE:=/var/log/health-monitor.log}"; : "${LOG_MAX_BYTES:=1048576}"
: "${STATE_DIR:=/var/tmp/health-monitor}"; : "${ALERT_COOLDOWN:=1800}"
: "${WEBHOOK_URL:=}"; : "${WEBHOOK_FORMAT:=slack}"; : "${ALERT_EMAIL:=}"; : "${ALERT_CMD:=}"; : "${DRY_RUN:=0}"

HOST="$(hostname)"
BREACH_KEYS=(); BREACH_MSGS=()

# ---------- logging ----------
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="${TMPDIR:-/tmp}/health-monitor.log"
if [[ -f "$LOG_FILE" ]] && (( $(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0) > LOG_MAX_BYTES )); then
  mv "$LOG_FILE" "$LOG_FILE.1"; : > "$LOG_FILE"
fi
mkdir -p "$STATE_DIR"

log() {
  local lvl="$1"; shift
  local line; line="$(date '+%Y-%m-%dT%H:%M:%S%z') $HOST [$lvl] $*"
  echo "$line"; echo "$line" >> "$LOG_FILE" 2>/dev/null || true
}

breach() { BREACH_KEYS+=("$1"); BREACH_MSGS+=("$2"); }

# ---------- metrics ----------
cpu_usage() {   # % busy over a 1s sample from /proc/stat
  local _ u n s i w irq sirq st t1 i1 t2 i2 dt
  read -r _ u n s i w irq sirq st _ < /proc/stat; t1=$((u+n+s+i+w+irq+sirq+st)); i1=$((i+w))
  sleep 1
  read -r _ u n s i w irq sirq st _ < /proc/stat; t2=$((u+n+s+i+w+irq+sirq+st)); i2=$((i+w))
  dt=$((t2-t1)); (( dt == 0 )) && { echo 0; return; }
  echo $(( 100 * (dt - (i2 - i1)) / dt ))
}
mem_usage() { awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf "%d", 100*(t-a)/t}' /proc/meminfo; }
disk_usage() { df -P "$1" 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5}'; }
svc_ok() {
  if command -v systemctl >/dev/null 2>&1 && systemctl list-units >/dev/null 2>&1; then
    systemctl is-active --quiet "$1"
  else
    pgrep -x "${1:0:15}" >/dev/null   # kernel truncates process names to 15 chars
  fi
}

# ---------- alerting ----------
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

send_alert() {   # subject, body
  local subject="$1" body="$2"
  log ALERT "$subject — $body"
  [[ "$DRY_RUN" == "1" ]] && return 0
  if [[ -n "$WEBHOOK_URL" ]]; then
    local field="text"; [[ "$WEBHOOK_FORMAT" == "discord" ]] && field="content"
    curl -fsS -m 10 -H 'Content-Type: application/json' \
      -d "{\"$field\":\"$(json_escape "[$HOST] $subject: $body")\"}" "$WEBHOOK_URL" >/dev/null \
      || log WARN "webhook delivery failed"
  fi
  if [[ -n "$ALERT_EMAIL" ]] && command -v mail >/dev/null 2>&1; then
    printf '%s\n' "$body" | mail -s "[$HOST] $subject" "$ALERT_EMAIL" || log WARN "email delivery failed"
  fi
  if [[ -n "$ALERT_CMD" ]]; then
    printf '[%s] %s: %s\n' "$HOST" "$subject" "$body" | bash -c "$ALERT_CMD" || log WARN "ALERT_CMD failed"
  fi
}

# ---------- run checks ----------
CPU="$(cpu_usage)"; MEM="$(mem_usage)"
(( CPU >= CPU_WARN )) && breach cpu "CPU usage ${CPU}% >= ${CPU_WARN}%"
(( MEM >= MEM_WARN )) && breach memory "Memory usage ${MEM}% >= ${MEM_WARN}%"

DISK_SUMMARY=""
for p in $DISK_PATHS; do
  d="$(disk_usage "$p")"; d="${d:-0}"
  DISK_SUMMARY+=" disk[$p]=${d}%"
  (( d >= DISK_WARN )) && breach "disk_$(echo "$p" | tr -c 'A-Za-z0-9\n' '_')" "Disk $p at ${d}% >= ${DISK_WARN}%"
done

SVC_SUMMARY=""
for s in $SERVICES; do
  if svc_ok "$s"; then SVC_SUMMARY+=" svc[$s]=up"; else SVC_SUMMARY+=" svc[$s]=DOWN"; breach "svc_$s" "Service $s is not running"; fi
done

log INFO "cpu=${CPU}% mem=${MEM}%${DISK_SUMMARY}${SVC_SUMMARY} breaches=${#BREACH_KEYS[@]}"

# ---------- alert with cooldown + recovery ----------
now="$(date +%s)"
for idx in "${!BREACH_KEYS[@]}"; do
  key="${BREACH_KEYS[$idx]}"; msg="${BREACH_MSGS[$idx]}"; state="$STATE_DIR/$key"
  if [[ -f "$state" ]] && (( now - $(cat "$state") < ALERT_COOLDOWN )); then
    log INFO "alert for '$key' suppressed (cooldown ${ALERT_COOLDOWN}s)"
  else
    send_alert "WARNING" "$msg"; echo "$now" > "$state"
  fi
done

for f in "$STATE_DIR"/*; do
  [[ -e "$f" ]] || continue
  k="$(basename "$f")"
  if ! printf '%s\n' ${BREACH_KEYS[@]+"${BREACH_KEYS[@]}"} | grep -qx "$k"; then
    send_alert "RECOVERED" "$k is back to normal"; rm -f "$f"
  fi
done

(( ${#BREACH_KEYS[@]} == 0 ))
