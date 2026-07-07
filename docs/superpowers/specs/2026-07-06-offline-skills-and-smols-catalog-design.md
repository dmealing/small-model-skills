# Offline skills expansion + the `smols` catalog — design

> **Name:** the catalog command is **`smols`** (not `smol` — `smol` collides with an npm CLI and the
> crowded `smol*` / smolvm / smolagents namespace; `smols` is unclaimed).

**Date:** 2026-07-06 · **Status:** proposed

Two things, one branch:
1. **`smols`** — a CLI catalog so a user (or the model) can *discover* installed skills offline, without
   digging through code. Solves the documented "auto-triggering is unreliable + I forgot what I have" gap.
2. **Four new read-only diagnostic skills** — `ollama-doctor`, `freeze-forensics`, `runaway-hunter`,
   `docker-hygiene` — each mapping to a recurring, fully-offline firefight.

## Non-negotiables (apply to everything here)
- **Read-only / propose-don't-apply.** Wrappers inspect and print; state-changing fixes are text for a
  human. `runaway-hunter` and `docker-hygiene` propose kills/prunes; they never run them.
- **No host-specific values in the repo.** This is public. Every IP, path, hostname, kernel version,
  process name, or model name is **auto-detected** or read from `~/.config/small-model-skills/config`,
  never hardcoded. Ships with *generic* defaults; the leak guard enforces it.
- **Cross-platform via helpers.** No OS-specific command called directly from a wrapper — add an `sms_*`
  helper to **both** `bin/lib/os-linux.sh` and `bin/lib/os-macos.sh`. Where a probe is genuinely
  OS-only, the helper degrades honestly on the other OS (never a bare "command not found").
- **AXI conventions.** `sms_identity` header, `sms_toon` for tables, `sms_help` hints, exit `0` (ran, even
  if it found a problem) / `1` (tool couldn't gather data) / `2` (usage).

---

## Part 1 — `smols` catalog CLI (`bin/smols`)

**Source of truth:** installed skills (`~/.claude/skills/*/SKILL.md` frontmatter → `name`, `description`)
+ the `bin/` wrappers (each already prints a one-line `sms_identity` description). No hardcoded list —
add a skill, it appears automatically.

**Skill→wrapper mapping:** add one optional frontmatter key to each `SKILL.md`:
```yaml
x-wrappers: [sys-diag]          # the command(s) this skill drives
```
`smols` falls back to name-matching if the key is absent, so third-party skills still list.

**Commands:**
- `smols` / `smols list` — grouped catalog. Per skill: **name**, one-liner, and **how to invoke it** —
  `say "use <name>"` *or* run `<wrapper>` directly. Also lists any wrapper not tied to a skill.
- `smols <name>` — detail for one skill: full description, its wrapper(s), a usage example, exit-code key.
- `smols --toon` (list, machine-readable) — so the model can read the catalog too.

**Properties:** pure bash + file reads (no network, no deps), colorized only on a TTY. Installed onto PATH
by `install.sh`. Config: `SMS_SKILLS_DIR` (default `~/.claude/skills`), reuses `bin/lib` for `bin/` dir.

---

## Part 2 — the four skills

Each = `skills/<name>/SKILL.md` (flat runbook, points at the wrapper) + `bin/<wrapper>` + new `sms_*`
helpers. All read-only.

### 2.1 `ollama-doctor` (wrapper `ollama-doctor`) — cross-platform
Diagnoses the local model stack (the offline brain itself).
- **Daemon:** `GET {OLLAMA_URL}/api/version` (config `OLLAMA_URL`, default `http://localhost:11434`).
- **Models + disk:** `GET /api/tags` (names, sizes, total).
- **Loaded now:** `GET /api/ps` → model, `size_vram` vs `size` (GPU vs **CPU spill**), context, expiry.
- **VRAM fit:** free VRAM via `sms_gpu_vram_free` → compare against loaded/named model size; flag "will
  spill to CPU (slow)". Linux: `nvidia-smi`. macOS: report unified memory (Metal); no hard yes/no.
- **Verdict:** daemon down · no models · model spilling to CPU · healthy. Proposes `ollama pull`, stop the
  spilling model, or a smaller quant — never runs them.
- **New helpers:** `sms_gpu_vram_free`, `sms_gpu_name` (both backends).

### 2.2 `freeze-forensics` (wrapper `freeze-forensics`) — **Linux/WSL-primary**, macOS-light
Reconstructs the *last* hard freeze and confirms anti-freeze mitigations are still armed. Distinct from
`log-triage` (that's current-boot failed units; this is **previous-boot forensics + hardware/watchdog**).
- **Prev-boot post-mortem:** boots list; did the previous boot end without a clean-shutdown marker? tail of
  its kernel warnings (GPF / RCU stall / hung-task / MCE / Xid signatures — matched generically).
- **Reset reason & hardware errors:** kernel "previous reset reason"; `ras-mc-ctl --summary` / MCE if
  present and readable.
- **Watchdog actually armed** (the classic latent bug): a watchdog module loaded + `/dev/watchdog*`
  claimed + systemd `RuntimeWatchdogSec`.
- **Mitigations intact:** report kernel cmdline flags (e.g. any `cgroup_disable=*`) and running kernel —
  *generically*, comparing to an optional `KNOWN_BAD_KERNELS` config (empty by default), never a
  baked-in version.
- **Optional remote black-box:** if `FREEZE_REMOTE_LOG_CMD` is set in config, run it to fetch a netconsole
  log. Off by default (host-specific).
- **macOS:** degrade to recent panic reports (`/Library/Logs/DiagnosticReports/*.panic`) + a note.
- **sudo:** `dmidecode`/`ras-mc-ctl` want root — use `sudo -n` (non-interactive) and **degrade** if not
  allowed. Never prompt.
- **New helpers:** `sms_boot_list`, `sms_prev_boot_kernel_tail`, `sms_watchdog_status`, `sms_reset_reason`,
  `sms_mce_summary` (Linux real; macOS panic-report equivalents / honest "n/a").

### 2.3 `runaway-hunter` (wrapper `runaway-hunter`) — cross-platform
Focused companion to `system-triage`: adds the **age** dimension + zombie detection a snapshot lacks.
- Flag processes that are **high-CPU AND aged**: `%cpu > RUNAWAY_CPU_PCT` (default 50) **and** elapsed
  `> RUNAWAY_AGE_HOURS` (default 4). Both configurable.
- **Zombie/wedged:** defunct (`Z`) children, uninterruptible-sleep (`D`) pileups.
- **Known offenders:** match `comm`/args against `RUNAWAY_OFFENDERS` (config; a small *generic* default of
  common leak patterns like runaway test-runners — no machine-specific names shipped).
- Proposes `SIGTERM` then `SIGKILL`; runs nothing.
- **New helper:** `sms_proc_age_secs` / `sms_procs_aged` (Linux `ps -o etimes`; macOS parses `etime`).

### 2.4 `docker-hygiene` (wrapper `docker-hygiene`) — cross-platform
Extends `disk-report` into Docker internals. If Docker is absent/down: one clean line, exit 0.
- `docker system df -v` (images / containers / volumes / build-cache).
- **Orphan anonymous volumes:** `docker volume ls -f dangling=true`, cross-referenced with the
  `com.docker.compose.project` label so **compose-managed data is spared** (report labels, delete nothing).
- Dead/exited containers (Testcontainers/`ryuk` leftovers), dangling images, reclaimable build cache.
- Data root via `docker info`. Proposes `docker volume rm` / `docker system prune` — never runs them.
- **New helpers:** none OS-specific (Docker CLI is uniform); just `have docker` + daemon-up check.

---

## Config additions (all optional, generic defaults)
```sh
OLLAMA_URL="http://localhost:11434"
RUNAWAY_CPU_PCT=50
RUNAWAY_AGE_HOURS=4
RUNAWAY_OFFENDERS=""            # extra comm/arg patterns, space-separated
KNOWN_BAD_KERNELS=""           # optional, for freeze-forensics
FREEZE_REMOTE_LOG_CMD=""       # optional netconsole fetch (host-specific; off by default)
```

## Out of scope (explicitly deferred to a later pass)
- `smols serve` (self-contained HTML docs on a configurable localhost/Tailscale host) and the SessionStart
  hook that injects the catalog — the other two discoverability surfaces.
- Tier-2 skills: `nvidia-doctor`, `symlink-offload-health`, `cron-timer-health`, `backup-status`.
- Folding cache prune-vs-nuke intelligence into `disk-report`.

## Verification
- Each wrapper: `bash -n`, runs on this box (Linux) with an identity header + zero `command not found`.
- `smols list` renders every installed skill with correct invoke lines.
- `skill-audit` + the `audit-small-model-skills` reasoning pass on each new `SKILL.md`.
- Leak-scan clean (proves no host-specifics slipped in). Ship through the `no-mistakes` gate.
