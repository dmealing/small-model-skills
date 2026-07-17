#!/usr/bin/env bash
# install.sh — set up small-model-skills on this machine.
#   copies runtime (bin/lib/modules) -> $XDG_DATA_HOME/small-model-skills
#   symlinks wrappers -> a bin dir on PATH (override with SMOLS_BINDIR)
#   installs skills — scope chosen by `--global`/`--local` flag, SMOLS_SKILLS_SCOPE env, a remembered
#   prior choice, or an interactive prompt (default global); remembered across runs:
#     global (default) -> ~/.claude/skills so EVERY `claude` session can use them, plus a curated
#                         cc-home view (symlinks) that exposes ONLY these to `claude-local`
#     local            -> cc-home ONLY (claude-local); scrubs ~/.claude/skills so a normal `claude`
#                         session doesn't load them
#   seeds ~/.config/small-model-skills/config from config.example (if absent)
#   checks dependencies
set -euo pipefail

# Bare (non-WSL2) Windows has no supported backend — point at WSL2 instead of failing deep
# inside some later script with a confusing missing-command error.
case "${OSTYPE:-}" in
  msys|cygwin|win32)
    echo "small-model-skills doesn't support native Windows — it needs a POSIX shell + coreutils."
    echo "Install WSL2 (https://learn.microsoft.com/windows/wsl/install), then run this installer"
    echo "from inside your WSL2 Linux distro — it uses the same Linux backend as a native install."
    exit 1
    ;;
esac
case "$(uname -s 2>/dev/null)" in
  Darwin) SMOLS_OS=macos ;;
  *) SMOLS_OS=linux ;;  # includes WSL2 — same backend as native Linux
esac

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/small-model-skills"
BINDIR="${SMOLS_BINDIR:-$HOME/.local/bin}"
SKILLS="$HOME/.claude/skills"          # global skills dir (loaded by every `claude`) — used in 'global' scope
CFG="$HOME/.config/small-model-skills/config"
CC_HOME="$(dirname "$CFG")/cc-home"    # claude-local's curated CLAUDE_CONFIG_DIR (always holds only these skills)

# Skill scope — where skills install:
#   global (default): ~/.claude/skills, so EVERY `claude` session loads them (+ a curated cc-home for claude-local)
#   local           : cc-home ONLY (claude-local); kept OUT of ~/.claude/skills so a normal `claude` won't load them
# Pick it any of these ways (first that resolves wins); the choice is remembered in SCOPE_FILE so a later bare
# `./install.sh` keeps it instead of reverting to the default:
#   1) flag:    ./install.sh --local | --global   (or --scope=local|global)
#   2) env:     SMOLS_SKILLS_SCOPE=local|global ./install.sh
#   3) memory:  what a previous run recorded in SCOPE_FILE
#   4) prompt:  interactive ask (TTY only), defaulting to global
SCOPE_FILE="$CC_HOME/.skills-scope"
SCOPE=""
for arg in "$@"; do case "$arg" in
  --local|--scope=local)   SCOPE="local" ;;
  --global|--scope=global) SCOPE="global" ;;
  -h|--help)
    echo "usage: install.sh [--global|--local]"
    echo "  --global  (default) install skills to ~/.claude/skills for ALL claude sessions + a curated claude-local view"
    echo "  --local   install skills to claude-local ONLY (cc-home); keep them out of normal claude sessions"
    echo "  env SMOLS_SKILLS_SCOPE=global|local also works; either way your choice is remembered for next time"
    exit 0 ;;
esac; done
[ -z "$SCOPE" ] && [ -n "${SMOLS_SKILLS_SCOPE:-}" ] && SCOPE="$SMOLS_SKILLS_SCOPE"
[ -z "$SCOPE" ] && [ -f "$SCOPE_FILE" ] && SCOPE="$(cat "$SCOPE_FILE" 2>/dev/null)"
if [ -z "$SCOPE" ] && [ -t 0 ]; then
  printf 'Install skills for [g]lobal (every claude session) or [l]ocal-only (claude-local)? [G/l] '
  read -r _ans || _ans=""
  case "$_ans" in [Ll]*) SCOPE="local" ;; *) SCOPE="global" ;; esac
fi
[ -z "$SCOPE" ] && SCOPE="global"
case "$SCOPE" in global|local) ;; *) echo "warning: unknown scope '$SCOPE' — using global"; SCOPE="global" ;; esac

echo "small-model-skills installer"
echo "  OS     : $SMOLS_OS ($(uname -s 2>/dev/null))"
echo "  source : $SRC"
echo "  runtime: $DATA"
echo "  bin    : $BINDIR   (must be on PATH)"
if [ "$SCOPE" = local ]; then echo "  skills : $CC_HOME/skills   (scope=local — claude-local only, not ~/.claude/skills)"
else echo "  skills : $SKILLS   (scope=global — all sessions) + curated cc-home for claude-local"; fi
echo

# 1. copy runtime. rm the dests first: 'cp -a src dest' nests when dest exists (dest/src) and a
#    plain merge-copy leaves stale files (a wrapper deleted from the repo would linger installed).
mkdir -p "$DATA"
rm -rf "$DATA/bin" "$DATA/modules" "$DATA/monitor"
cp -a "$SRC/bin" "$SRC/modules" "$DATA/"
[ -d "$SRC/monitor" ] && cp -a "$SRC/monitor" "$DATA/"   # the smon system monitor (bin/ + test/)
chmod +x "$DATA"/bin/* "$DATA"/monitor/bin/* 2>/dev/null || true

# 2. symlink wrappers onto PATH (skip the lib/ dir). Prune dangling links from a prior install
#    first so a removed wrapper's symlink doesn't linger.
mkdir -p "$BINDIR"
for l in "$BINDIR"/*; do [ -L "$l" ] && [ ! -e "$l" ] && rm -f "$l"; done 2>/dev/null || true
n=0; for f in "$DATA"/bin/*; do [ -f "$f" ] || continue; ln -sf "$f" "$BINDIR/$(basename "$f")"; n=$((n+1)); done
# smon (the monitor orchestrator) also goes on PATH, from monitor/bin.
if [ -x "$DATA/monitor/bin/smon" ]; then ln -sf "$DATA/monitor/bin/smon" "$BINDIR/smon"; n=$((n+1)); fi
echo "linked $n commands into $BINDIR"

# 3. install skills. cc-home always holds ONLY these skills (curated view for claude-local, whose small
# model's tool-selection degrades as the skill count grows). The SCOPE decides whether they ALSO live in
# ~/.claude/skills for normal sessions. rm each dest first: 'cp -a src dest' nests when dest already exists
# (dest/src), silently keeping a stale SKILL.md on re-install.
if compgen -G "$SRC/skills/*/" >/dev/null; then
  mkdir -p "$CC_HOME/skills"
  for d in "$SRC"/skills/*/; do
    n="$(basename "$d")"
    if [ "$SCOPE" = local ]; then
      # local: the real copy lives in cc-home; scrub the global dir so a normal `claude` won't load it.
      rm -rf "$SKILLS/$n"
      dst="$CC_HOME/skills/$n"; rm -rf "$dst"; cp -a "$d" "$dst"
    else
      # global: real copy in ~/.claude/skills (all sessions); cc-home just symlinks to it (stays in sync).
      mkdir -p "$SKILLS"; rm -rf "$SKILLS/$n"; cp -a "$d" "$SKILLS/$n"
      rm -rf "$CC_HOME/skills/$n"; ln -sfn "$SKILLS/$n" "$CC_HOME/skills/$n"
    fi
  done
  mkdir -p "$CC_HOME"; printf '%s' "$SCOPE" > "$SCOPE_FILE"   # remember the scope for future bare re-runs
  echo "installed skills [scope=$SCOPE]: $(ls "$SRC/skills" | tr '\n' ' ')"
  # Seed a credential-free, MCP-free minimal .claude.json so Claude Code doesn't re-prompt onboarding/theme
  # in this separate config home. Do NOT copy ~/.claude.json wholesale: it carries oauthAccount (credentials),
  # mcpServers (cloud servers curated/offline mode must not start), and projects (per-project trust/history).
  # Strip those with jq, keeping the onboarding/theme flags; fall back to '{}' when jq is absent or the parse
  # fails. chmod 600 the result — its source is 600 and a plain cp under a lax umask would widen it.
  if [ -f "$HOME/.claude.json" ] && [ ! -f "$CC_HOME/.claude.json" ]; then
    if command -v jq >/dev/null 2>&1 \
       && jq 'del(.oauthAccount, .mcpServers, .projects, .history)' "$HOME/.claude.json" > "$CC_HOME/.claude.json" 2>/dev/null; then
      :
    else
      printf '{}' > "$CC_HOME/.claude.json"
    fi
    chmod 600 "$CC_HOME/.claude.json"
  fi
  if [ -f "$HOME/.claude/settings.json" ] && cp "$HOME/.claude/settings.json" "$CC_HOME/settings.json" 2>/dev/null; then
    chmod 600 "$CC_HOME/settings.json"
  fi
  echo "curated skills home: $CC_HOME ($(ls "$CC_HOME/skills" 2>/dev/null | wc -l) skills for claude-local)"
fi

# 4. config
if [ ! -f "$CFG" ]; then
  mkdir -p "$(dirname "$CFG")"; cp "$SRC/config.example" "$CFG"; chmod 600 "$CFG"
  echo "created $CFG  <-- EDIT with your gateway / DNS / WAN interface / router values"
else
  echo "config exists ($CFG) — left as-is"
fi

# 5. dependency check (OS-aware — macOS uses native tools that replace ip/systemctl/etc.)
echo "-- dependencies --"
common_deps="dig ping snmpwalk curl jq df du ps"
if [ "$SMOLS_OS" = macos ]; then
  os_deps="sysctl vm_stat route ifconfig launchctl log"
else
  os_deps="ip systemctl journalctl free nproc"
fi
for c in $common_deps $os_deps; do
  if command -v "$c" >/dev/null 2>&1; then printf '  ok   %s\n' "$c"; else printf '  MISS %s (some skills degrade without it)\n' "$c"; fi
done
case ":$PATH:" in *":$BINDIR:"*) : ;; *) echo "  WARNING: $BINDIR is not on PATH — add it to use the wrappers by name.";; esac

echo
echo "Done. Next:"
echo "  1) edit $CFG"
echo "  2) make sure Ollama + a tool-capable model are set up, then launch with 'claude-local' (installed above; see README)"
echo "  3) ask your offline model: 'diagnose the network' / 'why is my computer slow' / 'prep this project for offline'"
