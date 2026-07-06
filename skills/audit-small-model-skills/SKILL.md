---
name: audit-small-model-skills
description: Audit SKILL.md skills in this project against the small-model authoring standard, using reasoning to catch issues that make skills fail on weak local models. Use when writing, reviewing, or before committing a skill here, or when asked to audit or lint skills. Read-only. Run with a capable model — the evaluation is judgment, not pattern-matching.
---

# Audit small-model skills

Evaluate skills against `docs/authoring-small-model-skills.md`. This is a REASONING task: read each skill
and judge it — do not rely on pattern-matching, which misses real problems and flags false ones. Read-only.
Run with a capable model, not the weak local one.

## Runbook
1. Read `docs/authoring-small-model-skills.md` — the standard and its section 7 checklist.
2. Run `skill-audit [path]` for objective METRICS only (name validity, description length, body line count,
   tool count, and signals such as literal IPs / home paths). Treat these as measurements, not verdicts.
3. For EACH skill, read its SKILL.md and evaluate with judgment:
   - Is the runbook actually FLAT — numbered imperative steps, no nested if/else branching?
   - Does it state concrete facts (or call a script that prints them), or lean on the model's world knowledge?
   - Read-only and propose-don't-apply? Is any destructive command presented as an ACTION rather than
     negated or proposed-for-the-user?
   - Is any HOST-SPECIFIC value hardcoded (an IP, absolute path, or hostname that belongs in config)? Use the
     skill-audit signals as a pointer, then judge whether each is a real leak or a harmless placeholder.
   - Does it summarize through a wrapper, or ask the model to dump raw logs/output into context?
   - Is the description a clean third-person trigger stating what AND when?
   - Is the tool surface small?
4. Report findings grouped by skill: blocking issues first, then warnings, then judgment notes — each with a
   concrete proposed edit and a one-line reason tied to the standard.
5. Propose fixes; do not rewrite skills unless asked.

## Tools
- `skill-audit [path]` — objective metrics (counts + spec-format), the factual input to your judgment above.
