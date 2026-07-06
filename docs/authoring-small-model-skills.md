# Authoring skills for small models — the standard

**Audience:** a capable model (Opus-class) or human *writing* a skill in this repo. Read this before
authoring or editing any `SKILL.md` here. The `audit-small-model-skills` skill + `skill-audit` linter
enforce the mechanically-checkable parts.

**Thesis.** Anthropic's official skill guidance assumes *"Claude is already very smart… only add context
Claude doesn't already have."* For a **7B–32B local model that assumption is false.** Author for the
*low-freedom* end of every spectrum: state facts it can't be trusted to know, flatten branching, move
logic into scripts, cap output, allowlist tools. Two empirical anchors: **lost-in-the-middle** (recall is
best at the very start/end of context and degrades in the middle, worse for weak models) and the
**attention budget** (recall drops as context grows). Goal: *the smallest set of high-signal tokens.*

## Contents
- [1. Frontmatter (hard rules)](#1-frontmatter)
- [2. Length & structure](#2-length--structure)
- [3. Writing for a weak model](#3-writing-for-a-weak-model)
- [4. Determinism (push logic to scripts)](#4-determinism)
- [5. Tool-call reliability](#5-tool-call-reliability)
- [6. Safety](#6-safety)
- [7. The lint checklist (what the auditor checks)](#7-lint-checklist)
- [Sources](#sources)

## 1. Frontmatter
- `name`: `^[a-z0-9-]{1,64}$`; no uppercase/spaces, no XML, must NOT contain `anthropic`/`claude`.
- `description`: **non-empty, ≤ 1024 chars, third person**, states **both what it does AND when to use it**
  (it's a classifier the model uses to pick the skill, injected at startup). Put the *trigger* first.
  Aim ≤ ~350 chars — the listing truncates and, under budget pressure, least-used skills are dropped.
- Read-only skills need nothing else. Any skill with side effects: see [§6](#6-safety).
- `x-wrappers` (optional): the wrapper command(s) this skill drives, as a list — `x-wrappers: [sys-diag]`
  (or several: `[net-diag, router-status]`). The `smols` catalog reads it to show *how to invoke* the
  skill; omit it and the wrapper still installs but the catalog can't tie it to the skill.

## 2. Length & structure
- **Body < 500 lines (hard). Aim < ~120 for a weak-model skill.** Front-load the load-bearing steps
  (start/end survive lost-in-the-middle; the middle gets dropped).
- Use progressive disclosure: keep detail in bundled `reference/` files, **one level deep** from SKILL.md
  (deeper nesting breaks — the model previews with `head` and misses content). Any reference file
  > 100 lines needs a **Contents/TOC** at the top.
- Once invoked, a SKILL.md is read **once** and stays in context — it is not re-read. Don't rely on re-reading.

## 3. Writing for a weak model
- **Flat, numbered, imperative steps.** "Run X → read result → report." No nested `if/else`. A single
  shallow branch is OK ("A? do this. B? do that."); anything deeper → split into separate files.
- **State concrete facts; never rely on world knowledge.** The weak model doesn't reliably know your
  OIDs, ports, service names, or topology. Provide them — or better, have a **script emit them** at
  runtime (this repo's pattern: generic skill + config-driven wrapper prints the facts).
- **One term per referent.** Don't alternate field/box/element or get/fetch/pull. Consistency = fewer
  wrong guesses. Use **MUST/NEVER**, not "should/try to," for load-bearing rules.
- **Fewer options.** Give one default with an escape hatch, not a menu of three tools.

## 4. Determinism
- **Push logic into wrapper scripts; the model orchestrates + explains.** Sorting/parsing/validation/
  multi-step API calls belong in code, not the token stream. Scripts are more reliable, cheaper, consistent.
- **Say run vs. read explicitly:** "Run `net-diag`" (execute) vs "See `x.md` for the algorithm" (reference).
- **Return short, structured output — never raw dumps.** A wrapper summarizes to a ~20-line digest with a
  verdict; it does not pipe a full `journalctl`/`df`/log into context (floods the attention budget).
- **No-overclaim verdicts.** A verdict MUST NOT assert one definitive conclusion when the right reading
  depends on context the wrapper can't know (is a GPU *expected*, is this process *supposed* to run, is the
  watchdog actually being *petted*). State the facts plus the clearly-labeled alternatives and flag the
  uncertainty, so the small model makes the final contextual call between labeled options instead of acting
  on a confidently-wrong verdict. E.g. no discrete GPU → "models run on CPU (expected on a CPU-only box)",
  not "CPU SPILL — free VRAM"; a `/dev/watchdog` node with nothing petting it → "armed=no — may NOT
  auto-reboot", not "protected."
- **Scripts solve, not punt:** handle their own errors with specific messages; no unexplained magic numbers.
- **Cross-platform primitives:** never call an OS-specific command directly (`nproc`, `ip`, `systemctl`,
  GNU-flavored `ps`/`df`/`du` flags, …) — call the `sms_*` helper in `bin/lib/common.sh` instead
  (`sms_nproc`, `sms_loadavg`, `sms_top_procs_cpu`, `sms_default_gw`, `sms_failed_services`, …). Add a new
  helper to *both* `bin/lib/os-linux.sh` and `bin/lib/os-macos.sh` if one doesn't exist yet — never fork
  wrapper logic per-OS. A silent-degrade bug beats a missing binary: verify field positions against real
  output on both platforms (BSD/GNU `ps`, `df`, `vm_stat` field counts differ by label length — index from
  the end, not a fixed position, when a line's word count varies).
- **AXI conventions** — every `bin/*` wrapper follows [AXI](https://axi.md/): an identity header
  (`sms_identity "one-line description"` as the first thing printed), TOON for list-shaped data
  (`... | sms_toon <name> <fields>`), structured `help[N]:` hints alongside the prose verdict (`sms_help
  "do this" "or this"`), and meaningful exit codes (`0` diagnosis ran even if it found a problem, `1` the
  tool itself failed to gather any data, `2` usage error).

## 5. Tool-call reliability
- **Fewer tools is the biggest lever.** Small-model tool-calling accuracy collapses as the tool/schema
  count grows (a cliff around ~7B params / many tools). Keep each skill pointed at a *tiny* tool surface.
- **Unambiguous names**, service-namespaced; resolve opaque IDs to human-readable strings.
- **Structured output → constrain it.** If a skill needs JSON/structured output from the model, use a
  JSON-schema constraint (Ollama `format` + temperature 0) or a validator step — don't hope it emits valid
  JSON. (Grammar/constrained decoding fixes *syntax*, not correctness — keep schemas minimal.)
- Fully-qualify MCP tools as `Server:tool`; prefer a small allowlisted script surface over a big MCP catalog.

## 6. Safety
- **Read-only by default.** A weak model will not reliably honor "don't run destructive commands" in prose.
- **Propose, don't apply.** State-changing fixes are described for a human to run — the skill does not run them.
- Gate any side-effecting skill with `disable-model-invocation: true` (removes it from auto-intent-matching;
  fires only on explicit user invocation). Scope tools with `allowed-tools`/`disallowed-tools`. Real
  enforcement is deny-rules/hooks, not skill prose.

## 7. Lint checklist
`skill-audit` implements these; `audit-small-model-skills` adds judgment on the softer ones. FAIL = block, WARN = review.

**Frontmatter** — 1) missing/vague `description` (FAIL). 2) first/second-person description (FAIL). 3) invalid
`name` (FAIL). 4) description > 1024 (FAIL) / > 500 (WARN).
**Length/structure** — 5) body > 500 lines (FAIL) / > 300 (WARN). 6) references nested deeper than one level
(FAIL). 7) reference file > 100 lines without a TOC (WARN).
**Weak-model load** — 8) nested conditionals beyond depth 1 (WARN). 9) ≥3 chained "or" alternatives with no
default (WARN). 10) inconsistent terminology cluster (WARN). 11) data/API skill with zero concrete
facts/reference (WARN). 12) time-sensitive info outside a "deprecated" block (WARN).
**Determinism** — 13) raw-dump instruction (`cat`/full `journalctl`/"paste all output") without a summarizing
wrapper (WARN). 14) deterministic op described as prose steps instead of a script call (WARN). 15) magic
constant in a bundled script with no justifying comment (WARN). 16) referenced script with no run/read verb (WARN).
**Tooling** — 17) too many distinct tools referenced (WARN). 18) unqualified MCP tool name (WARN). 19) assumes a
package/CLI without an availability check (WARN). 20) asks for structured output with no schema/validator (WARN).
**Safety** — 21) destructive command inline (`rm -rf|git push|git reset --hard|drop table|deploy|shutdown|
kubectl delete|dd `) without gating (FAIL). 22) side-effecting skill (commit/deploy/send/publish) missing
`disable-model-invocation` (FAIL). 23) write/exec skill with no read-only-default scoping (WARN).
**Portability** — 24) Windows backslash paths (WARN). 25) hardcoded host-specific values — absolute
`/home/<user>/…` paths, literal LAN IPs, hostnames, tokens — in SKILL.md; parameterize/move to config (FAIL).

**Beyond the linter:** every skill needs ≥3 evaluations run **on the actual target local model** — passing on
Opus proves nothing about Qwen-7B. Baseline skill-disabled vs. enabled in a fresh session.

## Sources
Anthropic: [skill best-practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) ·
[Agent Skills engineering](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) ·
[Claude Code skills](https://code.claude.com/docs/en/skills) ·
[writing tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents) ·
[context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents).
Research: [Lost in the Middle (arXiv:2307.03172)](https://arxiv.org/abs/2307.03172) ·
[Adapt Tool Schemas (arXiv:2510.07248)](https://arxiv.org/pdf/2510.07248) ·
[Small LMs for Agentic Systems survey (arXiv:2510.03847)](https://arxiv.org/abs/2510.03847) ·
[Ollama structured outputs](https://docs.ollama.com/capabilities/structured-outputs) ·
[llama.cpp GBNF](https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md).
