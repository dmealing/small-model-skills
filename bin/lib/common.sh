#!/usr/bin/env bash
# common.sh — OS detection + shared config loader + helpers for small-model-skills wrappers.
# Sourced by every bin/ wrapper. Read-only; defines no side effects beyond loading config.

have(){ command -v "$1" >/dev/null 2>&1; }
# smols_timeout <seconds> <cmd...> — run an EXTERNAL command with a wall-clock cap so a slow tool (a `du`
# over a huge tree, a hung mount) can't hang a wrapper past the model's patience. Uses timeout/gtimeout
# where available; degrades to running uncapped if neither is present. Exit 124 = it was killed for time.
smols_timeout(){ local s="$1"; shift
  if have timeout; then command timeout "$s" "$@"
  elif have gtimeout; then command gtimeout "$s" "$@"
  else smols_timeout_warn; "$@"; fi; }
# smols_timeout_warn — one-time stderr note that this host has neither timeout nor gtimeout, so smols_timeout
# can't enforce a wall-clock cap and a huge tree runs uncapped. Call it from a wrapper's PARENT context:
# the real callers redirect smols_timeout's own stderr to /dev/null (to hush the wrapped tool), so a note
# printed from inside smols_timeout is swallowed there. Prints at most once per process via the sentinel.
smols_timeout_warn(){
  { have timeout || have gtimeout; } && return 0
  [ -n "${_SMS_NO_TIMEOUT_WARNED:-}" ] && return 0
  _SMS_NO_TIMEOUT_WARNED=1
  echo "note: no timeout/gtimeout found — search/du not time-bounded on this host (install coreutils for gtimeout on macOS)" >&2
}
# smols_is_timeout <exit-code> — true if a command was killed by smols_timeout for running past its cap.
# 124 = GNU/coreutils timeout; 143 = 128+SIGTERM (BusyBox timeout); 137 = 128+SIGKILL.
smols_is_timeout(){ case "${1:-}" in 124|137|143) return 0 ;; *) return 1 ;; esac; }
smols_human(){ awk -v b="${1:-0}" 'BEGIN{split("B KB MB GB TB PB",u," "); i=1; while(b>=1024 && i<6){b/=1024;i++} printf (i==1?"%d %s":"%.1f %s"), b, u[i]}'; }

# --- OS detection (WSL2 counts as linux; override SMOLS_OS=linux|macos for manual testing) ---
if [ -z "${SMOLS_OS:-}" ]; then
  case "$(uname -s 2>/dev/null)" in
    Darwin) SMOLS_OS=macos ;;
    Linux)
      if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
        SMOLS_OS=linux   # WSL2 — runs the Linux backend unmodified
      else
        SMOLS_OS=linux
      fi
      ;;
    *) SMOLS_OS=linux ;;  # best-effort fallback for anything untested
  esac
fi
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$LIB_DIR/os-$SMOLS_OS.sh" ]; then
  # shellcheck disable=SC1090
  . "$LIB_DIR/os-$SMOLS_OS.sh"
else
  echo "common.sh: no os-$SMOLS_OS.sh backend (unsupported OS: $(uname -s 2>/dev/null))" >&2
  exit 1
fi

# --- load user config (host-specific values live here, never in the repo) ---
SMOLS_CONFIG="${SMOLS_CONFIG:-$HOME/.config/small-model-skills/config}"
# shellcheck disable=SC1090
[ -r "$SMOLS_CONFIG" ] && . "$SMOLS_CONFIG"

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
[ -n "$GATEWAY_IP" ] || GATEWAY_IP="$(smols_default_gw)"
[ -n "$PRIMARY_NIC" ] || PRIMARY_NIC="$(smols_default_iface)"
: "${ROUTER_HOST:=$GATEWAY_IP}"

# --- diagnostics tuning (ollama-doctor / runaway-hunter / freeze-forensics) ---
: "${OLLAMA_URL:=http://localhost:11434}"
: "${RUNAWAY_CPU_PCT:=50}"
: "${RUNAWAY_AGE_HOURS:=4}"
: "${RUNAWAY_OFFENDERS:=}"
: "${KNOWN_BAD_KERNELS:=}"
: "${FREEZE_REMOTE_LOG_CMD:=}"

# --- verdict thresholds (config-tunable; the monitoring probes key their WARN/FAIL on these) ---
: "${DISK_WARN_PCT:=85}"     # fullest filesystem at/above this % -> disk-report WARN
: "${DISK_CRIT_PCT:=95}"     # ...at/above this % -> disk-report FAIL
: "${LOAD_WARN_FACTOR:=1.5}" # 1-min load above cores*factor -> sys-diag WARN (HIGH_LOAD)
: "${CPU_HOG_PCT:=90}"       # a single process at/above this %core -> sys-diag WARN (CPU_HOG)
: "${SWAP_WARN_KB:=1048576}" # swap-in-use above this (KiB) -> sys-diag WARN (MEMORY_PRESSURE)
: "${TEMP_WARN_C:=85}"       # any CPU/GPU temp at/above this (°C) -> sys-diag WARN (THERMAL)

# --- output helpers (keep digests short — a weak model's context is scarce) ---
smols_identity(){ printf 'bin: %s\ndescription: %s\n\n' "$0" "$1"; }
smols_sec(){ echo "-- $1 --"; }
smols_line(){ printf '  %-22s %s\n' "$1" "$2"; }
smols_toon(){ # smols_toon <array-name> <fields> <<< "$rows" (rows: one comma-joined row per line, may be empty)
  local name="$1" fields="$2" rows n
  rows="$(cat)"
  if [ -z "$rows" ]; then n=0; else n=$(printf '%s\n' "$rows" | grep -c .); fi
  printf '%s[%d]{%s}:\n' "$name" "$n" "$fields"
  [ "$n" -gt 0 ] && printf '%s\n' "$rows" | sed 's/^/  /'
}
smols_help(){ local i=1; for h in "$@"; do echo "  help[$i]: $h"; i=$((i+1)); done; }

# smols_verdict <status> <tag> <prose...> — emit the ONE machine-greppable line every wrapper
# ends on. Format:  verdict: <OK|WARN|FAIL> <TAG> — <prose>   (always at column 0, one line).
# This is the monitoring contract: `smon` greps `^verdict:` from each probe and alerts on
# status/tag transitions, so the vocabulary is fixed:
#   OK   — nominal / healthy, nothing to do.
#   WARN — a real problem found that warrants attention but isn't an emergency.
#   FAIL — a critical state, OR the probe itself could not run. Both mean "look now": a broken
#          probe is lost visibility, which for a monitor is itself alert-worthy.
# TAG is a short SCREAMING_SNAKE label the monitor can key or escalate on (e.g. HIGH_LOAD,
# DISK_CRITICAL, DAEMON_DOWN, NOMINAL). Keep <prose> to a single sentence for weak-model
# context. The verdict STATUS is independent of the process exit code — a WARN still exits 0
# (the diagnosis ran); keep the wrapper's existing `exit` lines as they are.
smols_verdict(){ local s="$1" tag="$2"; shift 2; printf 'verdict: %s %s — %s\n' "$s" "$tag" "$*"; }

# smols_ps_rows: turns `ps` output shaped "pid comm... colA colB" (comm may contain spaces —
# common on macOS, e.g. "Microsoft Teams Helper (Renderer)") into "pid,comm,colA,colB" rows,
# without misreading embedded spaces in comm as extra columns.
smols_ps_rows(){ awk '{n=NF; comm=$2; for(i=3;i<=n-2;i++) comm=comm" "$i; printf "%s,%s,%s,%s\n",$1,comm,$(n-1),$n}'; }
