#!/usr/bin/env bash
# common.sh — shared config loader + helpers for small-model-skills wrappers.
# Sourced by every bin/ wrapper. Read-only; defines no side effects beyond loading config.

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
[ -n "$GATEWAY_IP" ] || GATEWAY_IP="$(ip route show default 2>/dev/null | awk '/default/{print $3; exit}')"
[ -n "$PRIMARY_NIC" ] || PRIMARY_NIC="$(ip route show default 2>/dev/null | awk '/default/{print $5; exit}')"
: "${ROUTER_HOST:=$GATEWAY_IP}"

# --- output helpers (keep digests short — a weak model's context is scarce) ---
have(){ command -v "$1" >/dev/null 2>&1; }
sms_head(){ echo "===== $1  $(date '+%F %T') ====="; }
sms_sec(){ echo "-- $1 --"; }
sms_line(){ printf '  %-22s %s\n' "$1" "$2"; }
sms_human(){ awk -v b="${1:-0}" 'BEGIN{split("B KB MB GB TB PB",u," "); i=1; while(b>=1024 && i<6){b/=1024;i++} printf (i==1?"%d %s":"%.1f %s"), b, u[i]}'; }
