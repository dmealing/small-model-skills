#!/usr/bin/env bash
# session-start-ambient-context.sh — Claude Code SessionStart hook.
#
# Surfaces a quick sys-diag health digest as ambient context, but ONLY for local-model sessions
# (detected via ANTHROPIC_BASE_URL pointing at the local Ollama endpoint claude-local sets up).
# For every normal (cloud) Claude Code session this is a single case-statement match, then exit —
# effectively zero overhead; it never touches other users' sessions.
#
# Rationale: this project's own documented weakness is that small local models don't reliably
# auto-trigger a skill from a vague prompt ("why is my computer slow?" -> just clarifying
# questions, no tool call — see README's "Auto-triggering is unreliable at this size"). Putting
# the health digest directly in context at session start means the model already has the facts
# without needing to be told "use system-triage" first. See DESIGN.md's AXI session-hook
# ambient-context section (previously scoped as a separate follow-on; this is that follow-on).
#
# This was an explicit, deliberate scope decision (out of the original cross-platform/AXI spec),
# not an accident — it touches hooks/settings.json, which is why it lives in its own directory
# instead of bin/, and why it is NOT wired into ~/.claude/settings.json automatically by
# install.sh: that's a global, shared file affecting every Claude Code session on the machine,
# so wiring it in is a separate, explicit, visible step (see README's Setup section).
set -uo pipefail

case "${ANTHROPIC_BASE_URL:-}" in
  http://localhost:11434*|http://127.0.0.1:11434*) ;;
  *) exit 0 ;;  # not a local-model session (claude-local always sets this) — no-op
esac

command -v sys-diag >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

digest="$(sys-diag 2>&1)"
[ $? -eq 1 ] && exit 0  # sys-diag itself failed — stay silent rather than inject a failure digest

ctx="Ambient system health at session start, from small-model-skills' sys-diag (say \"use system-triage\", \"use network-triage\", etc. to re-run a live check):

$digest"

jq -n --arg h "SessionStart" --arg ctx "$ctx" '{hookSpecificOutput: {hookEventName: $h, additionalContext: $ctx}}'
exit 0
