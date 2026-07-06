---
name: network-triage
description: Diagnose network and internet problems on this machine and its LAN. Use when the internet seems down, a site won't load, DNS is failing, connectivity is flaky, or when asked to check the network, WAN, or router/firewall. Works offline (LAN-only). Read-only — it diagnoses and proposes fixes for a human to run; it never changes configuration.
x-wrappers: [net-diag, router-status]
---

# Network triage

Diagnose a connectivity problem on this workstation and its LAN. This may run on a small local model with
no internet — use only the wrapper scripts below, do not fetch anything from the web, and do not rely on
memorized device syntax. The scripts read this machine's config and print the concrete facts.

## Rules
- Read-only. Run diagnostics freely. NEVER run a state-changing command (restart a service, bounce an
  interface, flush DNS, edit config) yourself — describe it and let the user run it.
- Use the wrappers; do not hand-compose raw `snmpwalk`/`curl` to the router.
- Keep it tight: run a step, read its verdict line, move on. Do not dump large output into your reply.

## Runbook
1. Run `net-diag`. Read its `verdict` line — it localizes the fault to: local link / gateway / DNS / ISP.
2. If the verdict points at ISP/WAN (gateway reachable but no internet): run `router-status`. Its verdict
   shows each WAN link up/down and which one carries traffic (primary vs backup / failover).
3. If net-diag's verdict says DNS (internet up but local DNS failing): report that the local DNS server is
   down and propose restarting it. net-diag already ran the resolver tests — do not re-run them.
4. If net-diag's verdict says LAN/local (gateway unreachable): cite the "local link" table net-diag already
   printed; the suspect is cable / Wi-Fi / switch, not the ISP.
5. Report a short plain-English summary: which layer is broken, the evidence, and the single most likely cause.
6. If a fix is warranted, PROPOSE it (flush DNS, restart a service, restart the DNS container) and WAIT for
   the user to run it. Do not execute state changes.

## Tools
- `net-diag` — read-only local / LAN / DNS / internet snapshot plus a verdict.
- `router-status` — read-only WAN and failover status (SNMP live signal plus optional router-module detail).
  Use `SW_SAMPLE_GAP=0 router-status` for an instant snapshot without the ~2s traffic-rate sample.
