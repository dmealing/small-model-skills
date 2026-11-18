---
name: docker-hygiene
description: Report Docker disk waste — host disk and Docker.raw size, orphaned anonymous volumes, dead containers, unused images, and build cache — while sparing compose-managed data. Use when the disk fills from Docker, or test runs leak containers/volumes. Proposes prunes; deletes nothing.
x-wrappers: [docker-hygiene]
---

# docker-hygiene

Use when Docker is eating disk, or after test runs (e.g. Testcontainers) leak volumes and containers.

## Steps
1. Run `docker-hygiene`. It reports (read-only): host free space and the Docker Desktop disk image size, total Docker disk use, orphan anonymous volumes (compose-managed data is excluded), dead/exited containers, dangling and unused images, and reclaimable build cache.
2. Read the verdict:
   - `FAIL HOST_DISK_LOW` — the host disk is nearly full. Docker may be returning I/O errors and prunes can fail. Propose freeing a few GB on the host first (package caches, Trash), restarting Docker, then the prunes below.
   - `WARN INCOMPLETE` — some checks failed (listed). Do NOT call it clean; report what could not be checked.
   - `WARN RECLAIMABLE` — propose the cleanup from its `help` lines, but let a human run it, since it deletes data.
3. The cleanup commands: `docker buildx prune -af` (build cache), `docker container prune` (dead containers), `docker image prune` (dangling images), `docker image prune -a` (unused images — they re-pull). Remove listed orphan volumes individually: `docker volume rm <name>`.
4. Never run a prune yourself. Never propose `docker volume prune` blindly — the wrapper already excluded compose-managed volumes, and pruning all dangling volumes can wipe real data.
5. Report what's reclaimable and the proposed commands.

Read-only: it inspects with `df`, `du`, `docker system df` / `buildx du` / `ls` / `inspect` and proposes prunes; it runs none.
