# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Verdict contract** — every `bin/*` wrapper now ends on exactly one machine-greppable line via the new
  `smols_verdict` helper: `verdict: <OK|WARN|FAIL> <TAG> — <prose>`. Fixed vocabulary (OK/WARN/FAIL; FAIL also
  covers a probe that couldn't run — `PROBE_FAILED` — or a down daemon), `SCREAMING_SNAKE` tags, verdict
  status independent of exit code. This turns every diagnostic wrapper into a monitoring probe (a future
  `smon` greps `^verdict:` and alerts on transitions). Documented in `docs/authoring-small-model-skills.md`.
- Config-tunable verdict thresholds: `DISK_WARN_PCT`/`DISK_CRIT_PCT`, `LOAD_WARN_FACTOR`, `CPU_HOG_PCT`,
  `SWAP_WARN_KB`, `TEMP_WARN_C` (documented in `config.example`). `smols_df_full_pct` helper added to both OS
  backends.
- `sys-diag` now has a **thermal verdict** (`WARN THERMAL` when the hottest CPU/GPU sensor ≥ `TEMP_WARN_C`) —
  previously thermals were only displayed, never judged.

### Fixed
- `docker-hygiene`: every `docker` call is now capped with `smols_timeout` (`SMOLS_DOCKER_TIMEOUT`) so a wedged
  daemon can't hang the report — matching what `disk-report` already did.
- `freeze-forensics`: the config-supplied `FREEZE_REMOTE_LOG_CMD` (executed as code) is now hard-capped at
  10s so an unreachable log host can't hang the probe for the TCP timeout; `config.example` recommends a
  `ConnectTimeout` in the command too.
- `log-triage`: no longer runs the (slow, esp. macOS `log show`) recent-errors query twice — counts the
  already-captured lines instead.
- `net-diag`: reports `skip (dig not installed)` instead of a false `FAIL` when `dig` is absent.

- `model-bench` skill — a repeatable hard-task benchmark + blind, pointwise Gemini LLM-as-judge that scores
  small models against per-task rubrics. First result (2026-07-07): cloud **GLM-5.2 34/36 >
  qwen3-coder-cc ~26 > qwen3-instruct-cc ~24**; the qwens trail mainly on tool selection and restraint,
  not raw reasoning. Use it to pick which model to route agent/review work to and to catch regressions.
  `run-bench.sh` is provider-driven (`ollama:`/`zai:`/`openrouter:` model specs).
- `docs/tuning-local-models.md` — measured tuning guidance (MoE vs dense ~15×, num_ctx, keep-alive, curated
  skills, and AXI output), from real benchmarks on a 12 GB GPU.
- `claude-local` curated-skills mode: points `CLAUDE_CONFIG_DIR` at a config home exposing only these
  skills (not every user skill), for a ~5% context trim + smaller tool surface on small models. Built by
  `install.sh`; opt out with `SMOLS_CURATED_SKILLS=0`.
- Diagnostic skills: `network-triage`, `system-triage`, `disk-report`, `log-triage`.
- Offline-dev skill: `offline-dev` (`offline-prep` pre-flight cache + `offline-doctor`).
- Deterministic, read-only wrappers (`bin/`): `net-diag`, `router-status`, `sys-diag`, `disk-report`,
  `log-triage`, `offline-prep`, `offline-doctor`.
- Authoring standard `docs/authoring-small-model-skills.md`, the `audit-small-model-skills` skill, and the
  `skill-audit` metrics linter.
- Config-driven setup (`config.example` + `~/.config/small-model-skills/config`) and `install.sh`.
- Pluggable router modules (`modules/router/`) with a SonicWall (SonicOS 7) reference implementation.
- Model recipe `models/qwen-coder/` — a Modelfile that raises `qwen3-coder` to `num_ctx 65536` for
  Claude Code (the tested default engine; any comparable ~30B MoE coder works).
- Public-repo leak guard (`.githooks/` pre-commit + pre-push, plus a CI `hygiene` workflow).
- README demo GIF, rendered from real output with no screen recording (`media/build-demo.py`).
- `bin/claude-local` — a single config-driven launcher (`claude-local [<ollama model tag>]`) replacing
  near-duplicate shell functions. The default model lives in `config.example` (`LOCAL_MODEL_DEFAULT`,
  `qwen3-coder-cc`). No short alias for a 70B+ model, on purpose.
- macOS support: `bin/lib/os-macos.sh` (native `sysctl`/`vm_stat`/`route`/`launchctl`/`log show` backend),
  alongside the extracted `bin/lib/os-linux.sh`. `bin/lib/common.sh` now detects the OS once and sources
  the matching backend. `install.sh` detects bare (non-WSL2) Windows and points at WSL2 instead of
  failing deep inside a wrapper.
- AXI ([axi.md](https://axi.md/)) output conventions across all four `bin/*` wrappers: an identity
  header, TOON for list-shaped data, structured `help[]` hints, and meaningful exit codes (`smols_identity`/
  `smols_toon`/`smols_help` in `common.sh`).
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
- New cross-platform `smols_*` helpers in `bin/lib/os-{linux,macos}.sh` for the above (`smols_gpu_vram_free`,
  `smols_watchdog_status`, `smols_procs_aged`, boot / MCE / reset-reason readers, …), kept at full parity.
- `file-search` skill + `find-files` wrapper — a read-only search for "find that file / where is X
  configured / which file mentions Y." Searches file **names** (fd → fdfind → find) and **contents**
  (ripgrep → grep) for a literal substring, including gitignored and hidden files (pruning only
  `.git`/`node_modules`/`.cache`), result-capped and time-bounded so a big tree can't hang it. Distinguishes
  a real "no matches" from a time-cutoff. Config `SEARCH_ROOT`/`SEARCH_MAX`/`SEARCH_NAME_TIMEOUT`/
  `SEARCH_CONTENT_TIMEOUT`. Only searches — never opens, edits, or deletes.
- `smols_timeout` / `smols_timeout_warn` / `smols_is_timeout` helpers in `bin/lib/common.sh` — a portable
  wall-clock cap (via `timeout`/`gtimeout`; degrades to uncapped with a one-line stderr note where neither
  exists) so a slow tool (`du` over a huge tree, a wedged mount/daemon) can't hang a wrapper. Exit
  124/137/143 means killed for time.

### Changed
- The model recipe ships `num_ctx 65536`. Claude Code's system prompt + tool/skill defs are ~27–30K tokens,
  so 32K truncates real sessions and a model's native max wastes KV cache; 64K is the measured safe minimum.
- Default local model is now **`qwen3-coder-cc`** — the `num_ctx 65536` build of the well-known, tool-capable
  ~30B MoE coder `qwen3-coder`.

### Fixed
- `bin/lib/os-macos.sh`: `vm_stat` field-position bug (indexing from a fixed column broke once a
  label had more/fewer words than assumed — fixed by indexing from `$(NF-1)`).
- `bin/lib/os-macos.sh`: `du` without `-x` crossed an APFS firmlink from `/` into a real, separate,
  occasionally-stalled SMB mount (`~/Backups`) — the same failure mode as [[nas-backup-lag-pattern]],
  here triggered by `disk-report` instead of a backup job.
- `bin/lib/common.sh`: `ps` rows with multi-word `comm` values (e.g. `"Microsoft Teams Helper
  (Renderer)"`, common on macOS) broke naive whitespace-split column parsing — added `smols_ps_rows`.
- `bin/lib/os-macos.sh`: `launchctl list`'s "failed services" analogue was 100% noise unfiltered —
  every quiet, healthy launchd job reports `-9` (SIGKILL) as normal teardown; only non-`-9`/`-15`
  exits are surfaced now.
- `bin/router-status`, `bin/offline-prep`, `bin/offline-doctor`: still called `smols_head`, which the AXI
  refactor had removed (renamed to `smols_identity`) — every run printed `smols_head: command not found` and
  emitted no identity header. Migrated the three stragglers to `smols_identity`.
- `bin/claude-local`: removed `--dangerously-skip-permissions` from the launched `claude`. It let the local
  model auto-run the state-changing fixes the skills are designed to only *propose*, contradicting the
  read-only-by-default thesis and `SECURITY.md`.
- `bin/lib/os-macos.sh`: `smols_swap_used_kb` printed `v*1024` via awk, which renders GB-scale swap in
  scientific notation (`3040.56M → 3.11353e+06`); `sys-diag`'s integer swap-pressure test then errored and
  silently never fired on macOS. Now `printf "%d"`.
- `bin/offline-doctor`: its internet check called raw `ping -c1 -W1`; on macOS `-W` is milliseconds, so it
  reported "DOWN" even when up. Routed through `smols_ping` (correct per-OS flags) like the other wrappers.
- `bin/claude-local`: a raw model tag (`claude-local qwen3-coder-cc`) was silently ignored — the launcher
  fell back to the default model and leaked the tag into `claude`'s args. Added the raw-tag case (still
  guards flags/empty).
- `install.sh`: the final hint still told users to set up a `freeclaude` launcher; it now points at
  `claude-local`, which the installer itself puts on PATH.
- `disk-report` hit Claude Code's 180s tool timeout with **blank** output on large filesystems — `du -x -d1`
  over a full tree (plus unbounded `du` on hogs like `/var/lib/docker`) walked the whole thing. The `du`
  walks are now time-bounded via `smols_timeout` (`SMOLS_DU_TIMEOUT`=20s for the biggest-dirs walk,
  `SMOLS_DU_HOG_TIMEOUT`=8s per hog) and `docker system df` is capped (`SMOLS_DOCKER_TIMEOUT`=8s); on a timeout
  the report says "too large — timed out" / "PARTIAL" honestly instead of hanging or printing blanks.
  Dropped the redundant `/var/lib/docker` du (`docker system df` already reports it) and added a
  container-json-log hint to the cleanup candidates. A 1.8T-used box went from a 180s timeout with no output
  to ~66s with full biggest-dirs + hogs output.
