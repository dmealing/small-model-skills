---
name: docker-hygiene
description: Report Docker disk waste — orphaned anonymous volumes, dead containers, dangling images, and build cache — while sparing compose-managed data. Use when the disk fills from Docker, or test runs leak containers/volumes. Proposes prunes; deletes nothing.
x-wrappers: [docker-hygiene]
---

# docker-hygiene

Use when Docker is eating disk, or after test runs (e.g. Testcontainers) leak volumes and containers.

## Steps
1. Run `docker-hygiene`. It reports (read-only): total Docker disk use, orphan anonymous volumes (compose-managed data is excluded), dead/exited containers, dangling images, and reclaimable build cache.
2. If the verdict is `RECLAIMABLE`, propose the cleanup — but let a human run it, since it deletes data:
   - `docker container prune` (dead containers), `docker image prune` (dangling images), `docker builder prune` (build cache).
   - Remove listed orphan volumes individually: `docker volume rm <name>`.
3. Never run a prune yourself. Never propose `docker volume prune` blindly — the wrapper already excluded compose-managed volumes, and pruning all dangling volumes can wipe real data.
4. Report what's reclaimable and the proposed commands.

Read-only: it inspects with `docker system df` / `ls` / `inspect` and proposes prunes; it runs none.
