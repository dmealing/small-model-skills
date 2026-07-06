# Contributing

Thanks for helping make small local models more useful. The bar here is specific: **every skill must work
on the actual small model**, not just a frontier one.

## Before you write a skill

Read [`docs/authoring-small-model-skills.md`](docs/authoring-small-model-skills.md) — the standard for
skills a ~7–30B model can execute (flat steps, read-only, scripts-do-the-work, tiny context, concrete
facts). It's short, and those rules are what keep a skill from quietly failing on a weak model.

## Adding a skill

1. **`skills/<name>/SKILL.md`** — the runbook. Third-person `description` stating *what* and *when*; a flat,
   numbered set of imperative steps (no nested if/else); point at the wrapper, not raw commands. Add
   `x-wrappers: [<wrapper>]` to the frontmatter so `smols` lists how to invoke it.
2. **`bin/<wrapper>`** — a deterministic script that does the work and prints a short digest ending in a
   verdict. Read-only. Read any host-specific value from `~/.config/small-model-skills/config` via
   `bin/lib/common.sh`; never hardcode IPs/paths/hostnames.
3. Keep it **read-only / propose-don't-apply.** Any state-changing step is text for a human to run, never an
   action the model takes.

## Check your work

- `skill-audit` — objective metrics (name/description validity, length, tool count, leak signals).
- The `audit-small-model-skills` skill — reasoning-based review against the standard. Run it with a
  **capable** model; a linter can't judge whether a runbook is actually flat or leans on world-knowledge.
- **Test on the target model.** Passing on a frontier model proves nothing about a 7B. Run a couple of real
  prompts through `claude-local <small-model>` and confirm the skill (or its wrapper) does the right thing.

## Public-repo hygiene

This repo is public — nothing host-specific goes in committed files. IPs, absolute paths, hostnames, and
private names live in your local config, not the repo. Activate the guard once per clone:

```bash
git config core.hooksPath .githooks
git config hooks.denyListPath /path/to/your/denylist.txt   # optional: names to block (kept private)
```

The `pre-commit` / `pre-push` hooks and CI scan **added lines** for local paths and denylisted names.
Genericize anything they flag (e.g. `a downstream consumer`, `<repo-root>`).

## Router / firewall modules

Adding another vendor for `network-triage`? See
[`modules/router/interface.md`](modules/router/interface.md) — implement one read-only function.

## Style

Bash: `set -uo pipefail`, `bin/lib/common.sh` helpers, short summarized output (never raw dumps). Keep a
`SKILL.md` body well under 500 lines (aim ~120). One term per concept. Forward-slash paths only.
