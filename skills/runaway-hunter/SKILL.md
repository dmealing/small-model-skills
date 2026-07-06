---
name: runaway-hunter
description: Find aged, high-CPU, zombie, or wedged processes that peg a core for hours — the classic freeze precursors — and propose the right kill. Use when load is high, fans are loud, or a process has been running for a very long time. Companion to system-triage, adding the process-age dimension.
x-wrappers: [runaway-hunter]
---

# runaway-hunter

Use when the machine is hot, loud, or slow and you suspect a stuck or runaway process. Complements `system-triage`: it adds the *age* dimension plus zombie/uninterruptible detection a one-shot snapshot misses.

## Steps
1. Run `runaway-hunter`. It lists (read-only): processes that are both high-CPU AND long-running, zombie/wedged processes, and any configured known offenders — with a verdict.
2. If the verdict is `RUNAWAY / WEDGED PROCESSES FOUND`, read the tables. For each candidate:
   - Inspect it first: propose `ps -fp <pid>`.
   - Propose stopping it: `kill <pid>`, and only if it ignores that, `kill -9 <pid>`.
3. Never kill a process yourself, and never propose killing one that may be mid-write (a backup, a DB flush).
4. Report which processes look runaway and the proposed commands.

Read-only: it reads the process table and proposes kills; it runs none of them.
