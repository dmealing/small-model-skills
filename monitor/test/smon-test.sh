#!/usr/bin/env bash
# smon shim test — drives smon with a FAKE probe (scriptable verdict) and a FAKE notify sink,
# asserting the transition/dedupe/sustain/quiet-hours/enrichment-fallback policy.
set -uo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
SMON="$REPO/monitor/bin/smon"

TMP="$(mktemp -d /tmp/smon-test.XXXXXX)"
STATE="$TMP/state"; mkdir -p "$STATE"
PROBE_OUT="$TMP/verdict.txt"      # the fake probe echoes whatever is here
SINK="$TMP/alerts.txt"; : > "$SINK"

# Fake probe: a script that prints the contents of PROBE_OUT. Install it into a fake bin dir
# that ALSO has the real lib (smon sources ../../bin/lib/common.sh relative to itself), so we
# instead point smon at the real repo but override which probe it runs via SMON_PROBES=fakeprobe
# and put fakeprobe on the real bin path? Simpler: use --once with a probe we drop into a temp
# copy of the repo bin. Cleanest: symlink a temp "probe bin" is not possible (smon derives it).
# So: create the fake probe INSIDE the real repo bin, named zz-faketest, and clean up after.
FAKE="$REPO/bin/zz-faketest"
cat > "$FAKE" <<EOF
#!/usr/bin/env bash
cat "$PROBE_OUT"
EOF
chmod +x "$FAKE"
trap 'rm -f "$FAKE"; rm -rf "$TMP"' EXIT

# Common env: route everything to a stdout sink we capture, no real network, deterministic.
run(){ # run one sweep; capture alert output
  SMON_CONFIG=/dev/null \
  SMON_PROBES="zz-faketest" \
  SMON_NOTIFY="stdout" \
  SMON_BRAIN="none" \
  SMON_STATE_DIR="$STATE" \
  SMON_LOG="$TMP/smon.log" \
  SMON_HOST="testhost" \
  SMON_WARN_SUSTAIN="${WARN_SUSTAIN:-2}" \
  SMON_QUIET_START="${QS:-23}" SMON_QUIET_END="${QE:-7}" \
  "$SMON" 2>/dev/null
}

set_verdict(){ printf 'verdict: %s\n' "$1" > "$PROBE_OUT"; }

PASS=0; FAIL=0
check(){ # desc, expected-substring-or-EMPTY, actual
  local desc="$1" exp="$2" act="$3"
  if [ "$exp" = "EMPTY" ]; then
    if [ -z "$act" ]; then echo "  ✓ $desc"; PASS=$((PASS+1)); else echo "  ✗ $desc — expected NO alert, got: $act"; FAIL=$((FAIL+1)); fi
  else
    if printf '%s' "$act" | grep -q "$exp"; then echo "  ✓ $desc"; PASS=$((PASS+1)); else echo "  ✗ $desc — expected '$exp', got: $act"; FAIL=$((FAIL+1)); fi
  fi
}

echo "=== 1. OK on first sweep -> silent ==="
set_verdict "OK NOMINAL — all good"; out="$(run)"; check "OK first sweep silent" EMPTY "$out"

echo "=== 2. OK->WARN (sustain=2): first WARN sweep -> silent ==="
set_verdict "WARN CPU_HOG — a proc is hot"; out="$(run)"; check "WARN sweep 1 silent (maturing)" EMPTY "$out"

echo "=== 3. WARN persists: second WARN sweep -> PUSH ==="
out="$(run)"; check "WARN sweep 2 pushes" "CPU_HOG" "$out"

echo "=== 4. WARN persists again (already alerted) -> silent ==="
out="$(run)"; check "WARN sweep 3 silent (already alerted)" EMPTY "$out"

echo "=== 5. WARN->OK recovery (we had alerted) -> PUSH resolved ==="
set_verdict "OK NOMINAL — back to normal"; out="$(run)"; check "recovery pushes" "recovered" "$out"

echo "=== 6. OK->FAIL -> PUSH immediately (no sustain needed) ==="
set_verdict "FAIL DAEMON_DOWN — service is down"; out="$(run)"; check "FAIL pushes immediately" "DAEMON_DOWN" "$out"

echo "=== 7. FAIL unchanged -> silent ==="
out="$(run)"; check "FAIL unchanged silent" EMPTY "$out"

echo "=== 8. FAIL->OK recovery -> PUSH ==="
set_verdict "OK NOMINAL — recovered"; out="$(run)"; check "FAIL recovery pushes" "recovered" "$out"

echo "=== 9. WARN_SUSTAIN=1: single WARN sweep pushes immediately ==="
rm -f "$STATE"/*.state
set_verdict "OK NOMINAL — start"; WARN_SUSTAIN=1 run >/dev/null   # seed OK
set_verdict "WARN DISK_HIGH — 88%"; out="$(WARN_SUSTAIN=1 run)"; check "sustain=1 WARN immediate" "DISK_HIGH" "$out"

echo "=== 10. quiet hours: WARN suppressed, FAIL still pushes ==="
rm -f "$STATE"/*.state
# force 'now' into quiet window by setting QS/QE to cover all hours
set_verdict "OK NOMINAL — start"; QS=0 QE=24 WARN_SUSTAIN=1 run >/dev/null
set_verdict "WARN CPU_HOG — hot"; out="$(QS=0 QE=24 WARN_SUSTAIN=1 run)"; check "WARN suppressed in quiet hours" EMPTY "$out"
set_verdict "FAIL DAEMON_DOWN — down"; out="$(QS=0 QE=24 WARN_SUSTAIN=1 run)"; check "FAIL NOT suppressed in quiet hours" "DAEMON_DOWN" "$out"

echo "=== 11. probe with NO verdict line -> treated as FAIL NO_VERDICT ==="
rm -f "$STATE"/*.state
printf 'some junk output\nno verdict here\n' > "$PROBE_OUT"; out="$(run)"; check "missing verdict -> FAIL" "NO_VERDICT" "$out"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
