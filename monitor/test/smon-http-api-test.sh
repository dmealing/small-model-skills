#!/usr/bin/env bash
# smon http-api delivery test — drives `smon --test-alert` with SMON_NOTIFY=http-api and an ha-push
# fallback, through a FAKE curl on PATH that plays the notify API (delivered / held / unreachable / 5xx)
# and Home Assistant. Asserts: delivered and held never fall back; unreachable and errors fall back to
# ha-push exactly once; the key (from a named env var) reaches the header file and is never logged.
set -uo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
SMON="$REPO/monitor/bin/smon"

TMP="$(mktemp -d /tmp/smon-http-api-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/stub" "$TMP/state"
SINK="$TMP/calls"

cat > "$TMP/stub/curl" <<'EOF'
#!/usr/bin/env bash
# Fake curl: records which endpoint was hit; answers per FAKE_API_MODE.
url="" hdrfile=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) shift ;;
    -H) shift; case "$1" in @*) hdrfile="${1#@}" ;; esac ;;
    -m|-o|-w|--data) shift ;;
    http*) url="$1" ;;
  esac
  shift
done
case "$url" in
  */api/services/notify/*) echo HA >> "$FAKE_SINK"; printf 200; exit 0 ;;
esac
echo API >> "$FAKE_SINK"
[ -n "$hdrfile" ] && grep -qx "X-API-Key: $FAKE_EXPECT_KEY" "$hdrfile" && echo KEY_OK >> "$FAKE_SINK"
case "$FAKE_API_MODE" in
  delivered) printf '{"delivered":true}\n200' ;;
  held)      printf '{"delivered":false,"held":true}\n200' ;;
  error)     printf 'oops\n500' ;;
  down)      printf '\n000'; exit 7 ;;
esac
EOF
chmod +x "$TMP/stub/curl"

run(){ # <mode>
  : > "$SINK"; : > "$TMP/smon.log"
  env PATH="$TMP/stub:$PATH" FAKE_SINK="$SINK" FAKE_API_MODE="$1" FAKE_EXPECT_KEY="s3cret-k3y" \
    TEST_NOTIFY_KEY="s3cret-k3y" \
    SMOLS_CONFIG=/dev/null SMON_CONFIG=/dev/null SMON_STATE_DIR="$TMP/state" SMON_LOG="$TMP/smon.log" \
    SMON_QUIET_START=0 SMON_QUIET_END=0 SMON_HOST=testhost SMON_BRAIN=none \
    SMON_NOTIFY=http-api SMON_FALLBACK_NOTIFY=ha-push \
    SMON_NOTIFY_API_URL="http://api.invalid/notify" SMON_NOTIFY_API_KEY_ENV=TEST_NOTIFY_KEY \
    SMON_HA_URL="http://ha.invalid" SMON_HA_TARGET="notify.phone" SMON_HA_TOKEN="ha-tok" \
    "$SMON" --test-alert >/dev/null 2>&1
  tr '\n' ' ' < "$SINK"
}

PASS=0; FAIL=0
check(){ local desc="$1" exp="$2" act="$3"
  if [ "$act" = "$exp" ]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc — expected '$exp', got: '$act'"; FAIL=$((FAIL+1)); fi; }
nolog(){ if grep -q 's3cret-k3y' "$TMP/smon.log"; then echo "  ✗ key leaked into the log"; FAIL=$((FAIL+1)); else echo "  ✓ key not in the log"; PASS=$((PASS+1)); fi; }

echo "=== delivered: API only, no fallback ==="
check "API hit with the env-var key, no HA" "API KEY_OK " "$(run delivered)"; nolog
echo "=== held: counts as delivered, no fallback ==="
check "held is delivered" "API KEY_OK " "$(run held)"
check "held logged as delivered" "1" "$(grep -c 'http-api delivered (HTTP 200' "$TMP/smon.log")"
echo "=== unreachable: falls back to ha-push once ==="
check "unreachable falls back" "API KEY_OK HA " "$(run down)"; nolog
echo "=== 5xx: falls back to ha-push once ==="
check "server error falls back" "API KEY_OK HA " "$(run error)"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
