---
name: model-bench
description: Run a hard diagnostic benchmark across small models (local Ollama Qwen vs cloud GLM) and score them with a Gemini LLM-as-judge against per-task rubrics. Use to pick or track which model to route code-review / agent work to. Re-runnable any time a model or prompt changes.
---

# Model bench + LLM-as-judge

A repeatable harness that (1) runs each configured model over a fixed set of **hard**
diagnostic tasks (multi-hop reasoning, restraint traps, strict-output formatting,
tool selection, negative-evidence, etc.), capturing full outputs, then (2) scores
every output **blind and pointwise** with **Gemini 2.5 Pro** against a per-task
rubric, and (3) prints a scorecard + ranking.

Use it to decide which model the no-mistakes PR-gate (or any agent loop) should
run on, and to catch regressions when a model or prompt changes.

## Rules
- The judge is **blind and pointwise**: it sees one model's output at a time, never
  the model name or other models' outputs. Do not "help" it by revealing identities.
- Do **not** reward verbosity — the judge prompt explicitly forbids it. A model that
  correctly did less can still score `full`.
- Scores are `full` / `partial` / `fail` (3 / 2 / 1 points). Re-runs at temperature 0
  are near-deterministic; treat single-digit point swings as noise.

## Runbook
1. **Run the benchmark** (captures outputs; minutes per model):
   ```sh
   ./skills/model-bench/run-bench.sh \
     ollama:qwen3-coder-cc ollama:qwen3-instruct-cc openrouter:z-ai/glm-5.2
   ```
   Models are `provider:modelid` where provider ∈ `ollama` (local), `zai`
   (z.ai native), `openrouter`. Writes `results.jsonl` next to the script.
2. **Judge + scorecard** (Gemini 2.5 Pro; ~1 min for 36 outputs):
   ```sh
   python3 skills/model-bench/judge.py
   ```
   Prints the scorecard and per-task matrix; writes `gemini-judgments.{json,jsonl}`
   and `reasons-by-model.md` next to the script.
3. Read the **RANKING** line. Higher = better reviewer/agent on these tasks.

## Customizing
- **Tasks / rubrics** live in `tasks-hard.json` — add tasks or tighten rubrics there.
  Each task is `{id, bash, prompt, rubric}`; `bash:true` grants the Bash tool.
- **Models** are CLI args to `run-bench.sh` (see step 1). Keys: `ollama` needs none;
  `zai` reads `~/.config/small-model-skills/zai.env` (`ZAI_API_KEY=...`); `openrouter` reads
  `~/.config/small-model-skills/openrouter.env` (`OPENROUTER_API_KEY=...`). The judge
  reads its Gemini key from `GEMINI_API_KEY` or `~/.config/small-model-skills/gemini.key`.

## Last result (2026-07-07)
GLM-5.2 (34/36) > qwen3-coder-cc (26/36) > qwen3-instruct-cc (24/36). GLM-5.2's only
fail was `systems-reasoning` (claimed the system was NOT over-subscribed, contradicting
the rubric) — the one task qwen3-coder got full. The qwens failed mostly on tool
selection (wrong/no tool) and restraint, not raw reasoning.
