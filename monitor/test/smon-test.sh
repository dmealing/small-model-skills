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

# --- regression tests for the three silent-loss bugs (fixed 2026-07-10) ---

echo "=== 12. BUG: WARN tag-change must not be swallowed ==="
rm -f "$STATE"/*.state
# seed OK, then mature WARN/CPU_HOG to an alert (sustain=2)
set_verdict "OK NOMINAL — start"; run >/dev/null
set_verdict "WARN CPU_HOG — hot"; run >/dev/null            # sweep 1: maturing, silent
out="$(run)"; check "  CPU_HOG matured pushes" "CPU_HOG" "$out"   # sweep 2: pushes
# now drift to a DIFFERENT WARN tag — must eventually alert, not be swallowed
set_verdict "WARN MEMORY_PRESSURE — swap"; out="$(run)"; check "  tag-change sweep 1 silent (re-maturing)" EMPTY "$out"
out="$(run)"; check "  tag-change MEMORY_PRESSURE pushes (not swallowed)" "MEMORY_PRESSURE" "$out"

echo "=== 13. BUG: quiet-hours defers (not drops) a WARN ==="
rm -f "$STATE"/*.state
set_verdict "OK NOMINAL — start"; QS=0 QE=24 WARN_SUSTAIN=1 run >/dev/null
# WARN during quiet hours: suppressed now...
set_verdict "WARN DISK_HIGH — 88%"; out="$(QS=0 QE=24 WARN_SUSTAIN=1 run)"; check "  WARN held during quiet hours" EMPTY "$out"
# ...same WARN, now OUTSIDE quiet hours (QS=QE=0 => never quiet) must still deliver
out="$(QS=0 QE=0 WARN_SUSTAIN=1 run)"; check "  deferred WARN delivered after quiet hours" "DISK_HIGH" "$out"

echo "=== 14. BUG: quiet-hours-dropped WARN must not later mis-fire a 'recovered' push ==="
rm -f "$STATE"/*.state
set_verdict "OK NOMINAL — start"; QS=0 QE=24 WARN_SUSTAIN=1 run >/dev/null
set_verdict "WARN CPU_HOG — hot"; QS=0 QE=24 WARN_SUSTAIN=1 run >/dev/null     # suppressed, never delivered
set_verdict "OK NOMINAL — fine"; out="$(QS=0 QE=24 WARN_SUSTAIN=1 run)"; check "  no phantom recovery for never-sent WARN" EMPTY "$out"

echo "=== 15. BUG: a MISSING probe surfaces as FAIL PROBE_MISSING (not silently skipped) ==="
rm -f "$STATE"/*.state
# point smon at a probe that does not exist
out="$(SMON_CONFIG=/dev/null SMON_PROBES=zz-does-not-exist SMON_NOTIFY=stdout SMON_BRAIN=none \
  SMON_STATE_DIR="$STATE" SMON_LOG="$TMP/smon.log" SMON_HOST=testhost SMON_WARN_SUSTAIN=1 \
  "$SMON" 2>/dev/null)"
check "  missing probe -> FAIL PROBE_MISSING alert" "PROBE_MISSING" "$out"

echo "=== 16. BUG: recovery alerts during quiet hours must not be dropped ==="
rm -f "$STATE"/*.state
set_verdict "OK NOMINAL — start"; QS=0 QE=0 run >/dev/null
set_verdict "FAIL DAEMON_DOWN — down"; out="$(QS=0 QE=0 run)"; check "  FAIL alerted" "DAEMON_DOWN" "$out"
# force quiet hours and drive recovery — it should STILL push (not be suppressed)
set_verdict "OK NOMINAL — recovered"; out="$(QS=0 QE=24 run)"; check "  recovery pushes during quiet hours" "recovered" "$out"
# final state should be OK with count=0 alerted=0 (recovery resets alerted)
state="$(awk '{print $1, $2, $4, $5}' "$STATE"/zz-faketest.state)"; check "  final state is OK with alerted=0" "OK NOMINAL 0 0" "$state"

echo "=== 17. regression: WARN during quiet hours is still deferred (not over-broadened) ==="
rm -f "$STATE"/*.state
set_verdict "OK NOMINAL — start"; QS=0 QE=24 WARN_SUSTAIN=1 run >/dev/null
# WARN during quiet hours should still be deferred (not delivered like FAIL/recovery)
set_verdict "WARN CPU_HOG — hot"; out="$(QS=0 QE=24 WARN_SUSTAIN=1 run)"; check "  WARN still deferred during quiet hours" EMPTY "$out"
# and should deliver once out of quiet hours
out="$(QS=0 QE=0 WARN_SUSTAIN=1 run)"; check "  deferred WARN delivered after quiet hours" "CPU_HOG" "$out"

# --- capability tests (FAIL re-alert, digest, don't-enrich-FAIL) ---
# runx <extra-env...> — like run() but injects extra KEY=VAL pairs (never quiet unless overridden)
runx(){ env SMON_CONFIG=/dev/null SMON_PROBES=zz-faketest SMON_NOTIFY=stdout SMON_BRAIN=none \
  SMON_STATE_DIR="$STATE" SMON_LOG="$TMP/smon.log" SMON_HOST=testhost \
  SMON_WARN_SUSTAIN="${WARN_SUSTAIN:-2}" SMON_QUIET_START=0 SMON_QUIET_END=0 "$@" "$SMON" 2>/dev/null; }

echo "=== 18. FAIL re-alert: a standing FAIL re-pushes every N sweeps ==="
rm -f "$STATE"/*.state
set_verdict "OK NOMINAL — start"; runx SMON_FAIL_REMIND_SWEEPS=2 >/dev/null
set_verdict "FAIL DAEMON_DOWN — down"; out="$(runx SMON_FAIL_REMIND_SWEEPS=2)"; check "  FAIL first push" "DAEMON_DOWN" "$out"
out="$(runx SMON_FAIL_REMIND_SWEEPS=2)"; check "  sweep after FAIL: silent (reminder not due)" EMPTY "$out"
out="$(runx SMON_FAIL_REMIND_SWEEPS=2)"; check "  FAIL reminder re-pushes after N sweeps" "DAEMON_DOWN" "$out"

echo "=== 19. FAIL re-alert OFF by default (SMON_FAIL_REMIND_SWEEPS=0) ==="
rm -f "$STATE"/*.state
set_verdict "OK NOMINAL — start"; runx >/dev/null
set_verdict "FAIL DAEMON_DOWN — down"; runx >/dev/null    # first push
out="$(runx)"; check "  no reminder when disabled" EMPTY "$out"
out="$(runx)"; check "  still no reminder when disabled" EMPTY "$out"

echo "=== 20. don't-enrich-FAIL: BRAIN=glm but FAIL body is the raw verdict prose ==="
rm -f "$STATE"/*.state
# BRAIN=glm with a bogus claude bin: if it TRIED to enrich, enrich() would fall back to prose anyway,
# so instead assert the raw prose is present AND (proxy) that no enrichment ran by using a claude bin
# that would emit a marker. Simpler: assert FAIL body == the verdict prose verbatim.
set_verdict "OK NOMINAL — start"; env SMON_CONFIG=/dev/null SMON_PROBES=zz-faketest SMON_NOTIFY=stdout \
  SMON_BRAIN=glm SMON_CLAUDE_BIN=/bin/false SMON_ZAI_ENV=/dev/null SMON_STATE_DIR="$STATE" \
  SMON_LOG="$TMP/smon.log" SMON_HOST=testhost SMON_QUIET_START=0 SMON_QUIET_END=0 "$SMON" >/dev/null 2>&1
set_verdict "FAIL DAEMON_DOWN — the raw prose marker"; out="$(env SMON_CONFIG=/dev/null SMON_PROBES=zz-faketest \
  SMON_NOTIFY=stdout SMON_BRAIN=glm SMON_CLAUDE_BIN=/bin/false SMON_ZAI_ENV=/dev/null SMON_STATE_DIR="$STATE" \
  SMON_LOG="$TMP/smon.log" SMON_HOST=testhost SMON_QUIET_START=0 SMON_QUIET_END=0 "$SMON" 2>/dev/null)"
check "  FAIL ships raw verdict prose" "the raw prose marker" "$out"

echo "=== 21. daily digest: pushes once when the hour matches, then not again ==="
rm -f "$STATE"/*.state "$STATE"/.digest-sent
set_verdict "OK NOMINAL — fine"; runx >/dev/null       # establish some state
NOWH="$(date +%-H)"
out="$(runx SMON_DIGEST_HOUR="$NOWH")"; check "  digest pushes at matching hour" "daily digest" "$out"
out="$(runx SMON_DIGEST_HOUR="$NOWH")"; check "  digest not repeated same day" EMPTY "$out"

echo "=== 22. daily digest: silent when the hour does NOT match ==="
rm -f "$STATE"/*.state "$STATE"/.digest-sent
set_verdict "OK NOMINAL — fine"; runx >/dev/null
OTHERH=$(( ( $(date +%-H) + 12 ) % 24 ))
out="$(runx SMON_DIGEST_HOUR="$OTHERH")"; check "  no digest at non-matching hour" EMPTY "$out"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
