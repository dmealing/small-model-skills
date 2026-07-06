---
name: freeze-forensics
description: Investigate the last hard freeze or unclean reboot and confirm the anti-freeze mitigations are still armed. Use after a lockup or unexpected reboot, or to audit stability. Reports the previous boot's crash trail, hardware errors, whether the watchdog is actually armed, and the active kernel mitigations. Linux-primary.
x-wrappers: [freeze-forensics]
---

# freeze-forensics

Use after the machine froze or rebooted unexpectedly, or to check whether it's protected against the next freeze. Distinct from `log-triage` (which covers the *current* boot's failed services) — this reconstructs the *previous* boot plus hardware/watchdog state.

## Steps
1. Run `freeze-forensics`. It reads boot history + kernel logs (read-only) and prints: whether the last session ended cleanly, the kernel tail if it was abrupt, hardware errors, watchdog state, and the active kernel mitigations.
2. Read the **verdict**:
   - `LAST SESSION ENDED ABRUPTLY` → treat as a freeze/panic; use the kernel tail + hardware errors as clues.
   - `LIMITED HISTORY` → the previous boot's logs aren't in the journal; rely on the watchdog + mitigation lines for whether you're protected now.
   - `No freeze on record` → the last shutdown was clean.
3. **Always check the watchdog line.** If it shows `device=none`, a freeze will hang forever instead of auto-rebooting — propose arming a watchdog.
4. Report the verdict and whether the watchdog is armed. Change nothing.

Read-only: some hardware checks want root and degrade silently when it isn't available.
