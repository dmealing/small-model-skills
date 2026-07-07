#!/usr/bin/env bash
# common.sh — OS detection + shared config loader + helpers for small-model-skills wrappers.
# Sourced by every bin/ wrapper. Read-only; defines no side effects beyond loading config.

have(){ command -v "$1" >/dev/null 2>&1; }
# sms_timeout <seconds> <cmd...> — run an EXTERNAL command with a wall-clock cap so a slow tool (a `du`
# over a huge tree, a hung mount) can't hang a wrapper past the model's patience. Uses timeout/gtimeout
# where available; degrades to running uncapped if neither is present. Exit 124 = it was killed for time.
sms_timeout(){ local s="$1"; shift
  if have timeout; then command timeout "$s" "$@"
  elif have gtimeout; then command gtimeout "$s" "$@"
  else "$@"; fi; }
sms_human(){ awk -v b="${1:-0}" 'BEGIN{split("B KB MB GB TB PB",u," "); i=1; while(b>=1024 && i<6){b/=1024;i++} printf (i==1?"%d %s":"%.1f %s"), b, u[i]}'; }

# --- OS detection (WSL2 counts as linux; override SMS_OS=linux|macos for manual testing) ---
if [ -z "${SMS_OS:-}" ]; then
  case "$(uname -s 2>/dev/null)" in
    Darwin) SMS_OS=macos ;;
    Linux)
      if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
        SMS_OS=linux   # WSL2 — runs the Linux backend unmodified
      else
        SMS_OS=linux
      fi
      ;;
    *) SMS_OS=linux ;;  # best-effort fallback for anything untested
  esac
fi
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$LIB_DIR/os-$SMS_OS.sh" ]; then
  # shellcheck disable=SC1090
  . "$LIB_DIR/os-$SMS_OS.sh"
else
  echo "common.sh: no os-$SMS_OS.sh backend (unsupported OS: $(uname -s 2>/dev/null))" >&2
  exit 1
fi

# --- load user config (host-specific values live here, never in the repo) ---
SMS_CONFIG="${SMS_CONFIG:-$HOME/.config/small-model-skills/config}"
# shellcheck disable=SC1090
[ -r "$SMS_CONFIG" ] && . "$SMS_CONFIG"

# --- defaults / auto-detection (safe fallbacks when config is absent) ---
: "${DNS_PUBLIC:=1.1.1.1}"
: "${DNS_PUBLIC2:=9.9.9.9}"
: "${DNS_LOCAL:=}"
: "${WAN_PRIMARY:=}"
: "${WAN_BACKUP:=}"
: "${PRIMARY_ISP_LABEL:=primary ISP}"
: "${BACKUP_ISP_LABEL:=backup link}"
: "${ROUTER_MODULE:=}"
: "${ROUTER_API_PORT:=443}"
: "${SNMP_COMMUNITY:=public}"
: "${ROUTER_CRED_ITEM:=}"
: "${ROUTER_CRED_FILE:=$HOME/.config/small-model-skills/router.cred}"
: "${GATEWAY_IP:=}"
: "${PRIMARY_NIC:=}"
[ -n "$GATEWAY_IP" ] || GATEWAY_IP="$(sms_default_gw)"
[ -n "$PRIMARY_NIC" ] || PRIMARY_NIC="$(sms_default_iface)"
: "${ROUTER_HOST:=$GATEWAY_IP}"

# --- diagnostics tuning (ollama-doctor / runaway-hunter / freeze-forensics) ---
: "${OLLAMA_URL:=http://localhost:11434}"
: "${RUNAWAY_CPU_PCT:=50}"
: "${RUNAWAY_AGE_HOURS:=4}"
: "${RUNAWAY_OFFENDERS:=}"
: "${KNOWN_BAD_KERNELS:=}"
: "${FREEZE_REMOTE_LOG_CMD:=}"

# --- output helpers (keep digests short — a weak model's context is scarce) ---
sms_identity(){ printf 'bin: %s\ndescription: %s\n\n' "$0" "$1"; }
sms_sec(){ echo "-- $1 --"; }
sms_line(){ printf '  %-22s %s\n' "$1" "$2"; }
sms_toon(){ # sms_toon <array-name> <fields> <<< "$rows" (rows: one comma-joined row per line, may be empty)
  local name="$1" fields="$2" rows n
  rows="$(cat)"
  if [ -z "$rows" ]; then n=0; else n=$(printf '%s\n' "$rows" | grep -c .); fi
  printf '%s[%d]{%s}:\n' "$name" "$n" "$fields"
  [ "$n" -gt 0 ] && printf '%s\n' "$rows" | sed 's/^/  /'
}
sms_help(){ local i=1; for h in "$@"; do echo "  help[$i]: $h"; i=$((i+1)); done; }

# sms_ps_rows: turns `ps` output shaped "pid comm... colA colB" (comm may contain spaces —
# common on macOS, e.g. "Microsoft Teams Helper (Renderer)") into "pid,comm,colA,colB" rows,
# without misreading embedded spaces in comm as extra columns.
sms_ps_rows(){ awk '{n=NF; comm=$2; for(i=3;i<=n-2;i++) comm=comm" "$i; printf "%s,%s,%s,%s\n",$1,comm,$(n-1),$n}'; }
