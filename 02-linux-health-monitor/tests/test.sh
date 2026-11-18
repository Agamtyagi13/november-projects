#!/usr/bin/env bash
# Self-contained tests: no root, no network. Run: ./tests/test.sh
cd "$(dirname "$0")/.." || exit 1
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAIL=0; SENT="$T/sent.txt"; : > "$SENT"
conf() { cat > "$T/c.conf" <<C
CPU_WARN=$1
MEM_WARN=$2
DISK_WARN=$3
SERVICES="$4"
LOG_FILE=$T/hm.log
STATE_DIR=$T/state
ALERT_COOLDOWN=3600
ALERT_CMD="cat >> $SENT"
C
}
run() { HM_CONFIG="$T/c.conf" ./health-monitor.sh >/dev/null; echo $?; }
assert() { if [[ "$2" == "$3" ]]; then echo "PASS  $1"; else echo "FAIL  $1 (expected '$2', got '$3')"; FAIL=1; fi; }
count() { grep -c "$1" "$SENT" 2>/dev/null || true; }

conf 101 101 101 ""
assert "healthy system exits 0"                 0 "$(run)"
assert "healthy system sends no alerts"         0 "$(wc -l < "$SENT")"

conf 0 0 0 ""
assert "breached thresholds exit 1"             1 "$(run)"
assert "CPU alert delivered"                    1 "$(count 'CPU usage')"
assert "memory alert delivered"                 1 "$(count 'Memory usage')"
assert "disk alert delivered"                   1 "$(count 'Disk / at')"

before="$(wc -l < "$SENT")"; run >/dev/null
assert "repeat run suppressed by cooldown"      "$before" "$(wc -l < "$SENT")"

conf 101 101 101 ""
assert "recovered system exits 0"               0 "$(run)"
assert "recovery notice sent"                   1 "$(count 'RECOVERED' | head -1 | awk '{print ($1>0)?1:0}')"

rm -rf "$T/state"; conf 101 101 101 "no-such-service-xyz"
assert "stopped service exits 1"                1 "$(run)"
assert "service alert names the service"        1 "$(count 'no-such-service-xyz' | awk '{print ($1>0)?1:0}')"
grep -q "cpu=" "$T/hm.log" && assert "results written to log" 1 1 || assert "results written to log" 1 0
exit $FAIL
