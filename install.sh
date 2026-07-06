#!/usr/bin/env bash
# install.sh — set up small-model-skills on this machine.
#   copies runtime (bin/lib/modules) -> $XDG_DATA_HOME/small-model-skills
#   symlinks wrappers -> a bin dir on PATH (override with SMS_BINDIR)
#   installs skills -> ~/.claude/skills
#   seeds ~/.config/small-model-skills/config from config.example (if absent)
#   checks dependencies
set -euo pipefail
SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/small-model-skills"
BINDIR="${SMS_BINDIR:-$HOME/.local/bin}"
SKILLS="$HOME/.claude/skills"
CFG="$HOME/.config/small-model-skills/config"

echo "small-model-skills installer"
echo "  source : $SRC"
echo "  runtime: $DATA"
echo "  bin    : $BINDIR   (must be on PATH)"
echo "  skills : $SKILLS"
echo

# 1. copy runtime
mkdir -p "$DATA"
cp -a "$SRC/bin" "$SRC/modules" "$DATA/"
chmod +x "$DATA"/bin/* 2>/dev/null || true

# 2. symlink wrappers onto PATH (skip the lib/ dir)
mkdir -p "$BINDIR"
n=0; for f in "$DATA"/bin/*; do [ -f "$f" ] || continue; ln -sf "$f" "$BINDIR/$(basename "$f")"; n=$((n+1)); done
echo "linked $n wrappers into $BINDIR"

# 3. install skills
mkdir -p "$SKILLS"
if compgen -G "$SRC/skills/*/" >/dev/null; then
  for d in "$SRC"/skills/*/; do cp -a "$d" "$SKILLS/$(basename "$d")"; done
  echo "installed skills: $(ls "$SRC/skills" | tr '\n' ' ')"
else
  echo "(no skills/ to install yet)"
fi

# 4. config
if [ ! -f "$CFG" ]; then
  mkdir -p "$(dirname "$CFG")"; cp "$SRC/config.example" "$CFG"; chmod 600 "$CFG"
  echo "created $CFG  <-- EDIT with your gateway / DNS / WAN interface / router values"
else
  echo "config exists ($CFG) — left as-is"
fi

# 5. dependency check
echo "-- dependencies --"
for c in ip dig ping snmpwalk curl jq systemctl journalctl df du ps free nproc; do
  if command -v "$c" >/dev/null 2>&1; then printf '  ok   %s\n' "$c"; else printf '  MISS %s (some skills degrade without it)\n' "$c"; fi
done
case ":$PATH:" in *":$BINDIR:"*) : ;; *) echo "  WARNING: $BINDIR is not on PATH — add it to use the wrappers by name.";; esac

echo
echo "Done. Next:"
echo "  1) edit $CFG"
echo "  2) make sure Ollama + a tool-capable model + a 'freeclaude' offline launcher are set up (see README)"
echo "  3) ask your offline model: 'diagnose the network' / 'why is my computer slow' / 'prep this project for offline'"
