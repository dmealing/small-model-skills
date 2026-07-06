# Security

## Threat model — what this does and doesn't do

small-model-skills runs **shell wrapper scripts** and **drives a local LLM** through Claude Code. The design
bounds the risk:

- **Wrappers are read-only.** They inspect state (interfaces, processes, disk, logs, and the router over
  SNMP / REST `GET`) and print a summary. They do not change system or router configuration.
- **The model proposes; a human runs.** Skills are propose-don't-apply, and the offline launcher keeps
  Claude Code's normal permission prompts — the model does not execute state-changing commands on its own.
  Don't run it with `--dangerously-skip-permissions`.
- **No secrets in the repo.** Host-specific values and any credentials live in
  `~/.config/small-model-skills/config` (and, for router REST, your password manager or a local file) —
  never committed. A pre-commit / pre-push leak guard blocks accidental leaks of paths and private names.

## Your responsibilities

- Trust the model you point at the skills — a local model still runs the wrappers you allow.
- Review third-party skills before installing: a `SKILL.md` can pre-grant broad tool access via
  `allowed-tools`. See the safety section of the authoring standard.
- Keep the router SNMP community / API credentials out of the repo and scoped to read-only where possible.

## Reporting a vulnerability

Please report privately — open a **GitHub Security Advisory** on the repository (Security → Advisories →
Report a vulnerability), or contact the maintainer directly. Do not open a public issue for an undisclosed
vulnerability.
