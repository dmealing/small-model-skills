---
name: disk-health
description: Check the SMART health of a machine's disks — is a drive failing or wearing out? Use when asked about drive health, SSD/NVMe wear or lifespan, SMART status, reallocated/bad sectors, or "is my disk dying?". Read-only — it inspects and reports; it changes nothing.
x-wrappers: [smart-health]
---

# Disk health (is a drive failing?)

Report the SMART health of this machine's disks. Read-only.

## Rules
- Read-only. Never run destructive disk commands (no `fsck`, `dd`, `mkfs`, partitioning). Propose, don't act.
- Use the `smart-health` wrapper; read its verdict. Keep output short.
- `smart-health` needs root to read the drives. If it reports `PROBE_FAILED` about access, tell the user to
  add the NOPASSWD sudoers entry shown in the wrapper's help (or run it with sudo) — do not work around it.

## Runbook
1. Run `smart-health`. Read the `verdict` line and the per-drive table.
2. Interpret the verdict:
   - `DRIVE_FAILING` (FAIL) → a drive reports FAILED health, an NVMe critical warning, pending sectors, or
     very high wear. This means imminent data loss — the reasons list names the drive(s).
   - `DRIVE_AGING` (WARN) → a drive has high (but not critical) wear, a few reallocated sectors, low spare,
     or an elevated temperature. Not urgent, but end-of-life is approaching for the named drive.
   - `NOMINAL` (OK) → all drives healthy.
3. Report the specific drive(s) and the specific reason (wear %, reallocated count, temperature) from the
   table — not a generic "a disk has an issue."
4. If a drive is FAILING, the ONE thing to tell the user: **back that drive up now and plan a replacement.**
   Propose it; do not attempt any migration or repair yourself.

## Tools
- `smart-health` — read-only SMART summary (NVMe wear/spare/critical warnings, SATA reallocated/pending
  sectors, temperatures) across all local disks, plus a verdict. Needs root/sudoers for device access.
