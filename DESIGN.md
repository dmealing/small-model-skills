# small-model-skills — design

A curated, **config-driven** library of Claude Code *Agent Skills* built for **small local models
running offline** (a ~30B MoE coder like `qwen3-coder`, served by Ollama). It turns a weak,
internet-less model into a useful **diagnostics + offline-dev assistant** for a Linux workstation.

> Why this exists: as of mid-2026 there is **no** skill library targeting small offline models —
> the big "awesome-skills" collections are general-purpose and cloud-assuming. This fills that gap.

## Design principles (from the research)

1. **Scripts do the work; the model orchestrates.** Diagnosis logic lives in deterministic wrapper
   scripts that emit short, structured digests. The model runs one command and explains the result —
   it never has to compose fragile `snmpwalk`/`ip`/`df` invocations itself. (K8sGPT / MCP-Diag pattern.)
2. **Read-only by default; propose, don't apply.** Skills diagnose and *suggest* fixes; any
   state-changing action is handed to the human to run. No skill mutates system state on its own.
3. **Short, linear runbooks.** One skill = one job, a flat numbered checklist. Small models fail at
   branchy decision trees; keep branching in the scripts, not the prose. Target < 200 lines/skill.
4. **Tiny context.** Wrappers summarize (a ~20-line digest, never a raw log dump). Skill descriptions
   are terse so a weak model's skill-selection stays accurate.
5. **Config-driven for portability.** No host-specific values are hardcoded. Every script reads
   `~/.config/small-model-skills/config` (user-supplied). This is what makes the library shareable *and*
   personal at once — your machine's values live in your config, never in the repo.
6. **Agent-ergonomic output (in design).** Every consumer of `bin/` output is an agent reading stdout,
   not a human at a terminal — so wrapper output is moving to
   [AXI](https://axi.md/) (Agent eXperience Interface) conventions, created by
   [Kun Chen](https://x.com/kunchenguid): TOON for list-shaped data (e.g. the top-process table in
   `sys-diag`), an identity header, structured `help[]` next-step hints alongside the existing
   plain-English verdict, and meaningful exit codes. See
   [Platform support & AXI conventions](#platform-support--axi-conventions-in-design) below.

## Architecture

```
Claude Code (offline, local model via Ollama)
        │  invokes
        ▼
   SKILL.md runbook  ──describes──►  bin/ wrapper script  ──sources──►  ~/.config/small-model-skills/config
        │                                   │                                (user values)
        │                                   └──router ops──►  modules/router/<vendor>.sh  (pluggable)
        ▼
  plain-English verdict + proposed fix (human approves)
```

- **Wrappers** (`bin/`) are deterministic, read-only, and print a compact digest ending in a verdict.
- **Router module** (`modules/router/`) abstracts vendor-specific firewall/router queries behind a
  common interface (`router_wan_status`, `router_info`). A SonicWall reference module ships first;
  others (OPNsense, pfSense, MikroTik, UniFi…) are drop-in additions.
- **Config** carries the only host-specific data (gateway IP, DNS servers, WAN interface names, NIC,
  router vendor + address, SNMP community, credential source). `config.example` is the generic template.

## Repo layout

```
bin/                 net-diag, router-status, sys-diag, disk-report, log-triage, offline-prep, offline-doctor
bin/lib/common.sh    config loader + shared helpers (digest formatting, PASS/FAIL, safe_run)
modules/router/      sonicwall.sh (reference) + interface.md (how to add a vendor)
skills/<name>/SKILL.md   runbooks, mirrors ~/.claude/skills layout
config.example       generic config template
install.sh           copy skills → ~/.claude/skills, link bin → PATH, create user config, dep-check
README.md            setup directions for adopters (Ollama + qwen-coder + Claude-Code offline + skills)
DESIGN.md            this file
LICENSE              MIT
```

## Skill catalog (v1)

**Diagnostics** (read-only triage, each = wrapper + SKILL.md):
| Skill | Wrapper | Answers |
|---|---|---|
| `network-triage` | `net-diag`, `router-status` | "internet down? ISP vs DNS vs LAN vs failover" |
| `system-triage` | `sys-diag` | "why is my computer slow?" (CPU/mem/load/top hogs/thermal) |
| `disk-report` | `disk-report` | "why is my disk full?" (biggest dirs/files, caches, docker, logs) |
| `log-service-triage` | `log-triage` | "what service is broken / what's in the logs?" (failed units, recent errors) |

**Search** (read-only; locate a file, not triage):
| Skill | Wrapper | Answers |
|---|---|---|
| `file-search` | `find-files` | "where is that file / where is X configured?" — find by name + content (ripgrep/fd, falls back to grep/find), result-capped and time-bounded |

**Offline-dev** (the plane case):
| Skill | Wrapper | Does |
|---|---|---|
| `offline-prep` | `offline-prep` | run *while online* before a flight: pre-cache deps (npm/pip/cargo/go), pull docker images, fetch offline docs, confirm the local model is pulled — reports what's cached vs missing |
| `offline-doctor` | `offline-doctor` | *while offline*: diagnose why a build/run fails for lack of network; point at local caches + offline flags (`--offline`, `--prefer-offline`, cached registries) |

## Safety model

- Wrappers are read-only. Anything that could change state is **not** in a wrapper — it's text in the
  skill for the human to run.
- Skills carry no `--dangerously-skip-permissions` in their own definitions or `SKILL.md`s — the
  read-only-by-design boundary lives in what the wrappers *do*, not in a launcher flag. The
  `claude-local` launcher likewise does **not** skip
  permissions: it keeps Claude Code's normal permission prompts, consistent with the propose-don't-apply model and
  `SECURITY.md`. The human-approval gate on the model's tool calls stays in place, and the wrappers stay
  read-only regardless.
- Cherry-picked community content (linux-troubleshooting, disk-cleaner analyzer, journalctl forensics)
  is **safety-edited**: destructive commands stripped or moved to human-run suggestions; attribution kept.
- Secrets never enter the repo. Credentials come from the user's password manager or a local
  `chmod 600` file referenced by config — outside the repo, gitignored.

## Setup (adopter's path, condensed — full steps in README)

1. Install Ollama; `ollama pull` a tool-capable coder model (`qwen3-coder`, or any comparable ~30B MoE).
2. Point Claude Code at it offline (native Anthropic endpoint at `localhost:11434`) via the `claude-local`
   launcher (installed onto PATH by `install.sh`).
3. `./install.sh` — copies skills, links wrappers, and walks you through creating your config.
4. Ask the offline model to "diagnose the network / why it's slow / prep for offline dev."

## Platform support & AXI conventions

Built on Linux originally; tested and now working natively on **macOS** as well (Doug's M4 Max is the
second real consumer/CI target, alongside the original Linux workstation). Full design:
[`docs/superpowers/specs/2026-07-06-cross-platform-axi-design.md`](docs/superpowers/specs/2026-07-06-cross-platform-axi-design.md).

**Cross-platform.** OS-specific primitives live behind shared function names (`smols_nproc`,
`smols_meminfo`, `smols_top_procs_cpu`, `smols_failed_services`, …) with one implementation file per OS —
`bin/lib/os-linux.sh` (original behavior, unchanged) and `bin/lib/os-macos.sh`
(`sysctl`/`vm_stat`/`route`/`launchctl`/`log show`). `bin/lib/common.sh` detects the OS once (`SMOLS_OS`)
and sources the matching file. Wrapper logic, digest structure, and every `skills/*/SKILL.md` file stay
untouched — the OS split lives entirely below the model-facing layer. Windows support means **WSL2**,
not a native PowerShell port: WSL2 runs `os-linux.sh` unmodified; `install.sh` detects bare (non-WSL2)
Windows and points at WSL2 setup instead of failing deep inside some later script.

Bugs the macOS pass actually caught (worth recording — these are the reason "index from the end" and
`-x` show up as hard rules in the authoring doc, not just style preferences): `vm_stat`'s field position
for a value shifts with the label's word count (`Pages active:` vs `Pages wired down:`) — fixed by
indexing from `$(NF-1)`, not a literal `$2`. `du` without `-x` silently walked through an APFS firmlink
(`/` and `/System/Volumes/Data` share a device ID) into a real, separate, occasionally-stalled network
mount (`~/Backups`, SMB) — the exact failure mode in [[nas-backup-lag-pattern]] memory, here triggered by
a diagnostic script instead of a backup job. `ps`'s `comm` column can contain literal spaces on macOS
(`"Microsoft Teams Helper (Renderer)"`), which broke naive whitespace-split parsing that happened to work
on Linux by luck (Linux `comm` is normally one token) — fixed with a shared `smols_ps_rows` helper that
joins from the *second* field to *N-2*, keeping the true first/last two columns intact regardless of
how many words are in between. `launchctl list`'s failed-jobs analogue was **100% noise** unfiltered —
every quiet, healthy launchd job on this machine reports `-9` (SIGKILL) as its last exit status as part
of completely normal agent teardown; only non-`-9`/`-15` exits are worth surfacing.

**AXI conventions.** Since every `bin/` wrapper is an agent-facing CLI (invoked by a local model
through Claude Code, never by a human directly), output follows
**[AXI — Agent eXperience Interface](https://axi.md/)** conventions, created by
**[Kun Chen](https://x.com/kunchenguid)** ([github.com/kunchenguid](https://github.com/kunchenguid)):
- an identity header (`bin: ~/.local/bin/sys-diag` + one-line description) — `smols_identity` in `common.sh`
- TOON for genuinely list-shaped data (process tables, failed-unit lists) — `smols_toon`
- structured `help[]` next-step hints alongside the existing plain-English verdict sentence — `smols_help`
- meaningful exit codes (`0` = diagnosis completed, even if it found a problem; `1` = the tool itself
  failed; `2` = usage error)

Not adopted: AXI's mutation/idempotency and pagination/aggregate-count conventions don't apply —
these wrappers are read-only single-shot snapshots, not stateful list/mutate resources.

**AXI session-hook ambient context** (`claude-hooks/session-start-ambient-context.sh`) — originally
scoped as a separate follow-on (see the design spec), now built: a Claude Code `SessionStart` hook that
runs `sys-diag` and injects its digest as ambient context, but *only* for local-model sessions (detected
by `ANTHROPIC_BASE_URL` pointing at the local Ollama endpoint `claude-local` sets — a single string
comparison, so it's a genuine no-op for every normal cloud Claude Code session). Addresses this project's
own documented weakness: small models don't reliably auto-trigger a skill from a vague prompt, so surfacing
the health digest up front means the model already has the facts without needing "use system-triage" said
explicitly. Not wired into `~/.claude/settings.json` by `install.sh` automatically — that's a global file
shared by every Claude Code session on the machine, so adding the hook is a separate, visible step (see
README's Setup section), not something an installer silently does to your global config.

## Local model launcher

`bin/claude-local [<ollama model tag>]` — one launcher, config-driven
(`LOCAL_MODEL_DEFAULT` in `config.example`, `qwen3-coder-cc`), replacing near-duplicate shell functions.
Deliberately has **no short alias for a 70B+ model** — picking one requires spelling out the full Ollama tag
(`claude-local llama3.3:70b`), not a single memorable word, because loading a model that size is a real
resource commitment on a laptop (it's taken this machine down before).

By default it also runs **curated-skills mode**: `CLAUDE_CONFIG_DIR` is repointed at a config home
(`install.sh`-built) exposing only this repo's skills, trading away the global `~/.claude` context
(`CLAUDE.md`, custom `agents/`/`commands/`) for a smaller, cleaner context a weak model handles better.
Opt out with `SMOLS_CURATED_SKILLS=0`; measured rationale in
[`docs/tuning-local-models.md`](docs/tuning-local-models.md#4-curated-skills).

## Roadmap

- v1: the catalog above, SonicWall router module, Doug's machine as first consumer.
- Done: cross-platform (macOS native + Windows via WSL2), AXI output conventions, the `claude-local`
  launcher, the AXI session-hook ambient-context follow-on (see above), four more read-only diagnostic
  skills (`ollama-doctor`, `freeze-forensics`, `runaway-hunter`, `docker-hygiene`), and the `smols`
  offline catalog CLI that discovers installed skills from their `x-wrappers` frontmatter.
- Later: publish public repo + docs; add router modules (OPNsense/pfSense/UniFi); add `grammar/` GBNF
  files to constrain tool-call JSON for the weakest models; optional `system-review` deep-dive port.
