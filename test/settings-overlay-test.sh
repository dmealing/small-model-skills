#!/usr/bin/env bash
# install.sh settings-overlay test — runs install.sh against a throwaway HOME (under $DEV_SCRATCH when set)
# and checks that the overlay in ~/.config/small-model-skills is merged over the copied settings.json.
# Never touches the real ~/.claude or cc-home. Needs jq.
set -uo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "skip: jq not installed"; exit 0; }
TMP="$(mktemp -d "${DEV_SCRATCH:-${TMPDIR:-/tmp}}/settings-overlay-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"; CFGD="$H/.config/small-model-skills"; S="$CFGD/cc-home/settings.json"
mkdir -p "$H/.claude" "$CFGD"
cat > "$H/.claude/settings.json" <<'JSON'
{"model":"opus","skillOverrides":{"keep-me":"off"},"env":{"A":"1"},
 "hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"keep-hook"},{"type":"command","command":"drop-hook"}]},
                          {"hooks":[{"type":"command","command":"drop-hook --only"}]}]}}
JSON
install(){ env -i PATH="$PATH" HOME="$H" XDG_DATA_HOME="$H/.local/share" SMOLS_BINDIR="$H/bin" \
  bash "$REPO/install.sh" --local </dev/null >"$TMP/out" 2>&1; }

PASS=0; FAIL=0
check(){ # desc, expected, actual
  if [ "$3" = "$2" ]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (want '$2', got '$3')"; FAIL=$((FAIL+1)); fi
}

echo "install.sh settings overlay"
install
check "no overlay: plain copy" "$(jq -S . "$H/.claude/settings.json")" "$(jq -S . "$S")"
check "web-search skill installed in cc-home" "yes" "$([ -f "$CFGD/cc-home/skills/web-search/SKILL.md" ] && echo yes)"

cp "$REPO/settings.overlay.example.json" "$CFGD/settings.overlay.json"
jq '. + {model: null, env: {B: "2"}}' "$CFGD/settings.overlay.json" > "$TMP/ov" && mv "$TMP/ov" "$CFGD/settings.overlay.json"
sed 's/example-tool-a|example-tool-b/drop-hook/' "$REPO/settings.overlay.example.jq" > "$CFGD/settings.overlay.jq"
install
check "objects merge key by key" "off/off" "$(jq -r '"\(.skillOverrides["keep-me"])/\(.skillOverrides.dataviz)"' "$S")"
check "scalar set" "0.03" "$(jq -r .skillListingBudgetFraction "$S")"
check "null removes key" "absent" "$(jq -r 'if has("model") then "present" else "absent" end' "$S")"
check "nested object merges" "1/2" "$(jq -r '"\(.env.A)/\(.env.B)"' "$S")"
check "jq filter drops hooks and empty groups" '["keep-hook"]' "$(jq -c '[.hooks.SessionStart[].hooks[].command]' "$S")"
check "settings stay mode 600" "600" "$(stat -c %a "$S" 2>/dev/null || stat -f %Lp "$S")"
check "source settings untouched" "drop-hook" "$(jq -r '.hooks.SessionStart[0].hooks[1].command' "$H/.claude/settings.json")"
first="$(jq -S . "$S")"; install
check "re-run is idempotent" "$first" "$(jq -S . "$S")"

printf '{"broken":' > "$CFGD/settings.overlay.json"
install
check "bad overlay warns" "yes" "$(grep -q 'settings overlay failed' "$TMP/out" && echo yes)"
check "bad overlay leaves the plain copy" "$(jq -S . "$H/.claude/settings.json")" "$(jq -S . "$S")"
check "no temp files left" "0" "$(find "$CFGD/cc-home" -maxdepth 1 -name '.settings.json.*' | wc -l | tr -d ' ')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
