#!/usr/bin/env bash
# SonicWall (SonicOS 7.x) router module for small-model-skills.
# Read-only REST enrichment for router-status. Exposes: router_module_enrich
# Prints firmware/model/uptime, failover-LB topology, and WAN interface IPs.
# Requires curl + jq. Credentials come from, in order: ROUTER_CRED_CMD (a command printing
# "user=..."/"pass=..." lines, e.g. a secrets-manager CLI), ROUTER_CRED_FILE (offline-safe), then
# ROUTER_CRED_ITEM via op-get (online only). A source that fails or yields no user+pass falls
# through to the next. GET-only — never changes config.

# Sets U, P, SRC in the caller's scope (declare them local there). Never prints a value.
sonicwall_resolve_cred(){
  local c
  if [ -n "${ROUTER_CRED_CMD:-}" ]; then
    if c=$(bash -c "$ROUTER_CRED_CMD" 2>/dev/null </dev/null) && [ -n "$c" ]; then
      U=$(printf '%s\n' "$c" | sed -n 's/^user=//p' | head -n1); P=$(printf '%s\n' "$c" | sed -n 's/^pass=//p' | head -n1)
      SRC="credential command"
    fi
    c=""
    [ -n "$U" ] && [ -n "$P" ] && return
    U=""; P=""; SRC=""
  fi
  if [ -n "${ROUTER_CRED_FILE:-}" ] && [ -r "$ROUTER_CRED_FILE" ]; then
    U=$(sed -n 's/^user=//p' "$ROUTER_CRED_FILE"); P=$(sed -n 's/^pass=//p' "$ROUTER_CRED_FILE"); SRC="cached file"
  elif [ -n "${ROUTER_CRED_ITEM:-}" ] && have op-get; then
    c=$(op-get "$ROUTER_CRED_ITEM" 2>/dev/null); U="${c%%,*}"; P="${c#*,}"; SRC="op-get (online)"
  fi
}

router_module_enrich(){
  have curl && have jq || { echo "  (sonicwall: curl/jq missing — skipping REST enrichment)"; return; }
  local U="" P="" SRC="" B
  sonicwall_resolve_cred
  [ -n "$U" ] && [ -n "$P" ] || { echo "  (sonicwall: no credential available — SNMP above is the offline signal)"; return; }
  B="https://${ROUTER_HOST}:${ROUTER_API_PORT:-8443}/api/sonicos"
  local A=(-k -s -u "$U:$P" --max-time 8)
  curl "${A[@]}" -X POST "$B/auth" --data '{"override":false}' -H 'Content-Type: application/json' -o /dev/null || { echo "  (sonicwall: REST auth failed)"; return; }
  smols_sec "router detail (REST via $SRC)"
  curl "${A[@]}" "$B/version" | jq -r '"  \(.model)  \(.firmware_version)  (up \(.system_uptime))"' 2>/dev/null
  curl "${A[@]}" "$B/failover-lb/groups" | jq -r '.failover_lb.group[]? | "  LB: \(.name|gsub("^ +";"")) | type=\(.type) preempt=\(.preempt) final_backup=\(.final_backup)"' 2>/dev/null
  curl "${A[@]}" "$B/interfaces/ipv4" | jq -r '.interfaces[]?.ipv4 | select(.ip_assignment.zone=="WAN") | "  \(.name) [WAN] mode=\(.ip_assignment.mode|keys[0]) ip=\(.ip_assignment.mode[(.ip_assignment.mode|keys[0])].ip // "dynamic")"' 2>/dev/null
  curl "${A[@]}" -X DELETE "$B/auth" -o /dev/null
}
