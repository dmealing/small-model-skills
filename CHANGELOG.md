# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `docs/tuning-local-models.md` — measured tuning guidance (MoE vs dense ~18×, num_ctx, keep-alive, curated
  skills, AXI output, and the thinking-toggle trap), from real benchmarks on a 12 GB GPU.
- `claude-local` curated-skills mode: points `CLAUDE_CONFIG_DIR` at a config home exposing only these
  skills (not every user skill), for a ~5% context trim + smaller tool surface on small models. Built by
  `install.sh`; opt out with `SMS_CURATED_SKILLS=0`.
- Diagnostic skills: `network-triage`, `system-triage`, `disk-report`, `log-triage`.
- Offline-dev skill: `offline-dev` (`offline-prep` pre-flight cache + `offline-doctor`).
- Deterministic, read-only wrappers (`bin/`): `net-diag`, `router-status`, `sys-diag`, `disk-report`,
  `log-triage`, `offline-prep`, `offline-doctor`.
- Authoring standard `docs/authoring-small-model-skills.md`, the `audit-small-model-skills` skill, and the
  `skill-audit` metrics linter.
- Config-driven setup (`config.example` + `~/.config/small-model-skills/config`) and `install.sh`.
- Pluggable router modules (`modules/router/`) with a SonicWall (SonicOS 7) reference implementation.
- Model recipe `models/agents-a1/` — patches the Qwen3.5 template's `raise_exception` guards so
  tool-calling works through Ollama (preserving the model's native tool + reasoning format).
- Public-repo leak guard (`.githooks/` pre-commit + pre-push, plus a CI `hygiene` workflow).
- README demo GIF, rendered from real output with no screen recording (`media/build-demo.py`).
- `bin/claude-local` — a single config-driven launcher (`claude-local qwable|agents-a1|<raw tag>`)
  replacing three near-duplicate shell functions that used to live directly in `~/.zshrc`. Model
  names/tags now live in `config.example` (`LOCAL_MODEL_*`). No short alias for a 70B+ model, on purpose.
- macOS support: `bin/lib/os-macos.sh` (native `sysctl`/`vm_stat`/`route`/`launchctl`/`log show` backend),
  alongside the extracted `bin/lib/os-linux.sh`. `bin/lib/common.sh` now detects the OS once and sources
  the matching backend. `install.sh` detects bare (non-WSL2) Windows and points at WSL2 instead of
  failing deep inside a wrapper.
- AXI ([axi.md](https://axi.md/)) output conventions across all four `bin/*` wrappers: an identity
  header, TOON for list-shaped data, structured `help[]` hints, and meaningful exit codes (`sms_identity`/
  `sms_toon`/`sms_help` in `common.sh`).
- `claude-hooks/session-start-ambient-context.sh` — a Claude Code `SessionStart` hook that surfaces a
  `sys-diag` digest as ambient context for local-model sessions only (checks `ANTHROPIC_BASE_URL`; a
  no-op for normal cloud sessions). The AXI session-hook follow-on from the original cross-platform spec.
- Four diagnostic skills: `ollama-doctor` (local Ollama daemon / models / VRAM-fit / CPU-spill — the
  offline brain), `freeze-forensics` (last-freeze forensics + is the watchdog/mitigations armed;
  Linux-primary, macOS reads panic reports), `runaway-hunter` (aged / zombie / runaway processes →
  propose the kill), `docker-hygiene` (orphan volumes / images / build cache, compose-aware).
- `smols` — an offline CLI catalog of installed skills (`smols` / `smols <name>` / `smols --toon`) so a
  user *or* the local model can discover what's available without a network or digging through code. Reads
  `SKILL.md` frontmatter + the wrappers via a new optional `x-wrappers:` key (added to every skill).
- New cross-platform `sms_*` helpers in `bin/lib/os-{linux,macos}.sh` for the above (`sms_gpu_vram_free`,
  `sms_watchdog_status`, `sms_procs_aged`, boot / MCE / reset-reason readers, …), kept at full parity.

### Changed
- `models/agents-a1` `num_ctx` default 262144 → **65536**. Claude Code's system prompt + tool/skill defs are
  ~27–30K tokens, so 32K truncates real sessions and 262K wastes KV cache; 64K is the measured safe minimum.

### Fixed
- `bin/lib/os-macos.sh`: `vm_stat` field-position bug (indexing from a fixed column broke once a
  label had more/fewer words than assumed — fixed by indexing from `$(NF-1)`).
- `bin/lib/os-macos.sh`: `du` without `-x` crossed an APFS firmlink from `/` into a real, separate,
  occasionally-stalled SMB mount (`~/Backups`) — the same failure mode as [[nas-backup-lag-pattern]],
  here triggered by `disk-report` instead of a backup job.
- `bin/lib/common.sh`: `ps` rows with multi-word `comm` values (e.g. `"Microsoft Teams Helper
  (Renderer)"`, common on macOS) broke naive whitespace-split column parsing — added `sms_ps_rows`.
- `bin/lib/os-macos.sh`: `launchctl list`'s "failed services" analogue was 100% noise unfiltered —
  every quiet, healthy launchd job reports `-9` (SIGKILL) as normal teardown; only non-`-9`/`-15`
  exits are surfaced now.
- `bin/router-status`, `bin/offline-prep`, `bin/offline-doctor`: still called `sms_head`, which the AXI
  refactor had removed (renamed to `sms_identity`) — every run printed `sms_head: command not found` and
  emitted no identity header. Migrated the three stragglers to `sms_identity`.
- `bin/claude-local`: removed `--dangerously-skip-permissions` from the launched `claude`. It let the local
  model auto-run the state-changing fixes the skills are designed to only *propose*, contradicting the
  read-only-by-default thesis and `SECURITY.md`.
- `bin/lib/os-macos.sh`: `sms_swap_used_kb` printed `v*1024` via awk, which renders GB-scale swap in
  scientific notation (`3040.56M → 3.11353e+06`); `sys-diag`'s integer swap-pressure test then errored and
  silently never fired on macOS. Now `printf "%d"`.
- `bin/offline-doctor`: its internet check called raw `ping -c1 -W1`; on macOS `-W` is milliseconds, so it
  reported "DOWN" even when up. Routed through `sms_ping` (correct per-OS flags) like the other wrappers.
- `bin/claude-local`: a raw model tag (`claude-local qwen3-coder-cc`) was silently ignored — the launcher
  fell back to the default model and leaked the tag into `claude`'s args. Added the raw-tag case (still
  guards flags/empty).
- `install.sh`: the final hint still told users to set up a `freeclaude` launcher; it now points at
  `claude-local`, which the installer itself puts on PATH.
