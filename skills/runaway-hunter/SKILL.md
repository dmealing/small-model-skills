---
name: runaway-hunter
description: Find aged, high-CPU, zombie, or wedged processes that peg a core for hours — the classic freeze precursors — and propose the right kill. Use when load is high, fans are loud, or a process has been running for a very long time. Companion to system-triage, adding the process-age dimension.
x-wrappers: [runaway-hunter]
---

# runaway-hunter

Use when the machine is hot, loud, or slow and you suspect a stuck or runaway process. Complements `system-triage`: it adds the *age* dimension plus zombie/uninterruptible detection a one-shot snapshot misses.

## Steps
1. Run `runaway-hunter`. It lists (read-only): processes that are both high-CPU AND long-running, zombie/wedged processes, and any configured known offenders — with a verdict.
2. Act on the verdict the wrapper prints:
   - `RUNAWAY` — a process is pegging a core for hours. Read the tables. For each candidate: inspect it first (propose `ps -fp <pid>`), then propose stopping it (`kill <pid>`, and only if it ignores that, `kill -9 <pid>`).
   - `KNOWN OFFENDER(S) RUNNING` — a process matches your `RUNAWAY_OFFENDERS` watch-list but nothing is hot-and-aged. Check its cpu/age in the offenders table first — it may be idle or short-lived. Inspect it (`ps -fp <pid>`); only propose a kill if it's genuinely stuck or hot.
   - `WEDGED/ZOMBIE present` — a lone zombie is usually benign (its parent will reap it); investigate the parent (`ps -o ppid= -p <pid>` then `ps -fp <ppid>`). A pile-up, or a D/U-state process, points at a stuck driver or mount — find what it's blocked on; never `kill -9` a D/U-state process.
   - `Nominal` — nothing hot-and-aged, no zombies, no known offenders; if it still feels slow, suggest `system-triage` or `disk-report`.
3. Never kill a process yourself, and never propose killing one that may be mid-write (a backup, a DB flush).
4. Report which processes look runaway and the proposed commands.

Read-only: it reads the process table and proposes kills; it runs none of them.
