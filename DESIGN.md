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

## Roadmap

- v1: the catalog above, SonicWall router module, Doug's machine as first consumer.
- Later: publish public repo + docs; add router modules (OPNsense/pfSense/UniFi); add `grammar/` GBNF
  files to constrain tool-call JSON for the weakest models; optional `system-review` deep-dive port.
