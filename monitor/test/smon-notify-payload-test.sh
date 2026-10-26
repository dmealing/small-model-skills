#!/usr/bin/env bash
# Unit test for the ha-script backend's pure payload builder (no network).
set -uo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
SMON="$REPO/monitor/bin/smon"
# Extract only the pure ha_script_payload function definition and eval it (avoids smon's load-time side effects).
eval "$(sed -n '/^ha_script_payload()/,/^}/p' "$SMON")"
eval "$(sed -n '/^notify_api_payload()/,/^}/p' "$SMON")"

fail=0
check(){ local d="$1" got="$2" exp="$3"; if [ "$got" = "$exp" ]; then echo "  ✓ $d"; else echo "  ✗ $d: got '$got' want '$exp'"; fail=1; fi; }
out="$(ha_script_payload fail disk-report pop-os "🔴 pop-os: DISK_CRITICAL" "disk full" pop-os-disk-report)"
check "severity" "$(printf '%s' "$out" | jq -r .severity)" "fail"
check "probe"    "$(printf '%s' "$out" | jq -r .probe)"    "disk-report"
check "host"     "$(printf '%s' "$out" | jq -r .host)"     "pop-os"
check "tag"      "$(printf '%s' "$out" | jq -r .tag)"      "pop-os-disk-report"
check "message"  "$(printf '%s' "$out" | jq -r .message)"  "disk full"
check "title"    "$(printf '%s' "$out" | jq -r .title)"    "🔴 pop-os: DISK_CRITICAL"
# http-api backend payload: {message, source}, message <= 1000 chars, source <= 40.
out="$(notify_api_payload "🟠 Internet: WAN_BACKUP"$'\n'"on backup" "wan-failover-host")"
check "api message" "$(printf '%s' "$out" | jq -r .message)" "🟠 Internet: WAN_BACKUP"$'\n'"on backup"
check "api source"  "$(printf '%s' "$out" | jq -r .source)"  "wan-failover-host"
check "api keys"    "$(printf '%s' "$out" | jq -c 'keys')"   '["message","source"]'
long="$(printf 'x%.0s' $(seq 1 1200))"
out="$(notify_api_payload "$long" "$(printf 's%.0s' $(seq 1 50))")"
check "api message cut to 1000" "$(printf '%s' "$out" | jq -r '.message | length')" "1000"
check "api source cut to 40"    "$(printf '%s' "$out" | jq -r '.source | length')"  "40"
echo "RESULT: $([ $fail = 0 ] && echo PASS || echo FAIL)"; [ $fail = 0 ]
