# Adding a router vendor module

`router-status` gets its **live WAN link + traffic** signal from generic SNMP (IF-MIB), which works
on any SNMP-capable router — you only need to set `WAN_PRIMARY` / `WAN_BACKUP` (the interface names as
your router labels them) and `SNMP_COMMUNITY` in your config.

A **module** adds *vendor-specific* read-only detail (firmware, failover-group config, WAN IPs) on top.

## Contract

Create `modules/router/<vendor>.sh` defining one function:

```bash
router_module_enrich(){
  # Called after the SNMP table + verdict are printed.
  # Read-only ONLY. Print a short, human-readable block. Helpers available: have, smols_sec, smols_line.
  # Config available: ROUTER_HOST, ROUTER_API_PORT, SNMP_COMMUNITY, ROUTER_CRED_FILE, ROUTER_CRED_ITEM.
  # Degrade gracefully (missing creds/tools/endpoints must not error).
}
```

Then set `ROUTER_MODULE=<vendor>` in your config. See `sonicwall.sh` for a reference (SonicOS REST API).

Rules: **GET/read-only only** — never commit config, reboot, or change state. Never hardcode secrets;
pull them from `ROUTER_CRED_FILE` or a password manager. Keep output to a few lines.
