#!/usr/bin/env bash
# ROUTER_CRED_CMD hook test — sources the SonicWall module and checks credential resolution with
# stub commands: success, failure falls back to the file, empty/incomplete output falls back.
# Uses only fake values, no network; never prints a credential value.
set -uo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
have(){ command -v "$1" >/dev/null 2>&1; }
. "$REPO/modules/router/sonicwall.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/router-cred-cmd-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
printf 'user=fileuser\npass=filepass\n' > "$TMP/router.cred"

PASS=0; FAIL=0
# resolve <cmd>: prints "<user-matches>|<src>" without ever echoing the values
resolve(){ local U="" P="" SRC="" ROUTER_CRED_CMD="$1" ROUTER_CRED_FILE="${2-$TMP/router.cred}" ROUTER_CRED_ITEM=""
  sonicwall_resolve_cred; echo "$U/$P/$SRC"; }
check(){ # desc, expected, actual
  if [ "$3" = "$2" ]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (mismatch)"; FAIL=$((FAIL+1)); fi
}

echo "ROUTER_CRED_CMD hook"
check "command success wins over file" "cmduser/cmdpass/credential command" "$(resolve "printf 'user=cmduser\npass=cmdpass\n'")"
check "command failure falls back to file" "fileuser/filepass/cached file" "$(resolve "printf 'user=cmduser\npass=cmdpass\n'; exit 3")"
check "empty output falls back to file" "fileuser/filepass/cached file" "$(resolve "true")"
check "incomplete output falls back to file" "fileuser/filepass/cached file" "$(resolve "printf 'user=cmduser\n'")"
check "unset command uses file" "fileuser/filepass/cached file" "$(resolve "")"
check "command success with no file" "cmduser/cmdpass/credential command" "$(resolve "printf 'user=cmduser\npass=cmdpass\n'" /nonexistent)"
check "command failure and no file yields nothing" "//" "$(resolve "false" /nonexistent)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
