#!/usr/bin/env bash
# Usage: smoke-test.sh [base_url]   -> exits non-zero if any check fails
set -u
URL="${1:-http://localhost:8080}"; FAIL=0
check() {  # name, expected, actual
  if [ "$2" = "$3" ]; then echo "  PASS $1"; else echo "  FAIL $1 (expected $2, got $3)"; FAIL=1; fi
}
echo "Smoke testing $URL"
check "GET /        -> 200" 200 "$(curl -s -o /dev/null -w '%{http_code}' "$URL/")"
check "GET /healthz -> 200" 200 "$(curl -s -o /dev/null -w '%{http_code}' "$URL/healthz")"
check "GET /style.css -> 200" 200 "$(curl -s -o /dev/null -w '%{http_code}' "$URL/style.css")"
check "GET /nope    -> 404" 404 "$(curl -s -o /dev/null -w '%{http_code}' "$URL/nope")"
HDR=$(curl -sI "$URL/" | tr -d '\r' | tr 'A-Z' 'a-z')
case "$HDR" in *"x-content-type-options: nosniff"*) check "security headers" ok ok;; *) check "security headers" ok missing;; esac
case "$HDR" in *"server: nginx/"*) check "server version hidden" ok leaked;; *) check "server version hidden" ok ok;; esac
exit $FAIL
