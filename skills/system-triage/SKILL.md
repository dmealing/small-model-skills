---
name: system-triage
description: Diagnose why a Linux computer is slow or sluggish. Use when the machine feels slow, laggy, or unresponsive, when fans are loud, or when asked about high CPU, memory, load, or thermals. Read-only — it inspects and proposes; it changes nothing.
---

# System triage (why is it slow?)

Find what is making this workstation slow. Read-only.

## Rules
- Read-only. Do NOT kill processes, change limits, or restart services yourself — propose it; the user runs it.
- Use the `sys-diag` wrapper; read its verdict. Keep output short.

## Runbook
1. Run `sys-diag`. Read the `verdict` line and the top-CPU and top-memory tables.
2. Interpret the verdict:
   - HIGH LOAD or CPU HOG → one or more processes are saturating the CPU (see the top-CPU table).
   - MEMORY PRESSURE (swap in use) → RAM is exhausted (see the top-memory table).
   - Nominal but still slow → suspect disk I/O; if `iostat` is available (the sysstat package) propose
     `iostat -x 2`, otherwise investigate one specific app.
3. Report the single most likely culprit — name the process and PID from the table — and the evidence.
4. If action is warranted, PROPOSE it (for example "consider stopping PID <x> (<name>)" or "restart <service>")
   and WAIT for the user. NEVER kill or restart anything yourself.

## Tools
- `sys-diag` — read-only CPU / load / memory / top-process / thermal snapshot plus a verdict.
