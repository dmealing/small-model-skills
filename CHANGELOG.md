# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
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
