#!/usr/bin/env bash
# wan-health shim test — feeds fixture status.json files to the probe via the WAN_HEALTH_STATUS
# env override and asserts the emitted verdict TAG for each branch of the priority-ordered
# decision tree, per the wan-health verdict contract (see the decision-tree comment atop
# bin/wan-health for the full priority order). One fixture per tag,
# plus a couple of documented edge cases (active-not-a-link, sensing-degraded, invalid JSON).
set -uo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
PROBE="$REPO/bin/wan-health"

TMP="$(mktemp -d /tmp/wan-health-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

NOW="$(date +%s)"
FRESH=$((NOW - 1))
STALE=$((NOW - 9999))

PASS=0; FAIL=0
check(){ # desc, expected-substring, actual
  local desc="$1" exp="$2" act="$3"
  if printf '%s' "$act" | grep -q "$exp"; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc — expected '$exp', got: $act"; FAIL=$((FAIL+1)); fi
}
check_rc(){ # desc, expected-rc, actual-rc
  local desc="$1" exp="$2" act="$3"
  if [ "$act" = "$exp" ]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc — expected rc=$exp, got rc=$act"; FAIL=$((FAIL+1)); fi
}

run(){ WAN_HEALTH_STATUS="$1" "$PROBE" 2>/dev/null; }
run_rc(){ WAN_HEALTH_STATUS="$1" "$PROBE" >/dev/null 2>&1; echo $?; }

# mk_status <file> <active|null> <primary> <backup> <state> <degraded:true|false> <ts> \
#           <p_score> <p_suppressed:true|false> <b_score> <b_suppressed:true|false>
mk_status(){
  local file="$1" active="$2" primary="$3" backup="$4" state="$5" degraded="$6" ts="$7" \
        p_score="$8" p_supp="$9" b_score="${10}" b_supp="${11}"
  local active_json; if [ "$active" = "null" ]; then active_json="null"; else active_json="\"$active\""; fi
  cat > "$file" <<EOF
{
  "active": $active_json,
  "primary": "$primary", "backup": "$backup",
  "state": "$state",
  "rank_order": ["$primary","$backup"],
  "degraded": $degraded,
  "dwell_s": 600.0,
  "last_write": null,
  "writes_last_hour": 0,
  "reason": "test fixture",
  "ts": $ts,
  "advisor": {"applied": false, "hold_multiplier": 1.0, "prefer": "none"},
  "links": {
    "$primary": {"score":$p_score,"hard_up":true,"suppressed":$p_supp,"loss_pct":0.0,"rtt_p90_ms":10.0,"jitter_ms":1.0,"baseline_ms":10.0,"healthy_since":1,"better_since":1},
    "$backup": {"score":$b_score,"hard_up":true,"suppressed":$b_supp,"loss_pct":0.0,"rtt_p90_ms":30.0,"jitter_ms":2.0,"baseline_ms":30.0,"healthy_since":1,"better_since":1}
  }
}
EOF
}

echo "=== 1. on primary, both healthy -> OK WAN_PRIMARY ==="
f="$TMP/on-primary-healthy.json"; mk_status "$f" X1 X1 X2 HOLD false "$FRESH" 100 false 100 false
out="$(run "$f")"; check "verdict tag" "verdict: OK WAN_PRIMARY" "$out"
check_rc "exit code 0" 0 "$(run_rc "$f")"
check "detail shows suppressed=false, not '?' (jq '//' falsy-on-false regression)" "suppressed=false" "$out"

echo "=== 2. on backup, both healthy -> OK WAN_BACKUP ==="
f="$TMP/on-backup-healthy.json"; mk_status "$f" X2 X1 X2 SOFT_SWITCH false "$FRESH" 90 false 100 false
out="$(run "$f")"; check "verdict tag" "verdict: OK WAN_BACKUP" "$out"
check_rc "exit code 0" 0 "$(run_rc "$f")"

echo "=== 3. active link degraded (score 40, not suppressed) -> WARN WAN_DEGRADED ==="
f="$TMP/active-degraded.json"; mk_status "$f" X1 X1 X2 HOLD false "$FRESH" 40 false 100 false
out="$(run "$f")"; check "verdict tag" "verdict: WARN WAN_DEGRADED" "$out"

echo "=== 4. a link suppressed (backup, while active is otherwise healthy) -> WARN WAN_FLAP_SUPPRESSED ==="
f="$TMP/link-suppressed.json"; mk_status "$f" X1 X1 X2 HOLD false "$FRESH" 100 false 60 true
out="$(run "$f")"; check "verdict tag" "verdict: WARN WAN_FLAP_SUPPRESSED" "$out"
check "prose names the suppressed link" "X2" "$out"

echo "=== 5. both links dead, state BOTH_BAD_HOLD -> FAIL WAN_BOTH_DEGRADED ==="
f="$TMP/both-dead.json"; mk_status "$f" X1 X1 X2 BOTH_BAD_HOLD false "$FRESH" 10 false 5 false
out="$(run "$f")"; check "verdict tag" "verdict: FAIL WAN_BOTH_DEGRADED" "$out"
check_rc "exit code 0 (diagnosis ran)" 0 "$(run_rc "$f")"

echo "=== 6. stale status.json (ts far in the past) -> FAIL WAN_PROBE_FAILED ==="
f="$TMP/stale.json"; mk_status "$f" X1 X1 X2 HOLD false "$STALE" 100 false 100 false
out="$(run "$f")"; check "verdict tag" "verdict: FAIL WAN_PROBE_FAILED" "$out"
check_rc "exit code 0 (diagnosis ran)" 0 "$(run_rc "$f")"

echo "=== 7. missing status.json -> FAIL WAN_PROBE_FAILED ==="
f="$TMP/does-not-exist.json"
out="$(run "$f")"; check "verdict tag" "verdict: FAIL WAN_PROBE_FAILED" "$out"
check_rc "exit code 0 (diagnosis ran)" 0 "$(run_rc "$f")"

echo "=== 8. edge case: invalid JSON -> FAIL WAN_PROBE_FAILED ==="
f="$TMP/invalid.json"; printf 'not valid json {' > "$f"
out="$(run "$f")"; check "verdict tag" "verdict: FAIL WAN_PROBE_FAILED" "$out"

echo "=== 9. edge case: active is null (data anomaly) -> WARN WAN_DEGRADED ==="
f="$TMP/active-null.json"; mk_status "$f" null X1 X2 HOLD false "$FRESH" 100 false 100 false
out="$(run "$f")"; check "verdict tag" "verdict: WARN WAN_DEGRADED" "$out"

echo "=== 10. edge case: .degraded==true (sensing failure this cycle) -> WARN WAN_DEGRADED ==="
f="$TMP/sensing-degraded.json"; mk_status "$f" X1 X1 X2 HOLD true "$FRESH" 100 false 100 false
out="$(run "$f")"; check "verdict tag" "verdict: WARN WAN_DEGRADED" "$out"

echo "=== 11. both_degraded disjunct A alone: state==BOTH_BAD_HOLD but link scores healthy -> FAIL WAN_BOTH_DEGRADED ==="
f="$TMP/both-bad-hold-state-only.json"; mk_status "$f" X1 X1 X2 BOTH_BAD_HOLD false "$FRESH" 100 false 100 false
out="$(run "$f")"; check "verdict tag" "verdict: FAIL WAN_BOTH_DEGRADED" "$out"

echo "=== 12. both_degraded disjunct B alone: both links dead by score but state!=BOTH_BAD_HOLD -> FAIL WAN_BOTH_DEGRADED ==="
f="$TMP/both-dead-scores-state-hold.json"; mk_status "$f" X1 X1 X2 HOLD false "$FRESH" 10 false 5 false
out="$(run "$f")"; check "verdict tag" "verdict: FAIL WAN_BOTH_DEGRADED" "$out"

echo "=== 13. valid JSON but missing a required field (.state absent) -> FAIL WAN_PROBE_FAILED ==="
f="$TMP/missing-required-field.json"
cat > "$f" <<EOF
{
  "active": "X1",
  "primary": "X1", "backup": "X2",
  "rank_order": ["X1","X2"],
  "degraded": false,
  "dwell_s": 600.0,
  "last_write": null,
  "writes_last_hour": 0,
  "reason": "test fixture - .state deliberately omitted",
  "ts": $FRESH,
  "advisor": {"applied": false, "hold_multiplier": 1.0, "prefer": "none"},
  "links": {
    "X1": {"score":100,"hard_up":true,"suppressed":false,"loss_pct":0.0,"rtt_p90_ms":10.0,"jitter_ms":1.0,"baseline_ms":10.0,"healthy_since":1,"better_since":1},
    "X2": {"score":100,"hard_up":true,"suppressed":false,"loss_pct":0.0,"rtt_p90_ms":30.0,"jitter_ms":2.0,"baseline_ms":30.0,"healthy_since":1,"better_since":1}
  }
}
EOF
out="$(run "$f")"; check "verdict tag" "verdict: FAIL WAN_PROBE_FAILED" "$out"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
