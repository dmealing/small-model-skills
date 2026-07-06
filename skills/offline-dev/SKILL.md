---
name: offline-dev
description: Help write and run code with no internet, for example on a plane. Use before going offline to pre-cache dependencies, or while offline when a build or run fails for lack of network. Read-only — it reports readiness and proposes the right offline commands; it does not auto-install or download.
---

# Offline development

Keep coding, building, and running apps when there is no internet. Read-only — propose commands; do not
auto-run large downloads or installs.

## Rules
- Read-only. Propose caching and install commands for the user to run; do NOT auto-download or auto-install.
- Pick the right wrapper by situation (see the runbook). Keep output short.

## Runbook
1. Determine the situation:
   - Preparing, still online (for example before a flight) → run `offline-prep [project-dir]`. Report what
     is cached versus missing, and give the user the exact commands to cache the rest (deps, docker images,
     the local model).
   - Already offline and something will not build or run → run `offline-doctor [project-dir]`. Report which
     stacks are cached, the per-stack `--offline` flags to use, and the likely offline blockers.
   - Unsure which applies → run `offline-doctor` first; it reports whether the network is actually up.
2. Report a short summary: what is ready, what is missing, and the exact next command.
3. If something is genuinely absent from cache while offline, say so plainly — it cannot be built until back
   online. PROPOSE the fix; do not auto-install.

## Tools
- `offline-prep [dir]` — pre-flight readiness report plus caching commands (run while online).
- `offline-doctor [dir]` — offline: per-stack offline flags plus blocker diagnosis.
