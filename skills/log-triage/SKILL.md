---
name: log-triage
description: Find broken services and recent errors on a Linux system via systemd and the journal. Use when a service will not start or keeps crashing, when asked what is failing or what is in the logs, or to check for recent errors. Read-only — it inspects logs and proposes next steps; it changes nothing.
x-wrappers: [log-triage]
---

# Log triage (what is broken / erroring?)

Find failed services and recent errors. Read-only.

## Rules
- Read-only. Do NOT restart, reset, or mask units, or edit configs yourself — propose it; the user runs it.
- Use the `log-triage` wrapper; read its output. Do not paste raw full logs into your reply.

## Runbook
1. Run `log-triage`. Read: failed units, recent error lines (last hour), and the top error sources this boot.
2. If there are FAILED units → name them. The next step is `systemctl status <unit>` and
   `journalctl -u <unit> -b --no-pager` — propose these; the user runs them if they want detail.
3. If there are no failed units but errors are logged → point at the top error source and suggest drilling
   in with `journalctl -u <name>`.
4. Report which service is broken (or that things are clean) and the single most likely cause.
5. PROPOSE any fix (restart a unit, correct a config) and WAIT for the user. NEVER restart or mask units yourself.

## Tools
- `log-triage` — read-only failed-units, recent-errors, and top-error-source summary.
