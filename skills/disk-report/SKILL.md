---
name: disk-report
description: Diagnose why a disk or filesystem is full and find what is using the space. Use when a disk is full or nearly full, a "no space left" error appears, or when asked what is using disk space. Read-only — it analyzes and proposes cleanup for a human to run; it never deletes anything.
---

# Disk report (what is using the disk?)

Find where disk space went. Read-only — NEVER delete anything.

## Rules
- Read-only. NEVER run `rm`, `apt clean`, `docker prune`, `journalctl --vacuum`, or any deletion yourself.
  Propose them; the user decides and runs them.
- Use the `disk-report` wrapper; read its output.

## Runbook
1. Run `disk-report`. Read the filesystem table (which mount is full), the biggest directories, and the
   common space hogs.
2. Identify where the space concentrates — a specific directory, package caches, docker, logs, or /tmp.
3. Report the top two or three space consumers with their sizes.
4. PROPOSE safe reclamation for the user to run (the wrapper lists candidates: package caches, journal
   vacuum, `docker system prune`, a biggest-files command). Always tell the user to confirm each is safe
   first. Do NOT delete anything yourself.

## Tools
- `disk-report` — read-only filesystem, biggest-directories, and space-hog analysis with cleanup suggestions.
