#!/usr/bin/env bash
# SonicWall (SonicOS 7.x) router module for small-model-skills.
# Read-only REST enrichment for router-status. Exposes: router_module_enrich
# Prints firmware/model/uptime, failover-LB topology, and WAN interface IPs.
# Requires curl + jq. Credentials come from ROUTER_CRED_FILE (offline-safe) or
# ROUTER_CRED_ITEM via op-get (online only). GET-only — never changes config.

router_module_enrich(){
  have curl && have jq || { echo "  (sonicwall: curl/jq missing — skipping REST enrichment)"; return; }
  local U="" P="" SRC="" B c
  if [ -n "${ROUTER_CRED_FILE:-}" ] && [ -r "$ROUTER_CRED_FILE" ]; then
    U=$(sed -n 's/^user=//p' "$ROUTER_CRED_FILE"); P=$(sed -n 's/^pass=//p' "$ROUTER_CRED_FILE"); SRC="cached file"
  elif [ -n "${ROUTER_CRED_ITEM:-}" ] && have op-get; then
    c=$(op-get "$ROUTER_CRED_ITEM" 2>/dev/null); U="${c%%,*}"; P="${c#*,}"; SRC="op-get (online)"
  fi
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
