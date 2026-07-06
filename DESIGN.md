# small-model-skills — design

A curated, **config-driven** library of Claude Code *Agent Skills* built for **small local models
running offline** (Qwen2.5 / Qwen3 / Qwable-class, ~7–30B, served by Ollama). It turns a weak,
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
README.md            setup directions for adopters (Ollama + qwen/qwable + Claude-Code offline + skills)
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

**Offline-dev** (the plane case):
| Skill | Wrapper | Does |
|---|---|---|
| `offline-prep` | `offline-prep` | run *while online* before a flight: pre-cache deps (npm/pip/cargo/go), pull docker images, fetch offline docs, confirm the local model is pulled — reports what's cached vs missing |
| `offline-doctor` | `offline-doctor` | *while offline*: diagnose why a build/run fails for lack of network; point at local caches + offline flags (`--offline`, `--prefer-offline`, cached registries) |

## Safety model

- Wrappers are read-only. Anything that could change state is **not** in a wrapper — it's text in the
  skill for the human to run.
- Skills carry no `--dangerously-skip-permissions`; the local `freeclaude` runs with normal permission
  prompts (human-in-the-loop is the gate, per the owner's preference — no auto-mutation).
- Cherry-picked community content (linux-troubleshooting, disk-cleaner analyzer, journalctl forensics)
  is **safety-edited**: destructive commands stripped or moved to human-run suggestions; attribution kept.
- Secrets never enter the repo. Credentials come from the user's password manager or a local
  `chmod 600` file referenced by config — outside the repo, gitignored.

## Setup (adopter's path, condensed — full steps in README)

1. Install Ollama; `ollama pull` a tool-capable coder model (`qwen2.5-coder:14b`, `qwen3-coder`, or a
   Qwable GGUF on Ollama ≥ 0.24).
2. Point Claude Code at it offline (native Anthropic endpoint at `localhost:11434`) via a `freeclaude`
   shell function.
3. `./install.sh` — copies skills, links wrappers, and walks you through creating your config.
4. Ask the offline model to "diagnose the network / why it's slow / prep for offline dev."

## Platform support & AXI conventions (in design)

Built and tested on Linux today; every `bin/` wrapper currently calls Linux-only primitives directly
(`nproc`, `/proc/loadavg`, `free`, GNU-flavored `ps`/`df`/`du` flags, `systemctl`/`journalctl`,
`iproute2`). Full design: [`docs/superpowers/specs/2026-07-06-cross-platform-axi-design.md`](docs/superpowers/specs/2026-07-06-cross-platform-axi-design.md).

**Cross-platform.** OS-specific primitives move behind shared function names (`sms_nproc`,
`sms_meminfo`, `sms_top_procs_cpu`, `sms_failed_services`, …) with one implementation file per OS —
`bin/lib/os-linux.sh` (today's behavior, unchanged) and a new `bin/lib/os-macos.sh`
(`sysctl`/`vm_stat`/`launchd`/`log show`). `bin/lib/common.sh` detects the OS once and sources the
right file. Wrapper logic, digest structure, and every `skills/*/SKILL.md` file are untouched — the
OS split stays entirely below the model-facing layer. Windows support means **WSL2**, not a native
PowerShell port: this project has no Windows box to test/maintain a from-scratch rewrite against, and
WSL2 runs `os-linux.sh` unmodified — `install.sh` treats a detected WSL2 environment as Linux.

**AXI conventions.** Since every `bin/` wrapper is an agent-facing CLI (invoked by a local model
through Claude Code, never by a human directly), output is adopting
**[AXI — Agent eXperience Interface](https://axi.md/)** conventions, created by
**[Kun Chen](https://x.com/kunchenguid)** ([github.com/kunchenguid](https://github.com/kunchenguid)),
where they fit a read-only diagnostic snapshot:
- an identity header (`bin: ~/.local/bin/sys-diag` + one-line description)
- TOON for genuinely list-shaped data (process tables, failed-unit lists)
- structured `help[]` next-step hints alongside the existing plain-English verdict sentence
- meaningful exit codes (`0` = diagnosis completed, even if it found a problem; `1` = the tool itself
  failed; `2` = usage error)

Not adopted: AXI's mutation/idempotency and pagination/aggregate-count conventions don't apply —
these wrappers are read-only single-shot snapshots, not stateful list/mutate resources. AXI's
session-hook ambient-context feature (surfacing e.g. network/disk health at session start via a
Claude Code/Codex/OpenCode `SessionStart` hook) is a well-matched idea for this project's own noted
weakness (small models don't reliably auto-trigger skills from a vague prompt) but is scoped as a
**separate follow-on design**, since it touches hooks/settings.json rather than `bin/`.

## Roadmap

- v1: the catalog above, SonicWall router module, Doug's machine as first consumer.
- In design: cross-platform (macOS native + Windows via WSL2) and AXI output conventions — see above.
- Later: publish public repo + docs; add router modules (OPNsense/pfSense/UniFi); add `grammar/` GBNF
  files to constrain tool-call JSON for the weakest models; optional `system-review` deep-dive port;
  possible follow-on: AXI session-hook ambient context.
