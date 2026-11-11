#!/usr/bin/env bash
# smart-health distrusted-sensor test. A fake `smartctl` (and a pass-through `sudo`) on PATH replay
# NVMe SMART fixtures, so the verdict for a stuck temperature sensor is checked without real drives.
set -uo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
PROBE="$REPO/bin/smart-health"

TMP="$(mktemp -d /tmp/smart-health-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/stub"
# shellcheck disable=SC2016  # single quotes: the stub script body must keep its $ references literal
printf '#!/bin/sh\ncat "$FAKE_SMART"\n' > "$TMP/stub/smartctl"
# shellcheck disable=SC2016
printf '#!/bin/sh\n[ "$1" = -n ] && shift\nexec "$@"\n' > "$TMP/stub/sudo"
chmod +x "$TMP/stub/smartctl" "$TMP/stub/sudo"

# nvme <file> <health> <crit> <composite> <s1> <s2> <media> <spare> <used>
nvme(){
  cat > "$1" <<EOF
SMART overall-health self-assessment test result: $2
SMART/Health Information (NVMe Log 0x02)
Critical Warning:                   $3
Temperature:                        $4 Celsius
Available Spare:                    $8%
Available Spare Threshold:          10%
Percentage Used:                    $9%
Media and Data Integrity Errors:    $7
Error Information Log Entries:      0
Temperature Sensor 1:               $5 Celsius
Temperature Sensor 2:               $6 Celsius
EOF
}

run(){ FAKE_SMART="$1" SMART_DEVICES=/dev/nvme9n1 SMOLS_CONFIG=/dev/null PATH="$TMP/stub:$PATH" "$PROBE" 2>/dev/null; }

PASS=0; FAIL=0
check(){ local desc="$1" exp="$2" act="$3"
  if printf '%s' "$act" | grep -q -- "$exp"; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc — expected '$exp', got: $act"; FAIL=$((FAIL+1)); fi; }
v(){ printf '%s\n' "$1" | grep '^verdict:'; }

echo "=== stuck sensor 1 pinned hot, sensor 2 normal, otherwise healthy ==="
nvme "$TMP/stuck" FAILED! 0x02 84 84 60 0 100 4
check "no distrust config: FAIL as before" "FAIL DRIVE_FAILING" "$(v "$(run "$TMP/stuck")")"
out="$(SMART_DISTRUST_SENSORS=nvme9n1:1 run "$TMP/stuck")"
check "distrusted sensor: no FAIL (OK)" "verdict: OK NOMINAL" "$out"
check "drive row uses the trusted temperature" "PASSED\*,4%wear,100%spare,60C" "$out"
check "the override is explained in a note" "ignoring distrusted Temperature Sensor 1 (84C" "$out"
check "full device path also accepted" "verdict: OK" "$(v "$(SMART_DISTRUST_SENSORS=/dev/nvme9n1:1 run "$TMP/stuck")")"
check "a different device's sensor is not distrusted" "FAIL DRIVE_FAILING" "$(v "$(SMART_DISTRUST_SENSORS=nvme0n1:1 run "$TMP/stuck")")"

echo "=== real faults on the same drive still FAIL ==="
nvme "$TMP/media" FAILED! 0x02 84 84 60 3 100 4
check "media errors still FAIL" "FAIL DRIVE_FAILING — /dev/nvme9n1: 3 media" "$(v "$(SMART_DISTRUST_SENSORS=nvme9n1:1 run "$TMP/media")")"
nvme "$TMP/media-ok" PASSED 0x00 40 40 38 1 100 4
check "a media error FAILs even on a cool, PASSED drive" "FAIL DRIVE_FAILING" "$(v "$(run "$TMP/media-ok")")"
nvme "$TMP/spare" FAILED! 0x03 84 84 60 0 5 4
check "another critical bit (spare 0x01) with 0x02 still FAILs" "critical warning 0x03" "$(v "$(SMART_DISTRUST_SENSORS=nvme9n1:1 run "$TMP/spare")")"
nvme "$TMP/rel" FAILED! 0x04 50 50 48 0 100 4
check "reliability bit 0x04 still FAILs" "critical warning 0x04" "$(v "$(SMART_DISTRUST_SENSORS=nvme9n1:1 run "$TMP/rel")")"
nvme "$TMP/wear" FAILED! 0x02 84 84 60 0 100 97
check "wear past the critical threshold still FAILs" "97% wear" "$(v "$(SMART_DISTRUST_SENSORS=nvme9n1:1 run "$TMP/wear")")"
nvme "$TMP/lowspare" FAILED! 0x02 84 84 60 0 15 4
check "low spare still WARNs" "WARN DRIVE_AGING — /dev/nvme9n1: 15% spare" "$(v "$(SMART_DISTRUST_SENSORS=nvme9n1:1 run "$TMP/lowspare")")"

echo "=== the drive really is hot: the override must not apply ==="
nvme "$TMP/hot" FAILED! 0x02 84 84 80 0 100 4
check "other sensor also hot: FAIL" "FAIL DRIVE_FAILING" "$(v "$(SMART_DISTRUST_SENSORS=nvme9n1:1 run "$TMP/hot")")"
nvme "$TMP/hotter" FAILED! 0x02 90 84 60 0 100 4
check "composite hotter than the distrusted sensor: FAIL" "FAIL DRIVE_FAILING" "$(v "$(SMART_DISTRUST_SENSORS=nvme9n1:1 run "$TMP/hotter")")"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
