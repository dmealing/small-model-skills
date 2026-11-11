#!/usr/bin/env bash
# Unit test for smon's pure notify helpers: ha-script/http-api payload builders, API key parsing, delivery decision (no network).
set -uo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
SMON="$REPO/monitor/bin/smon"
# Extract only the pure ha_script_payload function definition and eval it (avoids smon's load-time side effects).
eval "$(sed -n '/^ha_script_payload()/,/^}/p' "$SMON")"
eval "$(sed -n '/^notify_api_payload()/,/^}/p' "$SMON")"
eval "$(sed -n '/^notify_api_key()/,/^}/p' "$SMON")"
eval "$(sed -n '/^notify_api_outcome()/,/^}/p' "$SMON")"

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
# notify_api_key: bare, NAME=value, quoted, comments/blank lines, "=" inside a bare key.
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
key_of(){ printf '%s\n' "$1" > "$tmp"; notify_api_key "$tmp"; }
check "key bare"                 "$(key_of 'k3y-Value_1')"            "k3y-Value_1"
check "key NAME=value"           "$(key_of 'NOTIFY_API_KEY=k3y-Value_1')" "k3y-Value_1"
check "key NAME=\"quoted\""      "$(key_of 'NOTIFY_API_KEY="k3y-Value_1"')" "k3y-Value_1"
check "key NAME='quoted'"        "$(key_of "NOTIFY_API_KEY='k3y-Value_1'")" "k3y-Value_1"
check "key bare with padding =="  "$(key_of 'abc123==')"               "abc123=="
check "key bare with padding ="   "$(key_of 'abc123=')"                "abc123="
check "key NAME=value with =="    "$(key_of 'NOTIFY_API_KEY=abc123==')" "abc123=="
check "key skips comments/blank"  "$(printf '# note\n\n  # indented\nk3y\nother\n' > "$tmp"; notify_api_key "$tmp")" "k3y"
check "key empty file"            "$(: > "$tmp"; notify_api_key "$tmp")" ""
# notify_api_outcome: delivered/deduped/held true on 2xx = delivered; other 2xx = accepted (no fallback);
# no code or non-2xx = error (the only case that falls back). Includes bodies > 160 bytes.
pad="$(printf 'p%.0s' $(seq 1 300))"
outcome(){ local o; o="$(notify_api_outcome "$1" "$2")"; echo "$o/$?"; }
check "delivered true"            "$(outcome 200 '{"delivered":true}')" delivered/0
check "delivered true, long body" "$(outcome 200 "{\"delivered\":true,\"detail\":\"$pad\"}")" delivered/0
check "deduped true"              "$(outcome 200 '{"delivered":false,"deduped":true}')" delivered/0
check "held true"                 "$(outcome 200 '{"delivered":false,"held":true}')" delivered/0
check "delivered false: accepted" "$(outcome 200 '{"delivered":false}')" accepted/0
check "non-JSON 2xx: accepted"    "$(outcome 202 'ok')" accepted/0
check "non-2xx is an error"       "$(outcome 401 '{"delivered":true}')" error/1
check "5xx is an error"           "$(outcome 503 '')" error/1
check "no answer (000)"           "$(outcome 000 '')" error/1
check "empty code"                "$(outcome '' '{"delivered":true}')" error/1
echo "RESULT: $([ $fail = 0 ] && echo PASS || echo FAIL)"; [ $fail = 0 ]
